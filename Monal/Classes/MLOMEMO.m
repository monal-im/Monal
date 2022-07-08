//
//  MLOMEMO.m
//  Monal
//
//  Created by Friedrich Altheide on 21.06.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLOMEMO.h"
#import "MLXMPPConnection.h"
#import "MLHandler.h"
#import "xmpp.h"
#import "XMPPMessage.h"
#import "SignalAddress.h"
#import "MLSignalStore.h"
#import "SignalContext.h"
#import "AESGcm.h"
#import "HelperTools.h"
#import "XMPPIQ.h"
#import "xmpp.h"
#import "MLPubSub.h"
#import "DataLayer.h"
#import "MLNotificationQueue.h"

#include <stdlib.h>

typedef enum {
    LoggedOut,
    LoggedIn,
    CatchupDone
} OmemoLoginState;

@interface MLOMEMO ()

@property (atomic, strong) SignalContext* signalContext;

@property (nonatomic, strong) NSString* accountJid;

@property (nonatomic, weak) xmpp* account;
@property (nonatomic, assign) OmemoLoginState omemoLoginState;

// jid -> @[deviceID1, deviceID2]
@property (nonatomic, strong) NSMutableSet<NSNumber*>* ownReceivedDeviceList;
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSMutableSet<NSNumber*>*>* brokenSessions;
@property (nonatomic, strong) NSMutableSet<NSString*>* openPreKeySession;

@end

static const size_t MIN_OMEMO_KEYS = 25;
static const size_t MAX_OMEMO_KEYS = 100;

@implementation MLOMEMO

const int KEY_SIZE = 16;

-(MLOMEMO*) initWithAccount:(xmpp*) account;
{
    self = [super init];
    self.accountJid = account.connectionProperties.identity.jid;
    self.account = account;
    self.omemoLoginState = LoggedOut;
    self.openBundleFetchCnt = 0;
    self.closedBundleFetchCnt = 0;

    [self setupSignal];
    self.brokenSessions = [[NSMutableDictionary alloc] init];
    NSArray<NSNumber*>* ownCachedDevices = [[NSArray alloc] init];
    if([self createLocalIdentiyKeyPairIfNeeded:[[NSSet alloc] init]] == NO)
    {
        // local keys were already present
        ownCachedDevices = [self knownDevicesForAddressName:self.accountJid];
    }
    self.ownReceivedDeviceList = [[NSMutableSet alloc] initWithArray:ownCachedDevices];
    self.openPreKeySession = [[NSMutableSet alloc] init];

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(loggedIn:) name:kMLHasConnectedNotice object:nil];
    [nc addObserver:self selector:@selector(catchupDone:) name:kMonalFinishedCatchup object:nil];
    [nc addObserver:self selector:@selector(handleContactRemoved:) name:kMonalContactRemoved object:nil];

    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) loggedIn:(NSNotification*) notification
{
    xmpp* notiAccount = notification.object;
    if(!notiAccount || !self.account)
        return;
    if(self.account == notiAccount)
    {
        self.omemoLoginState = LoggedIn;
        // We don't have to clear ownReceivedDeviceList as it would have been cleared by a reconnect
        // rebuild broken omemo session after catchup
        [self rebuildSessions];
    }
}

-(void) catchupDone:(NSNotification*) notification
{
    xmpp* notiAccount = notification.object;
    if(!notiAccount || !self.account)
        return;
    if(self.account == notiAccount)
    {
        self.omemoLoginState = CatchupDone;
        if(!self.openBundleFetchCnt) // check if we have a session were we loggedIn
        {
            [self catchupAndOmemoDone];
        }
    }
}

-(void) handleContactRemoved:(NSNotification*) notification
{
    MLContact* removedContact = notification.userInfo[@"contact"];
    if(removedContact == nil || removedContact.accountId.intValue != self.account.accountNo.intValue)
       return;

    [self checkIfSessionIsStillNeeded:removedContact.contactJid isMuc:removedContact.isGroup];
}

-(void) catchupAndOmemoDone
{
    [self sendLocalDevicesIfNeeded];
    // send out
    for(NSString* preKeyJid in [self.openPreKeySession copy]) {
        [self sendKeyTransportElement:preKeyJid removeBrokenSessionForRid:nil];
    }
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalFinishedOmemoBundleFetch object:self userInfo:@{@"accountNo": self.account.accountNo}];
}

-(void) setupSignal
{
    self.monalSignalStore = [[MLSignalStore alloc] initWithAccountId:self.account.accountNo andAccountJid:self.accountJid];

    // signal store
    SignalStorage* signalStorage = [[SignalStorage alloc] initWithSignalStore:self.monalSignalStore];
    // signal context
    self.signalContext = [[SignalContext alloc] initWithStorage:signalStorage];

    // init MLPubSub handler
    [self.account.pubsub registerForNode:@"eu.siacs.conversations.axolotl.devicelist" withHandler:$newHandler(self, devicelistHandler)];
}

-(BOOL) createLocalIdentiyKeyPairIfNeeded:(NSSet<NSNumber*>*) ownDeviceIds
{
    if(self.monalSignalStore.deviceid == 0)
    {
        // signal helper
        SignalKeyHelper* signalHelper = [[SignalKeyHelper alloc] initWithContext:self.signalContext];

        do
        {
            // Generate a new device id
            self.monalSignalStore.deviceid = [signalHelper generateRegistrationId];
        } while([ownDeviceIds containsObject:[NSNumber numberWithUnsignedInt:self.monalSignalStore.deviceid]]);
        // Create identity key pair
        self.monalSignalStore.identityKeyPair = [signalHelper generateIdentityKeyPair];
        self.monalSignalStore.signedPreKey = [signalHelper generateSignedPreKeyWithIdentity:self.monalSignalStore.identityKeyPair signedPreKeyId:1];
        SignalAddress* address = [[SignalAddress alloc] initWithName:self.accountJid deviceId:self.monalSignalStore.deviceid];
        [self.monalSignalStore saveIdentity:address identityKey:self.monalSignalStore.identityKeyPair.publicKey];
        return YES;
    }
    return NO;
}

-(void) sendLocalDevicesIfNeeded
{
    DDLogInfo(@"sendLocalDevicesIfNeeded");
    if([self.ownReceivedDeviceList count] == 0) {
        // we need to publish a new devicelist if we did not receive our own list after a new connection
        DDLogInfo(@"Sending Bundle eventhough no new keys were generated");
        // generate new keys if needed and send them out
        [self sendOMEMODeviceWithForce:YES];
    }
    else
    {
        DDLogInfo(@"Publishing first OMEMO device");
        // Generate single use keys
        [self generateNewKeysIfNeeded:NO];
        [self sendOMEMODeviceWithForce:NO];
    }
}

$$instance_handler(devicelistHandler, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$ID(NSString*, type), $$ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    //type will be "publish", "retract", "purge" or "delete". "publish" and "retract" will have the data dictionary filled with id --> data pairs
    //the data for "publish" is the item node with the given id, the data for "retract" is always @YES
    MLAssert([node isEqualToString:@"eu.siacs.conversations.axolotl.devicelist"], @"pep node must be 'eu.siacs.conversations.axolotl.devicelist'");
    if([type isEqualToString:@"publish"])
    {
        MLXMLNode* publishedDevices = [data objectForKey:@"current"];
        if(publishedDevices && jid)
        {
            NSArray<NSNumber*>* deviceIds = [publishedDevices find:@"/{http://jabber.org/protocol/pubsub#event}item/{eu.siacs.conversations.axolotl}list/device@id|int"];
            NSSet<NSNumber*>* deviceSet = [[NSSet<NSNumber*> alloc] initWithArray:deviceIds];

            [self processOMEMODevices:deviceSet from:jid];
        }
    }
$$

-(void) sendOMEMOBundle
{
    if(self.monalSignalStore.deviceid == 0)
        return;
    [self publishKeysViaPubSubPreKeyId:[NSString stringWithFormat:@"%d",self.monalSignalStore.signedPreKey.preKeyId] withIdentityKey:self.monalSignalStore.identityKeyPair.publicKey withSignedPreKeySignature:self.monalSignalStore.signedPreKey.signature withSignedPreKeyPublic:self.monalSignalStore.signedPreKey.keyPair.publicKey  andPreKeys:[self.monalSignalStore readPreKeys] withDeviceId:self.monalSignalStore.deviceid];
}

/*
 * generates new omemo keys if we have less than MIN_OMEMO_KEYS left
 * returns YES if keys were generated and the new omemo bundle was send
 */
-(BOOL) generateNewKeysIfNeeded:(BOOL) force
{
    // generate new keys if less than MIN_OMEMO_KEYS are available
    unsigned int preKeyCount = [self.monalSignalStore getPreKeyCount];
    if(preKeyCount < MIN_OMEMO_KEYS)
    {
        SignalKeyHelper* signalHelper = [[SignalKeyHelper alloc] initWithContext:self.signalContext];

        // Generate new keys so that we have a total of MAX_OMEMO_KEYS keys again
        int lastPreyKedId = [self.monalSignalStore getHighestPreyKeyId];
        if(MAX_OMEMO_KEYS < preKeyCount)
        {
            DDLogWarn(@"OMEMO MAX_OMEMO_KEYs has changed: MAX: %zu current: %u", MAX_OMEMO_KEYS, preKeyCount);
            return NO;
        }
        size_t cntKeysNeeded = MAX_OMEMO_KEYS - preKeyCount;
        if(cntKeysNeeded == 0)
        {
            DDLogWarn(@"No new pre keys needed: force: %@", force ? @"YES" : @"NO");
            return NO;
        }
        // Start generating with keyId > last send key id
        self.monalSignalStore.preKeys = [signalHelper generatePreKeysWithStartingPreKeyId:(lastPreyKedId + 1) count:cntKeysNeeded];
        [self.monalSignalStore saveValues];

        // send out new omemo bundle
        [self sendOMEMOBundle];
        return YES;
    }
    return NO;
}

-(void) queryOMEMOBundleFrom:(NSString*) jid andDevice:(NSString*) deviceid
{
    NSString* bundleNode = [NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%@", deviceid];

    self.openBundleFetchCnt++;
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateBundleFetchStatus object:self userInfo:@{
        @"accountNo": self.account.accountNo,
        @"completed": @(self.closedBundleFetchCnt),
        @"all": @(self.openBundleFetchCnt + self.closedBundleFetchCnt)
    }];
    [self.account.pubsub fetchNode:bundleNode from:jid withItemsList:nil andHandler:$newHandler(self, handleBundleFetchResult, $ID(rid, deviceid))];
}

$$instance_handler(handleBundleFetchResult, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data), $$ID(NSString*, rid))
    if(!success)
    {
        if(errorIq)
            DDLogError(@"Could not fetch bundle from %@: rid: %@ - %@", jid, rid, errorIq);
        else if(errorReason)
            DDLogError(@"Could not fetch bundle from %@: rid: %@ - %@", jid, rid, errorReason);
        
        SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:rid.intValue];
        [self.monalSignalStore markDeviceAsDeleted:address];
    }
    else
    {
        // check that a corresponding buddy exists -> prevent foreign key errors
        MLXMLNode* receivedKeys = [data objectForKey:@"current"];
        if(!receivedKeys && data.count == 1)
        {
            // some clients do not use <item id="current">
            receivedKeys = [[data allValues] firstObject];
        }
        else if(!receivedKeys && data.count > 1)
        {
            DDLogWarn(@"More than one bundle item found from %@ rid: %@", jid, rid);
        }
        if(receivedKeys)
        {
            [self processOMEMOKeys:receivedKeys forJid:jid andRid:rid];
        }
    }
    
    //this has to be done even in error cases!
    if(self.openBundleFetchCnt > 1 && self.omemoLoginState >= LoggedIn)
    {
        self.openBundleFetchCnt--;
        self.closedBundleFetchCnt++;
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateBundleFetchStatus object:self userInfo:@{
            @"accountNo": self.account.accountNo,
            @"completed": @(self.closedBundleFetchCnt),
            @"all": @(self.openBundleFetchCnt + self.closedBundleFetchCnt)
        }];
    }
    else
    {
        self.openBundleFetchCnt = 0;
        self.closedBundleFetchCnt = 0;
        if(self.omemoLoginState == CatchupDone)
        {
            [self catchupAndOmemoDone];
        }
    }
$$

-(void) queryOMEMODevices:(NSString*) jid
{
    [self.account.pubsub subscribeToNode:@"eu.siacs.conversations.axolotl.devicelist" onJid:jid withHandler:$newHandler(self, handleDevicelistSubscribe)];
    // fetch newest devicelist
    [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:jid withItemsList:nil andHandler:$newHandler(self, handleManualDevices)];
}

$$instance_handler(handleDevicelistSubscribe, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(success == NO)
    {
        if(errorIq)
            DDLogError(@"Error while subscribe to omemo deviceslist from: %@ - %@", jid, errorIq);
        else
            DDLogError(@"Error while subscribe to omemo deviceslist from: %@ - %@", jid, errorReason);
    }
    // TODO: improve error handling
$$

$$instance_handler(handleDevicelistUnsubscribe, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    if(success == NO)
    {
        if(errorIq)
            DDLogError(@"Error while unsubscribing omemo deviceslist from: %@ - %@", jid, errorIq);
        else
            DDLogError(@"Error while unsubscribing omemo deviceslist from: %@ - %@", jid, errorReason);
    }
    // TODO: improve error handling
$$

$$instance_handler(handleManualDevices, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    if(success == NO)
    {
        if(errorIq)
            DDLogError(@"Error while fetching omemo devices: jid: %@ - %@", jid, errorIq);
        else
            DDLogError(@"Error while fetching omemo devices: jid: %@ - %@", jid, errorReason);
        // TODO: improve error handling
    }
    else
    {
        MLXMLNode* publishedDevices = [data objectForKey:@"current"];
        if(!publishedDevices && data.count == 1)
        {
            // some clients do not use <item id="current">
            publishedDevices = [[data allValues] firstObject];
        }
        else if(!publishedDevices && data.count > 1)
        {
            DDLogWarn(@"More than one devicelist item found from %@", jid);
        }
        if(publishedDevices)
        {
            NSArray<NSNumber*>* deviceIds = [publishedDevices find:@"/{http://jabber.org/protocol/pubsub}item/{eu.siacs.conversations.axolotl}list/device@id|int"];
            NSSet<NSNumber*>* deviceSet = [[NSSet<NSNumber*> alloc] initWithArray:deviceIds];

            [self processOMEMODevices:deviceSet from:jid];
        }
    }
$$

-(void) processOMEMODevices:(NSSet<NSNumber*>*) receivedDevices from:(NSString*) source
{
    if(receivedDevices)
    {
        MLAssert([self.accountJid caseInsensitiveCompare:self.account.connectionProperties.identity.jid] == NSOrderedSame, @"connection jid should be equal to the senderJid");

        NSArray<NSNumber*>* existingDevices = [self.monalSignalStore knownDevicesWithValidSessionEntryForName:source];

        // query omemo bundles from devices that are not in our signalStorage
        // TODO: queryOMEMOBundleFrom when sending first msg without session
        for(NSNumber* deviceId in receivedDevices)
        {
            SignalAddress* address = [[SignalAddress alloc] initWithName:source deviceId:deviceId.intValue];
            // remove mark that the device was not found in the devicelist
            [self.monalSignalStore removeDeviceDeletedMark:address];

            if(![existingDevices containsObject:deviceId])
            {
                [self queryOMEMOBundleFrom:source andDevice:[deviceId stringValue]];
            }
        }
        // remove devices from our signalStorage when they are no longer published
        for(NSNumber* deviceId in existingDevices)
        {
            if(![receivedDevices containsObject:deviceId])
            {
                // only delete other devices from signal store && keep our own entry
                if(!([source isEqualToString:self.accountJid] && deviceId.unsignedIntValue == self.monalSignalStore.deviceid))
                {
                    SignalAddress* address = [[SignalAddress alloc] initWithName:source deviceId:deviceId.intValue];
                    [self.monalSignalStore markDeviceAsDeleted:address];
                }
            }
        }
        // remove broken rids that are no longer available
        NSMutableSet<NSNumber*>* brokenContactRids = [self.brokenSessions objectForKey:source];
        if(brokenContactRids)
        {
            for(NSNumber* brokenRid in brokenContactRids) {
                if(![receivedDevices containsObject:brokenRid]) {
                    [brokenContactRids removeObject:brokenRid];
                }
            }
            [self.brokenSessions setObject:brokenContactRids forKey:source];
        }

        // Send our own device id when it is missing on the server
        if(!source || [source caseInsensitiveCompare:self.accountJid] == NSOrderedSame)
        {
            if(receivedDevices.count > 0)
            {
                // save own receivedDevices for catchupDone handling
                [self.ownReceivedDeviceList setSet:receivedDevices];
            }
            else
            {
                // list was empty -> remove all devices from local list
                // next if will ensure that eventually our device id is published
                [self.ownReceivedDeviceList removeAllObjects];
            }
            if(self.omemoLoginState == CatchupDone)
            {
                // the catchup done handler or the bundleFetch handler will send our own devices while logging in
                [self sendOMEMODeviceWithForce:NO];
            }
        }
    }
}

-(BOOL) knownDevicesForAddressNameExist:(NSString*) addressName
{
    return ([[self.monalSignalStore knownDevicesForAddressName:addressName] count] > 0);
}

-(NSArray<NSNumber*>*) knownDevicesForAddressName:(NSString*) addressName
{
    return [self.monalSignalStore knownDevicesForAddressName:addressName];
}

-(BOOL) isTrustedIdentity:(SignalAddress*)address identityKey:(NSData*)identityKey
{
    return [self.monalSignalStore isTrustedIdentity:address identityKey:identityKey];
}

-(NSNumber*) getTrustLevel:(SignalAddress*)address identityKey:(NSData*)identityKey
{
    return [self.monalSignalStore getTrustLevel:address identityKey:identityKey];
}

-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress*)address
{
    [self.monalSignalStore updateTrust:trust forAddress:address];
}

-(void) untrustAllDevicesFrom:(NSString*) jid
{
    [self.monalSignalStore untrustAllDevicesFrom:jid];
}

-(NSData*) getIdentityForAddress:(SignalAddress*) address
{
    return [self.monalSignalStore getIdentityForAddress:address];
}

-(void) sendOMEMODeviceWithForce:(BOOL) force
{
    // Check if our own device string is already in our set
    if(![self.ownReceivedDeviceList containsObject:[NSNumber numberWithInt:self.monalSignalStore.deviceid]] || force)
    {
        DDLogInfo(@"Publishing OMEMO Devices with Force %u", force);
        [self.ownReceivedDeviceList addObject:[NSNumber numberWithInt:self.monalSignalStore.deviceid]];
        // generate new keys if we are already publishing a new bundle
        if([self generateNewKeysIfNeeded:YES] == NO)
        {
            [self sendOMEMOBundle];
        }
        [self publishDevicesViaPubSub:self.ownReceivedDeviceList];
    }
}

-(void) processOMEMOKeys:(MLXMLNode*) item forJid:(NSString*) jid andRid:(NSString*) ridString
{
    MLAssert(self.signalContext != nil, @"self.signalContext must not be nil");
    if(!ridString)
        return;
    NSNumber* rid = @([ridString intValue]);
    if(rid == nil)
        return;

    NSArray* bundles = [item find:@"{eu.siacs.conversations.axolotl}bundle"];

    // there should only be one bundle per device
    if([bundles count] != 1) {
        return;
    }
    MLXMLNode* bundle = [bundles firstObject];

    // parse
    NSData* signedPreKeyPublic = [bundle findFirst:@"signedPreKeyPublic#|base64"];
    NSString* signedPreKeyPublicId = [bundle findFirst:@"signedPreKeyPublic@signedPreKeyId"];
    NSData* signedPreKeySignature = [bundle findFirst:@"signedPreKeySignature#|base64"];
    NSData* identityKey = [bundle findFirst:@"identityKey#|base64"];

    if(!signedPreKeyPublic || !signedPreKeyPublicId || !signedPreKeySignature || !identityKey)
        return;

    uint32_t device = (uint32_t)[rid intValue];
    SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:device];
    SignalSessionBuilder* builder = [[SignalSessionBuilder alloc] initWithAddress:address context:self.signalContext];
    NSArray<NSNumber*>* preKeyIds = [bundle find:@"prekeys/preKeyPublic@preKeyId|int"];

    if(preKeyIds == nil || preKeyIds.count == 0)
    {
        DDLogWarn(@"Could not create array of preKeyIds");
        return;
    }
    // parse preKeys
    const uint32_t preKeyIdsCnt = (uint32_t)preKeyIds.count;
    unsigned long processedKeysIdx = 0;
    do
    {
        // select random preKey and try to import it
        const uint32_t preKeyIdxToTest = arc4random_uniform(preKeyIdsCnt);
        // load preKey
        NSNumber* preKeyId = preKeyIds[preKeyIdxToTest];
        if(preKeyId == nil)
            continue;;
        NSData* key = [bundle findFirst:@"prekeys/preKeyPublic<preKeyId=%@>#|base64", preKeyId];
        if(!key)
            continue;

        DDLogDebug(@"Generating keyBundle for jid: %@ rid: %@ and key id %@...", jid, ridString, preKeyId);
        NSError* error;
        SignalPreKeyBundle* keyBundle = [[SignalPreKeyBundle alloc] initWithRegistrationId:0
                                                                    deviceId:device
                                                                    preKeyId:[preKeyId intValue]
                                                                    preKeyPublic:key
                                                                    signedPreKeyId:signedPreKeyPublicId.intValue
                                                                    signedPreKeyPublic:signedPreKeyPublic
                                                                    signature:signedPreKeySignature
                                                                    identityKey:identityKey
                                                                    error:&error];
        if(error || !keyBundle)
        {
            DDLogWarn(@"Error creating preKeyBundle: %@", error);
            continue;
        }
        [builder processPreKeyBundle:keyBundle error:&error];
        if(error)
        {
            DDLogWarn(@"Error adding preKeyBundle: %@", error);
            continue;
        }
        // found a key
        // Build new session when a device session is marked as broken
        [self sendKeyTransportElement:jid removeBrokenSessionForRid:rid];
        break;
    } while(++processedKeysIdx <= preKeyIds.count);
}

-(void) sendKeyTransportElement:(NSString*) jid removeBrokenSessionForRid:(NSNumber* _Nullable) rid
{
    [self.openPreKeySession removeObject:jid];

    // The needed device bundle for this contact/device was fetched
    // Send new keys
    XMPPMessage* messageNode = [[XMPPMessage alloc] init];
    [messageNode.attributes setObject:jid forKey:@"to"];
    [messageNode.attributes setObject:kMessageChatType forKey:@"type"];

    // Send KeyTransportElement only to the one device (overrideDevices)
    [self encryptMessage:messageNode withMessage:nil toContact:jid];
    DDLogDebug(@"Sending KeyTransportElement to jid: %@", jid);
    [self.account send:messageNode];

    if(rid != nil) {
        NSMutableSet<NSNumber*>* brokenContactRids = [self.brokenSessions objectForKey:jid];
        if(brokenContactRids) {
            if([brokenContactRids containsObject:rid]) {
                [brokenContactRids removeObject:rid];
            }
            [self.brokenSessions setObject:brokenContactRids forKey:jid];
        }
    }
}

-(void) addEncryptionKeyForAllDevices:(NSArray*) devices encryptForJid:(NSString*) encryptForJid withEncryptedPayload:(MLEncryptedPayload*) encryptedPayload withXMLHeader:(MLXMLNode*) xmlHeader {
    // Encrypt message for all devices known from the recipient
    for(NSNumber* device in devices)
    {
        // Do not encrypt for our own device
        if(device.unsignedIntValue == self.monalSignalStore.deviceid && [encryptForJid isEqualToString:self.accountJid]) {
            continue;
        }
        SignalAddress* address = [[SignalAddress alloc] initWithName:encryptForJid deviceId:(uint32_t)device.intValue];

        NSData* identity = [self.monalSignalStore getIdentityForAddress:address];
        if(!identity)
        {
            DDLogWarn(@"Could not get Identity for: %@ device id %@", encryptForJid, device);
            continue;
        }
        // Only add encryption key for devices that are trusted
        if([self.monalSignalStore isTrustedIdentity:address identityKey:identity])
        {
            SignalSessionCipher* cipher = [[SignalSessionCipher alloc] initWithAddress:address context:self.signalContext];
            NSError* error;
            SignalCiphertext* deviceEncryptedKey = [cipher encryptData:encryptedPayload.key error:&error];
            if(error)
            {
                DDLogWarn(@"Error while adding encryption key for jid: %@ device: %@ error: %@", encryptForJid, device, error);
                [self needNewSessionForContact:encryptForJid andDevice:device];
                continue;
            }
            [xmlHeader addChildNode:[[MLXMLNode alloc] initWithElement:@"key" withAttributes:@{
                @"rid": [NSString stringWithFormat:@"%@", device],
                @"prekey": (deviceEncryptedKey.type == SignalCiphertextTypePreKeyMessage ? @"1" : @"0"),
            } andChildren:@[] andData:[HelperTools encodeBase64WithData:deviceEncryptedKey.data]]];
        }
    }
}

-(void) encryptMessage:(XMPPMessage*) messageNode withMessage:(NSString*) message toContact:(NSString*) toContact
{
    MLAssert(self.signalContext != nil, @"signalContext should be inited.");

    if(message)
        [messageNode setBody:@"[This message is OMEMO encrypted]"];
    else
    {
        // KeyTransportElements should not contain a body
        [messageNode setStoreHint];
    }
    NSMutableSet<NSString*>* recipients = [[NSMutableSet alloc] init];
    if([[DataLayer sharedInstance] isBuddyMuc:toContact forAccount:self.account.accountNo])
    {
        for(NSDictionary* participant in [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:toContact forAccountId:self.account.accountNo])
        {
            if(participant[@"participant_jid"])
                [recipients addObject:participant[@"participant_jid"]];
            else if(participant[@"member_jid"])
                [recipients addObject:participant[@"member_jid"]];
        }
    }
    else
    {
        [recipients addObject:toContact];
    }
    NSMutableDictionary<NSString*, NSArray<NSNumber*>*>* contactDeviceMap = [[NSMutableDictionary alloc] init];
    for(NSString* recipient in recipients)
    {
        //contactDeviceMap
        NSArray<NSNumber*>* recipientDevices = [self.monalSignalStore knownDevicesForAddressName:recipient];
        if(recipientDevices && recipientDevices.count > 0)
            [contactDeviceMap setObject:recipientDevices forKey:recipient];
    }
    NSArray<NSNumber*>* myDevices = [self.monalSignalStore knownDevicesForAddressName:self.accountJid];

    // Check if we found omemo keys from the recipient
    if(contactDeviceMap.count > 0)
    {
        MLXMLNode* encrypted = [[MLXMLNode alloc] initWithElement:@"encrypted" andNamespace:@"eu.siacs.conversations.axolotl"];

        MLEncryptedPayload* encryptedPayload;
        if(message)
        {
            // Encrypt message
            NSData* messageBytes = [message dataUsingEncoding:NSUTF8StringEncoding];
            encryptedPayload = [AESGcm encrypt:messageBytes keySize:KEY_SIZE];
            if(encryptedPayload == nil)
            {
                DDLogWarn(@"Could not encrypt message: AESGcm error");
                return;
            }
            [encrypted addChildNode:[[MLXMLNode alloc] initWithElement:@"payload" andData:[HelperTools encodeBase64WithData:encryptedPayload.body]]];
        }
        else
        {
            // There is no message that can be encrypted -> create new session keys
            NSData* newKey = [AESGcm genKey:KEY_SIZE];
            NSData* newIv = [AESGcm genIV];
            if(newKey == nil || newIv == nil)
            {
                DDLogWarn(@"Could not create key or iv");
                return;
            }
            encryptedPayload = [[MLEncryptedPayload alloc] initWithKey:newKey iv:newIv];
            if(encryptedPayload == nil)
            {
                DDLogWarn(@"Could not encrypt message: AESGcm error");
                return;
            }
        }

        // Get own device id
        MLXMLNode* header = [[MLXMLNode alloc] initWithElement:@"header" withAttributes:@{
            @"sid": [NSString stringWithFormat:@"%d", self.monalSignalStore.deviceid],
        } andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"iv" andData:[HelperTools encodeBase64WithData:encryptedPayload.iv]],
        ] andData:nil];

        // add encryption for all of our recipients's devices
        for(NSString* recipient in contactDeviceMap)
        {
            [self addEncryptionKeyForAllDevices:contactDeviceMap[recipient] encryptForJid:recipient withEncryptedPayload:encryptedPayload withXMLHeader:header];
        }
        // add encryption fro all of our own device
        [self addEncryptionKeyForAllDevices:myDevices encryptForJid:self.accountJid withEncryptedPayload:encryptedPayload withXMLHeader:header];

        [encrypted addChildNode:header];
        [messageNode addChildNode:encrypted];
    }
}

-(void) needNewSessionForContact:(NSString*) contact andDevice:(NSNumber*) deviceId
{
    NSMutableSet<NSNumber*>* contactBrokenRids = [self.brokenSessions objectForKey:contact];
    if(!contactBrokenRids)
    {
        // first broken session for contact -> create new set
        contactBrokenRids = [[NSMutableSet<NSNumber*> alloc] init];
    }
    // add device to broken session contact set
    [contactBrokenRids addObject:deviceId];

    if(self.omemoLoginState == CatchupDone) {
        [self rebuildSessions];
    }
}



// called after a new MUC member was added
-(void) checkIfMucMemberHasExistingSession:(NSString*) buddyJid
{
    if([self.monalSignalStore sessionsExistForBuddy:buddyJid] == NO)
    {
        [self queryOMEMODevices:buddyJid];
    }
}

// called after a buddy was deleted from roster OR after a MUC member was removed
-(void) checkIfSessionIsStillNeeded:(NSString*) buddyJid isMuc:(BOOL) isMuc
{
    NSMutableSet<NSString*>* danglingJids = [[NSMutableSet alloc] init];
    if(isMuc == YES)
        danglingJids = [[NSMutableSet alloc] initWithSet:[self.monalSignalStore removeDanglingMucSessions]];
    else if([self.monalSignalStore checkIfSessionIsStillNeeded:buddyJid] == NO)
            [danglingJids addObject:buddyJid];

    [self unsubscribeFromDanglingJids:danglingJids];
}

-(void) unsubscribeFromDanglingJids:(NSSet<NSString*>*) danglingJids
{
    for(NSString* jid in danglingJids)
    {
        [self.account.pubsub unsubscribeFromNode:@"eu.siacs.conversations.axolotl.devicelist" forJid:jid withHandler:$newHandler(self, handleDevicelistUnsubscribe)];
    }
}

-(void) rebuildSessions
{
    if(self.omemoLoginState < CatchupDone) {
        DDLogInfo(@"Ignoring rebuildSessionsstate %u", self.omemoLoginState);
        return;
    }
    if([self.brokenSessions count] == 0 && [self generateNewKeysIfNeeded:NO] == YES) {
        return;
    }
    for(NSString* contactJid in self.brokenSessions) {
        NSSet* rids = [self.brokenSessions objectForKey:contactJid];
        for(NSNumber* rid in rids) {
            if(rid.unsignedIntValue == self.monalSignalStore.deviceid)
            {
                // We should not generate a new session to our own device
                continue;
            }

            SignalAddress* address = [[SignalAddress alloc] initWithName:contactJid deviceId:(uint32_t)rid.intValue];

            // mark session as broken
            [self.monalSignalStore markSessionAsBroken:address];
        }
        // query omemo devices of broken contact
        [self queryOMEMODevices:contactJid];

        // request device bundle again -> check for new preKeys
        // use received preKeys to build new session
        // [self queryOMEMOBundleFrom:contact andDevice:deviceId.stringValue];
        // rebuild session when preKeys of the requested bundle arrived
    }
}

-(NSString* _Nullable) decryptMessage:(XMPPMessage*) messageNode withMucParticipantJid:(NSString* _Nullable) mucParticipantJid
{
    if(![messageNode check:@"{eu.siacs.conversations.axolotl}encrypted/header"])
    {
        DDLogDebug(@"DecryptMessage called but the message has no encryption header");
        return nil;
    }
    BOOL isKeyTransportElement = ![messageNode check:@"{eu.siacs.conversations.axolotl}encrypted/payload"];

    NSNumber* sid = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/header@sid|int"];
    NSString* senderJid = nil;
    if([messageNode check:@"/<type=groupchat>"])
    {
        if(mucParticipantJid == nil)
        {
            DDLogError(@"Could not get muc participant jid and corresponding signal address of muc participant '%@': %@", messageNode.from, mucParticipantJid);
#ifdef IS_ALPHA
            return [NSString stringWithFormat:@"Could not get muc participant jid and corresponding signal address of muc participant '%@': %@", messageNode.from, mucParticipantJid];
#else
            return nil;
#endif
        }
        else
            senderJid = mucParticipantJid;
    }
    else
        senderJid = messageNode.fromUser;

    SignalAddress* address = [[SignalAddress alloc] initWithName:senderJid deviceId:(uint32_t)sid.intValue];

    if(!self.signalContext)
    {
        DDLogError(@"Missing signal context");
        return NSLocalizedString(@"Error decrypting message", @"");
    }
    // check if we received our own bundle
    if([senderJid isEqualToString:self.accountJid] && sid.unsignedIntValue == self.monalSignalStore.deviceid)
    {
        // Nothing to do
        return nil;
    }

    NSMutableSet<NSNumber*>* contactBrokenRids = [self.brokenSessions objectForKey:senderJid];
    if(contactBrokenRids && [contactBrokenRids containsObject:sid]) {
#ifdef IS_ALPHA
        return @"Dedupl. broken session error";
#else
        return nil;
#endif
    }
    NSString* deviceKeyPath = [NSString stringWithFormat:@"{eu.siacs.conversations.axolotl}encrypted/header/key<rid=%u>#|base64", self.monalSignalStore.deviceid];
    NSString* deviceKeyPathPreKey = [NSString stringWithFormat:@"{eu.siacs.conversations.axolotl}encrypted/header/key<rid=%u>@prekey|bool", self.monalSignalStore.deviceid];

    NSData* messageKey = [messageNode findFirst:deviceKeyPath];
    BOOL devicePreKey = [[messageNode findFirst:deviceKeyPathPreKey] boolValue];
    DDLogVerbose(@"Decrypting using:\n%@ --> %@\n%@ --> %@", deviceKeyPath, messageKey, deviceKeyPathPreKey, devicePreKey ? @"YES" : @"NO");

    if(!messageKey && isKeyTransportElement)
    {
        DDLogVerbose(@"Received KeyTransportElement without our own rid included --> Ignore it");
        // Received KeyTransportElement without our own rid included
        // Ignore it
        return nil;
    }
    else if(!messageKey)
    {
        DDLogError(@"Message was not encrypted for this device: %d", self.monalSignalStore.deviceid);
        [self needNewSessionForContact:senderJid andDevice:sid];
        return [NSString stringWithFormat:NSLocalizedString(@"Message was not encrypted for this device. Please make sure the sender trusts deviceid %d and that they have you as a contact.", @""), self.monalSignalStore.deviceid];
    }
    else
    {
        // subscribe to remote devicelist if no session exists yet
        [self checkIfMucMemberHasExistingSession:senderJid];

        SignalSessionCipher* cipher = [[SignalSessionCipher alloc] initWithAddress:address context:self.signalContext];
        SignalCiphertextType messagetype;

        // Check if message is encrypted with a prekey
        if(devicePreKey)
            messagetype = SignalCiphertextTypePreKeyMessage;
        else
            messagetype = SignalCiphertextTypeMessage;

        NSData* decoded = messageKey;

        SignalCiphertext* ciphertext = [[SignalCiphertext alloc] initWithData:decoded type:messagetype];
        NSError* error;
        NSData* decryptedKey = [cipher decryptCiphertext:ciphertext error:&error];
        if(error != nil)
        {
            DDLogError(@"Could not decrypt to obtain key: %@", error);
            [self needNewSessionForContact:senderJid andDevice:sid];
#ifdef IS_ALPHA
            if(isKeyTransportElement)
                return [NSString stringWithFormat:@"There was an error decrypting this encrypted KEY TRANSPORT message (Signal error). To resolve this, try sending an encrypted message to this person. (%@)", error];
#endif
            if(!isKeyTransportElement)
                return [NSString stringWithFormat:NSLocalizedString(@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person. (%@)", @""), error];
            return nil;
        }
        NSData* key;
        NSData* auth;

        if(decryptedKey == nil)
        {
            DDLogError(@"Could not decrypt to obtain key.");
            [self needNewSessionForContact:senderJid andDevice:sid];
#ifdef IS_ALPHA
            if(isKeyTransportElement)
                return @"There was an error decrypting this encrypted KEY TRANSPORT message (Signal error). To resolve this, try sending an encrypted message to this person.";
#endif
            if(!isKeyTransportElement)
                return NSLocalizedString(@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person.", @"");
            return nil;
        }
        else
        {
            if(messagetype == SignalCiphertextTypePreKeyMessage)
            {
                // check if we need to generate new preKeys
                if(self.omemoLoginState == CatchupDone) {
                    [self generateNewKeysIfNeeded:NO];
                    // build session
                    [self sendKeyTransportElement:senderJid removeBrokenSessionForRid:sid];
                }
                else {
                    [self.openPreKeySession addObject:senderJid];
                }
            }
            // save last successfull decryption time
            [self.monalSignalStore updateLastSuccessfulDecryptTime:address];
            if(contactBrokenRids) {
                [contactBrokenRids removeObject:sid];
                [self.brokenSessions setObject:contactBrokenRids forKey:senderJid];
            }

            // if no payload is available -> KeyTransportElement
            if(isKeyTransportElement)
            {
                // nothing to do
                DDLogInfo(@"KeyTransportElement received from jid: %@ device: %@", senderJid, sid);
#ifdef IS_ALPHA
                return [NSString stringWithFormat:@"ALPHA_DEBUG_MESSAGE: KeyTransportElement received from jid: %@ device: %@", senderJid, sid];
#else
                return nil;
#endif
            }

            if(decryptedKey.length == 16 * 2)
            {
                key = [decryptedKey subdataWithRange:NSMakeRange(0, 16)];
                auth = [decryptedKey subdataWithRange:NSMakeRange(16, 16)];
            }
            else
                key = decryptedKey;

            if(key)
            {
                NSString* ivStr = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/header/iv#"];
                NSString* encryptedPayload = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/payload#"];

                NSData* iv = [HelperTools dataWithBase64EncodedString:ivStr];
                if(iv.length != 12)
                {
                    DDLogError(@"Could not decrypt message: iv length: %lu", (unsigned long)iv.length);
                    return NSLocalizedString(@"Error while decrypting: iv.length != 12", @"");
                }
                if(encryptedPayload == nil)
                {
                    return NSLocalizedString(@"Error: Received message is empty", @"");
                }
                NSData* decodedPayload = [HelperTools dataWithBase64EncodedString:encryptedPayload];
                if(decodedPayload == nil || key == nil || iv == nil || auth == nil)
                {
                    DDLogError(@"Could not decrypt message: GCM params missing");
                    return NSLocalizedString(@"Error while decrypting", @"");
                }
                NSData* decData = [AESGcm decrypt:decodedPayload withKey:key andIv:iv withAuth:auth];
                if(!decData) {
                    DDLogError(@"Could not decrypt message with key that was decrypted. (GCM error)");
                    return NSLocalizedString(@"Encrypted message was sent in an older format Monal can't decrypt. Please ask them to update their client. (GCM error)", @"");
                }
                else
                {
                    DDLogInfo(@"Decrypted message passing bask string.");
                }
                NSString* messageString = [[NSString alloc] initWithData:decData encoding:NSUTF8StringEncoding];
                return messageString;
            }
            else
            {
                DDLogError(@"Could not get key");
                return NSLocalizedString(@"Could not decrypt message", @"");
            }
        }
    }
}


// create IQ messages
#pragma mark - signal
/**
 publishes a device.
 */
-(void) publishDevicesViaPubSub:(NSSet<NSNumber*>*) devices
{
    MLXMLNode* listNode = [[MLXMLNode alloc] initWithElement:@"list" andNamespace:@"eu.siacs.conversations.axolotl"];
    for(NSNumber* deviceNum in devices)
        [listNode addChildNode:[[MLXMLNode alloc] initWithElement:@"device" withAttributes:@{kId: [deviceNum stringValue]} andChildren:@[] andData:nil]];

    // publish devices via pubsub
    [self.account.pubsub publishItem:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{kId: @"current"} andChildren:@[
        listNode,
    ] andData:nil] onNode:@"eu.siacs.conversations.axolotl.devicelist" withConfigOptions:@{
        @"pubsub#persist_items": @"true",
        @"pubsub#access_model": @"open"
    }];
}

/**
 publishes signal keys and prekeys
 */
-(void) publishKeysViaPubSubPreKeyId:(NSString* _Nonnull) signedPreKeyId withIdentityKey:(NSData* _Nonnull) identityKey withSignedPreKeySignature:(NSData* _Nonnull) signedPreKeySignature withSignedPreKeyPublic:(NSData* _Nonnull) signedPreKeyPublic andPreKeys:(NSArray*) prekeys withDeviceId:(u_int32_t) deviceid
{
    MLXMLNode* prekeyNode = [[MLXMLNode alloc] initWithElement:@"prekeys"];
    for(SignalPreKey* prekey in prekeys)
    {
        MLXMLNode* preKeyPublic = [[MLXMLNode alloc] initWithElement:@"preKeyPublic" withAttributes:@{
            @"preKeyId": [NSString stringWithFormat:@"%d", prekey.preKeyId],
        } andChildren:@[] andData:[HelperTools encodeBase64WithData:prekey.keyPair.publicKey]];
        [prekeyNode addChildNode:preKeyPublic];
    };

    // send bundle via pubsub interface
    [self.account.pubsub publishItem:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{kId: @"current"} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"bundle" andNamespace:@"eu.siacs.conversations.axolotl" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"signedPreKeyPublic" withAttributes:@{
                @"signedPreKeyId": signedPreKeyId
            } andChildren:@[] andData:[HelperTools encodeBase64WithData: signedPreKeyPublic]],
            [[MLXMLNode alloc] initWithElement:@"signedPreKeySignature" withAttributes:@{} andChildren:@[] andData:[HelperTools encodeBase64WithData:signedPreKeySignature]],
            [[MLXMLNode alloc] initWithElement:@"identityKey" withAttributes:@{} andChildren:@[] andData:[HelperTools encodeBase64WithData:identityKey]],
            prekeyNode,
        ] andData:nil]
    ] andData:nil] onNode:[NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%u", deviceid] withConfigOptions:@{
        @"pubsub#persist_items": @"true",
        @"pubsub#access_model": @"open"
    }];
}

-(void) deleteDeviceForSource:(NSString*) source andRid:(unsigned int) rid
{
    // We should not delete our own device
    if([source isEqualToString:self.accountJid] && rid == self.monalSignalStore.deviceid)
        return;
    else if([source isEqualToString:self.accountJid])
        [self.ownReceivedDeviceList removeObject:[NSNumber numberWithUnsignedInt:rid]];

    SignalAddress* address = [[SignalAddress alloc] initWithName:source deviceId:rid];
    [self.monalSignalStore deleteDeviceforAddress:address];
    [self.monalSignalStore deleteSessionRecordForAddress:address];
}

-(void) clearAllSessionsForJid:(NSString*) jid
{
    NSArray<NSNumber*>* devices = [self knownDevicesForAddressName:jid];
    for(NSNumber* device in devices)
    {
        [self deleteDeviceForSource:jid andRid:device.intValue];
    }
    [self sendOMEMOBundle];
    [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:self.accountJid withItemsList:nil andHandler:$newHandler(self, handleManualDevices)];
    [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:jid withItemsList:nil andHandler:$newHandler(self, handleManualDevices)];
}

-(void) cleanup {
    NSSet<NSString*>* danglingJids = [self.monalSignalStore removeDanglingMucSessions];
    [self unsubscribeFromDanglingJids:danglingJids];
}

@end
