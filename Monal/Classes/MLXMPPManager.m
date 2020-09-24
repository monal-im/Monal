//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <BackgroundTasks/BackgroundTasks.h>
#import <UserNotifications/UserNotifications.h>

#import "MLXMPPManager.h"
#import "DataLayer.h"
#import "HelperTools.h"
#import "MonalAppDelegate.h"

@import Network;
@import MobileCoreServices;
@import SAMKeychain;

static const NSString* kBackgroundFetchingTask = @"im.monal.fetch";

//this is in seconds
#define SHORT_PING 4.0
#define LONG_PING 16.0

static const int pingFreqencyMinutes = 5;       //about the same Conversations uses
static const int sendMessageTimeoutSeconds = 10;

@interface MLXMPPManager()
{
    nw_path_monitor_t _path_monitor;
    UIBackgroundTaskIdentifier _bgTask;
    BGTask* _bgFetch;
    BOOL _hasConnectivity;
    void (^_pushCompletion)(UIBackgroundFetchResult result);
    monal_void_block_t _cancelPushTimer;
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

    // upgrade udp logger
    [self upgradeBoolUserSettingsIfUnset:@"udpLoggerEnabled" toDefault:NO];
    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerHostname" toDefault:@""];
    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerPort" toDefault:@""];

    // upgrade ASCII wallpaper name
    if([[[HelperTools defaultsDB] stringForKey:@"BackgroundImage"] isEqualToString:@"Tie_My_Boat_by_Ray_García"]) {
        [[HelperTools defaultsDB] setObject:@"Tie_My_Boat_by_Ray_Garcia" forKey:@"BackgroundImage"];
    }

    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerKey" toDefault:@""];
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

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sendOutbox:) name:kMLHasConnectedNotice object:nil];

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

    //this is only for debugging purposes, the real handler has to be added to the NotificationServiceExtension
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(catchupFinished:) name:kMonalFinishedCatchup object:nil];

    //process idle state changes
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];

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
    DDLogVerbose(@"### MAM/SMACKS CATCHUP FINISHED ###");
}

-(void) nowIdle:(NSNotification*) notification
{
    DDLogVerbose(@"### SOME ACCOUNT CHANGED TO IDLE STATE ###");
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
        //remove syncError notification because all accounts are idle and fully synced now
        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[@"syncError"]];
        
        if(![HelperTools isAppExtension])
        {
            DDLogVerbose(@"### NOT EXTENSION --> checking if background is still needed ###");
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
                        DDLogVerbose(@"stopping UIKit _bgTask");
                        [DDLog flushLog];
                        [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
                        _bgTask = UIBackgroundTaskInvalid;
                        stopped = YES;
                    }
                    if(_bgFetch)
                    {
                        DDLogVerbose(@"stopping backgroundFetchingTask");
                        [DDLog flushLog];
                        [_bgFetch setTaskCompletedWithSuccess:YES];
                        stopped = YES;
                    }
                    if(!stopped)
                        DDLogVerbose(@"no background tasks running, nothing to stop");
                    [DDLog flushLog];
                } onQueue:dispatch_get_main_queue()];
            }
            if(_pushCompletion)
            {
                DDLogInfo(@"### All accounts idle, calling push completion handler ###");
                [DDLog flushLog];
                if(_cancelPushTimer)
                    _cancelPushTimer();
                //we don't need to call disconnectAll if we are in background here, because we already did this in the if above (don't reorder these 2 ifs!)
                _pushCompletion(UIBackgroundFetchResultNewData);
                _pushCompletion = nil;
                _cancelPushTimer = nil;
            }
        }
        else
            DDLogVerbose(@"### IN EXTENSION --> ignoring in MLXMPPManager ###");
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
    task.expirationHandler = ^{
        DDLogWarn(@"*** BGTASK EXPIRED ***");
        [self disconnectAll];       //disconnect all accounts to prevent TCP buffer leaking
        _bgFetch = nil;
        [task setTaskCompletedWithSuccess:NO];
        [self scheduleBackgroundFetchingTask];      //schedule new one if neccessary
        [DDLog flushLog];
        [HelperTools postSendingErrorNotification];
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
    if(![HelperTools isInBackground])
    {
        DDLogError(@"Ignoring incomingPushWithCompletionHandler: because app is in FG!");
        completionHandler(UIBackgroundFetchResultNoData);
        return;
    }
    _pushCompletion = completionHandler;
    // should any accounts reconnect?
    [self pingAllAccounts];
    _cancelPushTimer = [HelperTools startTimer:28.0 withHandler:^{
        DDLogWarn(@"### Push timer triggered!! ###");
        _pushCompletion(UIBackgroundFetchResultFailed);
        _pushCompletion = nil;
        _cancelPushTimer = nil;
    }];
}

#pragma mark - client state

-(void) setClientsInactive
{
    [self addBackgroundTask];
    
    for(xmpp* xmppAccount in [self connectedXMPP])
        [xmppAccount setClientInactive];
    [self checkIfBackgroundTaskIsStillNeeded];
}

-(void) setClientsActive
{
    [self addBackgroundTask];
    
    //*** we don't need to check for a running service extension here because the appdelegate does this already for us ***
    
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        if(_hasConnectivity)
            [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        [xmppAccount setClientActive];
    }
}

-(void) pingAllAccounts
{
    for(xmpp* xmppAccount in [self connectedXMPP])
        if(_hasConnectivity)
            [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
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

#pragma mark - Connection related

-(void) connectAccount:(NSString*) accountNo
{
    NSArray* accountDetails = [[DataLayer sharedInstance] detailsForAccount:accountNo];
    if(accountDetails.count == 1) {
        NSDictionary* account = [accountDetails objectAtIndex:0];
        [self connectAccountWithDictionary:account];
    } else {
        DDLogVerbose(@"Expected account settings in db for accountNo: %@", accountNo);
    }
}

-(void) connectAccountWithDictionary:(NSDictionary*)account
{
    xmpp* existing=[self getConnectedAccountForID:[NSString stringWithFormat:@"%@", [account objectForKey:kAccountID]]];
    if(existing)
    {
        DDLogVerbose(@"existing account just pinging.");
        if(_hasConnectivity)
            [existing sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        else
            DDLogVerbose(@"NOT pinging because no connectivity.");
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
    server.selfSignedCert=[[account objectForKey:kSelfSigned] boolValue];

    xmpp* xmppAccount=[[xmpp alloc] initWithServer:server andIdentity:identity andAccountNo:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];
    xmppAccount.pushNode=self.pushNode;
    xmppAccount.pushSecret=self.pushSecret;

    if(xmppAccount)
    {
        @synchronized(_connectedXMPP) {
            [_connectedXMPP addObject:xmppAccount];
        }
        [_connectedXMPP addObject:xmppAccount];

        if(_hasConnectivity)
        {
            DDLogVerbose(@"starting connect");
            [xmppAccount connect];
        }
        else
            DDLogVerbose(@"NOT connecting because no connectivity.");
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
-(void) sendMessageAndAddToHistory:(NSString*) message toContact:(NSString*)recipient fromAccount:(NSString*) accountID fromJID:(NSString*) fromJID isEncrypted:(BOOL) encrypted isMUC:(BOOL) isMUC  isUpload:(BOOL) isUpload withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion {
    NSString* msgid = [[NSUUID UUID] UUIDString];

    NSAssert(message, @"Message should not be nil");

    // Save message to history
    [[DataLayer sharedInstance] addMessageHistoryFrom:fromJID to:recipient forAccount:accountID withMessage:message actuallyFrom:fromJID withId:msgid encrypted:encrypted withCompletion:^(BOOL successHist, NSString *messageTypeHist) {
        // Send message
        if(successHist) {
            [self sendMessage:message toContact:recipient fromAccount:accountID isEncrypted:encrypted isMUC:NO  isUpload:NO messageId:msgid withCompletionHandler:^(BOOL successSend, NSString *messageIdSend) {
                if(successSend) completion(successSend, messageIdSend);
            }];
        }
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

-(void) getServiceDetailsForAccount:(NSInteger) row
{
    xmpp* account;
    @synchronized(_connectedXMPP) {
        if(row < [_connectedXMPP count] && row>=0)
            account = [_connectedXMPP objectAtIndex:row];
    }
    if(account)
        [account getServiceDetails];
}

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
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
     [account addToRoster:contact.contactJid];
}

-(void) getVCard:(MLContact *) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    [account getVCard:contact.contactJid];
}

-(void) getEntitySoftWareVersion:(MLContact *) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    NSArray *contactResourceArr = [[DataLayer sharedInstance] resourcesForContact:contact.contactJid];
    
    NSString *xmppId = @"";
    if ((contactResourceArr == nil) && ([contactResourceArr count] == 0)) {
        xmppId = [NSString stringWithFormat:@"%@",contact.contactJid];
    } else {
        if ([contactResourceArr count] == 0) {
            xmppId = [NSString stringWithFormat:@"%@",contact.contactJid];
        } else {
            xmppId = [NSString stringWithFormat:@"%@/%@",contact.contactJid, [[contactResourceArr objectAtIndex:0] objectForKey:@"resource"] ];
        }        
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

-(void)  leaveRoom:(NSString*) roomName withNick:(NSString *) nick forAccountId:(NSString*) accountId
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

-(void) setPushNode:(NSString *)node andSecret:(NSString *)secret
{
    self.pushNode = node;
    [[HelperTools defaultsDB] setObject:self.pushNode forKey:@"pushNode"];
    
    if(secret)
    {
        self.pushSecret=secret;
        [[HelperTools defaultsDB] setObject:self.pushSecret forKey:@"pushSecret"];
    }
    else    //use saved one (push server not reachable via http(s)) --> the old secret might still be valid
        self.pushSecret = [[HelperTools defaultsDB] objectForKey:@"pushSecret"];

    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        xmppAccount.pushNode = self.pushNode;
        xmppAccount.pushSecret = self.pushSecret;
        [xmppAccount enablePush];
    }
}

#pragma mark - share sheet added

-(void) sendOutbox: (NSNotification *) notification {
    NSDictionary *dic = notification.object;
    NSString *account= [dic objectForKey:@"AccountNo"];

    [self sendOutboxForAccount:account];
}

- (void) sendOutboxForAccount:(NSString *) account{
    NSMutableArray* outbox = [[[HelperTools defaultsDB] objectForKey:@"outbox"] mutableCopy];
    NSMutableArray* outboxClean = [[[HelperTools defaultsDB] objectForKey:@"outbox"] mutableCopy];

    for (NSDictionary* row in outbox)
    {
        NSDictionary* accountDic = [row objectForKey:@"account"] ;
        if([[accountDic objectForKey:kAccountID] integerValue] == [account integerValue])
        {
            NSString* accountID = [NSString stringWithFormat:@"%@", [accountDic objectForKey:kAccountID]];
            NSString* recipient = [row objectForKey:@"recipient"];
            NSAssert(recipient != nil, @"Recipient missing");
            NSAssert(recipient != nil, @"Recipient missing");
            BOOL encryptMessages = [[DataLayer sharedInstance] shouldEncryptForJid:recipient andAccountNo:accountID];
            NSString* fromJID = [NSString stringWithFormat:@"%@@%@", [accountDic objectForKey:@"username"], [accountDic objectForKey:@"domain"]];

            if([[row objectForKey:@"type"] isEqualToString:@"public.url"]) {
                [self sendMessageAndAddToHistory:[row objectForKey:@"url"] toContact:recipient fromAccount:accountID fromJID:fromJID isEncrypted:encryptMessages isMUC:NO isUpload:NO withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                    if(successSendObject) {
                        NSString* comment = (NSString*)[row objectForKey:@"comment"];
                        if(comment.length > 0) {
                            [self sendMessageAndAddToHistory:comment toContact:recipient fromAccount:accountID fromJID:fromJID isEncrypted:encryptMessages isMUC:NO isUpload:NO withCompletionHandler:^(BOOL successSendComment, NSString* messageIdSendComment) {
                            }];
                        }
                        [outboxClean removeObject:row];
                        [[HelperTools defaultsDB] setObject:outboxClean forKey:@"outbox"];
                    }
                }];
            }
        }
    }
}

-(void) sendMessageForConnectedAccounts
{
    for(xmpp* xmppAccount in [self connectedXMPP])
        [self sendOutboxForAccount:xmppAccount.accountNo];
}

@end
