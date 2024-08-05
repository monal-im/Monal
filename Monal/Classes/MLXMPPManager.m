//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <UserNotifications/UserNotifications.h>

#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "DataLayer.h"
#import "HelperTools.h"
#import "xmpp.h"
#import "XMPPMessage.h"
#import "MLNotificationQueue.h"
#import "MLNotificationManager.h"
#import "MLOMEMO.h"
#import <monalxmpp/monalxmpp-Swift.h>

@import Network;
@import MobileCoreServices;
@import SAMKeychain;
@import Intents;

static const int pingFreqencyMinutes = 5;       //about the same Conversations uses
#define FIRST_LOGIN_TIMEOUT 30.0

@interface MLXMPPManager()
{
    nw_path_monitor_t _path_monitor;
    BOOL _hasConnectivity;
    NSMutableArray* _connectedXMPP;
}
@end

@implementation MLXMPPManager

-(void) defaultSettings
{
    [self upgradeBoolUserSettingsIfUnset:@"Sound" toDefault:YES];
    [self upgradeObjectUserSettingsIfUnset:@"AlertSoundFile" toDefault:@"alert2"];

    // upgrade ShowGeoLocation
    [self upgradeBoolUserSettingsIfUnset:@"ShowGeoLocation" toDefault:YES];

    // upgrade SendLastUserInteraction
    [self upgradeBoolUserSettingsIfUnset:@"SendLastUserInteraction" toDefault:YES];

    // upgrade SendLastChatState
    [self upgradeBoolUserSettingsIfUnset:@"SendLastChatState" toDefault:YES];

    // upgrade received and displayed markers
    [self upgradeBoolUserSettingsIfUnset:@"SendReceivedMarkers" toDefault:YES];
    [self upgradeBoolUserSettingsIfUnset:@"SendDisplayedMarkers" toDefault:YES];
    
    //upgrade url preview
    [self upgradeBoolUserSettingsIfUnset:@"ShowURLPreview" toDefault:YES];
    
    //upgrade message autodeletion and migrate old "3 days" setting
    NSNumber* oldAutodelete = [[HelperTools defaultsDB] objectForKey:@"AutodeleteAllMessagesAfter3Days"];
    if(oldAutodelete != nil && [oldAutodelete boolValue])
    {
        [self upgradeIntegerUserSettingsIfUnset:@"AutodeleteInterval" toDefault:259200];
        [self removeObjectUserSettingsIfSet:@"AutodeleteAllMessagesAfter3Days"];
    }
    else
        [self upgradeIntegerUserSettingsIfUnset:@"AutodeleteInterval" toDefault:0];
    
    //upgrade default omemo on
    [self upgradeBoolUserSettingsIfUnset:@"OMEMODefaultOn" toDefault:YES];
    
    // upgrade udp logger
    [self upgradeBoolUserSettingsIfUnset:@"udpLoggerEnabled" toDefault:NO];
    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerHostname" toDefault:@""];
    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerPort" toDefault:@""];
    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerKey" toDefault:@""];

    // upgrade Message Settings / Privacy
    [self upgradeIntegerUserSettingsIfUnset:@"NotificationPrivacySetting" toDefault:NotificationPrivacySettingOptionDisplayNameAndMessage];

    // upgrade filetransfer settings
    [self upgradeBoolUserSettingsIfUnset:@"AutodownloadFiletransfers" toDefault:YES];

    //upgrade syncErrorsDisplayed list
    [self upgradeObjectUserSettingsIfUnset:@"syncErrorsDisplayed" toDefault:@{}];

    [self upgradeFloatUserSettingsToInteger:@"AutodownloadFiletransfersMobileMaxSize"];
    [self upgradeFloatUserSettingsToInteger:@"AutodownloadFiletransfersWifiMaxSize"];
    [self upgradeIntegerUserSettingsIfUnset:@"AutodownloadFiletransfersMobileMaxSize" toDefault:5*1024*1024];     // 5 MiB
    [self upgradeIntegerUserSettingsIfUnset:@"AutodownloadFiletransfersWifiMaxSize" toDefault:32*1024*1024];     // 32 MiB

    // upgrade default image quality
    [self upgradeFloatUserSettingsIfUnset:@"ImageUploadQuality" toDefault:0.50];

    // remove old settings from shareSheet outbox
    [self removeObjectUserSettingsIfSet:@"lastRecipient"];
    [self removeObjectUserSettingsIfSet:@"lastAccount"];
    // remove HasSeenIntro bool
    [self removeObjectUserSettingsIfSet:@"HasSeenIntro"];

    // add default pushserver
    [self upgradeObjectUserSettingsIfUnset:@"selectedPushServer" toDefault:[HelperTools getSelectedPushServerBasedOnLocale]];
    
    //upgrade background image settings
    NSString* bgImage = [[HelperTools defaultsDB] objectForKey:@"BackgroundImage"];
    //image was selected, but it was no custom image --> remove it
    if(bgImage != nil && [@"CUSTOM" isEqualToString:bgImage])
        [self removeObjectUserSettingsIfSet:@"BackgroundImage"];
    [self removeObjectUserSettingsIfSet:@"ChatBackgrounds"];

    // add STUN / TURN settings
    [self upgradeBoolUserSettingsIfUnset:@"webrtcAllowP2P" toDefault:YES];
    [self upgradeBoolUserSettingsIfUnset:@"webrtcUseFallbackTurn" toDefault:YES];
    
    //jabber:iq:version
    [self upgradeBoolUserSettingsIfUnset:@"allowVersionIQ" toDefault:YES];
    
    //default value for sanbox is no (e.g. production)
    [self upgradeBoolUserSettingsIfUnset:@"isSandboxAPNS" toDefault:NO];
    
    //anti spam/privacy setting, but default to yes (current behavior, conversations behavior etc.)
    [self upgradeBoolUserSettingsIfUnset:@"allowNonRosterContacts" toDefault:YES];
    [self upgradeBoolUserSettingsIfUnset:@"allowCallsFromNonRosterContacts" toDefault:YES];
    
    //mac catalyst will not show a soft-keyboard when setting focus, ios will
    //--> only automatically set focus on macos and make this configurable
#if TARGET_OS_MACCATALYST
    [self upgradeBoolUserSettingsIfUnset:@"showKeyboardOnChatOpen" toDefault:YES];
#else
    [self upgradeBoolUserSettingsIfUnset:@"showKeyboardOnChatOpen" toDefault:NO];
#endif
    
#ifdef IS_ALPHA
    [self upgradeBoolUserSettingsIfUnset:@"useDnssecForAllConnections" toDefault:YES];
#else
    [self upgradeBoolUserSettingsIfUnset:@"useDnssecForAllConnections" toDefault:NO];
#endif
    
    NSTimeZone* timeZone = [NSTimeZone localTimeZone];
    DDLogVerbose(@"Current timezone name: '%@'...", [timeZone name]);
    if([[timeZone name] containsString:@"Europe"])
        [self upgradeBoolUserSettingsIfUnset:@"useInlineSafari" toDefault:NO];
    else
        [self upgradeBoolUserSettingsIfUnset:@"useInlineSafari" toDefault:YES];
    
    [self upgradeBoolUserSettingsIfUnset:@"hasCompletedOnboarding" toDefault:NO];
    
    [self upgradeBoolUserSettingsIfUnset:@"uploadImagesOriginal" toDefault:NO];
    
    [self upgradeBoolUserSettingsIfUnset:@"hardlinkFiletransfersIntoDocuments" toDefault:YES];
    
// //always show onboarding on simulator for now
// #if TARGET_OS_SIMULATOR
//     [[HelperTools defaultsDB] setBool:NO forKey:@"hasCompletedOnboarding"];
// #endif
}

-(void) upgradeFloatUserSettingsToInteger:(NSString*) settingsName
{
    if([[HelperTools defaultsDB] objectForKey:settingsName] == nil)
        return;
    NSInteger value = (NSInteger)[[HelperTools defaultsDB] floatForKey:settingsName];
    [[HelperTools defaultsDB] setInteger:value forKey:settingsName];
    [[HelperTools defaultsDB] synchronize];
}

-(void) upgradeBoolUserSettingsIfUnset:(NSString*) settingsName toDefault:(BOOL) defaultVal
{
    NSNumber* currentSettingVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingVal == nil)
    {
        [[HelperTools defaultsDB] setBool:defaultVal forKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

-(void) upgradeIntegerUserSettingsIfUnset:(NSString*) settingsName toDefault:(NSInteger) defaultVal
{
    NSNumber* currentSettingVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingVal == nil)
    {
        [[HelperTools defaultsDB] setInteger:defaultVal forKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

-(void) upgradeFloatUserSettingsIfUnset:(NSString*) settingsName toDefault:(float) defaultVal
{
    NSNumber* currentSettingVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingVal == nil)
    {
        [[HelperTools defaultsDB] setFloat:defaultVal forKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

-(void) upgradeObjectUserSettingsIfUnset:(NSString*) settingsName toDefault:(nullable id) defaultVal
{
    NSNumber* currentSettingVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingVal == nil)
    {
        [[HelperTools defaultsDB] setObject:defaultVal forKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

-(void) removeObjectUserSettingsIfSet:(NSString*) settingsName
{
    NSObject* currentSettingsVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingsVal != nil)
    {
        DDLogInfo(@"Removing defaultsDB Entry %@", settingsName);
        [[HelperTools defaultsDB] removeObjectForKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

+(MLXMPPManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLXMPPManager* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [MLXMPPManager new] ;
    });
    return sharedInstance;
}

-(id) init
{
    self = [super init];

    _connectedXMPP = [NSMutableArray new];
    _hasConnectivity = NO;
    _isBackgrounded = NO;
    _isNotInFocus = NO;
    _onMobile = NO;
    _isConnectBlocked = NO;
    
    [self defaultSettings];
    [self setPushToken:nil];       //load push settings from defaultsDB (can be overwritten later on in mainapp, but *not* in appex)

    //set up regular ping
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    _pinger = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q_background);

    dispatch_source_set_timer(_pinger,
                              DISPATCH_TIME_NOW,
                              60ull * NSEC_PER_SEC * pingFreqencyMinutes,
                              60ull * NSEC_PER_SEC);        //allow for better battery optimizations

    dispatch_source_set_event_handler(_pinger, ^{
        for(xmpp* xmppAccount in [self connectedXMPP])
        {
            if(xmppAccount.accountState>=kStateBound) {
                DDLogInfo(@"began a idle ping");
                [xmppAccount sendPing:LONG_PING];        //long ping timeout because this is a background/interval ping
            }
        }
    });

    dispatch_source_set_cancel_handler(_pinger, ^{
        DDLogInfo(@"pinger canceled");
    });

    dispatch_resume(_pinger);

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];

    //this processes the sharesheet outbox only, the handler in the NotificationServiceExtension will do more interesting things
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(catchupFinished:) name:kMonalFinishedCatchup object:nil];

    _path_monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(_path_monitor, q_background);
    nw_path_monitor_set_update_handler(_path_monitor, ^(nw_path_t path) {
        DDLogVerbose(@"*** nw_path_monitor: update_handler called");
        DDLogDebug(@"*** nw_path_monitor: nw_path_is_constrained=%@", bool2str(nw_path_is_constrained(path)));
        DDLogDebug(@"*** nw_path_monitor: nw_path_is_expensive=%@", bool2str(nw_path_is_expensive(path)));
        self->_onMobile = nw_path_is_constrained(path) || nw_path_is_expensive(path);
        DDLogDebug(@"*** nw_path_monitor: on 'mobile' --> %@", bool2str(self->_onMobile));
        if(nw_path_get_status(path) == nw_path_status_satisfied && !self->_hasConnectivity)
        {
            DDLogVerbose(@"reachable again");
            self->_hasConnectivity = YES;
            for(xmpp* xmppAccount in [self connectedXMPP])
            {
                if(![HelperTools isAppExtension])
                {
                    //try to send a ping. if it fails, it will reconnect
                    DDLogVerbose(@"manager pinging");
                    [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
                }
                else
                {
                    //don't reconnect if appex has frozen our queues!
                    if(!xmppAccount.parseQueueFrozen)
                        [xmppAccount reconnect:0];      //try to immediately reconnect, don't bother pinging
                    else
                        DDLogDebug(@"Not trying to reconnect in 0s, parse queue frozen!");
                }
            }
            
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalConnectivityChange object:self userInfo:@{@"reachable": @YES}];
        }
        else if(nw_path_get_status(path) != nw_path_status_satisfied && self->_hasConnectivity)
        {
            DDLogVerbose(@"NOT reachable");
            self->_hasConnectivity = NO;
            
            DDLogVerbose(@"scheduling background fetching task to start app in background once our connectivity gets restored");
            //this will automatically start the app if connectivity gets restored
            //always force as soon as possible to make sure any missed pushes get compensated for
            //don't queue this notification because it should be handled immediately
            [[NSNotificationCenter defaultCenter] postNotificationName:kScheduleBackgroundTask object:nil userInfo:@{@"force": @YES}];
            
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalConnectivityChange object:self userInfo:@{@"reachable": @NO}];
        }
        else if(nw_path_get_status(path) == nw_path_status_satisfied)
        {
            DDLogVerbose(@"still reachable");
            //when switching from wifi to mobile (or back) we sometimes don't have any unreachable state in between
            //--> reconnect directly because switching from wifi to mobile will cut the connection a few seconds after the switch anyways
            //NOTE: wait for 1 sec before reconnecting to compensate for multiple nw_path updates in a row
            for(xmpp* xmppAccount in [self connectedXMPP])
                //don't reconnect if appex has frozen our queues!
                if(!xmppAccount.parseQueueFrozen)
                {
                    [NSThread sleepForTimeInterval:1];
                    [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
                }
                else
                    DDLogDebug(@"Not pinging after 1s, parse queue frozen!");
            
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalConnectivityChange object:self userInfo:@{@"reachable": @YES}];
        }
        else
            DDLogVerbose(@"nothing changed, still NOT reachable");
    });
    nw_path_monitor_start(_path_monitor);
    
    //trigger iq invalidations and idle timers from a background thread because timeouts aren't time critical
    //we use this to decrement the timeout value of an iq handler / idle timer every second until it reaches zero
    dispatch_async(dispatch_queue_create_with_target("im.monal.timeouts", DISPATCH_QUEUE_SERIAL, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)), ^{
        while(YES) {
            for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
                [account updateIqHandlerTimeouts];
            
            //needed to not crash the app with an obscure EXC_BREAKPOINT while deleting something in a currently open chat
            //the crash report then contains: message at /usr/lib/system/libdispatch.dylib: API MISUSE: Resurrection of an object
            //(triggered by [HelperTools dispatchAsync:reentrantOnQueue:withBlock:] in it's call to dispatch_get_current_queue())
            dispatch_async(dispatch_get_main_queue(), ^{
                NSInteger autodeleteInterval = [[HelperTools defaultsDB] integerForKey:@"AutodeleteInterval"];
                if(autodeleteInterval > 0)
                {
                    NSNumber* deletionCount = [[DataLayer sharedInstance] autoDeleteMessagesAfterInterval:(NSTimeInterval)autodeleteInterval];
                    //make sure our ui updates after a deletion
                    if(deletionCount.integerValue > 0)
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
                }
            });
            
            [NSThread sleepForTimeInterval:1];
        }
    });
    
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if(_pinger)
        dispatch_source_cancel(_pinger);
}

//this returns a copy to iterate on without the need of a synchronized block while iterating
-(NSArray*) connectedXMPP
{
    @synchronized(_connectedXMPP) {
        return [[NSArray alloc] initWithArray:_connectedXMPP];
    }
}

-(void) catchupFinished:(NSNotification*) notification
{
    xmpp* account = notification.object;
    DDLogInfo(@"### MAM/SMACKS CATCHUP FINISHED FOR ACCOUNT NO %@ ###", account.accountNo);
}

-(BOOL) allAccountsIdle
{
    for(xmpp* xmppAccount in [self connectedXMPP])
        if(!xmppAccount.idle)
            return NO;
    return YES;
}

#pragma mark - app state

-(void) noLongerInFocus
{
    _isBackgrounded = NO;
    _isNotInFocus = YES;
}

-(void) nowBackgrounded
{
    DDLogInfo(@"App now backgrounded...");
    
    _isBackgrounded = YES;
    _isNotInFocus = YES;
    
    for(xmpp* xmppAccount in [self connectedXMPP])
        [xmppAccount setClientInactive];
}

-(void) nowForegrounded
{
    DDLogInfo(@"App now foregrounded...");
    
    _isBackgrounded = NO;
    _isNotInFocus = NO;
    
    //*** we don't need to check for a running service extension here because the appdelegate does this already for us ***
    
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        [xmppAccount unfreeze];
        [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        [xmppAccount setClientActive];
    }
    
    //we are in foreground now (or at least we have been for a few seconds)
    //--> clear sync error notifications so that they can appear again
    //wait some time to make sure all xmpp class instances have been created
    createTimer(1, (^{
        [HelperTools clearSyncErrorsOnAppForeground];
    }));
}

#pragma mark - Connection related

-(BOOL) isAccountForIdConnected:(NSNumber*) accountNo
{
    xmpp* account = [self getConnectedAccountForID:accountNo];
    if(account.accountState>=kStateBound) return YES;
    return NO;
}

-(NSDate *) connectedTimeFor:(NSNumber*) accountNo
{
    xmpp* account = [self getConnectedAccountForID:accountNo];
    return account.connectedTime;
}

-(xmpp* _Nullable) getConnectedAccountForID:(NSNumber*) accountNo
{
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        //using stringWithFormat: makes sure this REALLY is a string
        if(xmppAccount.accountNo.intValue == accountNo.intValue)
            return xmppAccount;
    }
    return nil;
}

-(void) connectAccount:(NSNumber*) accountNo
{
    NSDictionary* account = [[DataLayer sharedInstance] detailsForAccount:accountNo];
    if(!account)
        DDLogError(@"Expected account settings in db for accountNo: %@", accountNo);
    else
        [self connectAccountWithDictionary:account];
}

-(void) connectAccountWithDictionary:(NSDictionary*) account
{
    xmpp* existing = [self getConnectedAccountForID:[account objectForKey:kAccountID]];
    if(existing)
    {
        if(![account[@"enabled"] boolValue])
        {
            DDLogInfo(@"existing but disabled account, ignoring");
            return;
        }
        if(_isConnectBlocked)
        {
            DDLogWarn(@"connect blocked, ignoring");
            return;
        }
        DDLogInfo(@"existing account, calling unfreeze");
        [existing unfreeze];
        DDLogInfo(@"existing account, just pinging.");
        [existing sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        return;
    }
    DDLogVerbose(@"connecting account %@@%@",[account objectForKey:kUsername], [account objectForKey:kDomain]);

    NSError* error;
    NSString* jid = [NSString stringWithFormat:@"%@@%@", account[kUsername], account[kDomain]];
    NSString* password = [SAMKeychain passwordForService:kMonalKeychainName account:((NSNumber*)account[kAccountID]).stringValue error:&error];
    if(error)
    {
        DDLogError(@"Keychain error: %@", error);
        
        // Disable account because login will not be possible
        [[DataLayer sharedInstance] disableAccountForPasswordMigration:account[kAccountID]];
        [self disconnectAccount:account[kAccountID] withExplicitLogout:YES];
        
        //show notifications for disabled accounts to warn user if in appex
        if([HelperTools isAppExtension])
        {
            UNMutableNotificationContent* content = [UNMutableNotificationContent new];
            content.title = NSLocalizedString(@"Account disabled", @"");;
            content.subtitle = jid;
            content.body = NSLocalizedString(@"You restored an iCloud backup of Monal, please open the app to reenable this account.", @"");
            content.sound = [UNNotificationSound defaultSound];
            content.categoryIdentifier = @"simple";
            UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:[NSString stringWithFormat:@"disabled::%@", jid] content:content trigger:nil];
            error = [HelperTools postUserNotificationRequest:request];
            if(error)
                DDLogError(@"Error posting account disabled notification: %@", error);
        }
        
        return;
    }
    MLXMPPIdentity* identity = [[MLXMPPIdentity alloc] initWithJid:jid password:password andResource:[account objectForKey:kResource]];
    MLXMPPServer* server = [[MLXMPPServer alloc] initWithHost:[account objectForKey:kServer] andPort:[account objectForKey:kPort] andDirectTLS:[[account objectForKey:kDirectTLS] boolValue]];
    xmpp* xmppAccount = [[xmpp alloc] initWithServer:server andIdentity:identity andAccountNo:[account objectForKey:kAccountID]];
    xmppAccount.statusMessage = [account objectForKey:@"statusMessage"];

    @synchronized(_connectedXMPP) {
        [_connectedXMPP addObject:xmppAccount];
    }

    if(![account[@"enabled"] boolValue])
    {
        DDLogInfo(@"existing but disabled account, not connecting");
        return;
    }
    if(!self.isConnectBlocked)
    {
        DDLogInfo(@"starting connect");
        [xmppAccount connect];
    }
    else
        DDLogWarn(@"connect blocked, not connecting newly created xmpp* instance");
}

-(void) disconnectAccount:(NSNumber*) accountNo withExplicitLogout:(BOOL) explicitLogout
{
    int index = 0;
    int pos = -1;
    xmpp* account;
    @synchronized(_connectedXMPP) {
        for(xmpp* xmppAccount in _connectedXMPP)
        {
            if(xmppAccount.accountNo.intValue == accountNo.intValue)
            {
                account = xmppAccount;
                pos=index;
                break;
            }
            index++;
        }

        if((pos >= 0) && (pos < (int)[_connectedXMPP count]))
        {
            [_connectedXMPP removeObjectAtIndex:pos];
            DDLogVerbose(@"removed account at pos  %d", pos);
        }
    }
    if(account)
    {
        DDLogVerbose(@"got account and cleaning up.. ");
        [account disconnect:explicitLogout];
        account = nil;
        DDLogVerbose(@"done cleaning up account ");
    }
}


-(void) reconnectAll
{
    NSArray* allAccounts = [[DataLayer sharedInstance] accountList];        //this will also "disconnect" disabled account, just to make sure
    for(NSDictionary* account in allAccounts)
    {
        DDLogVerbose(@"Forcefully disconnecting account %@ (%@@%@)", [account objectForKey:kAccountID], [account objectForKey:@"username"], [account objectForKey:@"domain"]);
        xmpp* xmppAccount = [self getConnectedAccountForID:[account objectForKey:kAccountID]];
        if(xmppAccount != nil)
            [xmppAccount disconnect:YES];
    }
    createTimer(2.0, (^{
        [self connectIfNecessary];
    }));
}

-(void) disconnectAll
{
    DDLogVerbose(@"manager disconnecAll");
    dispatch_queue_t queue = dispatch_queue_create("im.monal.disconnect", DISPATCH_QUEUE_CONCURRENT);
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        //disconnect to prevent endless loops trying to connect
        dispatch_async(queue, ^{
            DDLogVerbose(@"manager disconnecting: %@", xmppAccount.accountNo);
            [xmppAccount disconnect];
            DDLogVerbose(@"manager disconnected: %@", xmppAccount.accountNo);
        });
    }
    dispatch_barrier_sync(queue, ^{
        DDLogVerbose(@"manager disconnecAll done (inside barrier)");
    });
    DDLogVerbose(@"manager disconnecAll done");
}

-(void) connectIfNecessary
{
    DDLogVerbose(@"manager connectIfNecessary");
    NSArray* enabledAccountList = [[DataLayer sharedInstance] enabledAccountList];
    for(NSDictionary* account in enabledAccountList)
        [self connectAccountWithDictionary:account];
    DDLogVerbose(@"manager connectIfNecessary done");
}

-(void) updatePassword:(NSString*) password forAccount:(NSNumber*) accountNo
{
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
    [SAMKeychain setPassword:password forService:kMonalKeychainName account:accountNo.stringValue];
    xmpp* xmpp = [self getConnectedAccountForID:accountNo];
    [xmpp.connectionProperties.identity updatPassword:password];
}

-(BOOL) isValidPassword:(NSString*) password forAccount:(NSNumber*) accountNo
{
    return [password isEqualToString:[SAMKeychain passwordForService:kMonalKeychainName account:accountNo.stringValue]];
}

#pragma mark -  XMPP commands
-(void) sendMessageAndAddToHistory:(NSString*) message havingType:(NSString*) messageType toContact:(MLContact*) contact isEncrypted:(BOOL) encrypted uploadInfo:(NSDictionary* _Nullable) uploadInfo withCompletionHandler:(void (^ _Nullable)(BOOL success, NSString* messageId)) completion
{
    NSString* msgid = [[NSUUID UUID] UUIDString];
    xmpp* account = [self getConnectedAccountForID:contact.accountId];

    MLAssert(message != nil, @"Message should not be nil");
    MLAssert(account != nil, @"Account should not be nil");
    MLAssert(contact != nil, @"Contact should not be nil");
    MLAssert(uploadInfo == nil || messageType == kMessageTypeFiletransfer, @"You must use message type = filetransfer if you supply an uploadInfo!");
    
    // Save message to history
    NSNumber* messageDBId = [[DataLayer sharedInstance]
        addMessageHistoryTo:contact.contactJid
                   forAccount:contact.accountId
                  withMessage:message
                 actuallyFrom:(contact.isGroup ? contact.accountNickInGroup : account.connectionProperties.identity.jid)
                       withId:msgid
                    encrypted:encrypted
                  messageType:messageType
                     mimeType:uploadInfo[@"mimeType"]
                         size:uploadInfo[@"size"]
    ];
    // Send message
    if(messageDBId != nil)
    {
        DDLogInfo(@"Message added to history with id %ld, now sending...", (long)[messageDBId intValue]);
        [self sendMessage:message toContact:contact isEncrypted:encrypted isUpload:(uploadInfo != nil) messageId:msgid withCompletionHandler:^(BOOL successSend, NSString* messageIdSend) {
            completion(successSend, messageIdSend);
        }];
        DDLogVerbose(@"Notifying active chats of change for contact %@", contact);
        [[MLNotificationQueue currentQueue] postNotificationName:kMLMessageSentToContact object:self userInfo:@{@"contact":contact}];
        
        //create and donate interaction to allow for ios 15 suggestions
        if(@available(iOS 15.0, macCatalyst 15.0, *))
            [[MLNotificationManager sharedInstance] donateInteractionForOutgoingDBId:messageDBId];
    }
    else
    {
        DDLogError(@"Could not add message to history!");
        completion(false, nil);
    }
}

-(void) sendMessage:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypted isUpload:(BOOL) isUpload messageId:(NSString*) messageId withCompletionHandler:(void (^ _Nullable)(BOOL success, NSString* messageId)) completion
{
    BOOL success = NO;
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    if(account)
    {
        success = YES;
        [account sendMessage:message toContact:contact isEncrypted:encrypted isUpload:isUpload andMessageId:messageId];
    }
    if(completion)
        completion(success, messageId);
}

-(void) sendChatState:(BOOL) isTyping toContact:(MLContact*) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    if(account)
        [account sendChatState:isTyping toContact:contact];
}

#pragma mark - login/register

//this will NOT set plain_activated to YES, only using the advanced account creation ui can do this
-(NSNumber*) login:(NSString*) jid password:(NSString*) password
{
    //check if it is a JID
    NSArray* elements = [jid componentsSeparatedByString:@"@"];
    MLAssert([elements count] > 1, @"Got invalid jid", (@{@"jid": nilWrapper(jid), @"elements": elements}));

    NSString* domain;
    NSString* user;
    user = ((NSString*)[elements objectAtIndex:0]).lowercaseString;
    domain = ((NSString*)[elements objectAtIndex:1]).lowercaseString;

    if([[DataLayer sharedInstance] doesAccountExistUser:user andDomain:domain])
    {
        [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:nil userInfo:@{
            @"title": NSLocalizedString(@"Duplicate Account", @""),
            @"description": NSLocalizedString(@"This account already exists on this instance", @"")
        }];
        return nil;
    }

    NSMutableDictionary* dic  = [NSMutableDictionary new];
    [dic setObject:domain forKey:kDomain];
    [dic setObject:user forKey:kUsername];
    [dic setObject:[HelperTools encodeRandomResource]  forKey:kResource];
    [dic setObject:@YES forKey:kEnabled];
    [dic setObject:@NO forKey:kDirectTLS];
    //we don't want to set kPlainActivated (not even according to our preload list) and default to plain_activated=false,
    //because the error message will warn the user and direct them to the advanced account creation menu to activate PLAIN
    //if they still want to connect to this server
    //only exception: yax.im --> we don't want to suggest a server during account creation that has a scary warning
    //when logging in using another device afterwards
    //TODO: to be removed once yax.im and quicksy.im supports SASL2 and SSDP!!
    //TODO: use preload list and allow PLAIN for all others once enough domains are on this list
    [dic setObject:([domain isEqualToString:@"yax.im"] || [domain isEqualToString:@"quicksy.im"] ? @YES : @NO) forKey:kPlainActivated];

    NSNumber* accountNo = [[DataLayer sharedInstance] addAccountWithDictionary:dic];
    if(accountNo == nil)
        return nil;
    [self addNewAccountToKeychainAndConnectWithPassword:password andAccountNo:accountNo];
    return accountNo;
}

-(void) addNewAccountToKeychainAndConnectWithPassword:(NSString*) password andAccountNo:(NSNumber*) accountNo
{
    if(accountNo != nil && password != nil)
    {
        [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
        [SAMKeychain setPassword:password forService:kMonalKeychainName account:accountNo.stringValue];
        [self connectAccount:accountNo];
    }
}

-(void) removeAccountForAccountNo:(NSNumber*) accountNo
{
    [self disconnectAccount:accountNo withExplicitLogout:YES];
    [[DataLayer sharedInstance] removeAccount:accountNo];
    [SAMKeychain deletePasswordForService:kMonalKeychainName account:accountNo.stringValue];
    [HelperTools removeAllShareInteractionsForAccountNo:accountNo];
    // trigger UI removal
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
}

#pragma mark - getting details

-(NSString*) getAccountNameForConnectedRow:(NSUInteger) row
{
    xmpp* account;
    @synchronized(_connectedXMPP) {
        if(row<[_connectedXMPP count] && row>=0)
            account = [_connectedXMPP objectAtIndex:row];
    }
    if(account)
        return account.connectionProperties.identity.jid;
    return @"";
}

#pragma mark - contact

//this handler will simply retry the removeContact: call
$$class_handler(handleRemoveContact, $$ID(MLContact*, contact))
    [[MLXMPPManager sharedInstance] removeContact:contact];
$$
-(void) removeContact:(MLContact*) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    if(account)
    {
        //queue remove contact for execution once bound (e.g. on catchup done)
        if(account.accountState < kStateBound)
        {
            [account addReconnectionHandler:$newHandler(self, handleRemoveContact, $ID(contact))];
            return;
        }
        
        if(contact.isGroup)
            [account leaveMuc:contact.contactJid];
        else
            [account removeFromRoster:contact];
        
        //remove from DB
        [[DataLayer sharedInstance] removeBuddy:contact.contactJid forAccount:contact.accountId];
        [contact removeShareInteractions];
        
        //notify the UI
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRemoved object:account userInfo:@{
            @"contact": [MLContact createContactFromJid:contact.contactJid andAccountNo:contact.accountId]
        }];
    }
}

-(void) addContact:(MLContact*) contact
{
    [self addContact:contact withPreauthToken:nil];
}

//this handler will simply retry the addContact:withPreauthToken: call
$$class_handler(handleAddContact, $$ID(MLContact*, contact), $_ID(NSString*, preauthToken))
    [[MLXMPPManager sharedInstance] addContact:contact withPreauthToken:preauthToken];
$$
-(void) addContact:(MLContact*) contact withPreauthToken:(NSString* _Nullable) preauthToken
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    if(account)
    {
        //queue add contact for execution once bound (e.g. on catchup done)
        if(account.accountState < kStateBound)
        {
            [account addReconnectionHandler:$newHandler(self, handleAddContact, $ID(contact), $ID(preauthToken))];
            return;
        }
        
        if(contact.isGroup)
            [account joinMuc:contact.contactJid];
        else
        {
            [account addToRoster:contact withPreauthToken:preauthToken];
            
#ifndef DISABLE_OMEMO
            // Request omemo devicelist
            [account.omemo subscribeAndFetchDevicelistIfNoSessionExistsForJid:contact.contactJid];
#endif// DISABLE_OMEMO
        }
        
        //notify the UI
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self userInfo:@{
            @"contact": [MLContact createContactFromJid:contact.contactJid andAccountNo:contact.accountId]
        }];
    }
}

-(void) getEntitySoftWareVersionForContact:(MLContact*) contact andResource:(NSString*) resource
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    
    NSString* xmppId = @"";
    if ((resource == nil) || ([resource length] == 0)) {
        xmppId = [NSString stringWithFormat:@"%@",contact.contactJid];
    } else {
        xmppId = [NSString stringWithFormat:@"%@/%@",contact.contactJid, resource];
    }
    
    [account getEntitySoftWareVersion:xmppId];
}

-(void) block:(BOOL) isBlocked contact:(MLContact*) contact
{
    DDLogVerbose(@"Blocking %@: %@", contact, bool2str(isBlocked));
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    [account setBlocked:isBlocked forJid:contact.contactJid];
}

-(void) block:(BOOL) isBlocked fullJid:(NSString*) fullJid onAccount:(NSNumber*) accountNo
{
    DDLogVerbose(@"Blocking %@ on account %@: %@", fullJid, accountNo, bool2str(isBlocked));
    xmpp* account = [self getConnectedAccountForID:accountNo];
    [account setBlocked:isBlocked forJid:fullJid];
}

#pragma mark message signals

-(void) handleSentMessage:(NSNotification*) notification
{
    NSString* messageId = ((XMPPMessage*)notification.userInfo[@"message"]).id;
    DDLogInfo(@"message %@ sent, setting status accordingly", messageId);
    [[DataLayer sharedInstance] setMessageId:messageId sent:YES];
}

#pragma mark - APNS

-(void) setPushToken:(NSString* _Nullable) token
{
    if(token && ![token isEqualToString:_pushToken])
    {
        _pushToken = token;
        [[HelperTools defaultsDB] setObject:_pushToken forKey:@"pushToken"];
        //this will be used by XMPPIQ setPushEnableWithNode and DataLayerMigrations
        //save it when the token changes, to keep token and type in sync
        [[HelperTools defaultsDB] setBool:[HelperTools isSandboxAPNS] forKey:@"isSandboxAPNS"];
    }
    else    //use saved one if we are in NSE appex --> we can't get a new token and the old token might still be valid
        _pushToken = [[HelperTools defaultsDB] objectForKey:@"pushToken"];

    //check node and secret values
    if(
        _pushToken &&
        _pushToken.length
    )
    {
        DDLogInfo(@"push token valid, current push settings: token=%@, isSandboxAPNS=%@", _pushToken, [[HelperTools defaultsDB] boolForKey:@"isSandboxAPNS"] ? @"YES" : @"NO");
        self.hasAPNSToken = YES;
    }
    else
    {
        self.hasAPNSToken = NO;
        DDLogWarn(@"push token invalid, current push settings: token=%@, isSandboxAPNS=%@", _pushToken, [[HelperTools defaultsDB] boolForKey:@"isSandboxAPNS"] ? @"YES" : @"NO");
    }

    //only try to enable push if we have a node and secret value
    if(self.hasAPNSToken)
        for(xmpp* xmppAccount in [self connectedXMPP])
            [xmppAccount enablePush];
}

-(void) removeToken
{
    DDLogWarn(@"APNS removing push token");

    [[HelperTools defaultsDB] removeObjectForKey:@"pushToken"];
    self.hasAPNSToken = NO;
    for(xmpp* xmppAccount in [self connectedXMPP])
        [xmppAccount disablePush];
}

@end
