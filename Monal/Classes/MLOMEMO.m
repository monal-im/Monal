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

#include <stdlib.h>

@interface MLOMEMO ()

@property (atomic, strong) SignalContext* signalContext;

@property (nonatomic, strong) NSString* accountJid;

@property (nonatomic, strong) xmpp* account;
@property (nonatomic, strong) NSMutableSet<NSNumber*>* ownReceivedDeviceList;
@property (nonatomic, assign) BOOL loggedIn;

// jid -> @[deviceID1, deviceID2]
@property (nonatomic, strong) NSMutableDictionary* devicesWithBrokenSession;
@property (nonatomic, strong) NSMutableDictionary* devicesThatAreNotInDeviceList;
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
    self.ownReceivedDeviceList = [[NSMutableSet alloc] init];
    self.loggedIn = NO;
    self.hasCatchUpDone = NO;
    self.openBundleFetchCnt = 0;
    self.closedBundleFetchCnt = 0;

    self.devicesWithBrokenSession = [[NSMutableDictionary alloc] init];
    self.devicesThatAreNotInDeviceList = [[NSMutableDictionary alloc] init];

    [self setupSignal];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loggedIn:) name:kMLHasConnectedNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(catchupDone:) name:kMonalFinishedCatchup object:nil];

    return self;
}

-(void) loggedIn:(NSNotification *) notification {
    NSDictionary* dic = notification.object;
    if(!dic) return;
    NSString* accountNo = [dic objectForKey:@"AccountNo"];
    if(!accountNo) return;
    if([self.account.accountNo isEqualToString:accountNo]) {
        self.loggedIn = YES;
        // We don't have to clear ownReceivedDeviceList as it would have been cleared by a reconnect
    }
}

-(void) catchupDone:(NSNotification *) notification {
    xmpp* notiAccount = notification.object;
    if(!notiAccount) return;

    if([self.account.accountNo isEqualToString:notiAccount.accountNo]) {
        self.hasCatchUpDone = YES;
        if(!self.openBundleFetchCnt && self.loggedIn) // check if we have a session were we loggedIn
        {
            [self sendLocalDevicesIfNeeded];
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFinishedOmemoBundleFetch object:self];
        }
    }
}

-(void) setupSignal
{
    self.monalSignalStore = [[MLSignalStore alloc] initWithAccountId:self.account.accountNo];

    // signal store
    SignalStorage* signalStorage = [[SignalStorage alloc] initWithSignalStore:self.monalSignalStore];
    // signal context
    self.signalContext = [[SignalContext alloc] initWithStorage:signalStorage];

    // init MLPubSub handler
    [self.account.pubsub registerForNode:@"eu.siacs.conversations.axolotl.devicelist" withHandler:$newHandler(self, devicelistHandler)];

    [self createLocalIdentiyKeyPairIfNeeded:[[NSSet alloc] init]];
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
    if([self.ownReceivedDeviceList count] == 0) {
        // we need to publish a new devicelist if we did not receive our own list after a new connection
        // Generate single use keys
        [self generateNewKeysIfNeeded];
        [self sendOMEMOBundle];

        [self sendOMEMODeviceWithForce:YES];
        [self.ownReceivedDeviceList addObject:[NSNumber numberWithInt:(self.monalSignalStore.deviceid)]];
    }
    else
    {
        // Generate single use keys
        [self generateNewKeysIfNeeded];
        [self sendOMEMODevice:self.ownReceivedDeviceList force:NO];
    }
}

$$handler(devicelistHandler, $_ID(xmpp*, account), $_ID(NSString*, node), $_ID(NSString*, jid), $_ID(NSString*, type), $_ID(NSDictionary*, data))
    //type will be "publish", "retract", "purge" or "delete", "publish" and "retract" will have the data dictionary filled with id --> data pairs
    //the data for "publish" is the item node with the given id, the data for "retract" is always @YES
    assert([node isEqualToString:@"eu.siacs.conversations.axolotl.devicelist"]);
    if(type && [type isEqualToString:@"publish"]) {
        MLXMLNode* publishedDevices = [data objectForKey:@"current"];
        if(publishedDevices && jid) {
            NSArray<NSNumber*>* deviceIds = [publishedDevices find:@"/{http://jabber.org/protocol/pubsub#event}item/{eu.siacs.conversations.axolotl}list/device@id|int"];
            NSSet<NSNumber*>* deviceSet = [[NSSet<NSNumber*> alloc] initWithArray:deviceIds];

            [account.omemo processOMEMODevices:deviceSet from:jid];
        }
    }
$$

-(void) sendOMEMOBundle
{
    if(self.monalSignalStore.deviceid == 0)
        return;
    [self publishKeysViaPubSub:@{
        @"signedPreKeyPublic":self.monalSignalStore.signedPreKey.keyPair.publicKey,
        @"signedPreKeySignature":self.monalSignalStore.signedPreKey.signature,
        @"identityKey":self.monalSignalStore.identityKeyPair.publicKey,
        @"signedPreKeyId": [NSString stringWithFormat:@"%d",self.monalSignalStore.signedPreKey.preKeyId]
    } andPreKeys:[self.monalSignalStore readPreKeys] withDeviceId:self.monalSignalStore.deviceid];
}

/*
 * generates new omemo keys if we have less than MIN_OMEMO_KEYS left
 * returns YES if keys were generated and the new omemo bundle was send
 */
-(BOOL) generateNewKeysIfNeeded
{
    // generate new keys if less than MIN_OMEMO_KEYS are available
    int preKeyCount = [self.monalSignalStore getPreKeyCount];
    if(preKeyCount < MIN_OMEMO_KEYS)
    {
        SignalKeyHelper* signalHelper = [[SignalKeyHelper alloc] initWithContext:self.signalContext];

        // Generate new keys so that we have a total of MAX_OMEMO_KEYS keys again
        int lastPreyKedId = [self.monalSignalStore getHighestPreyKeyId];
        size_t cntKeysNeeded = MAX_OMEMO_KEYS - preKeyCount;
        // Start generating with keyId > last send key id
        self.monalSignalStore.preKeys = [signalHelper generatePreKeysWithStartingPreKeyId:(lastPreyKedId + 1) count:cntKeysNeeded];
        [self.monalSignalStore saveValues];

        // send out new omemo bundle
        [self sendOMEMOBundle];
        return YES;
    }
    return NO;
}

-(void) queryOMEMOBundleFrom:(NSString *) jid andDevice:(NSString *) deviceid
{
    NSString* bundleNode = [NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%@", deviceid];

    self.openBundleFetchCnt++;
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalUpdateBundleFetchStatus object:self userInfo:@{
        @"completed": @(self.closedBundleFetchCnt),
        @"all": @(self.openBundleFetchCnt + self.closedBundleFetchCnt)
    }];
    [self.account.pubsub fetchNode:bundleNode from:jid withItemsList:nil andHandler:$newHandler(self, handleBundleFetchResult, $ID(rid, deviceid))];
}

$$handler(handleBundleFetchResult, $_ID(xmpp*, account), $_ID(NSString*, jid), $_ID(XMPPIQ*, errorIq), $_ID(NSDictionary*, data), $_ID(NSString*, rid))
    if(errorIq)
    {
        DDLogError(@"Could not fetch bundle from %@: rid: %@ - %@", jid, rid, errorIq);
        NSString* bundleName = [errorIq findFirst:@"/{jabber:client}iq/{http://jabber.org/protocol/pubsub}pubsub/items<node=eu\\.siacs\\.conversations\\.axolotl\\.bundles:[0-9]+>@node"];
        if(bundleName)
        {
            NSString* ridFromIQ = [bundleName componentsSeparatedByString:@":"][1];
            if(ridFromIQ)
            {
                [account.omemo deleteDeviceForSource:jid andRid:rid.intValue];
                // We may have a broken session with a device that does not have a bundle anymore
                [account.omemo sendKeyTransportElementIfNeeded:jid removeBrokenSessionForRid:rid];
            }
        }
    }
    else
    {
        if(!rid)
            return;
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
            [account.omemo processOMEMOKeys:receivedKeys forJid:jid andRid:rid];
            [account.omemo markSessionAsStableForJid:jid andDevice:[NSNumber numberWithInt:[rid intValue]]];
        }
    }
    if(account.omemo.openBundleFetchCnt > 1 && account.omemo.loggedIn)
    {
        account.omemo.openBundleFetchCnt--;
        account.omemo.closedBundleFetchCnt++;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalUpdateBundleFetchStatus object:account.omemo userInfo:@{
            @"completed": @(account.omemo.closedBundleFetchCnt),
            @"all": @(account.omemo.openBundleFetchCnt + account.omemo.closedBundleFetchCnt)
        }];
    }
    else
    {
        account.omemo.openBundleFetchCnt = 0;
        account.omemo.closedBundleFetchCnt = 0;
        if(account.omemo.hasCatchUpDone && account.omemo.loggedIn)
        {
            [account.omemo sendLocalDevicesIfNeeded];
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFinishedOmemoBundleFetch object:self];
        }
    }
$$

-(void) markSessionAsStableForJid:(NSString*) jid andDevice:(NSNumber*) ridNum
{
    // Remove device from broken sessions if needed
    NSMutableSet<NSNumber*>* devicesWithBrokenSession = [self.devicesWithBrokenSession objectForKey:jid];
    if(devicesWithBrokenSession && [devicesWithBrokenSession containsObject:ridNum])
    {
        [devicesWithBrokenSession removeObject:ridNum];
        [self.devicesWithBrokenSession setObject:devicesWithBrokenSession forKey:jid];
    }
}

-(void) queryOMEMODevices:(NSString *) jid
{
    [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:jid withItemsList:nil andHandler:$newHandler(self, handleManualDevices)];
}

$$handler(handleManualDevices, $_ID(xmpp*, account), $_ID(NSString*, jid), $_ID(XMPPIQ*, errorIq), $_ID(NSDictionary*, data))
    if(errorIq)
    {
        DDLogWarn(@"Error while fetching omemo devices: jid: %@ - %@", jid, errorIq);
    }
    else
    {
        if(!jid)
            return;
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
        if(publishedDevices) {
            NSArray<NSNumber*>* deviceIds = [publishedDevices find:@"/{http://jabber.org/protocol/pubsub}item/{eu.siacs.conversations.axolotl}list/device@id|int"];
            NSSet<NSNumber*>* deviceSet = [[NSSet<NSNumber*> alloc] initWithArray:deviceIds];

            [account.omemo processOMEMODevices:deviceSet from:jid];
        }
    }
$$

-(void) processOMEMODevices:(NSSet<NSNumber*>*) receivedDevices from:(NSString *) source
{
    if(receivedDevices)
    {
        NSAssert([self.accountJid caseInsensitiveCompare:self.account.connectionProperties.identity.jid] == NSOrderedSame, @"connection jid should be equal to the senderJid");

        NSArray<NSNumber*>* existingDevices = [self.monalSignalStore knownDevicesForAddressName:source];

        // query omemo bundles from devices that are not in our signalStorage
        // TODO: queryOMEMOBundleFrom when sending first msg without session
        for(NSNumber* deviceId in receivedDevices)
        {
            if(![existingDevices containsObject:deviceId])
            {
                [self queryOMEMOBundleFrom:source andDevice:[deviceId stringValue]];
            }
            // unblock
            // TODO:
            NSMutableSet<NSNumber*>* devicesThatAreNotInList = [self.devicesThatAreNotInDeviceList objectForKey:source];
            if(devicesThatAreNotInList && [devicesThatAreNotInList containsObject:deviceId])
            {
                [devicesThatAreNotInList removeObject:deviceId];
                [self.devicesThatAreNotInDeviceList setObject:devicesThatAreNotInList forKey:source];
            }
        }
        
        // remove devices from our signalStorage when they are no longer published
        for(NSNumber* deviceId in existingDevices)
        {
            if(![receivedDevices containsObject:deviceId])
            {
                // only delete other devices from signal store && keep our own entry
                if(!([source isEqualToString:self.accountJid] && deviceId.intValue == self.monalSignalStore.deviceid))
                {
                    [self deleteDeviceForSource:source andRid:deviceId.intValue];
                }
            }
        }
        
        // TODO: delete deviceid from new session array
        // Send our own device id when it is missing on the server
        if(!source || [source caseInsensitiveCompare:self.accountJid] == NSOrderedSame)
        {
            if(receivedDevices.count > 0)
            {
                // save own receivedDevices for catchupDone handling
                [self.ownReceivedDeviceList unionSet:receivedDevices];
            }
            if(self.hasCatchUpDone == true && !self.openBundleFetchCnt)
            {
                // the catchup done handler or the bundleFetch handler will send our own devices while logging in
                [self sendOMEMODevice:receivedDevices force:NO];
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

-(void) deleteDeviceForSource:(NSString*) source andRid:(int) rid
{
    // We should not delete our own device
    if([source isEqualToString:self.accountJid] && rid == self.monalSignalStore.deviceid)
        return;

    SignalAddress* address = [[SignalAddress alloc] initWithName:source deviceId:rid];
    [self.monalSignalStore deleteDeviceforAddress:address];
    [self.monalSignalStore deleteSessionRecordForAddress:address];
}

-(BOOL) isTrustedIdentity:(SignalAddress*)address identityKey:(NSData*)identityKey
{
    return [self.monalSignalStore isTrustedIdentity:address identityKey:identityKey];
}

-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress*)address
{
    [self.monalSignalStore updateTrust:trust forAddress:address];
}

-(NSData *) getIdentityForAddress:(SignalAddress*)address
{
    return [self.monalSignalStore getIdentityForAddress:address];
}



-(void) sendOMEMODeviceWithForce:(BOOL) force
{
    NSArray* ownCachedDevices = [self knownDevicesForAddressName:self.accountJid];
    NSSet<NSNumber*>* ownCachedDevicesSet = [[NSSet alloc] initWithArray:ownCachedDevices];
    [self sendOMEMODevice:ownCachedDevicesSet force:force];
}

-(void) sendOMEMODevice:(NSSet<NSNumber*>*) receivedDevices force:(BOOL) force
{
    NSMutableSet<NSNumber*>* devices = [[NSMutableSet alloc] init];
    if(receivedDevices && [receivedDevices count] > 0)
    {
        [devices unionSet:receivedDevices];
    }

    // Check if our own device string is already in our set
    if(![devices containsObject:[NSNumber numberWithInt:self.monalSignalStore.deviceid]] || force)
    {
        [devices addObject:[NSNumber numberWithInt:self.monalSignalStore.deviceid]];
        [self sendOMEMOBundle];
        [self publishDevicesViaPubSub:devices];
    }
    if(devices.count > 0)
    {
        [self.ownReceivedDeviceList unionSet:devices];
    }
}

-(void) processOMEMOKeys:(MLXMLNode*) iqNode forJid:(NSString*) jid andRid:(NSString*) rid
{
    assert(self.signalContext);
    {
        if(!rid)
            return;

        NSArray* bundles = [iqNode find:@"/{http://jabber.org/protocol/pubsub}item/{eu.siacs.conversations.axolotl}bundle"];

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
            NSData* key = [bundle findFirst:[NSString stringWithFormat:@"prekeys/preKeyPublic<preKeyId=%@>#|base64", preKeyId]];
            if(!key)
                continue;

            DDLogDebug(@"Generating keyBundle for key id %@...", preKeyId);
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
            [self sendKeyTransportElementIfNeeded:jid removeBrokenSessionForRid:rid];
            break;
        } while (++processedKeysIdx <= preKeyIds.count);
    }
}

-(void) sendKeyTransportElementIfNeeded:(NSString*) jid removeBrokenSessionForRid:(NSString*) rid
{
    // Build new session when a device session is marked as broken
    NSMutableSet<NSNumber*>* devicesWithBrokenSession = [self.devicesWithBrokenSession objectForKey:jid];
    NSNumber* ridNum = [NSNumber numberWithInt:[rid intValue]];
    if(devicesWithBrokenSession && [devicesWithBrokenSession containsObject:ridNum])
    {
        // The needed device bundle for this contact/device was fetched
        // Send new keys
        XMPPMessage* messageNode = [[XMPPMessage alloc] init];
        [messageNode.attributes setObject:jid forKey:@"to"];
        [messageNode.attributes setObject:kMessageChatType forKey:@"type"];

        // Send KeyTransportElement only to the one device (overrideDevices)
        [self encryptMessage:messageNode withMessage:nil toContact:jid];
        DDLogDebug(@"Send KeyTransportElement to jid: %@", jid);
        if(self.account) [self.account send:messageNode];

        // Remove device from list
        [devicesWithBrokenSession removeObject:ridNum];
        [self.devicesWithBrokenSession setObject:devicesWithBrokenSession forKey:jid];
        DDLogDebug(@"Removed jid: %@, rid: %@ from devicesWithBrokenSession", jid, rid);
        if([devicesWithBrokenSession count] != 0) {
            return;
        }
    }
}

-(void) addEncryptionKeyForAllDevices:(NSArray*) devices encryptForJid:(NSString*) encryptForJid withEncryptedPayload:(MLEncryptedPayload*) encryptedPayload withXMLHeader:(MLXMLNode*) xmlHeader {
    // Encrypt message for all devices known from the recipient
    for(NSNumber* device in devices)
    {
        // Do not encrypt for our own device
        if(device.intValue == self.monalSignalStore.deviceid && [encryptForJid isEqualToString:self.accountJid]) {
            continue;
        }
        SignalAddress* address = [[SignalAddress alloc] initWithName:encryptForJid deviceId:(uint32_t)device.intValue];

        NSData* identity = [self.monalSignalStore getIdentityForAddress:address];

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
            MLXMLNode* keyNode = [[MLXMLNode alloc] initWithElement:@"key"];
            [keyNode.attributes setObject:[NSString stringWithFormat:@"%@", device] forKey:@"rid"];
            if(deviceEncryptedKey.type == SignalCiphertextTypePreKeyMessage)
            {
                [keyNode.attributes setObject:@"1" forKey:@"prekey"];
            }

            [keyNode setData:[HelperTools encodeBase64WithData:deviceEncryptedKey.data]];
            [xmlHeader.children addObject:keyNode];
        }
    }
}

-(void) encryptMessage:(XMPPMessage *)messageNode withMessage:(NSString *)message toContact:(NSString *)toContact
{
    [self encryptMessage:messageNode withMessage:message toContact:toContact overrideDevices:nil];
}

-(void) encryptMessage:(XMPPMessage*) messageNode withMessage:(NSString*) message toContact:(NSString*) toContact overrideDevices:(NSArray<NSNumber*>* _Nullable) overrideDevices
{
    NSAssert(self.signalContext, @"signalContext should be inited.");

    if(message)
        [messageNode setBody:@"[This message is OMEMO encrypted]"];
    else
    {
        // KeyTransportElements should not contain a body
        [messageNode setStoreHint];
    }

    NSArray* devices = [self.monalSignalStore knownDevicesForAddressName:toContact];
    NSArray* myDevices = [self.monalSignalStore knownDevicesForAddressName:self.accountJid];

    // Check if we found omemo keys from the recipient
    if(devices.count > 0 || overrideDevices.count > 0)
    {
        MLXMLNode* encrypted = [[MLXMLNode alloc] initWithElement:@"encrypted"];
        [encrypted.attributes setObject:@"eu.siacs.conversations.axolotl" forKey:kXMLNS];
        [messageNode.children addObject:encrypted];

        MLEncryptedPayload* encryptedPayload;
        if(message)
        {
            NSData* messageBytes = [message dataUsingEncoding:NSUTF8StringEncoding];

            // Encrypt message
            encryptedPayload = [AESGcm encrypt:messageBytes keySize:KEY_SIZE];
            if(encryptedPayload == nil)
            {
                DDLogWarn(@"Could not encrypt message: AESGcm error");
                return;
            }

            MLXMLNode* payload = [[MLXMLNode alloc] initWithElement:@"payload"];
            [payload setData:[HelperTools encodeBase64WithData:encryptedPayload.body]];
            [encrypted.children addObject:payload];
        } else {
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
        NSString* deviceid = [NSString stringWithFormat:@"%d", self.monalSignalStore.deviceid];
        MLXMLNode* header = [[MLXMLNode alloc] initWithElement:@"header"];
        [header.attributes setObject:deviceid forKey:@"sid"];
        [encrypted.children addObject:header];

        MLXMLNode* ivNode = [[MLXMLNode alloc] initWithElement:@"iv"];
        [ivNode setData:[HelperTools encodeBase64WithData:encryptedPayload.iv]];
        [header.children addObject:ivNode];

        if(!overrideDevices)
        {
            // normal encryption -> add encryption for all of our own devices as well as to all of our contact's devices
            [self addEncryptionKeyForAllDevices:devices encryptForJid:toContact withEncryptedPayload:encryptedPayload withXMLHeader:header];

            [self addEncryptionKeyForAllDevices:myDevices encryptForJid:self.accountJid withEncryptedPayload:encryptedPayload withXMLHeader:header];
        }
        else
        {
            // We sometimes need to send a message only to one specific device
            // all devices in overrideDevices must belong to a single jid.
            [self addEncryptionKeyForAllDevices:overrideDevices encryptForJid:toContact withEncryptedPayload:encryptedPayload withXMLHeader:header];
        }
    }
}

-(void) needNewSessionForContact:(NSString*) contact andDevice:(NSNumber*) deviceId
{
    [self sendOMEMOBundle];
    
    if(deviceId.intValue == self.monalSignalStore.deviceid)
    {
        // We should not generate a new session to our own device
        return;
    }

    // get set of broken device sessions for the given contact
    NSMutableSet<NSNumber*>* devicesWithInvalSession = [self.devicesWithBrokenSession objectForKey:contact];
    if(!devicesWithInvalSession)
    {
        // first broken session for contact -> create new set
        devicesWithInvalSession = [[NSMutableSet<NSNumber*> alloc] init];
    }
    // add device to broken session contact set
    if([devicesWithInvalSession containsObject:deviceId])
    {
        return;
    }
    [devicesWithInvalSession addObject:deviceId];
    [self.devicesWithBrokenSession setObject:devicesWithInvalSession forKey:contact];
    
    // TODO:
    NSMutableSet<NSNumber*>* devicesThatAreNotInList = [self.devicesThatAreNotInDeviceList objectForKey:contact];
    if(!devicesThatAreNotInList)
    {
        // first broken session for contact -> create new set
        devicesThatAreNotInList = [[NSMutableSet<NSNumber*> alloc] init];
    }
    // add device to broken session contact set
    if([devicesThatAreNotInList containsObject:deviceId])
    {
        return;
    }
    [devicesThatAreNotInList addObject:deviceId];
    [self.devicesThatAreNotInDeviceList setObject:devicesThatAreNotInList forKey:contact];

    // delete broken session from our storage
    SignalAddress* address = [[SignalAddress alloc] initWithName:contact deviceId:(uint32_t)deviceId.intValue];
    [self.monalSignalStore deleteSessionRecordForAddress:address];
    [self.monalSignalStore deleteDeviceforAddress:address];

    // DEBUG START
    if(![self.accountJid isEqualToString:contact])
    {
        [self queryOMEMODevices:self.accountJid];
    }
    [self queryOMEMODevices:contact];
    // DEBUG END
    
    // request device bundle again -> check for new preKeys
    // use received preKeys to build new session
    // [self queryOMEMOBundleFrom:contact andDevice:deviceId.stringValue];
    // rebuild session when preKeys of the requested bundle arrived
}

-(NSString *) decryptMessage:(XMPPMessage *) messageNode
{
    if(![messageNode check:@"{eu.siacs.conversations.axolotl}encrypted/header"])
    {
        DDLogDebug(@"DecryptMessage called but the message has no encryption header");
        return nil;
    }
    BOOL isKeyTransportElement = ![messageNode check:@"{eu.siacs.conversations.axolotl}encrypted/payload"];

    NSNumber* sid = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/header@sid|int"];
    SignalAddress* address = [[SignalAddress alloc] initWithName:messageNode.fromUser deviceId:(uint32_t)sid.intValue];
    if(!self.signalContext)
    {
        DDLogError(@"Missing signal context");
        return NSLocalizedString(@"Error decrypting message", @"");
    }
    // check if we received our own bundle
    if([messageNode.fromUser isEqualToString:self.accountJid] && sid.intValue == self.monalSignalStore.deviceid)
    {
        // Nothing to do
        return nil;
    }
    
    NSMutableSet<NSNumber*>* devicesThatAreNotInList = [self.devicesThatAreNotInDeviceList objectForKey:messageNode.fromUser];
    if(devicesThatAreNotInList && [devicesThatAreNotInList containsObject:sid]) {
#ifdef IS_ALPHA
        return @"ERROR: NEW ERROR";
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
        [self needNewSessionForContact:messageNode.fromUser andDevice:sid];
        return [NSString stringWithFormat:NSLocalizedString(@"Message was not encrypted for this device. Please make sure the sender trusts deviceid %d and that they have you as a contact.", @""), self.monalSignalStore.deviceid];
    }
    else
    {
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
        if(error) {
            DDLogError(@"Could not decrypt to obtain key: %@", error);
            [self needNewSessionForContact:messageNode.fromUser andDevice:sid];
            return [NSString stringWithFormat:@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person. (%@)", error];
        }
        NSData* key;
        NSData* auth;

        if(messagetype == SignalCiphertextTypePreKeyMessage)
        {
            // check if we need to generate new preKeys
            if(![self generateNewKeysIfNeeded]) {
                // send new bundle without the used preKey if no new keys were generated
                [self sendOMEMOBundle];
            }
            else {
                // nothing todo as generateNewKeysIfNeeded sends out the new bundle if new keys were generated
            }
        }

        if(!decryptedKey)
        {
            DDLogError(@"Could not decrypt to obtain key.");
            [self needNewSessionForContact:messageNode.fromUser andDevice:sid];
            return NSLocalizedString(@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person.", @"");
        }
        else
        {
            // We seem to have a valid session -> remove device from broken session list
            NSMutableSet<NSNumber*>* devicesWithBrokenSession = [self.devicesWithBrokenSession objectForKey:messageNode.fromUser];
            if(devicesWithBrokenSession && [devicesWithBrokenSession containsObject:sid])
            {
                // Remove device from list
                [devicesWithBrokenSession removeObject:sid];
                [self.devicesWithBrokenSession setObject:devicesWithBrokenSession forKey:messageNode.fromUser];
            }
            // if no payload is available -> KeyTransportElement
            if(isKeyTransportElement)
            {
                // nothing to do
                DDLogInfo(@"KeyTransportElement received from device: %@", sid);
#ifdef DEBUG_ALPHA
                return [NSString stringWithFormat:@"ALPHA_DEBUG_MESSAGE: KeyTransportElement received from device: %@", sid];
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
            {
                key = decryptedKey;
            }
            if(key){
                NSString* ivStr = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/header/iv#"];
                NSString* encryptedPayload = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/payload#"];

                NSData* iv = [HelperTools dataWithBase64EncodedString:ivStr];
                if(iv.length != 12)
                {
                    DDLogError(@"Could not decrypt message: iv length: %lu", (unsigned long)iv.length);
                    return NSLocalizedString(@"Error while decrypting: iv.length != 12", @"");
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
    MLXMLNode* itemNode = [[MLXMLNode alloc] initWithElement:@"item"];
    [itemNode.attributes setObject:@"current" forKey:kId];

    MLXMLNode* listNode = [[MLXMLNode alloc] init];
    listNode.element=@"list";
    [listNode.attributes setObject:@"eu.siacs.conversations.axolotl" forKey:kXMLNS];

    for(NSNumber* deviceNum in devices)
    {
        NSString* deviceid = [deviceNum stringValue];
        MLXMLNode* device = [[MLXMLNode alloc] init];
        device.element = @"device";
        [device.attributes setObject:deviceid forKey:kId];
        [listNode addChild:device];
    }
    [itemNode addChild:listNode];

    // publish devices via pubsub
    [self.account.pubsub publishItem:itemNode onNode:@"eu.siacs.conversations.axolotl.devicelist" withConfigOptions:@{
        @"pubsub#persist_items": @"true",
        @"pubsub#access_model": @"open"
    }];
}

/**
 publishes signal keys and prekeys
 */
-(void) publishKeysViaPubSub:(NSDictionary *) keys andPreKeys:(NSArray *) prekeys withDeviceId:(u_int32_t) deviceid
{
    MLXMLNode* itemNode = [[MLXMLNode alloc] init];
    itemNode.element = @"item";
    [itemNode.attributes setObject:@"current" forKey:kId];

    MLXMLNode* bundle = [[MLXMLNode alloc] init];
    bundle.element = @"bundle";
    [bundle.attributes setObject:@"eu.siacs.conversations.axolotl" forKey:kXMLNS];

    MLXMLNode* signedPreKeyPublic = [[MLXMLNode alloc] init];
    signedPreKeyPublic.element = @"signedPreKeyPublic";
    [signedPreKeyPublic.attributes setObject:[keys objectForKey:@"signedPreKeyId"] forKey:@"signedPreKeyId"];
    signedPreKeyPublic.data = [HelperTools encodeBase64WithData: [keys objectForKey:@"signedPreKeyPublic"]];
    [bundle addChild:signedPreKeyPublic];

    MLXMLNode* signedPreKeySignature = [[MLXMLNode alloc] init];
    signedPreKeySignature.element = @"signedPreKeySignature";
    signedPreKeySignature.data = [HelperTools encodeBase64WithData:[keys objectForKey:@"signedPreKeySignature"]];
    [bundle addChild:signedPreKeySignature];

    MLXMLNode* identityKey = [[MLXMLNode alloc] init];
    identityKey.element = @"identityKey";
    identityKey.data = [HelperTools encodeBase64WithData:[keys objectForKey:@"identityKey"]];
    [bundle addChild:identityKey];

    MLXMLNode* prekeyNode = [[MLXMLNode alloc] init];
    prekeyNode.element = @"prekeys";

    for(SignalPreKey* prekey in prekeys)
    {
        MLXMLNode* preKeyPublic = [[MLXMLNode alloc] init];
        preKeyPublic.element = @"preKeyPublic";
        [preKeyPublic.attributes setObject:[NSString stringWithFormat:@"%d", prekey.preKeyId] forKey:@"preKeyId"];
        preKeyPublic.data = [HelperTools encodeBase64WithData:prekey.keyPair.publicKey];
        [prekeyNode addChild:preKeyPublic];
    };

    [bundle addChild:prekeyNode];
    [itemNode addChild:bundle];

    // send bundle via pubsub interface
    [self.account.pubsub publishItem:itemNode onNode:[NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%u", deviceid] withConfigOptions:@{
        @"pubsub#persist_items": @"true",
        @"pubsub#access_model": @"open"
    }];
}

@end
