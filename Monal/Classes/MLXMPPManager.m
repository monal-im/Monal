//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <BackgroundTasks/BackgroundTasks.h>
#import <UserNotifications/UserNotifications.h>

#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "DataLayer.h"
#import "HelperTools.h"
#import "MonalAppDelegate.h"
#import "xmpp.h"

@import Network;
@import MobileCoreServices;
@import SAMKeychain;

typedef void (^pushCompletion)(UIBackgroundFetchResult result);

static NSString* kBackgroundFetchingTask = @"im.monal.fetch";

//this is in seconds
#define SHORT_PING 4.0
#define LONG_PING 16.0

static const int pingFreqencyMinutes = 5;       //about the same Conversations uses

@interface MLXMPPManager()
{
    nw_path_monitor_t _path_monitor;
    UIBackgroundTaskIdentifier _bgTask;
    API_AVAILABLE(ios(13.0)) BGTask* _bgFetch;
    BOOL _hasConnectivity;
    NSMutableDictionary* _pushCompletions;
    NSMutableArray* _connectedXMPP;
}
@end

@implementation MLXMPPManager

-(void) defaultSettings
{
    BOOL setDefaults = [[HelperTools defaultsDB] boolForKey:@"SetDefaults"];
    if(!setDefaults)
    {
        // [[HelperTools defaultsDB] setObject:@"" forKey:@"StatusMessage"];   // we dont want anything set
        [[HelperTools defaultsDB] setBool:NO forKey:@"Away"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"MusicStatus"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"Sound"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"MessagePreview"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"Logging"];

        [[HelperTools defaultsDB] setBool:YES forKey:@"OfflineContact"];
        [[HelperTools defaultsDB] setBool:NO forKey:@"SortContacts"];

        [[HelperTools defaultsDB] setBool:YES forKey:@"ChatBackgrounds"];

        // Privacy Settings
        [[HelperTools defaultsDB] setBool:YES forKey:@"ShowImages"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"ShowGeoLocation"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"SendLastUserInteraction"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"SendLastChatState"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"SendReceivedMarkers"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"SendDisplayedMarkers"];

        // Message Settings / Privacy
        [[HelperTools defaultsDB] setInteger:DisplayNameAndMessage forKey:@"NotificationPrivacySetting"];

        // udp logger
        [[HelperTools defaultsDB] setBool:NO forKey:@"udpLoggerEnabled"];
        [[HelperTools defaultsDB] setObject:@"" forKey:@"udpLoggerHostname"];
        [[HelperTools defaultsDB] setObject:@"" forKey:@"udpLoggerPort"];
        [[HelperTools defaultsDB] setObject:@"" forKey:@"udpLoggerKey"];

        [[HelperTools defaultsDB] setBool:YES forKey:@"SetDefaults"];
        [[HelperTools defaultsDB] synchronize];
    }

    // on upgrade this one needs to be set to yes. Can be removed later.
    [self upgradeBoolUserSettingsIfUnset:@"ShowImages" toDefault:YES];

    // upgrade ChatBackgrounds
    [self upgradeBoolUserSettingsIfUnset:@"ChatBackgrounds" toDefault:YES];

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

    // upgrade udp logger
    [self upgradeBoolUserSettingsIfUnset:@"udpLoggerEnabled" toDefault:NO];
    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerHostname" toDefault:@""];
    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerPort" toDefault:@""];

    // upgrade ASCII wallpaper name
    if([[[HelperTools defaultsDB] stringForKey:@"BackgroundImage"] isEqualToString:@"Tie_My_Boat_by_Ray_García"]) {
        [[HelperTools defaultsDB] setObject:@"Tie_My_Boat_by_Ray_Garcia" forKey:@"BackgroundImage"];
    }

    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerKey" toDefault:@""];

    // upgrade Message Settings / Privacy
    [self upgradeIntegerUserSettingsIfUnset:@"NotificationPrivacySetting" toDefault:DisplayNameAndMessage];
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

-(void) upgradeObjectUserSettingsIfUnset:(NSString*) settingsName toDefault:(nullable id) defaultVal
{
    NSNumber* currentSettingVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingVal == nil)
    {
        [[HelperTools defaultsDB] setObject:defaultVal forKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

+ (MLXMPPManager*) sharedInstance
{
    static dispatch_once_t once;
    static MLXMPPManager* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[MLXMPPManager alloc] init] ;
    });
    return sharedInstance;
}

-(id) init
{
    self=[super init];

    _connectedXMPP = [[NSMutableArray alloc] init];
    _bgTask = UIBackgroundTaskInvalid;
    _hasConnectivity = NO;
    _isBackgrounded = NO;
    
    [self defaultSettings];

    //set up regular ping
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _pinger = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q_background);

    dispatch_source_set_timer(_pinger,
                              DISPATCH_TIME_NOW,
                              60ull * NSEC_PER_SEC * pingFreqencyMinutes,
                              60ull * NSEC_PER_SEC);        //allow for better battery optimizations

    dispatch_source_set_event_handler(_pinger, ^{
        //only ping when having connectivity
        if(_hasConnectivity)
        {
            for(xmpp* xmppAccount in [self connectedXMPP])
            {
                if(xmppAccount.accountState>=kStateBound) {
                    DDLogInfo(@"began a idle ping");
                    [xmppAccount sendPing:LONG_PING];        //long ping timeout because this is a background/interval ping
                }
            }
        }
    });

    dispatch_source_set_cancel_handler(_pinger, ^{
        DDLogInfo(@"pinger canceled");
    });

    dispatch_resume(_pinger);

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(autoJoinRoom:) name:kMLHasConnectedNotice object:nil];

    //this processes the sharesheet outbox only, the handler in the NotificationServiceExtension will do more interesting things
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(catchupFinished:) name:kMonalFinishedCatchup object:nil];

    //process idle state changes
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];


    _path_monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(_path_monitor, q_background);
    nw_path_monitor_set_update_handler(_path_monitor, ^(nw_path_t path) {
        DDLogVerbose(@"*** nw_path_monitor update_handler called");
        if(nw_path_get_status(path) == nw_path_status_satisfied && !_hasConnectivity)
        {
            DDLogVerbose(@"reachable");
            _hasConnectivity = YES;
            for(xmpp* xmppAccount in [self connectedXMPP])
            {
                if(![HelperTools isAppExtension])
                {
                    //try to send a ping. if it fails, it will reconnect
                    DDLogVerbose(@"manager pinging");
                    [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
                }
                else
                    [xmppAccount reconnect:0];      //try to immediately reconnect, don't bother pinging
            }
        }
        else if(nw_path_get_status(path) != nw_path_status_satisfied && _hasConnectivity)
        {
            DDLogVerbose(@"NOT reachable");
            _hasConnectivity = NO;
            //we only want to react on connectivity changes if not in NSE because disconnecting would terminate the NSE
            //we want do do "polling" reconnects in NSE instead to make sure we try as long as possible until the NSE times out
            if(![HelperTools isAppExtension])
            {
                BOOL wasIdle = [self allAccountsIdle];      //we have to check that here because disconnect: makes them idle
                [self disconnectAll];
                if(!wasIdle)
                {
                    DDLogVerbose(@"scheduling background fetching task to start app in background once our connectivity gets restored");
                    [self scheduleBackgroundFetchingTask];      //this will automatically start the app if connectivity gets restored
                }
            }
        }
    });
    nw_path_monitor_start(_path_monitor);

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
    
    //send sharesheet outbox
    [self sendOutboxForAccount:account];
}

-(void) nowIdle:(NSNotification*) notification
{
    DDLogInfo(@"### SOME ACCOUNT CHANGED TO IDLE STATE ###");
    [self checkIfBackgroundTaskIsStillNeeded];
}

-(BOOL) allAccountsIdle
{
    for(xmpp* xmppAccount in [self connectedXMPP])
        if(!xmppAccount.idle)
            return NO;
    return YES;
}

-(void) checkIfBackgroundTaskIsStillNeeded
{
    if([self allAccountsIdle])
    {
        DDLogInfo(@"### ALL ACCOUNTS IDLE NOW ###");
        
        //remove syncError notification because all accounts are idle and fully synced now
        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[@"syncError"]];
        
        if(![HelperTools isAppExtension])
        {
#if !TARGET_OS_MACCATALYST
            //use a synchronized block to disconnect only once
            @synchronized(self) {
                DDLogInfo(@"### NOT EXTENSION --> checking if background is still needed ###");
                BOOL background = [HelperTools isInBackground];
                if(background)
                {
                    DDLogInfo(@"### All accounts idle, disconnecting and stopping all background tasks ###");
                    [DDLog flushLog];
                    [self disconnectAll];       //disconnect all accounts to prevent TCP buffer leaking
                    [HelperTools dispatchSyncReentrant:^{
                        BOOL stopped = NO;
                        if(_bgTask != UIBackgroundTaskInvalid)
                        {
                            DDLogDebug(@"stopping UIKit _bgTask");
                            [DDLog flushLog];
                            [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
                            _bgTask = UIBackgroundTaskInvalid;
                            stopped = YES;
                        }
                        if(_bgFetch)
                        {
                            DDLogDebug(@"stopping backgroundFetchingTask");
                            [DDLog flushLog];
                            [_bgFetch setTaskCompletedWithSuccess:YES];
                            _bgFetch = nil;
                            stopped = YES;
                        }
                        if(!stopped)
                            DDLogDebug(@"no background tasks running, nothing to stop");
                        [DDLog flushLog];
                    } onQueue:dispatch_get_main_queue()];
                }
                if([_pushCompletions count])
                {
                    //we don't need to call disconnectAll if we are in background here, because we already did this in the if above (don't reorder these 2 ifs!)
                    DDLogInfo(@"### All accounts idle, calling push completion handlers ###");
                    [DDLog flushLog];
                    for(NSString* completionId in _pushCompletions)
                    {
                        //cancel running timer and push completion handler
                        ((monal_void_block_t)_pushCompletions[completionId][@"timer"])();
                        ((pushCompletion)_pushCompletions[completionId][@"handler"])(UIBackgroundFetchResultNewData);
                        [_pushCompletions removeObjectForKey:completionId];
                    }
                }
            }
#else
            DDLogInfo(@"### CATALYST BUILD --> ignoring in MLXMPPManager ###");
#endif
        }
        else
            DDLogInfo(@"### IN APPEX --> ignoring in MLXMPPManager ###");
    }
}

-(void) addBackgroundTask
{
    if(![HelperTools isAppExtension])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            //start indicating we want to do work even when the app is put into background
            if(_bgTask == UIBackgroundTaskInvalid)
            {
                _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
                    DDLogWarn(@"BG WAKE EXPIRING");
                    [DDLog flushLog];
                    
                    [self disconnectAll];       //disconnect all accounts to prevent TCP buffer leaking
                    
                    [HelperTools postSendingErrorNotification];

                    //schedule a BGProcessingTaskRequest to process this further as soon as possible
                    if(@available(iOS 13.0, *))
                    {
                        DDLogInfo(@"calling scheduleBackgroundFetchingTask");
                        [self scheduleBackgroundFetchingTask];
                    }
                    
                    [DDLog flushLog];
                    [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
                    _bgTask = UIBackgroundTaskInvalid;
                }];
            }
        });
    }
}

-(void) handleBackgroundFetchingTask:(BGTask*) task API_AVAILABLE(ios(13.0))
{
    DDLogVerbose(@"RUNNING BGTASK");
    _bgFetch = task;
    __weak BGTask* weakTask = task;
    task.expirationHandler = ^{
        DDLogWarn(@"*** BGTASK EXPIRED ***");
        _bgFetch = nil;
        [self disconnectAll];       //disconnect all accounts to prevent TCP buffer leaking
        [HelperTools postSendingErrorNotification];
        [weakTask setTaskCompletedWithSuccess:NO];
        [self scheduleBackgroundFetchingTask];      //schedule new one if neccessary
        [DDLog flushLog];
    };
    
    if(_hasConnectivity)
    {
        for(xmpp* xmppAccount in [self connectedXMPP])
        {
            //try to send a ping. if it fails, it will reconnect
            DDLogVerbose(@"manager pinging");
            [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        }
    }
    else
        DDLogWarn(@"BGTASK has *no* connectivity? That's strange!");
    
    //log bgtask ticks
    unsigned long tick = 0;
    while(1)
    {
        DDLogVerbose(@"BGTASK TICK: %lu", tick++);
        [DDLog flushLog];
        [NSThread sleepForTimeInterval:1.000];
    }
}

-(void) configureBackgroundFetchingTask
{
    if(![HelperTools isAppExtension])
    {
        if(@available(iOS 13.0, *))
        {
            [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBackgroundFetchingTask usingQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) launchHandler:^(BGTask *task) {
                DDLogVerbose(@"RUNNING BGTASK LAUNCH HANDLER");
                [self handleBackgroundFetchingTask:task];
            }];
        } else {
            // No fallback unfortunately
        }
    }
}

-(void) scheduleBackgroundFetchingTask
{
    if(![HelperTools isAppExtension])
    {
        if(@available(iOS 13.0, *))
        {
            [HelperTools dispatchSyncReentrant:^{
                NSError *error = NULL;
                // cancel existing task (if any)
                [BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:kBackgroundFetchingTask];
                // new task
                //BGAppRefreshTaskRequest* request = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:kBackgroundFetchingTask];
                BGProcessingTaskRequest* request = [[BGProcessingTaskRequest alloc] initWithIdentifier:kBackgroundFetchingTask];
                //do the same like the corona warn app from germany which leads to this hint: https://developer.apple.com/forums/thread/134031
                request.requiresNetworkConnectivity = YES;
                request.requiresExternalPower = NO;
                request.earliestBeginDate = nil;
                //request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:40];        //begin nearly immediately (if we have network connectivity)
                BOOL success = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
                if(!success) {
                    // Errorcodes https://stackoverflow.com/a/58224050/872051
                    DDLogError(@"Failed to submit BGTask request: %@", error);
                } else {
                    DDLogVerbose(@"Success submitting BGTask request %@", request);
                }
            } onQueue:dispatch_get_main_queue()];
        }
        else
        {
            // No fallback unfortunately
            DDLogError(@"BGTask needed but NOT supported!");
        }
    }
}

-(void) incomingPushWithCompletionHandler:(void (^)(UIBackgroundFetchResult result)) completionHandler
{
    DDLogInfo(@"got incomingPushWithCompletionHandler");
    
#if TARGET_OS_MACCATALYST
    DDLogError(@"Ignoring incomingPushWithCompletionHandler: we are a catalyst app!");
    completionHandler(UIBackgroundFetchResultNoData);
    return;
#endif
    
    if(![HelperTools isInBackground])
    {
        DDLogError(@"Ignoring incomingPushWithCompletionHandler: because app is in FG!");
        completionHandler(UIBackgroundFetchResultNoData);
        return;
    }
    
    // should any accounts reconnect?
    [self pingAllAccounts];
    
    //register push completion handler and associated timer
    NSString* completionId = [[NSUUID UUID] UUIDString];
    _pushCompletions[completionId] = @{
        @"handler": completionHandler,
        @"timer": [HelperTools startTimer:28.0 withHandler:^{
            DDLogWarn(@"### Push timer triggered!! ###");
            [_pushCompletions removeObjectForKey:completionId];
            completionHandler(UIBackgroundFetchResultFailed);
        }]
    };
}

#pragma mark - app state

-(void) nowBackgrounded
{
    _isBackgrounded = YES;
    
    [self addBackgroundTask];
    
    for(xmpp* xmppAccount in [self connectedXMPP])
        [xmppAccount setClientInactive];
    [self checkIfBackgroundTaskIsStillNeeded];
}

-(void) nowForegrounded
{
    _isBackgrounded = NO;
    
    [self addBackgroundTask];
    
    //*** we don't need to check for a running service extension here because the appdelegate does this already for us ***
    
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        [xmppAccount unfreezed];
        if(_hasConnectivity)
            [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        [xmppAccount setClientActive];
    }
}

#pragma mark - Connection related

-(void) pingAllAccounts
{
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        [xmppAccount unfreezed];
        if(_hasConnectivity)
            [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
    }
}

-(void) rejectContact:(MLContact*) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    [account rejectFromRoster:contact.contactJid];
}

-(void) approveContact:(MLContact*) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    [account approveToRoster:contact.contactJid];
}

-(BOOL) isAccountForIdConnected:(NSString*) accountNo
{
    xmpp* account = [self getConnectedAccountForID:accountNo];
    if(account.accountState>=kStateBound) return YES;
    return NO;
}

-(NSDate *) connectedTimeFor:(NSString*) accountNo
{
    xmpp* account = [self getConnectedAccountForID:accountNo];
    return account.connectedTime;
}

-(xmpp*) getConnectedAccountForID:(NSString*) accountNo
{
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        if([xmppAccount.accountNo isEqualToString:accountNo])
            return xmppAccount;
    }
    return nil;
}

-(void) connectAccount:(NSString*) accountNo
{
    NSDictionary* account = [[DataLayer sharedInstance] detailsForAccount:accountNo];
    if(!account)
        DDLogError(@"Expected account settings in db for accountNo: %@", accountNo);
    else
        [self connectAccountWithDictionary:account];
}

-(void) connectAccountWithDictionary:(NSDictionary*)account
{
    xmpp* existing = [self getConnectedAccountForID:[NSString stringWithFormat:@"%@", [account objectForKey:kAccountID]]];
    if(existing)
    {
        DDLogInfo(@"existing account, calling unfreezed");
        [existing unfreezed];
        DDLogInfo(@"existing account, just pinging.");
        if(_hasConnectivity)
            [existing sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        else
            DDLogWarn(@"NOT pinging because no connectivity.");
        return;
    }
    DDLogVerbose(@"connecting account %@@%@",[account objectForKey:kUsername], [account objectForKey:kDomain]);

    NSError* error;
    NSString *password = [SAMKeychain passwordForService:@"Monal" account:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]] error:&error];
    error = nil;
    if(error)
    {
        DDLogError(@"Keychain error: %@", [NSString stringWithFormat:@"%@", error]);
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:nil];
    }
    MLXMPPIdentity *identity = [[MLXMPPIdentity alloc] initWithJid:[NSString stringWithFormat:@"%@@%@",[account objectForKey:kUsername],[account objectForKey:kDomain] ] password:password andResource:[account objectForKey:kResource]];

    MLXMPPServer *server = [[MLXMPPServer alloc] initWithHost:[account objectForKey:kServer] andPort:[account objectForKey:kPort] andDirectTLS:[[account objectForKey:kDirectTLS] boolValue]];
    server.selfSignedCert = [[account objectForKey:kSelfSigned] boolValue];

    xmpp* xmppAccount = [[xmpp alloc] initWithServer:server andIdentity:identity andAccountNo:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];
    xmppAccount.pushNode = self.pushNode;
    xmppAccount.pushSecret = self.pushSecret;

    if(xmppAccount)
    {
        @synchronized(_connectedXMPP) {
            [_connectedXMPP addObject:xmppAccount];
        }

        if(_hasConnectivity)
        {
            DDLogInfo(@"starting connect");
            [xmppAccount connect];
        }
        else
            DDLogWarn(@"NOT connecting because no connectivity.");
    }
}


-(void) disconnectAccount:(NSString*) accountNo
{
    int index=0;
    int pos=-1;
    xmpp* account;
    @synchronized(_connectedXMPP) {
        for(xmpp* xmppAccount in _connectedXMPP)
        {
            if([xmppAccount.accountNo isEqualToString:accountNo] )
            {
                account = xmppAccount;
                pos=index;
                break;
            }
            index++;
        }

        if((pos>=0) && (pos<[_connectedXMPP count]))
        {
            [_connectedXMPP removeObjectAtIndex:pos];
            DDLogVerbose(@"removed account at pos  %d", pos);
        }
    }
    if(account)
    {
        DDLogVerbose(@"got account and cleaning up.. ");
        [account disconnect:YES];
        DDLogVerbose(@"done cleaning up account ");
    }
}


-(void) logoutAll
{
    NSArray* enabledAccountList = [[DataLayer sharedInstance] enabledAccountList];
    for(NSDictionary* account in enabledAccountList) {
        DDLogVerbose(@"Disconnecting account %@@%@", [account objectForKey:@"username"], [account objectForKey:@"domain"]);
        [self disconnectAccount:[NSString stringWithFormat:@"%@", [account objectForKey:kAccountID]]];
    }
}

-(void) disconnectAll
{
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        //disconnect to prevent endless loops trying to connect
        DDLogVerbose(@"manager disconnecting");
        [xmppAccount disconnect];
    }
}

-(void) connectIfNecessary
{
    [self addBackgroundTask];
    NSArray* enabledAccountList = [[DataLayer sharedInstance] enabledAccountList];
    for(NSDictionary* account in enabledAccountList) {
        [self connectAccountWithDictionary:account];
    }
}

-(void) updatePassword:(NSString *) password forAccount:(NSString *) accountNo
{
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
    [SAMKeychain setPassword:password forService:@"Monal" account:accountNo];
    xmpp* xmpp =[self getConnectedAccountForID:accountNo];
    [xmpp.connectionProperties.identity updatPassword:password];
}

#pragma mark -  XMPP commands
-(void) sendMessageAndAddToHistory:(NSString*) message toContact:(NSString*) recipient fromAccount:(NSString*) accountID isEncrypted:(BOOL) encrypted isMUC:(BOOL) isMUC isUpload:(BOOL) isUpload withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion
{
    NSString* msgid = [[NSUUID UUID] UUIDString];
    xmpp* account = [self getConnectedAccountForID:accountID];
    MLContact* contact = [[DataLayer sharedInstance] contactForUsername:recipient forAccount:accountID];

    NSAssert(message, @"Message should not be nil");
    NSAssert(account, @"Account should not be nil");
    NSAssert(contact, @"Contact should not be nil");
    
    // Save message to history
    [[DataLayer sharedInstance] addMessageHistoryFrom:account.connectionProperties.identity.jid
                                                   to:recipient
                                           forAccount:accountID
                                          withMessage:message
                                         actuallyFrom:(isMUC ? contact.accountNickInGroup : account.connectionProperties.identity.jid)
                                               withId:msgid
                                            encrypted:encrypted
                                       withCompletion:^(BOOL successHist, NSString* messageTypeHist, NSNumber* messageDBId) {
        // Send message
        if(successHist) {
            DDLogInfo(@"Message added to history with id %ld, now sending...", (long)[messageDBId intValue]);
            [self sendMessage:message toContact:recipient fromAccount:accountID isEncrypted:encrypted isMUC:isMUC isUpload:NO messageId:msgid withCompletionHandler:^(BOOL successSend, NSString *messageIdSend) {
                if(successSend)
                    completion(successSend, messageIdSend);
            }];
            DDLogVerbose(@"Notifying active chats of change for contact %@", contact);
            [[NSNotificationCenter defaultCenter] postNotificationName:kMLMessageSentToContact object:self userInfo:@{@"contact":contact}];
        }
        else
            DDLogError(@"Could not add message to history!");
    }];
}

-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo isEncrypted:(BOOL) encrypted isMUC:(BOOL) isMUC  isUpload:(BOOL) isUpload messageId:(NSString *) messageId withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion
{
    BOOL success=NO;
    xmpp* account = [self getConnectedAccountForID:accountNo];
    if(account)
    {
        success=YES;
        [account sendMessage:message toContact:contact isMUC:isMUC isEncrypted:encrypted isUpload:isUpload andMessageId:messageId];
    }

    if(completion)
        completion(success, messageId);
}

-(void) sendChatState:(BOOL) isTyping fromAccount:(NSString*) accountNo toJid:(NSString*) jid
{
    xmpp* account = [self getConnectedAccountForID:accountNo];
    if(account)
        [account sendChatState:isTyping toJid:jid];
}


#pragma  mark - HTTP upload

-(void) httpUploadJpegData:(NSData*) fileData   toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion{

    NSString *fileName = [NSString stringWithFormat:@"%@.jpg",[NSUUID UUID].UUIDString];

    //get file type
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)@"jpg", NULL);
    NSString *mimeType = (__bridge_transfer NSString *)(UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType));
    CFRelease(UTI);
    [self httpUploadData:fileData withFilename:fileName andType:mimeType toContact:contact onAccount:accountNo withCompletionHandler:completion];
}

-(void) httpUploadFileURL:(NSURL*) fileURL  toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion{

    //get file name
    NSString *fileName =  fileURL.pathComponents.lastObject;

    //get file type
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)fileURL.pathExtension, NULL);
    NSString *mimeType = (__bridge NSString *)(UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType));
    CFRelease(UTI);
    //get data
    NSData *fileData = [[NSData alloc] initWithContentsOfURL:fileURL];

    [self httpUploadData:fileData withFilename:fileName andType:mimeType toContact:contact onAccount:accountNo withCompletionHandler:completion];
}


-(void)httpUploadData:(NSData *)data withFilename:(NSString*) filename andType:(NSString*)contentType  toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion
{
    if(!data || !filename || !contentType || !contact || !accountNo)
    {
        NSError *error = [NSError errorWithDomain:@"Empty" code:0 userInfo:@{}];
        if(completion) completion(nil, error);
        return;
    }

    xmpp* account=[self getConnectedAccountForID:accountNo];
    if(account)
    {
        NSDictionary *params =@{kData:data,kFileName:filename, kContentType:contentType, kContact:contact};
        [account requestHTTPSlotWithParams:params andCompletion:completion];
    }
}


#pragma mark - getting details

-(NSString*) getAccountNameForConnectedRow:(NSInteger) row
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

-(void) removeContact:(MLContact *) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    if(account)
    {
        if(contact.isGroup)
        {
            //if MUC
            [account leaveRoom:contact.contactJid withNick:contact.accountNickInGroup];
        } else  {
            [account removeFromRoster:contact.contactJid];
        }
        //remove from DB
        [[DataLayer sharedInstance] removeBuddy:contact.contactJid forAccount:contact.accountId];
    }
}

-(void) addContact:(MLContact *) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    [account addToRoster:contact.contactJid];
}

-(void) getEntitySoftWareVersionForContact:(MLContact *) contact andResource:(NSString*) resource
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    
    NSString *xmppId = @"";
    if ((resource == nil) || ([resource length] == 0)) {
        xmppId = [NSString stringWithFormat:@"%@",contact.contactJid];
    } else {
        xmppId = [NSString stringWithFormat:@"%@/%@",contact.contactJid, resource];
    }
    
    [account getEntitySoftWareVersion:xmppId];
}

-(void) blocked:(BOOL) isBlockd Jid:(MLContact *) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    [account setBlocked:isBlockd forJid:contact.contactJid];
}

#pragma mark - MUC commands

-(void)  joinRoom:(NSString*) roomName  withNick:(NSString *)nick andPassword:(NSString*) password forAccounId:(NSString *) accountId
{
    xmpp* account= [self getConnectedAccountForID:accountId];
    [account joinRoom:roomName withNick:nick andPassword:password];
}


-(void)  joinRoom:(NSString*) roomName  withNick:(NSString *)nick andPassword:(NSString*) password forAccountRow:(NSInteger) row
{
    xmpp* account;
    @synchronized(_connectedXMPP) {
        if(row<[_connectedXMPP count] && row>=0)
            account = [_connectedXMPP objectAtIndex:row];
    }
    if(account)
        [account joinRoom:roomName withNick:nick andPassword:password];
}

-(void) leaveRoom:(NSString*) roomName withNick:(NSString *) nick forAccountId:(NSString*) accountId
{
    xmpp* account= [self getConnectedAccountForID:accountId];
    [account leaveRoom:roomName withNick:nick];
    [[DataLayer sharedInstance] removeBuddy:roomName forAccount:accountId];
}

-(void) autoJoinRoom:(NSNotification *) notification
{
    NSDictionary *dic = notification.object;

    NSMutableArray* results = [[DataLayer sharedInstance] mucFavoritesForAccount:[dic objectForKey:@"AccountNo"]];
    for(NSDictionary *row in results)
    {
        NSNumber *autoJoin =[row objectForKey:@"autojoin"] ;
        if(autoJoin.boolValue)
            [self joinRoom:[row objectForKey:@"room"] withNick:[row objectForKey:@"nick"] andPassword:[row objectForKey:@""] forAccounId:[NSString stringWithFormat:@"%@", [row objectForKey:kAccountID]]];
    }
}

#pragma mark - Jingle VOIP
-(void) callContact:(MLContact*) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    [account call:contact];
}


-(void) hangupContact:(MLContact*) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    [account hangup:contact];
}

-(void) handleCall:(NSDictionary *) userDic withResponse:(BOOL) accept
{
    //find account
     xmpp* account =[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[userDic objectForKey:kAccountID]]];

    if(accept) {
        [account acceptCall:userDic];
    }
    else  {
         [account declineCall:userDic];
    }

}


#pragma mark - XMPP settings

-(void) setStatusMessage:(NSString*) message
{
    for(xmpp* xmppAccount in [self connectedXMPP])
        [xmppAccount setStatusMessageText:message];
}

-(void) setAway:(BOOL) isAway
{
    for(xmpp* xmppAccount in [self connectedXMPP])
        [xmppAccount setAway:isAway];
}

#pragma mark message signals
-(void) handleNewMessage:(NSNotification *)notification
{
    if(![HelperTools isAppExtension])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            MonalAppDelegate* appDelegate = (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
            [appDelegate updateUnread];
        });
    }
}


-(void) handleSentMessage:(NSNotification*) notification
{
    NSDictionary* info = notification.userInfo;
    NSString* messageId = [info objectForKey:kMessageId];
    DDLogInfo(@"message %@ sent, setting status accordingly", messageId);
    [[DataLayer sharedInstance] setMessageId:messageId sent:YES];
}

#pragma mark - properties

-(void) cleanArrayOfConnectedAccounts:(NSMutableArray*) dirtySet
{
    //yes, this is ineffecient but the size shouldnt ever be huge
    NSMutableIndexSet* indexSet = [[NSMutableIndexSet alloc] init];
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        NSInteger pos=0;
        for(MLContact* row in dirtySet)
        {
            if([row.contactJid isEqualToString:xmppAccount.connectionProperties.identity.jid])
                [indexSet addIndex:pos];
            pos++;
        }
    }
    [dirtySet removeObjectsAtIndexes:indexSet];
}


#pragma mark - APNS

-(void) setPushNode:(NSString*) node andSecret:(NSString*) secret
{
    if(node && ![node isEqualToString:self.pushNode])
    {
        self.pushNode = node;
        [[HelperTools defaultsDB] setObject:self.pushNode forKey:@"pushNode"];
    }
    else    //use saved one: push server not reachable via http(s) --> the old node might still be valid
        self.pushNode = [[HelperTools defaultsDB] objectForKey:@"pushNode"];

    if(secret && ![secret isEqualToString:self.pushSecret])
    {
        self.pushSecret = secret;
        [[HelperTools defaultsDB] setObject:self.pushSecret forKey:@"pushSecret"];
    }
    else    //use saved one: push server not reachable via http(s) --> the old secret might still be valid
        self.pushSecret = [[HelperTools defaultsDB] objectForKey:@"pushSecret"];

    //check node and secret values
    if(
        self.pushNode &&
        self.pushSecret &&
        self.pushNode.length &&
        self.pushSecret.length
    )
    {
        DDLogInfo(@"push token valid, current push settings: node=%@, secret=%@", [MLXMPPManager sharedInstance].pushNode, [MLXMPPManager sharedInstance].pushSecret);
        self.hasAPNSToken = YES;
    }
    else
    {
        self.hasAPNSToken = NO;
        DDLogWarn(@"push token invalid, current push settings: node=%@, secret=%@", [MLXMPPManager sharedInstance].pushNode, [MLXMPPManager sharedInstance].pushSecret);
    }

    //only try to enable push if we have a node and secret value
    if(self.hasAPNSToken)
        for(xmpp* xmppAccount in [self connectedXMPP])
        {
            xmppAccount.pushNode = self.pushNode;
            xmppAccount.pushSecret = self.pushSecret;
            [xmppAccount enablePush];
        }
}

#pragma mark - share sheet added

-(void) sendOutboxForAccount:(xmpp*) account
{
    NSMutableArray* outbox = [[[HelperTools defaultsDB] objectForKey:@"outbox"] mutableCopy];
    NSMutableArray* outboxClean = [[[HelperTools defaultsDB] objectForKey:@"outbox"] mutableCopy];

    DDLogInfo(@"Got message outbox: %@", outbox);
    for(NSDictionary* row in outbox)
    {
        NSDictionary* accountDic = [row objectForKey:@"account"] ;
        if([[accountDic objectForKey:kAccountID] integerValue] == [account.accountNo integerValue])
        {
            NSString* accountID = [NSString stringWithFormat:@"%@", [accountDic objectForKey:kAccountID]];
            NSString* recipient = [row objectForKey:@"recipient"];
            NSAssert(recipient != nil, @"Recipient missing");
            NSAssert(recipient != nil, @"Recipient missing");
            BOOL encryptMessages = [[DataLayer sharedInstance] shouldEncryptForJid:recipient andAccountNo:accountID];

            if([row objectForKey:@"comment"]) {
                [self sendMessageAndAddToHistory:[row objectForKey:@"comment"] toContact:recipient fromAccount:accountID isEncrypted:encryptMessages isMUC:NO isUpload:NO withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                }];
            }
            if([row objectForKey:@"url"]) {
                [self sendMessageAndAddToHistory:[row objectForKey:@"url"] toContact:recipient fromAccount:accountID isEncrypted:encryptMessages isMUC:NO isUpload:NO withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                }];
            }
            // remove msg even after error
            [outboxClean removeObject:row];
            [[HelperTools defaultsDB] setObject:outboxClean forKey:@"outbox"];
        }
    }
}

@end
