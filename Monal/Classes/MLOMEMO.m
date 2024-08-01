//
//  MLOMEMO.m
//  Monal
//
//  Created by Friedrich Altheide on 21.06.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//
#import <UserNotifications/UserNotifications.h>
#import <stdlib.h>

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

    //_state is intentionally left unset and will be updated from [xmpp readState] before [self activate] is called
    //(but only if the state wasn't invalidated, in which case [self activate] will create a new empty state)
    return self;
}

-(void) activate
{
    if(self->_state == nil)
        self->_state = [OmemoState new];
    
    //read own devicelist from database
    self.ownDeviceList = [[self knownDevicesForAddressName:self.account.connectionProperties.identity.jid] mutableCopy];
    DDLogVerbose(@"Own devicelist for account %@ is now: %@", self.account, self.ownDeviceList);
    DDLogVerbose(@"Deviceid of this device: %@", @(self.monalSignalStore.deviceid));
    
    [self createLocalIdentiyKeyPairIfNeeded];
    
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

-(void) notifyKnownDevicesUpdated:(NSString*) jid
{
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalOmemoStateUpdated object:self.account userInfo:@{
        @"jid": jid
    }];
}

-(BOOL) createLocalIdentiyKeyPairIfNeeded
{
    if(self.monalSignalStore.deviceid == 0)
    {
        //signal key helper
        SignalKeyHelper* signalHelper = [[SignalKeyHelper alloc] initWithContext:self.signalContext];

        //Generate a new device id
        do {
            self.monalSignalStore.deviceid = [signalHelper generateRegistrationId];
        } while(self.monalSignalStore.deviceid == 0 || [self.ownDeviceList containsObject:[NSNumber numberWithUnsignedInt:self.monalSignalStore.deviceid]]);
        //Create identity key pair
        self.monalSignalStore.identityKeyPair = [signalHelper generateIdentityKeyPair];
        self.monalSignalStore.signedPreKey = [signalHelper generateSignedPreKeyWithIdentity:self.monalSignalStore.identityKeyPair signedPreKeyId:1];
        SignalAddress* address = [[SignalAddress alloc] initWithName:self.account.connectionProperties.identity.jid deviceId:self.monalSignalStore.deviceid];
        [self.monalSignalStore saveIdentity:address identityKey:self.monalSignalStore.identityKeyPair.publicKey];
        //do everything done in MLSignalStore init not already mimicked above
        [self.monalSignalStore cleanupKeys];
        [self.monalSignalStore reloadCachedPrekeys];
        [self notifyKnownDevicesUpdated:address.name];
        //we generated a new identity
        DDLogWarn(@"Created new omemo identity with deviceid: %@", @(self.monalSignalStore.deviceid));
        //don't alert on new deviceids we could never see before because this is our first connection (otherwise, we'd already have our own deviceid)
        //this has to be a property of the xmpp class to persist it even across state resets
        self.account.hasSeenOmemoDeviceListAfterOwnDeviceid = NO;
        return YES;
    }
    //we did not generate a new identity
    //keep the value of hasSeenOmemoDeviceListAfterOwnDeviceid in this case
    return NO;
}

-(void) handleContactRemoved:(NSNotification*) notification
{
#ifndef DISABLE_OMEMO
    MLContact* removedContact = notification.userInfo[@"contact"];
    DDLogVerbose(@"Got kMonalContactRemoved event for contact: %@", removedContact);
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
        //OR: our own devicelist could have been delayed by the server having to do a disco query to us to discover our +notify
        //for the devicelist (e.g. either we are the first omemo capable client, or the devicelist has just been delayed)
        //--> forcefully fetch devicelist to be sure (but don't subscribe, we are +notify and have a presence subscription to our own account)
        //If our device is not listed in this devicelist node, that fetch and the headline push eventually coming in
        //may both trigger a devicelist publish, but that should not do any harm
        if(self.state.hasSeenDeviceList == NO)
        {
            DDLogInfo(@"We did not see any devicelist during catchup since last non-smacks-resume reconnect, forcefully fetching own devicelist...");
            [self queryOMEMODevices:self.account.connectionProperties.identity.jid withSubscribe:NO];
        }
        else
        {
            [self generateNewKeysIfNeeded];     //generate new prekeys if needed and publish them
            [self repairQueuedSessions];
        }
    }
#endif
}

-(void) handleOwnDevicelistFetchError
{
    //devicelist could neither be fetched explicitly nor by using +notify --> publish own devicelist by faking an empty server-sent devicelist
    //self.state.hasSeenDeviceList will be set to YES once the published devicelist gets returned to us by a pubsub headline echo
    //(e.g. once the devicelist was safely stored on our server)
    DDLogInfo(@"Could not fetch own devicelist, faking empty devicelist to publish our own deviceid...");
    [self processOMEMODevices:[NSSet<NSNumber*> new] from:self.account.connectionProperties.identity.jid];
    
    [self repairQueuedSessions];
}

-(void) repairQueuedSessions
{
    DDLogInfo(@"Own devicelist was handled, now trying to repair queued sessions...");
    
    //send all needed key transport elements now (added by incoming catchup messages or bundle fetches)
    //the queue is needed to make sure we won't send multiple key transport messages to a single contact/device
    //only because we received multiple messages from this user in the catchup or fetched multiple bundles
    //queuedKeyTransportElements will survive any smacks or non-smacks resumptions and eventually trigger key transport elements
    //once the catchup could be finished (could take several smacks resumptions to finish the whole (mam) catchup)
    //has to be synchronized because [xmpp sendMessage:] could be called from main thread
    @synchronized(self.state.queuedKeyTransportElements) {
        DDLogDebug(@"Replaying queuedKeyTransportElements for all jids: %@", self.state.queuedKeyTransportElements);
        for(NSString* jid in [self.state.queuedKeyTransportElements allKeys])
            [self retriggerKeyTransportElementsForJid:jid];
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
    
    //check bundle fetch status and inform ui if we are now catchupDone *and* all bundles are fetched
    //(this method is only called by the catchupDone handler above or by the devicelist fetch triggered by the catchupDone handler)
    [self checkBundleFetchCount];
    
    DDLogVerbose(@"New state: %@", self.state);
}

-(void) retriggerKeyTransportElementsForJid:(NSString*) jid
{
    //send all needed key transport elements now (added by incoming catchup messages or bundle fetches)
    //the queue is needed to make sure we won't send multiple key transport messages to a single contact/device
    //only because we received multiple messages from this user in the catchup or fetched multiple bundles
    //queuedKeyTransportElements will survive any smacks or non-smacks resumptions and eventually trigger key transport elements
    //once the catchup could be finished (could take several smacks resumptions to finish the whole (mam) catchup)
    //has to be synchronized because [xmpp sendMessage:] could be called from main thread
    @synchronized(self.state.queuedKeyTransportElements) {
        NSMutableSet* rids = self.state.queuedKeyTransportElements[jid];
        if(rids == nil)
        {
            DDLogVerbose(@"No key transport elements queued for %@", jid);
            return;
        }
        DDLogDebug(@"Replaying queuedKeyTransportElements for %@: %@", jid, rids);
        //rids can be added back by sendKeyTransportElement: if the sending is still blocked by open bundle fetches etc.
        [self.state.queuedKeyTransportElements removeObjectForKey:jid];
        [self sendKeyTransportElement:jid forRids:rids];
    }
}

$$instance_handler(devicelistHandler, account.omemo, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$ID(NSString*, type), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    //type will be "publish", "retract", "purge" or "delete". "publish" and "retract" will have the data dictionary filled with id --> data pairs
    //the data for "publish" is the item node with the given id, the data for "retract" is always @YES
    MLAssert([node isEqualToString:@"eu.siacs.conversations.axolotl.devicelist"], @"pep node must be 'eu.siacs.conversations.axolotl.devicelist'");
    NSSet<NSNumber*>* deviceIds = [NSSet new];      //default value used for retract, purge and delete
    if([type isEqualToString:@"publish"])
    {
        MLXMLNode* publishedDevices = [data objectForKey:@"current"];
        if(publishedDevices == nil && data.count == 1)
        {
            DDLogInfo(@"Client does not use 'current' as item id for it's bundle! keys=%@", [data allKeys]);
            //some clients do not use <item id="current">
            publishedDevices = [[data allValues] firstObject];
        }
        else if(publishedDevices == nil && data.count > 1)
            DDLogWarn(@"More than one devicelist item found from %@, ignoring all items!", jid);
        
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

-(void) queryOMEMODevices:(NSString*) jid withSubscribe:(BOOL) subscribe
{
    //don't fetch devicelist twice (could be triggered by multiple useractions in a row)
    if([self.state.openDevicelistFetches containsObject:jid])
        DDLogInfo(@"Deduplicated devicelist fetches from %@", jid);
    else
    {
        //fetch newest devicelist (this is needed even after a subscribe on at least prosody)
        [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:jid withItemsList:nil andHandler:$newHandlerWithInvalidation(self, handleDevicelistFetch, handleDevicelistFetchInvalidation, $BOOL(subscribe))];
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
    
    //our own devicelist fetch can't be invalidated because of a iq timeout introduced by a slow s2s connection
    //--> the only reason for such an invalidation can be a disconnect/bind and in this case we don't need to do something
    //    because the fetch will be retriggered after the next catchup
    //[self handleOwnDevicelistFetchError];
    
    //retrigger queued key transport elements for this jid (if any)
    [self retriggerKeyTransportElementsForJid:jid];
$$

$$instance_handler(handleDevicelistFetch, account.omemo, $$ID(xmpp*, account), $$BOOL(subscribe), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID((NSDictionary<NSString*, MLXMLNode*>*), data))
    //mark devicelist fetch as done
    [self.state.openDevicelistFetches removeObject:jid];
    
    if(success == NO)
    {
        if(errorIq)
            DDLogError(@"Error while fetching omemo devices: jid: %@ - %@", jid, errorIq);
        else
            DDLogError(@"Error while fetching omemo devices: jid: %@ - %@", jid, errorReason);
        if([self.account.connectionProperties.identity.jid isEqualToString:jid])
            [self handleOwnDevicelistFetchError];
        else
        {
            // TODO: improve error handling
        }
    }
    else
    {
        if(subscribe && ![self.account.connectionProperties.identity.jid isEqualToString:jid])
        {
            DDLogInfo(@"Successfully fetched devicelist, now subscribing to this node for updates...");
            //don't subscribe devicelist twice (could be triggered by multiple useractions in a row)
            if([self.state.openDevicelistSubscriptions containsObject:jid])
                DDLogInfo(@"Deduplicated devicelist subscribe from %@", jid);
            else
                [self.account.pubsub subscribeToNode:@"eu.siacs.conversations.axolotl.devicelist" onJid:jid withHandler:$newHandlerWithInvalidation(self, handleDevicelistSubscribe, handleDevicelistSubscribeInvalidation)];
        }
        
        MLXMLNode* publishedDevices = [data objectForKey:@"current"];
        if(publishedDevices == nil && data.count == 1)
        {
            DDLogInfo(@"Client does not use 'current' as item id for it's bundle! keys=%@", [data allKeys]);
            //some clients do not use <item id="current">
            publishedDevices = [[data allValues] firstObject];
        }
        else if(publishedDevices == nil && data.count > 1)
            DDLogWarn(@"More than one devicelist item found from %@, ignoring all items!", jid);
        
        if(publishedDevices)
        {
            NSSet<NSNumber*>* deviceSet = [[NSSet<NSNumber*> alloc] initWithArray:[publishedDevices find:@"{eu.siacs.conversations.axolotl}list/device@id|uint"]];
            [self processOMEMODevices:deviceSet from:jid];
        }
        
    }
    
    if([self.account.connectionProperties.identity.jid isEqualToString:jid])
        [self repairQueuedSessions];                        //now try to repair all broken sessions (our catchup is now really done)
    else
        [self retriggerKeyTransportElementsForJid:jid];     //retrigger queued key transport elements for this jid (if any)
$$

-(void) postOMEMOMessageForUser:(NSString*) jid withMessage:(NSString*) omemoMessage
{
    if(![[DataLayer sharedInstance] isContactInList:jid forAccount:self.account.accountNo]) {
        [[DataLayer sharedInstance] addContact:jid forAccount:self.account.accountNo nickname:nil];
    }
    NSString* newMessageID = [[NSUUID UUID] UUIDString];
    NSNumber* historyId = [[DataLayer sharedInstance] addMessageHistoryTo:jid forAccount:self.account.accountNo withMessage:omemoMessage actuallyFrom:jid withId:newMessageID encrypted:NO messageType:kMessageTypeStatus mimeType:nil size:nil];

    MLMessage* message = [[DataLayer sharedInstance] messageForHistoryID:historyId];
    MLContact* contact = [MLContact createContactFromJid:jid andAccountNo:self.account.accountNo];
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalNewMessageNotice object:self.account userInfo:@{
        @"message": message,
        @"showAlert": @(NO),
        @"contact": contact,
    }];
}

-(void) processOMEMODevices:(NSSet<NSNumber*>*) receivedDevices from:(NSString*) source
{
    DDLogVerbose(@"Processing omemo devices from %@: %@", source, receivedDevices);

    NSMutableSet<NSNumber*>* existingDevices = [[self knownDevicesForAddressName:source] mutableCopy];
    // ensure that we refetch bundles of devices with broken bundles again after some time
    NSSet<NSNumber*>* existingDevicesReqPendingFetch = [NSSet setWithArray:[self.monalSignalStore knownDevicesWithPendingBrokenSessionHandling:source]];
    [existingDevices minusSet:existingDevicesReqPendingFetch];

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
            [self postOMEMOMessageForUser:source withMessage:[NSString stringWithFormat:NSLocalizedString(@"OMEMO: Device %@ is now inactive, because it is no longer advertised by your contact", @"OMEMO warning shown inside chat view"), deviceId]];
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
    else
        [self notifyKnownDevicesUpdated:source];
}

-(void) handleOwnDevicelistUpdate:(NSSet<NSNumber*>*) receivedDevices
{
    //check for new deviceids not previously known, but only if this isn't the first login we see a devicelist
    //this has to be a property of the xmpp class to persist it even across state resets
    if(self.account.hasSeenOmemoDeviceListAfterOwnDeviceid)
    {
        NSMutableSet<NSNumber*>* newDevices = [receivedDevices mutableCopy];
        [newDevices minusSet:self.ownDeviceList];
        //alert for all devices now still listed in newDevices
        for(NSNumber* device in newDevices)
            if([device unsignedIntValue] != self.monalSignalStore.deviceid)
            {
                DDLogWarn(@"Got new deviceid %@ for own account %@", device, self.account.connectionProperties.identity.jid);
                UNMutableNotificationContent* content = [UNMutableNotificationContent new];
                content.title = NSLocalizedString(@"New omemo device", @"");;
                content.subtitle = self.account.connectionProperties.identity.jid;
                content.body = [NSString stringWithFormat:NSLocalizedString(@"Detected a new omemo device on your account: %@", @""), device];
                content.sound = [UNNotificationSound defaultSound];
                content.categoryIdentifier = @"simple";
                UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:[NSString stringWithFormat:@"newOwnOmemoDevice::%@::%@", self.account.connectionProperties.identity.jid, device] content:content trigger:nil];
                NSError* error = [HelperTools postUserNotificationRequest:request];
                if(error)
                    DDLogError(@"Error posting new deviceid notification: %@", error);
            }
    }
    
    //update own devicelist (this can be an empty list, if the list on our server is empty)
    self.ownDeviceList = [receivedDevices mutableCopy];
    //this has to be a property of the xmpp class to persist it even across state resets
    self.account.hasSeenOmemoDeviceListAfterOwnDeviceid = YES;
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

    [self notifyKnownDevicesUpdated:self.account.connectionProperties.identity.jid];
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
    
    //update bundle fetch status
    self.openBundleFetchCnt++;
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateBundleFetchStatus object:self userInfo:@{
        @"accountNo": self.account.accountNo,
        @"completed": @(self.closedBundleFetchCnt),
        @"all": @(self.openBundleFetchCnt + self.closedBundleFetchCnt)
    }];
    
    NSString* bundleNode = [NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%@", deviceid];
    [self.account.pubsub fetchNode:bundleNode from:jid withItemsList:nil andHandler:$newHandlerWithInvalidation(self, handleBundleFetchResult, handleBundleFetchInvalidation, $ID(jid), $ID(rid, deviceid))];
    
    if(self.state.openBundleFetches[jid] == nil)
        self.state.openBundleFetches[jid] = [NSMutableSet new];
    [self.state.openBundleFetches[jid] addObject:deviceid];
    
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
    
    //retrigger queued key transport elements for this jid (if any)
    [self retriggerKeyTransportElementsForJid:jid];
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
                [self handleBundleWithInvalidEntryForJid:jid andRid:rid];
            }
        }
        //don't delete this device for errorReasons (normally server bugs or transient problems inside monal)
        else if(errorReason)
            DDLogError(@"Could not fetch bundle from %@: rid: %@ - %@", jid, rid, errorReason);
    }
    else
    {
        [self postOMEMOMessageForUser:jid withMessage:[NSString stringWithFormat:NSLocalizedString(@"OMEMO: Detected new device with id: %@", @"OMEMO warning shown inside chat view"), rid]];

        //check that a corresponding buddy exists -> prevent foreign key errors
        MLXMLNode* receivedKeys = data[@"current"];
        if(receivedKeys == nil && data.count == 1)
        {
            DDLogInfo(@"Client does not use 'current' as item id for it's bundle! rid=%@, keys=%@", rid, [data allKeys]);
            //some clients do not use <item id="current">
            receivedKeys = [[data allValues] firstObject];
        }
        else if(receivedKeys == nil && data.count > 1)
            DDLogWarn(@"More than one bundle item found from %@ rid: %@, ignoring all items!", jid, rid);
        
        if(receivedKeys)
            [self processOMEMOKeys:receivedKeys forJid:jid andRid:rid];
        else
        {
            DDLogWarn(@"Could not find any bundle in pubsub data from %@ rid: %@, data=%@", jid, rid, data);
            [self handleBundleWithInvalidEntryForJid:jid andRid:rid];
        }
    }
    
    //update bundle fetch status (this has to be done even in error cases!)
    [self decrementBundleFetchCount];
    
    //retrigger queued key transport elements for this jid (if any)
    [self retriggerKeyTransportElementsForJid:jid];
$$

-(void) handleBundleWithInvalidEntryForJid:(NSString*) jid andRid:(NSNumber*) rid
{
    SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:rid.unsignedIntValue];
    DDLogInfo(@"Marking device %@ bundle as broken, due to a invalid bundle", rid);
    [self.monalSignalStore markBundleAsBroken:address];
    if([jid isEqualToString:self.account.connectionProperties.identity.jid] && rid.unsignedIntValue != self.monalSignalStore.deviceid)
    {
        DDLogInfo(@"Removing device %@ from own device list, due to a invalid bundle", rid);
        [self.monalSignalStore markDeviceAsDeleted:address];
        // removing this device from own bundle
        [self.ownDeviceList removeObject:rid];
        // publish updated device list
        [self publishOwnDeviceList];
    }
}

-(BOOL) checkBundleFetchCount
{
    if(self.openBundleFetchCnt == 0 && self.state.catchupDone)
    {
        //update bundle fetch status (e.g. complete)
        self.openBundleFetchCnt = 0;
        self.closedBundleFetchCnt = 0;
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalFinishedOmemoBundleFetch object:self userInfo:@{
            @"accountNo": self.account.accountNo,
        }];
        return YES;
    }
    return NO;
}

-(void) decrementBundleFetchCount
{
    //update bundle fetch status (e.g. pending)
    self.openBundleFetchCnt--;
    self.closedBundleFetchCnt++;
    
    //check if we should send a bundle fetch status update or if checkBundleFetchCount already sent the final finished notification for us
    if(![self checkBundleFetchCount])
    {
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalUpdateBundleFetchStatus object:self userInfo:@{
            @"accountNo": self.account.accountNo,
            @"completed": @(self.closedBundleFetchCnt),
            @"all": @(self.openBundleFetchCnt + self.closedBundleFetchCnt),
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
    {
        DDLogWarn(@"bundle count != 1, ignoring: %@", bundles);
        return;
    }
    MLXMLNode* bundle = [bundles firstObject];

    //extract bundle data
    NSData* signedPreKeyPublic = [bundle findFirst:@"signedPreKeyPublic#|base64"];
    NSNumber* signedPreKeyPublicId = [bundle findFirst:@"signedPreKeyPublic@signedPreKeyId|uint"];
    NSData* signedPreKeySignature = [bundle findFirst:@"signedPreKeySignature#|base64"];
    NSData* identityKey = [bundle findFirst:@"identityKey#|base64"];

    //ignore bundles not conforming to the standard
    if(signedPreKeyPublic == nil || signedPreKeyPublicId == nil || signedPreKeySignature == nil || identityKey == nil)
    {
        DDLogWarn(@"Bundle not conforming to omemo standard, ignoring: signedPreKeyPublic=%@, signedPreKeyPublicId=%@, signedPreKeySignature=%@, identityKey=%@", signedPreKeyPublic, signedPreKeyPublicId, signedPreKeySignature, identityKey);
        return;
    }

    uint32_t deviceId = (uint32_t)rid.unsignedIntValue;
    SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:deviceId];
    SignalSessionBuilder* builder = [[SignalSessionBuilder alloc] initWithAddress:address context:self.signalContext];
    NSArray<NSNumber*>* preKeyIds = [bundle find:@"prekeys/preKeyPublic@preKeyId|uint"];

    if(preKeyIds == nil || preKeyIds.count == 0)
    {
        DDLogWarn(@"Could not create array of preKeyIds, ignoring: preKeyIds=%@ %lu", preKeyIds, (unsigned long)preKeyIds.count);
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
        // mark session as functional
        SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:(uint32_t)rid.unsignedIntValue];
        [self.monalSignalStore markBundleAsFixed:address];

        //found and imported a working key --> try to (re)build a new session proactively (or repair a broken one)
        [self sendKeyTransportElement:jid forRids:[NSSet setWithArray:@[rid]]];      //this will remove the queuedSessionRepairs entry, if any

        [self notifyKnownDevicesUpdated:jid];

        return;
    } while(++processedKeys < preKeyIds.count);
    DDLogError(@"Could not import a single prekey from bundle for rid %@ (tried %lu keys)", rid, processedKeys);
    //TODO: should we blacklist this device id?
    @synchronized(self.state.queuedSessionRepairs) {
        //remove this jid-rid combinations from queuedSessionRepairs
        if(self.state.queuedSessionRepairs[jid] != nil)
        {
            DDLogDebug(@"Removing deviceid %@ on jid %@ from queuedSessionRepairs...", rid, jid);
            [self.state.queuedSessionRepairs[jid] removeObject:rid];
        }
    }
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
    //OR
    //queue all actions until all devicelists and bundles of this jid are fetched
    if(!self.state.catchupDone || ([self.state.openDevicelistFetches containsObject:jid] || (self.state.openBundleFetches[jid] != nil && self.state.openBundleFetches[jid].count > 0)))
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
    //this will remove any queued key transport elements for rids used to encrypt so that we only send one key transport element
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

-(void) removeQueuedKeyTransportElementsFor:(NSString*) jid andDevices:(NSSet*) devices
{
    @synchronized(self.state.queuedKeyTransportElements) {
        if(self.state.queuedKeyTransportElements[jid] != nil)
        {
            [self.state.queuedKeyTransportElements[jid] minusSet:devices];
            if(self.state.queuedKeyTransportElements[jid].count == 0)
                [self.state.queuedKeyTransportElements removeObjectForKey:jid];
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

-(MLXMLNode* _Nullable) encryptString:(NSString* _Nullable) message toDeviceids:(NSDictionary<NSString*, NSSet<NSNumber*>*>*) contactDeviceMap
{
    
    MLXMLNode* encrypted = [[MLXMLNode alloc] initWithElement:@"encrypted" andNamespace:@"eu.siacs.conversations.axolotl"];

    MLEncryptedPayload* encryptedPayload;
    if(message)
    {
        // Encrypt message
        encryptedPayload = [AESGcm encrypt:[message dataUsingEncoding:NSUTF8StringEncoding] keySize:KEY_SIZE];
        if(encryptedPayload == nil)
        {
            showErrorOnAlpha(self.account, @"Could not encrypt normal message: AESGcm error");
            return nil;
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
            return nil;
        }
        encryptedPayload = [[MLEncryptedPayload alloc] initWithKey:newKey iv:newIv];
        if(encryptedPayload == nil)
        {
            showErrorOnAlpha(self.account, @"Could not encrypt transport message: AESGcm error");
            return nil;
        }
    }

    //add crypto header with our own deviceid
    MLXMLNode* header = [[MLXMLNode alloc] initWithElement:@"header" withAttributes:@{
        @"sid": [NSString stringWithFormat:@"%u", self.monalSignalStore.deviceid],
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"iv" andData:[HelperTools encodeBase64WithData:encryptedPayload.iv]],
    ] andData:nil];

    //add encryption for all given contacts' devices
    for(NSString* recipient in contactDeviceMap)
    {
        DDLogVerbose(@"Adding encryption for devices of %@: %@", recipient, contactDeviceMap[recipient]);
        [self addEncryptionKeyForAllDevices:contactDeviceMap[recipient] encryptForJid:recipient withEncryptedPayload:encryptedPayload withXMLHeader:header];
    }
    
    [encrypted addChildNode:header];
    return encrypted;
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
    
    NSMutableSet<NSString*>* recipients = [NSMutableSet new];
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
    
    NSMutableDictionary<NSString*, NSSet<NSNumber*>*>* contactDeviceMap = [NSMutableDictionary new];
    for(NSString* recipient in recipients)
    {
        //contactDeviceMap
        NSMutableSet<NSNumber*>* recipientDevices = [NSMutableSet new];
        [recipientDevices addObjectsFromArray:[self.monalSignalStore knownDevicesWithValidSession:recipient]];
        // add devices with known but old broken session to trigger a bundle refetch
        [recipientDevices addObjectsFromArray:[self.monalSignalStore knownDevicesWithPendingBrokenSessionHandling:recipient]];

         if(recipientDevices && recipientDevices.count > 0)
            contactDeviceMap[recipient] = recipientDevices;
    }

    //check if we found omemo keys of at least one of the recipients or more than 1 own device, otherwise don't encrypt anything
    NSSet<NSNumber*>* myDevices = [self knownDevicesForAddressName:self.account.connectionProperties.identity.jid];
    if(contactDeviceMap.count > 0 || myDevices.count > 1)
    {
        //add encryption for all of our own devices to contactDeviceMap
        DDLogVerbose(@"Adding encryption for OWN (%@) devices to contactDeviceMap: %@", self.account.connectionProperties.identity.jid, myDevices);
        contactDeviceMap[self.account.connectionProperties.identity.jid] = myDevices;
        
        //now encrypt everything to all collected deviceids
        MLXMLNode* envelope = [self encryptString:message toDeviceids:contactDeviceMap];
        if(envelope == nil)
        {
            DDLogError(@"Got nil envelope!");
            return;
        }
        [messageNode addChildNode:envelope];
    }
}

-(NSNumber* _Nullable) getTrustLevelForJid:(NSString*) jid andDeviceId:(NSNumber*) deviceid
{
    SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:(uint32_t)deviceid.unsignedIntValue];
    NSData* identity = [self.monalSignalStore getIdentityForAddress:address];
    if(!identity)
    {
        showErrorOnAlpha(self.account, @"Could not get Identity for: %@ device id %@", jid, deviceid);
        return nil;
    }
    return [self getTrustLevel:address identityKey:identity];
}

-(void) addEncryptionKeyForAllDevices:(NSSet<NSNumber*>*) devices encryptForJid:(NSString*) encryptForJid withEncryptedPayload:(MLEncryptedPayload*) encryptedPayload withXMLHeader:(MLXMLNode*) xmlHeader
{
    NSMutableSet* usedRids = [NSMutableSet new];
    //encrypt message for all given deviceids
    for(NSNumber* device in devices)
    {
        //do not encrypt for our own device (MUST be scoped by jid for omemo 2)
        if(device.unsignedIntValue == self.monalSignalStore.deviceid)
            continue;
        
        if(self.state.openBundleFetches[encryptForJid] != nil && [self.state.openBundleFetches[encryptForJid] containsObject:device])
        {
            DDLogWarn(@"Ignoring deviceid %@ of %@ for KeyTransportElement: bundle fetch still pending...", device, encryptForJid);
            continue;
        }
        
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
                //only show errors not being of type "unknown error"
                if(![error.domain isEqualToString:@"org.whispersystems.SignalProtocol"] || error.code != 0)
                    showErrorOnAlpha(self.account, @"Error while adding encryption key for jid: %@ device: %@ error: %@", encryptForJid, device, error);
                [self rebuildSessionWithJid:encryptForJid forRid:device];
                continue;
            }
            [xmlHeader addChildNode:[[MLXMLNode alloc] initWithElement:@"key" withAttributes:@{
                @"rid": [NSString stringWithFormat:@"%@", device],
                @"prekey": (deviceEncryptedKey.type == SignalCiphertextTypePreKeyMessage ? @"1" : @"0"),
            } andChildren:@[] andData:[HelperTools encodeBase64WithData:deviceEncryptedKey.data]]];
            
            //record this deviceid as used for encryption (it doesn't need any further key transport element potentially already queued)
            [usedRids addObject:device];
        }
    }
    
    //remove queued key transport element entry
    [self removeQueuedKeyTransportElementsFor:encryptForJid andDevices:usedRids];
}

-(NSString* _Nullable) decryptOmemoEnvelope:(MLXMLNode*) envelope forSenderJid:(NSString*) senderJid andReturnErrorString:(BOOL) returnErrorString
{
    DDLogVerbose(@"OMEMO envelope: %@", envelope);
    
    if(![envelope check:@"header"])
    {
        showErrorOnAlpha(self.account, @"decryptOmemoEnvelope called but the envelope has no encryption header");
        return nil;
    }
    
    BOOL isKeyTransportElement = ![envelope check:@"payload"];
    NSNumber* sid = [envelope findFirst:@"header@sid|uint"];

    SignalAddress* address = [[SignalAddress alloc] initWithName:senderJid deviceId:(uint32_t)sid.unsignedIntValue];

    if(!self.signalContext)
    {
        showErrorOnAlpha(self.account, @"Missing signal context in decrypt!");
        return !returnErrorString ? nil : NSLocalizedString(@"Error decrypting message", @"");
    }
    
    //don't try to decrypt our own messages (could be mirrored by MUC etc.)
    if([senderJid isEqualToString:self.account.connectionProperties.identity.jid] && sid.unsignedIntValue == self.monalSignalStore.deviceid)
        return nil;

    NSData* messageKey = [envelope findFirst:@"header/key<rid=%u>#|base64", self.monalSignalStore.deviceid];
    BOOL devicePreKey = [[envelope findFirst:@"header/key<rid=%u>@prekey|bool", self.monalSignalStore.deviceid] boolValue];
    
    DDLogVerbose(@"Decrypting using:\nrid=%u --> messageKey=%@\nrid=%u --> isPreKey=%@", self.monalSignalStore.deviceid, messageKey, self.monalSignalStore.deviceid, bool2str(devicePreKey));

    if(!messageKey && isKeyTransportElement)
    {
        DDLogVerbose(@"Received KeyTransportElement without our own rid included --> Ignore it");
        return nil;
    }
    else if(!messageKey)
    {
        DDLogError(@"Message was not encrypted for this device: %u", self.monalSignalStore.deviceid);
        [self rebuildSessionWithJid:senderJid forRid:sid];
        return !returnErrorString ? nil : [NSString stringWithFormat:NSLocalizedString(@"Message was not encrypted for this device. Please make sure the sender trusts deviceid %u.", @""), self.monalSignalStore.deviceid];
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
                return !returnErrorString ? nil : [NSString stringWithFormat:@"There was an error decrypting this encrypted KEY TRANSPORT message (Signal error). To resolve this, try sending an encrypted message to this person. (%@)", error];
#endif
            if(!isKeyTransportElement)
                return !returnErrorString ? nil : [NSString stringWithFormat:NSLocalizedString(@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person. (%@)", @""), error];
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
                return !returnErrorString ? nil : @"There was an error decrypting this encrypted KEY TRANSPORT message (Signal error). To resolve this, try sending an encrypted message to this person.";
#endif
            if(!isKeyTransportElement)
                return !returnErrorString ? nil : NSLocalizedString(@"There was an error decrypting this encrypted message (Signal error). To resolve this, try sending an encrypted message to this person.", @"");
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
                return !returnErrorString ? nil : [NSString stringWithFormat:@"ALPHA_DEBUG_MESSAGE: KeyTransportElement received from jid: %@ device: %@", senderJid, sid];
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
                NSData* iv = [envelope findFirst:@"header/iv#|base64"];
                NSData* decodedPayload = [envelope findFirst:@"payload#|base64"];
                if(iv == nil || iv.length != 12)
                {
                    showErrorOnAlpha(self.account, @"Could not decrypt message: iv length: %lu", (unsigned long)iv.length);
                    return !returnErrorString ? nil : NSLocalizedString(@"Error while decrypting: iv.length != 12", @"");
                }
                if(decodedPayload == nil)
                {
                    return !returnErrorString ? nil : NSLocalizedString(@"Error: Received OMEMO message is empty", @"");
                }
                
                NSData* decData = [AESGcm decrypt:decodedPayload withKey:key andIv:iv withAuth:auth];
                if(decData == nil)
                {
                    showErrorOnAlpha(self.account, @"Could not decrypt message with key that was decrypted. (GCM error)");
                    return !returnErrorString ? nil : NSLocalizedString(@"Encrypted message was sent in an older format Monal can't decrypt. Please ask them to update their client. (GCM error)", @"");
                }
                else
                    DDLogInfo(@"Successfully decrypted message, passing back cleartext string...");
                return [[NSString alloc] initWithData:decData encoding:NSUTF8StringEncoding];
            }
            else
            {
                showErrorOnAlpha(self.account, @"Could not get omemo decryption key");
                return !returnErrorString ? nil : NSLocalizedString(@"Could not decrypt message", @"");
            }
        }
    }
}

-(NSString* _Nullable) decryptMessage:(XMPPMessage*) messageNode withMucParticipantJid:(NSString* _Nullable) mucParticipantJid
{
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
    
    return [self decryptOmemoEnvelope:[messageNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted"] forSenderJid:senderJid andReturnErrorString:YES];
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

//called after new contact was added via roster or a new MUC member was added by MLMucProcessor
-(void) subscribeAndFetchDevicelistIfNoSessionExistsForJid:(NSString*) buddyJid
{
    if([self.monalSignalStore sessionsExistForBuddy:buddyJid] == NO)
    {
        MLContact* contact = [MLContact createContactFromJid:buddyJid andAccountNo:self.account.accountNo];
        //only do so if we don't receive automatic headline pushes of the devicelist
        if(!contact.isSubscribedTo)
            [self queryOMEMODevices:buddyJid withSubscribe:YES];
    }
}

//called after a buddy was deleted from roster OR by MLMucProcessor after a MUC member was removed
-(void) checkIfSessionIsStillNeeded:(NSString*) buddyJid isMuc:(BOOL) isMuc
{
    NSMutableSet<NSString*>* danglingJids = [NSMutableSet new];
    if(isMuc == YES)
        danglingJids = [[NSMutableSet alloc] initWithSet:[self.monalSignalStore removeDanglingMucSessions]];
    else if([self.monalSignalStore checkIfSessionIsStillNeeded:buddyJid] == NO)
        [danglingJids addObject:buddyJid];

    [self notifyKnownDevicesUpdated:buddyJid];
    DDLogVerbose(@"Unsubscribing from dangling jids: %@", danglingJids);
    for(NSString* jid in danglingJids)
        [self.account.pubsub unsubscribeFromNode:@"eu.siacs.conversations.axolotl.devicelist" forJid:jid withHandler:$newHandler(self, handleDevicelistUnsubscribe)];
}

//interfaces for UI
-(BOOL) isTrustedIdentity:(SignalAddress*) address identityKey:(NSData*) identityKey
{
    return [self.monalSignalStore isTrustedIdentity:address identityKey:identityKey];
}

-(NSNumber*) getTrustLevel:(SignalAddress*) address identityKey:(NSData*) identityKey
{
    return [self.monalSignalStore getTrustLevel:address identityKey:identityKey];
}

// add OMEMO identity manually to our signalstore
// only intended to be called from OMEMO QR scan UI
-(void) addIdentityManually:(SignalAddress*) address identityKey:(NSData* _Nonnull) identityKey
{
    [self.monalSignalStore saveIdentity:address identityKey:identityKey];
    [self notifyKnownDevicesUpdated:address.name];
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
    [self notifyKnownDevicesUpdated:address.name];
}

//debug button in contactdetails ui
-(void) clearAllSessionsForJid:(NSString*) jid
{
    NSSet<NSNumber*>* devices = [self knownDevicesForAddressName:jid];
    for(NSNumber* device in devices)
    {
        [self deleteDeviceForSource:jid andRid:device];
    }
    [self sendOMEMOBundle];
    [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:self.account.connectionProperties.identity.jid withItemsList:nil andHandler:$newHandlerWithInvalidation(self, handleDevicelistFetch, handleDevicelistFetchInvalidation, $BOOL(subscribe, NO))];
    [self.account.pubsub fetchNode:@"eu.siacs.conversations.axolotl.devicelist" from:jid withItemsList:nil andHandler:$newHandlerWithInvalidation(self, handleDevicelistFetch, handleDevicelistFetchInvalidation, $BOOL(subscribe, NO))];
}

@end

NS_ASSUME_NONNULL_END
