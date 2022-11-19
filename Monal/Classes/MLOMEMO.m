//
//  MLOMEMO.m
//  Monal
//
//  Created by Friedrich Altheide on 21.06.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#include <stdlib.h>
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

NS_ASSUME_NONNULL_BEGIN

static const size_t MIN_OMEMO_KEYS = 25;
static const size_t MAX_OMEMO_KEYS = 100;
static const int KEY_SIZE = 16;

@interface MLOMEMO ()
{
    OmemoState* _state;
}
@property (nonatomic, weak) xmpp* account;
@property (nonatomic, strong) MLSignalStore* monalSignalStore;
@property (nonatomic, strong) SignalContext* signalContext;
@property (nonatomic, strong) NSMutableSet<NSNumber*>* ownDeviceList;
@end

@implementation MLOMEMO

-(MLOMEMO*) initWithAccount:(xmpp*) account;
{
    self = [super init];
    self.account = account;
    self.monalSignalStore = [[MLSignalStore alloc] initWithAccountId:self.account.accountNo andAccountJid:self.account.connectionProperties.identity.jid];
    SignalStorage* signalStorage = [[SignalStorage alloc] initWithSignalStore:self.monalSignalStore];
    self.signalContext = [[SignalContext alloc] initWithStorage:signalStorage];
    self.openBundleFetchCnt = 0;
    self.closedBundleFetchCnt = 0;

    //create empty state (will be updated from [xmpp readState] before [self activate] is called
    self->_state = [OmemoState new];
    
    //read own devicelist from database
    self.ownDeviceList = [[self knownDevicesForAddressName:self.account.connectionProperties.identity.jid] mutableCopy];
    DDLogVerbose(@"Own devicelist for account %@ is now: %@", self.account, self.ownDeviceList);
    
    [self createLocalIdentiyKeyPairIfNeeded];
    
    return self;
}

-(void) activate
{
    //init pubsub devicelist handler
    [self.account.pubsub registerForNode:@"eu.siacs.conversations.axolotl.devicelist" withHandler:$newHandler(self, devicelistHandler)];
    
    //register notification handler
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleContactRemoved:) name:kMonalContactRemoved object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleHasLoggedIn:) name:kMLIsLoggedInNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleResourceBound:) name:kMLResourceBoundNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleCatchupDone:) name:kMonalFinishedCatchup object:nil];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) setState:(OmemoState*) state
{
    [self->_state updateWith:state];
}

-(OmemoState*) state
{
    return self->_state;
}

//updateIfIdNotEqual(self.contactJid, contact.contactJid);

-(NSSet<NSNumber*>*) knownDevicesForAddressName:(NSString*) addressName
{
    return [NSSet setWithArray:[self.monalSignalStore knownDevicesForAddressName:addressName]];
}

-(BOOL) createLocalIdentiyKeyPairIfNeeded
{
    if(self.monalSignalStore.deviceid == 0)
    {
        // signal key helper
        SignalKeyHelper* signalHelper = [[SignalKeyHelper alloc] initWithContext:self.signalContext];

        // Generate a new device id
        do {
            self.monalSignalStore.deviceid = [signalHelper generateRegistrationId];
        } while(self.monalSignalStore.deviceid == 0 || [self.ownDeviceList containsObject:[NSNumber numberWithUnsignedInt:self.monalSignalStore.deviceid]]);
        // Create identity key pair
        self.monalSignalStore.identityKeyPair = [signalHelper generateIdentityKeyPair];
        self.monalSignalStore.signedPreKey = [signalHelper generateSignedPreKeyWithIdentity:self.monalSignalStore.identityKeyPair signedPreKeyId:1];
        SignalAddress* address = [[SignalAddress alloc] initWithName:self.account.connectionProperties.identity.jid deviceId:self.monalSignalStore.deviceid];
        [self.monalSignalStore saveIdentity:address identityKey:self.monalSignalStore.identityKeyPair.publicKey];
        // do everything done in MLSignalStore init not already mimicked above
        [self.monalSignalStore cleanupKeys];
        [self.monalSignalStore reloadCachedPrekeys];
        // we generated a new identity
        return YES;
    }
    // we did not generate a new identity
    return NO;
}

-(void) handleContactRemoved:(NSNotification*) notification
{
#ifndef DISABLE_OMEMO
    MLContact* removedContact = notification.userInfo[@"contact"];
    if(removedContact == nil || removedContact.accountId.intValue != self.account.accountNo.intValue)
       return;

    [self checkIfSessionIsStillNeeded:removedContact.contactJid isMuc:removedContact.isGroup];
#endif
}

-(void) handleHasLoggedIn:(NSNotification*) notification
{
    //this event will be called as soon as we are successfully authenticated, but BEFORE handleResourceBound: will be called
    //NOTE: handleResourceBound: won't be called for smacks resumptions at all
#ifndef DISABLE_OMEMO
    if(self.account.accountNo.intValue == ((xmpp*)notification.object).accountNo.intValue)
    {
        //mark catchup as running (will be smacks catchup or mam catchup)
        //this will queue any session repair attempts and key transport elements
        self.state.catchupDone = NO;
    }
#endif
}

-(void) handleResourceBound:(NSNotification*) notification
{
    //this event will be called as soon as we are bound, but BEFORE mam catchup happens
    //NOTE: this event won't be called for smacks resumes!
#ifndef DISABLE_OMEMO
    if(self.account.accountNo.intValue == ((xmpp*)notification.object).accountNo.intValue)
    {
        DDLogInfo(@"We did a non-smacks-resume reconnect, resetting some of our state...");
        DDLogVerbose(@"Current state: %@", self.state);
        
        //we bound a new xmpp session --> reset our whole state
        self.openBundleFetchCnt = 0;
        self.closedBundleFetchCnt = 0;
        self.state.openBundleFetches = [NSMutableDictionary new];
        self.state.openDevicelistFetches = [NSMutableSet new];
        self.state.openDevicelistSubscriptions = [NSMutableSet new];
        self.ownDeviceList = [[self knownDevicesForAddressName:self.account.connectionProperties.identity.jid] mutableCopy];
        DDLogVerbose(@"Own devicelist for account %@ is now: %@", self.account, self.ownDeviceList);
        
        //we will get our own devicelist when sending our first presence after being bound (because we are using +notify for the devicelist)
        self.state.hasSeenDeviceList = NO;
        
        //the catchup is still pending after being bound (mam catchup)
        self.state.catchupDone = NO;
        
        DDLogVerbose(@"New state: %@", self.state);
    }
#endif
}

-(void) handleCatchupDone:(NSNotification*) notification
{
#ifndef DISABLE_OMEMO
    //this event will be called as soon as mam OR smacks catchup on our account is done, it does not wait for muc mam catchups!
    if(self.account.accountNo.intValue == ((xmpp*)notification.object).accountNo.intValue)
    {
        DDLogInfo(@"Catchup done now, handling omemo stuff...");
        DDLogVerbose(@"Current state: %@", self.state);
        
        //the catchup completed now
        self.state.catchupDone = YES;
        
        //if we did not see our own devicelist until now that means the server does not have any devicelist stored
        //(e.g. we are the first omemo capable client)
        //--> publish devicelist by faking an empty server-sent devicelist
        //self.state.hasSeenDeviceList will be set to YES once the published devicelist gets returned to us by a pubsub headline echo
        //(e.g. once the devicelist was safely stored on our server)
        if(self.state.hasSeenDeviceList == NO)
        {
            DDLogInfo(@"We did not see any devicelist during catchup since last non-smacks-resume reconnect, adding our device to an otherwise empty devicelist and publishing this list...");
            [self processOMEMODevices:[NSSet<NSNumber*> new] from:self.account.connectionProperties.identity.jid];
        }
        else
        {
            //generate new prekeys if needed and publish them
            [self generateNewKeysIfNeeded];
        }
        
        //send all needed key transport elements now (added by incoming catchup messages)
        //the queue is needed to make sure we won't send multiple key transport messages to a single contact/device
        //only because we received multiple messages from this user in the catchup
        //queuedKeyTransportElements will survive any smacks or non-smacks resumptions and eventually trigger key transport elements
        //once the catchup could be finished (could take several smacks resumptions to finish the whole (mam) catchup)
        //has to be synchronized because [xmpp sendMessage:] could be called from main thread
        @synchronized(self.state.queuedKeyTransportElements) {
            DDLogDebug(@"Replaying queuedKeyTransportElements: %@", self.state.queuedKeyTransportElements);
            for(NSString* jid in self.state.queuedKeyTransportElements)
            {
                [self sendKeyTransportElement:jid forRids:self.state.queuedKeyTransportElements[jid]];
                [self.state.queuedKeyTransportElements[jid] removeAllObjects];       //this gets us better logging while doing replay
            }
            self.state.queuedKeyTransportElements = [NSMutableDictionary new];
        }
        
        //handle all broken sessions now (e.g. reestablish them by fetching their bundles and sending key transport elements afterwards)
        //the code handling the fetched bundle will check for an entry in queuedSessionRepairs and send
        //a key transport element if such an entry can be found
        //it removes the entry in queuedSessionRepairs afterwards, so no need to remove it here
        //queuedSessionRepairs will survive a non-smacks relogin and trigger these dropped bundle fetches again to complete them
        //has to be synchronized because [xmpp sendMessage:] could be called from main thread
        @synchronized(self.state.queuedSessionRepairs) {
            DDLogDebug(@"Replaying queuedSessionRepairs: %@", self.state.queuedSessionRepairs);
            for(NSString* jid in self.state.queuedSessionRepairs)
                for(NSNumber* rid in self.state.queuedSessionRepairs[jid])
                    [self queryOMEMOBundleFrom:jid andDevice:rid];
        }
        
        DDLogVerbose(@"New state: %@", self.state);
    }
#endif
}

$$instance_handler(devicelistHandler, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$ID(NSString*, type), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    //type will be "publish", "retract", "purge" or "delete". "publish" and "retract" will have the data dictionary filled with id --> data pairs
    //the data for "publish" is the item node with the given id, the data for "retract" is always @YES
    MLAssert([node isEqualToString:@"eu.siacs.conversations.axolotl.devicelist"], @"pep node must be 'eu.siacs.conversations.axolotl.devicelist'");
    NSSet<NSNumber*>* deviceIds = [NSSet new];      //default value used for retract, purge and delete
    if([type isEqualToString:@"publish"])
    {
        MLXMLNode* publishedDevices = data[@"current"];
        if(publishedDevices != nil)
            deviceIds = [[NSSet<NSNumber*> alloc] initWithArray:[publishedDevices find:@"{eu.siacs.conversations.axolotl}list/device@id|uint"]];
    }
    
    //this will add our own deviceid if the devicelist is our own and our deviceid is missing
    [self processOMEMODevices:deviceIds from:jid];
    
    //mark our own devicelist as received (e.g. not empty on the server)
    if([jid isEqualToString:self.account.connectionProperties.identity.jid])
    {
        DDLogInfo(@"Marking our own devicelist as seen now...");
        self.state.hasSeenDeviceList = YES;
    }
$$

-(void) queryOMEMODevices:(NSString*) jid
{
    //don't subscribe devicelist twice (could be triggered by multiple useractions in a row)
    if([self.state.openDevicelistSubscriptions containsObject:jid])
        DDLogInfo(@"Deduplicated devicelist subscribe from %@", jid);
    else
        [self.account.pubsub subscribeToNode:@"eu.siacs.conversations.axolotl.devicelist" onJid:jid withHandler:$newHandlerWithInvalidation(self, handleDevicelistSubscribe, handleDevicelistSubscribeInvalidation)];
    
    //don't fetch devicelist twice (could be triggered by multiple useractions in a row)
    if([self.state.openDevicelistFetches containsObject:jid])
        DDLogInfo(@"Deduplicated devicelist fetches from %@", jid);
    else
    {
        //fetch newest devicelist (this is needed even after a subscribe on at least prosody)
        [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:jid withItemsList:nil andHandler:$newHandlerWithInvalidation(self, handleDevicelistFetch, handleDevicelistFetchInvalidation)];
    }
}

$$instance_handler(handleDevicelistSubscribeInvalidation, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid))
    //mark devicelist subscription as done
    [self.state.openDevicelistSubscriptions removeObject:jid];
$$

$$instance_handler(handleDevicelistSubscribe, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
    [self.state.openDevicelistSubscriptions removeObject:jid];
    
    if(success == NO)
    {
        if(errorIq)
            DDLogError(@"Error while subscribe to omemo deviceslist from: %@ - %@", jid, errorIq);
        else
            DDLogError(@"Error while subscribe to omemo deviceslist from: %@ - %@", jid, errorReason);
    }
    // TODO: improve error handling
$$

$$instance_handler(handleDevicelistFetchInvalidation, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid))
    //mark devicelist fetch as done
    [self.state.openDevicelistFetches removeObject:jid];
$$

$$instance_handler(handleDevicelistFetch, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    [self.state.openDevicelistFetches removeObject:jid];
    
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
            //some clients do not use <item id="current">
            publishedDevices = [[data allValues] firstObject];
        }
        else if(!publishedDevices && data.count > 1)
            DDLogWarn(@"More than one devicelist item found from %@, ignoring all items!", jid);
        
        if(publishedDevices)
        {
            NSArray<NSNumber*>* deviceIds = [publishedDevices find:@"{eu.siacs.conversations.axolotl}list/device@id|uint"];
            NSSet<NSNumber*>* deviceSet = [[NSSet<NSNumber*> alloc] initWithArray:deviceIds];

            [self processOMEMODevices:deviceSet from:jid];
        }
    }
$$

-(void) processOMEMODevices:(NSSet<NSNumber*>*) receivedDevices from:(NSString*) source
{
    DDLogVerbose(@"Processing omemo devices from %@: %@", source, receivedDevices);
    
    NSSet<NSNumber*>* existingDevices = [NSSet setWithArray:[self.monalSignalStore knownDevicesWithValidSessionEntryForName:source]];
    NSMutableSet<NSNumber*>* newDevices = [receivedDevices mutableCopy];
    [newDevices minusSet:existingDevices];
    DDLogVerbose(@"New devices detected: %@", newDevices);
    
    NSMutableSet<NSNumber*>* removedDevices = [existingDevices mutableCopy];
    [removedDevices minusSet:receivedDevices];
    DDLogVerbose(@"Removed devices detected: %@", removedDevices);
    
    //iterate through all received deviceids and query the corresponding bundle, if we don't know that deviceid yet
    for(NSNumber* deviceId in receivedDevices)
    {
        //remove mark that the device was not found in the devicelist (if that mark was present)
        [self.monalSignalStore removeDeviceDeletedMark:[[SignalAddress alloc] initWithName:source deviceId:deviceId.unsignedIntValue]];
        //fetch bundle of this device if it's a new device or if the session to this device is broken, but only do this for remote devices
        //this will automatically send a key transport element to this device, once the bundle arrives and the session is still broken
        if(![existingDevices containsObject:deviceId] && deviceId.unsignedIntValue != self.monalSignalStore.deviceid)
        {
            DDLogDebug(@"Device new or session broken, fetching bundle %@ (again)...", deviceId);
            [self queryOMEMOBundleFrom:source andDevice:deviceId];
        }
    }
    
    //remove devices from our signalStorage when they are no longer published
    for(NSNumber* deviceId in removedDevices)
    {
        //only delete other devices from signal store but keep the entry for this device
        if(![source isEqualToString:self.account.connectionProperties.identity.jid] || deviceId.unsignedIntValue != self.monalSignalStore.deviceid)
        {
            DDLogDebug(@"Removing device %@", deviceId);
            SignalAddress* address = [[SignalAddress alloc] initWithName:source deviceId:deviceId.unsignedIntValue];
            [self.monalSignalStore markDeviceAsDeleted:address];
        }
    }
        
    //remove deviceids from queuedSessionRepairs list if these devices are no longer available
    @synchronized(self.state.queuedSessionRepairs) {
        if(self.state.queuedSessionRepairs[source] != nil)
            for(NSNumber* brokenRid in [self.state.queuedSessionRepairs[source] copy])
                if(![receivedDevices containsObject:brokenRid])
                {
                    DDLogDebug(@"Removing deviceid %@ on jid %@ from queuedSessionRepairs...", brokenRid, source);
                    [self.state.queuedSessionRepairs[source] removeObject:brokenRid];
                }
    }

    //handle our own devicelist
    if([self.account.connectionProperties.identity.jid isEqualToString:source])
        [self handleOwnDevicelistUpdate:receivedDevices];
}

-(void) handleOwnDevicelistUpdate:(NSSet<NSNumber*>*) receivedDevices
{
    //update own devicelist (this can be an empty list, if the list on our server is empty)
    self.ownDeviceList = [receivedDevices mutableCopy];
    DDLogVerbose(@"Own devicelist for account %@ is now: %@", self.account, self.ownDeviceList);
    
    //make sure to add our own deviceid to the devicelist if it's not yet there
    if(![self.ownDeviceList containsObject:[NSNumber numberWithUnsignedInt:self.monalSignalStore.deviceid]])
    {
        [self.ownDeviceList addObject:[NSNumber numberWithUnsignedInt:self.monalSignalStore.deviceid]];
        //generate new prekeys (piggyback the prekey refill onto the bundle push already needed because our device was unknown before)
        //publishing our prekey bundle must be done BEFORE publishing a new devicelist containing our deviceid
        DDLogDebug(@"Publishing own OMEMO bundle...");
        //in this case (e.g. deviceid unknown) we can't be sure our bundle is saved on the server already
        //--> publish bundle even if generateNewKeysIfNeeded did not publish a bundle
        if([self generateNewKeysIfNeeded] == NO)
            [self sendOMEMOBundle];
        
        //publish own devicelist directly after publishing our bundle
        [self publishOwnDeviceList];
    }
}

-(void) publishOwnDeviceList
{
    DDLogInfo(@"Publishing own OMEMO device list...");
    MLXMLNode* listNode = [[MLXMLNode alloc] initWithElement:@"list" andNamespace:@"eu.siacs.conversations.axolotl"];
    for(NSNumber* deviceNum in self.ownDeviceList)
        [listNode addChildNode:[[MLXMLNode alloc] initWithElement:@"device" withAttributes:@{kId: [deviceNum stringValue]} andChildren:@[] andData:nil]];
    [self.account.pubsub publishItem:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{kId: @"current"} andChildren:@[
        listNode,
    ] andData:nil] onNode:@"eu.siacs.conversations.axolotl.devicelist" withConfigOptions:@{
        @"pubsub#persist_items": @"true",
        @"pubsub#access_model": @"open"
    }];
}

-(void) queryOMEMOBundleFrom:(NSString*) jid andDevice:(NSNumber*) deviceid
{
    //don't fetch bundle twice (could be triggered by multiple devicelist pushes in a row)
    if(self.state.openBundleFetches[jid] != nil && [self.state.openBundleFetches[jid] containsObject:deviceid])
    {
        DDLogInfo(@"Deduplicated bundle fetches of deviceid %@ from %@", jid, deviceid);
        return;
    }
    
    NSString* bundleNode = [NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%@", deviceid];
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateBundleFetchStatus object:self userInfo:@{
        @"accountNo": self.account.accountNo,
        @"completed": @(self.closedBundleFetchCnt),
        @"all": @(self.openBundleFetchCnt + self.closedBundleFetchCnt)
    }];
    [self.account.pubsub fetchNode:bundleNode from:jid withItemsList:nil andHandler:$newHandlerWithInvalidation(self, handleBundleFetchResult, handleBundleFetchInvalidation, $ID(jid), $ID(rid, deviceid))];
    
    if(self.state.openBundleFetches[jid] == nil)
        self.state.openBundleFetches[jid] = [NSMutableSet new];
    [self.state.openBundleFetches[jid] addObject:deviceid];
    
    //update bundle fetch status
    self.openBundleFetchCnt++;
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateBundleFetchStatus object:self userInfo:@{
        @"accountNo": self.account.accountNo,
        @"completed": @(self.closedBundleFetchCnt),
        @"all": @(self.openBundleFetchCnt + self.closedBundleFetchCnt)
    }];
}

//don't mark any devices as deleted in this invalidation handler (like we do for an error in the normal handler below),
//because a timeout could mean a very slow s2s connection and a disconnect will invalidate all handlers, too
//--> we don't want to delete the device in this cases
$$instance_handler(handleBundleFetchInvalidation, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid), $$ID(NSNumber*, rid))
    //mark bundle fetch as done
    if(self.state.openBundleFetches[jid] != nil && [self.state.openBundleFetches[jid] containsObject:rid])
        [self.state.openBundleFetches[jid] removeObject:rid];
    if(self.state.openBundleFetches[jid] != nil && self.state.openBundleFetches[jid].count == 0)
        [self.state.openBundleFetches removeObjectForKey:jid];
    
    //update bundle fetch status (this has to be done even in error cases!)
    [self decrementBundleFetchCount];
$$

$$instance_handler(handleBundleFetchResult, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data), $$ID(NSNumber*, rid))
    //mark bundle fetch as done
    if(self.state.openBundleFetches[jid] != nil && [self.state.openBundleFetches[jid] containsObject:rid])
        [self.state.openBundleFetches[jid] removeObject:rid];
    if(self.state.openBundleFetches[jid] != nil && self.state.openBundleFetches[jid].count == 0)
        [self.state.openBundleFetches removeObjectForKey:jid];
    
    if(!success)
    {
        if(errorIq)
        {
            DDLogError(@"Could not fetch bundle from %@: rid: %@ - %@", jid, rid, errorIq);
            //delete this device for all non-wait errors
            if(![errorIq check:@"error<type=wait>"])
            {
                SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:rid.unsignedIntValue];
                [self.monalSignalStore markDeviceAsDeleted:address];
            }
        }
        //don't delete this device for errorReasons (normally server bugs or transient problems inside monal)
        else if(errorReason)
            DDLogError(@"Could not fetch bundle from %@: rid: %@ - %@", jid, rid, errorReason);
    }
    else
    {
        //check that a corresponding buddy exists -> prevent foreign key errors
        MLXMLNode* receivedKeys = data[@"current"];
        if(receivedKeys != nil && data.count == 1)
        {
            //some clients do not use <item id="current">
            receivedKeys = [[data allValues] firstObject];
        }
        else if(!receivedKeys && data.count > 1)
            DDLogWarn(@"More than one bundle item found from %@ rid: %@, ignoring all items!", jid, rid);
        
        if(receivedKeys)
            [self processOMEMOKeys:receivedKeys forJid:jid andRid:rid];
    }
    
    //update bundle fetch status (this has to be done even in error cases!)
    [self decrementBundleFetchCount];
$$

-(void) decrementBundleFetchCount
{
    if(self.openBundleFetchCnt > 1)
    {
        //update bundle fetch status (e.g. pending)
        self.openBundleFetchCnt--;
        self.closedBundleFetchCnt++;
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateBundleFetchStatus object:self userInfo:@{
            @"accountNo": self.account.accountNo,
            @"completed": @(self.closedBundleFetchCnt),
            @"all": @(self.openBundleFetchCnt + self.closedBundleFetchCnt),
        }];
    }
    else
    {
        //update bundle fetch status (e.g. complete)
        self.openBundleFetchCnt = 0;
        self.closedBundleFetchCnt = 0;
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalFinishedOmemoBundleFetch object:self userInfo:@{
            @"accountNo": self.account.accountNo,
        }];
    }
}

-(void) processOMEMOKeys:(MLXMLNode*) item forJid:(NSString*) jid andRid:(NSNumber*) rid
{
    MLAssert(self.signalContext != nil, @"self.signalContext must not be nil");
    
    //there should only be one bundle per device
    //ignore all bundles, if this requirement is not met, to make sure we don't enter some
    //strange "omemo loop" with a broken remote software
    NSArray* bundles = [item find:@"{eu.siacs.conversations.axolotl}bundle"];
    if([bundles count] != 1)
        return;
    MLXMLNode* bundle = [bundles firstObject];

    //extract bundle data
    NSData* signedPreKeyPublic = [bundle findFirst:@"signedPreKeyPublic#|base64"];
    NSNumber* signedPreKeyPublicId = [bundle findFirst:@"signedPreKeyPublic@signedPreKeyId|uint"];
    NSData* signedPreKeySignature = [bundle findFirst:@"signedPreKeySignature#|base64"];
    NSData* identityKey = [bundle findFirst:@"identityKey#|base64"];

    //ignore bundles not conforming to the standard
    if(signedPreKeyPublic == nil || signedPreKeyPublicId == nil || signedPreKeySignature == nil || identityKey == nil)
        return;

    uint32_t deviceId = (uint32_t)rid.unsignedIntValue;
    SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:deviceId];
    SignalSessionBuilder* builder = [[SignalSessionBuilder alloc] initWithAddress:address context:self.signalContext];
    NSArray<NSNumber*>* preKeyIds = [bundle find:@"prekeys/preKeyPublic@preKeyId|uint"];

    if(preKeyIds == nil || preKeyIds.count == 0)
    {
        DDLogWarn(@"Could not create array of preKeyIds");
        return;
    }
    
    //parse preKeys
    unsigned long processedKeys = 0;
    do
    {
        // select random preKey and try to import it
        const uint32_t preKeyIdxToTest = arc4random_uniform((uint32_t)preKeyIds.count);
        // load preKey
        NSNumber* preKeyId = preKeyIds[preKeyIdxToTest];
        if(preKeyId == nil)
            continue;;
        NSData* key = [bundle findFirst:@"prekeys/preKeyPublic<preKeyId=%@>#|base64", preKeyId];
        if(!key)
            continue;

        DDLogDebug(@"Generating keyBundle for jid: %@ rid: %u and key id %@...", jid, deviceId, preKeyId);
        NSError* error;
        SignalPreKeyBundle* keyBundle = [[SignalPreKeyBundle alloc] initWithRegistrationId:0
                                                                    deviceId:deviceId
                                                                    preKeyId:[preKeyId unsignedIntValue]
                                                                    preKeyPublic:key
                                                                    signedPreKeyId:signedPreKeyPublicId.unsignedIntValue
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
        
        //found and imported a working key --> try to (re)build a new session proactively (or repair a broken one)
        [self sendKeyTransportElement:jid forRids:[NSSet setWithArray:@[rid]]];      //this will remove the queuedSessionRepairs entry, if any
        
        return;
    } while(++processedKeys < preKeyIds.count);
    DDLogError(@"Could not import a single prekey from bundle for rid %@ (tried %lu keys)", rid, processedKeys);
}

-(void) rebuildSessionWithJid:(NSString*) jid forRid:(NSNumber*) rid
{
    //don't rebuild session to ourselves (MUST be scoped by jid for omemo 2)
    if(rid.unsignedIntValue == self.monalSignalStore.deviceid)
        return;
    
    //mark session as broken
    SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:(uint32_t)rid.unsignedIntValue];
    [self.monalSignalStore markSessionAsBroken:address];
    
    //queue all actions until the catchup was done
    if(!self.state.catchupDone)
    {
        DDLogDebug(@"Adding deviceid %@ for jid %@ to queuedSessionRepairs...", rid, jid);
        @synchronized(self.state.queuedSessionRepairs) {
            if(self.state.queuedSessionRepairs[jid] == nil)
                self.state.queuedSessionRepairs[jid] = [NSMutableSet new];
            [self.state.queuedSessionRepairs[jid] addObject:rid];
        }
        return;
    }
    
    //this will query the bundle and send a key transport element to rebuild the session afterwards
    DDLogDebug(@"Trying to repair session with deviceid %@ on jid %@...", rid, jid);
    [self queryOMEMOBundleFrom:jid andDevice:rid];
}

-(void) sendKeyTransportElement:(NSString*) jid forRids:(NSSet<NSNumber*>*) rids
{
    //queue all actions until the catchup was done
    if(!self.state.catchupDone)
    {
        @synchronized(self.state.queuedKeyTransportElements) {
            if(self.state.queuedKeyTransportElements[jid] == nil)
                self.state.queuedKeyTransportElements[jid] = [NSMutableSet new];
            [self.state.queuedKeyTransportElements[jid] unionSet:rids];
        }
        return;
    }
    
    //generate new prekeys if needed and publish them
    //this is important to empower the remote device to build a new session for us using prekeys, if needed
    [self generateNewKeysIfNeeded];
    
    //send key-transport element for all known rids (e.g. devices) to recover broken sessions
    DDLogDebug(@"Sending KeyTransportElement to jid: %@", jid);
    XMPPMessage* messageNode = [[XMPPMessage alloc] initWithType:kMessageChatType to:jid];
    [self encryptMessage:messageNode withMessage:nil toContact:jid];
    [self.account send:messageNode];
    
    @synchronized(self.state.queuedSessionRepairs) {
        //remove this jid-rid combinations from queuedSessionRepairs
        for(NSNumber* rid in rids)
            if(rid != nil && self.state.queuedSessionRepairs[jid] != nil)
            {
                DDLogDebug(@"Removing deviceid %@ on jid %@ from queuedSessionRepairs...", rid, jid);
                [self.state.queuedSessionRepairs[jid] removeObject:rid];
            }
    }
}

-(void) sendOMEMOBundle
{
    MLAssert(self.monalSignalStore.deviceid > 0, @"Tried to publish own bundle without knowing my own deviceid!");
    
    MLXMLNode* prekeyNode = [[MLXMLNode alloc] initWithElement:@"prekeys"];
    for(SignalPreKey* prekey in [self.monalSignalStore readPreKeys])
        [prekeyNode addChildNode:[[MLXMLNode alloc] initWithElement:@"preKeyPublic" withAttributes:@{
            @"preKeyId": [NSString stringWithFormat:@"%u", prekey.preKeyId],
        } andChildren:@[] andData:[HelperTools encodeBase64WithData:prekey.keyPair.publicKey]]];

    //publish whole bundle via pubsub interface
    [self.account.pubsub publishItem:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{kId: @"current"} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"bundle" andNamespace:@"eu.siacs.conversations.axolotl" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"signedPreKeyPublic" withAttributes:@{
                @"signedPreKeyId": [NSString stringWithFormat:@"%u",self.monalSignalStore.signedPreKey.preKeyId]
            } andChildren:@[] andData:[HelperTools encodeBase64WithData:self.monalSignalStore.signedPreKey.keyPair.publicKey]],
            [[MLXMLNode alloc] initWithElement:@"signedPreKeySignature" withAttributes:@{} andChildren:@[] andData:[HelperTools encodeBase64WithData:self.monalSignalStore.signedPreKey.signature]],
            [[MLXMLNode alloc] initWithElement:@"identityKey" withAttributes:@{} andChildren:@[] andData:[HelperTools encodeBase64WithData:self.monalSignalStore.identityKeyPair.publicKey]],
            prekeyNode,
        ] andData:nil]
    ] andData:nil] onNode:[NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%u", self.monalSignalStore.deviceid] withConfigOptions:@{
        @"pubsub#persist_items": @"true",
        @"pubsub#access_model": @"open"
    }];
}

/*
 * generates new omemo keys if we have less than MIN_OMEMO_KEYS left
 * returns YES if keys were generated and the new omemo bundle was send
 */
-(BOOL) generateNewKeysIfNeeded
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
            DDLogWarn(@"No new prekeys needed");
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

-(void) encryptMessage:(XMPPMessage*) messageNode withMessage:(NSString* _Nullable) message toContact:(NSString*) toContact
{
    MLAssert(self.signalContext != nil, @"signalContext should be initiated.");

    //add xmpp message fallback body (needed to make clear that this is not a key transport message)
    //don't remove this, message contains the cleartext message!
    if(message)
        [messageNode setBody:@"[This message is OMEMO encrypted]"];
    else
    {
        //KeyTransportElements don't contain a body --> force storage to MAM nonetheless
        [messageNode setStoreHint];
    }
    
    NSMutableSet<NSString*>* recipients = [[NSMutableSet alloc] init];
    if([[DataLayer sharedInstance] isBuddyMuc:toContact forAccount:self.account.accountNo])
        for(NSDictionary* participant in [[DataLayer sharedInstance] getMembersAndParticipantsOfMuc:toContact forAccountId:self.account.accountNo])
        {
            if(participant[@"participant_jid"])
                [recipients addObject:participant[@"participant_jid"]];
            else if(participant[@"member_jid"])
                [recipients addObject:participant[@"member_jid"]];
        }
    else
        [recipients addObject:toContact];
    
    //remove own jid from recipients (our own devices get special treatment via myDevices NSSet below)
    [recipients removeObject:self.account.connectionProperties.identity.jid];
    
    NSMutableDictionary<NSString*, NSArray<NSNumber*>*>* contactDeviceMap = [[NSMutableDictionary alloc] init];
    for(NSString* recipient in recipients)
    {
        //contactDeviceMap
        NSArray<NSNumber*>* recipientDevices = [self.monalSignalStore knownDevicesForAddressName:recipient];
        if(recipientDevices && recipientDevices.count > 0)
            contactDeviceMap[recipient] = recipientDevices;
    }
    NSArray<NSNumber*>* myDevices = [self.monalSignalStore knownDevicesForAddressName:self.account.connectionProperties.identity.jid];

    //check if we found omemo keys of at least one of the recipients or more than 1 own device, otherwise don't encrypt anything
    if(contactDeviceMap.count > 0 || myDevices.count > 1)
    {
        MLXMLNode* encrypted = [[MLXMLNode alloc] initWithElement:@"encrypted" andNamespace:@"eu.siacs.conversations.axolotl"];

        MLEncryptedPayload* encryptedPayload;
        if(message)
        {
            // Encrypt message
            encryptedPayload = [AESGcm encrypt:[message dataUsingEncoding:NSUTF8StringEncoding] keySize:KEY_SIZE];
            if(encryptedPayload == nil)
            {
                showErrorOnAlpha(self.account, @"Could not encrypt message: AESGcm error");
                return;
            }
            [encrypted addChildNode:[[MLXMLNode alloc] initWithElement:@"payload" andData:[HelperTools encodeBase64WithData:encryptedPayload.body]]];
        }
        else
        {
            //there is no message that can be encrypted -> create new session keys (e.g. this is a key transport message)
            NSData* newKey = [AESGcm genKey:KEY_SIZE];
            NSData* newIv = [AESGcm genIV];
            if(newKey == nil || newIv == nil)
            {
                showErrorOnAlpha(self.account, @"Could not create key or iv");
                return;
            }
            encryptedPayload = [[MLEncryptedPayload alloc] initWithKey:newKey iv:newIv];
            if(encryptedPayload == nil)
            {
                showErrorOnAlpha(self.account, @"Could not encrypt message: AESGcm error");
                return;
            }
        }

        //add crypto header with our own deviceid
        MLXMLNode* header = [[MLXMLNode alloc] initWithElement:@"header" withAttributes:@{
            @"sid": [NSString stringWithFormat:@"%u", self.monalSignalStore.deviceid],
        } andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"iv" andData:[HelperTools encodeBase64WithData:encryptedPayload.iv]],
        ] andData:nil];

        //add encryption for all of our recipients' devices
        for(NSString* recipient in contactDeviceMap)
            [self addEncryptionKeyForAllDevices:contactDeviceMap[recipient] encryptForJid:recipient withEncryptedPayload:encryptedPayload withXMLHeader:header];
        
        //add encryption for all of our own devices
        [self addEncryptionKeyForAllDevices:myDevices encryptForJid:self.account.connectionProperties.identity.jid withEncryptedPayload:encryptedPayload withXMLHeader:header];

        [encrypted addChildNode:header];
        [messageNode addChildNode:encrypted];
    }
}

-(void) addEncryptionKeyForAllDevices:(NSArray*) devices encryptForJid:(NSString*) encryptForJid withEncryptedPayload:(MLEncryptedPayload*) encryptedPayload withXMLHeader:(MLXMLNode*) xmlHeader
{
    //encrypt message for all given deviceids
    for(NSNumber* device in devices)
    {
        //do not encrypt for our own device (MUST be scoped by jid for omemo 2)
        if(device.unsignedIntValue == self.monalSignalStore.deviceid)
            continue;
        
        SignalAddress* address = [[SignalAddress alloc] initWithName:encryptForJid deviceId:(uint32_t)device.unsignedIntValue];

        NSData* identity = [self.monalSignalStore getIdentityForAddress:address];
        if(!identity)
        {
            showErrorOnAlpha(self.account, @"Could not get Identity for: %@ device id %@", encryptForJid, device);
            //TODO: is it correct to rebuild broken(?) session here, too?
            [self rebuildSessionWithJid:encryptForJid forRid:device];
            continue;
        }
        //only encrypt for devices that are trusted (tofu or explicitly)
        if([self.monalSignalStore isTrustedIdentity:address identityKey:identity])
        {
            SignalSessionCipher* cipher = [[SignalSessionCipher alloc] initWithAddress:address context:self.signalContext];
            NSError* error;
            SignalCiphertext* deviceEncryptedKey = [cipher encryptData:encryptedPayload.key error:&error];
            if(error)
            {
                showErrorOnAlpha(self.account, @"Error while adding encryption key for jid: %@ device: %@ error: %@", encryptForJid, device, error);
                [self rebuildSessionWithJid:encryptForJid forRid:device];
                continue;
            }
            [xmlHeader addChildNode:[[MLXMLNode alloc] initWithElement:@"key" withAttributes:@{
                @"rid": [NSString stringWithFormat:@"%@", device],
                @"prekey": (deviceEncryptedKey.type == SignalCiphertextTypePreKeyMessage ? @"1" : @"0"),
            } andChildren:@[] andData:[HelperTools encodeBase64WithData:deviceEncryptedKey.data]]];
        }
    }
}

-(NSString* _Nullable) decryptMessage:(XMPPMessage*) messageNode withMucParticipantJid:(NSString* _Nullable) mucParticipantJid
{
    if(![messageNode check:@"{eu.siacs.conversations.axolotl}encrypted/header"])
    {
        showErrorOnAlpha(self.account, @"DecryptMessage called but the message has no encryption header");
        return nil;
    }
    BOOL isKeyTransportElement = ![messageNode check:@"{eu.siacs.conversations.axolotl}encrypted/payload"];

    NSNumber* sid = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/header@sid|uint"];
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

    SignalAddress* address = [[SignalAddress alloc] initWithName:senderJid deviceId:(uint32_t)sid.unsignedIntValue];

    if(!self.signalContext)
    {
        showErrorOnAlpha(self.account, @"Missing signal context in decrypt!");
        return NSLocalizedString(@"Error decrypting message", @"");
    }
    
    //don't try to decrypt our own messages (could be mirrored by MUC etc.)
    if([senderJid isEqualToString:self.account.connectionProperties.identity.jid] && sid.unsignedIntValue == self.monalSignalStore.deviceid)
        return nil;

    NSData* messageKey = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/header/key<rid=%u>#|base64", self.monalSignalStore.deviceid];
    BOOL devicePreKey = [[messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/header/key<rid=%u>@prekey|bool", self.monalSignalStore.deviceid] boolValue];
    
    DDLogVerbose(@"Decrypting using:\nrid=%u --> messageKey=%@\nrid=%u --> isPreKey=%@", self.monalSignalStore.deviceid, messageKey, self.monalSignalStore.deviceid, devicePreKey ? @"YES" : @"NO");

    if(!messageKey && isKeyTransportElement)
    {
        DDLogVerbose(@"Received KeyTransportElement without our own rid included --> Ignore it");
        return nil;
    }
    else if(!messageKey)
    {
        DDLogError(@"Message was not encrypted for this device: %u", self.monalSignalStore.deviceid);
        [self rebuildSessionWithJid:senderJid forRid:sid];
        return [NSString stringWithFormat:NSLocalizedString(@"Message was not encrypted for this device. Please make sure the sender trusts deviceid %u.", @""), self.monalSignalStore.deviceid];
    }
    else
    {
        SignalSessionCipher* cipher = [[SignalSessionCipher alloc] initWithAddress:address context:self.signalContext];
        SignalCiphertextType messagetype;

        //check if message is encrypted with a prekey
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
            //don't report error or try to rebuild session, if this was just a duplicated message
            if([@"org.whispersystems.SignalProtocol" isEqualToString:error.domain] && error.code == 3)
            {
                DDLogDebug(@"Deduplicated %@ message via omemo...", isKeyTransportElement ? @"key transport" : @"normal");
                return nil;
            }
            [self rebuildSessionWithJid:senderJid forRid:sid];
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
            DDLogError(@"Could not decrypt to obtain key (returned nil)");
            [self rebuildSessionWithJid:senderJid forRid:sid];
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
                //(re)build session
                [self sendKeyTransportElement:senderJid forRids:[NSSet setWithArray:@[sid]]];
            }
            
            //save last successfull decryption time and remove possibly queued session repair
            [self.monalSignalStore updateLastSuccessfulDecryptTime:address];
            @synchronized(self.state.queuedSessionRepairs) {
                if(self.state.queuedSessionRepairs[senderJid] != nil)
                {
                    DDLogDebug(@"Removing deviceid %@ on jid %@ from queuedSessionRepairs (we successfully decrypted a message)...", sid, senderJid);
                    [self.state.queuedSessionRepairs[senderJid] removeObject:sid];
                }
            }

            //key transport elements have an empty payload --> nothing to return as decrypted
            if(isKeyTransportElement)
            {
                DDLogInfo(@"KeyTransportElement received from jid: %@ device: %@", senderJid, sid);
#ifdef IS_ALPHA
                return [NSString stringWithFormat:@"ALPHA_DEBUG_MESSAGE: KeyTransportElement received from jid: %@ device: %@", senderJid, sid];
#else
                return nil;
#endif
            }

            //some clients have the auth parameter in the ciphertext?
            if(decryptedKey.length == 16 * 2)
            {
                key = [decryptedKey subdataWithRange:NSMakeRange(0, 16)];
                auth = [decryptedKey subdataWithRange:NSMakeRange(16, 16)];
            }
            else
                key = decryptedKey;

            if(key != nil)
            {
                NSData* iv = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/header/iv#|base64"];
                NSData* decodedPayload = [messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted/payload#|base64"];
                if(iv == nil || iv.length != 12)
                {
                    showErrorOnAlpha(self.account, @"Could not decrypt message: iv length: %lu", (unsigned long)iv.length);
                    return NSLocalizedString(@"Error while decrypting: iv.length != 12", @"");
                }
                if(decodedPayload == nil)
                {
                    return NSLocalizedString(@"Error: Received OMEMO message is empty", @"");
                }
                
                NSData* decData = [AESGcm decrypt:decodedPayload withKey:key andIv:iv withAuth:auth];
                if(decData == nil)
                {
                    showErrorOnAlpha(self.account, @"Could not decrypt message with key that was decrypted. (GCM error)");
                    return NSLocalizedString(@"Encrypted message was sent in an older format Monal can't decrypt. Please ask them to update their client. (GCM error)", @"");
                }
                else
                    DDLogInfo(@"Successfully decrypted message, passing back cleartext string...");
                return [[NSString alloc] initWithData:decData encoding:NSUTF8StringEncoding];
            }
            else
            {
                showErrorOnAlpha(self.account, @"Could not get omemo decryption key");
                return NSLocalizedString(@"Could not decrypt message", @"");
            }
        }
    }
}

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

//called after a new MUC member was added by MLMucProcessor
-(void) subscribeAndFetchDevicelistIfNoSessionExistsForJid:(NSString*) buddyJid
{
    if([self.monalSignalStore sessionsExistForBuddy:buddyJid] == NO)
        [self queryOMEMODevices:buddyJid];
}

//called after a buddy was deleted from roster OR by MLMucProcessor after a MUC member was removed
-(void) checkIfSessionIsStillNeeded:(NSString*) buddyJid isMuc:(BOOL) isMuc
{
    NSMutableSet<NSString*>* danglingJids = [[NSMutableSet alloc] init];
    if(isMuc == YES)
        danglingJids = [[NSMutableSet alloc] initWithSet:[self.monalSignalStore removeDanglingMucSessions]];
    else if([self.monalSignalStore checkIfSessionIsStillNeeded:buddyJid] == NO)
        [danglingJids addObject:buddyJid];

    for(NSString* jid in danglingJids)
        [self.account.pubsub unsubscribeFromNode:@"eu.siacs.conversations.axolotl.devicelist" forJid:jid withHandler:$newHandler(self, handleDevicelistUnsubscribe)];
}


//interfaces for UI
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

-(BOOL) isSessionBrokenForJid:(NSString*) jid andDeviceId:(NSNumber*) rid
{
    return [self.monalSignalStore isSessionBrokenForJid:jid andDeviceId:rid];
}

-(NSNumber*) getDeviceId
{
    return [NSNumber numberWithUnsignedInt:self.monalSignalStore.deviceid];
}

-(void) deleteDeviceForSource:(NSString*) source andRid:(NSNumber*) rid
{
    //we should not delete our own device
    if([source isEqualToString:self.account.connectionProperties.identity.jid] && rid.unsignedIntValue == self.monalSignalStore.deviceid)
        return;
    //handle removal of own deviceids
    if([source isEqualToString:self.account.connectionProperties.identity.jid])
    {
        [self.ownDeviceList removeObject:rid];
        [self publishOwnDeviceList];
    }

    SignalAddress* address = [[SignalAddress alloc] initWithName:source deviceId:rid.unsignedIntValue];
    [self.monalSignalStore deleteDeviceforAddress:address];
    [self.monalSignalStore deleteSessionRecordForAddress:address];
}

//debug button in contactdetails ui
-(void) clearAllSessionsForJid:(NSString*) jid
{
    NSSet<NSNumber*>* devices = [self knownDevicesForAddressName:jid];
    for(NSNumber* device in devices)
        [self deleteDeviceForSource:jid andRid:device];
    [self sendOMEMOBundle];
    [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:self.account.connectionProperties.identity.jid withItemsList:nil andHandler:$newHandlerWithInvalidation(self, handleDevicelistFetch, handleDevicelistFetchInvalidation)];
    [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:jid withItemsList:nil andHandler:$newHandlerWithInvalidation(self, handleDevicelistFetch, handleDevicelistFetchInvalidation)];
}

@end

NS_ASSUME_NONNULL_END
