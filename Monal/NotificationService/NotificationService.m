//
//  NotificationService.m
//  NotificationService
//
//  Created by Anurodh Pokharel on 9/16/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "NotificationService.h"
#import "MLConstants.h"
#import "HelperTools.h"
#import "IPC.h"
#import "MLProcessLock.h"
#import "MLXMPPManager.h"
#import "MLNotificationManager.h"
#import "MLFiletransfer.h"
#import "xmpp.h"

@import CallKit;

@interface NotificationService ()
+(BOOL) getAppexCleanShutdownStatus;
+(void) setAppexCleanShutdownStatus:(BOOL) shutdownStatus;
@end

@interface PushSingleton : NSObject
@property (atomic, strong) NSMutableArray* handlerList;
@property (atomic) BOOL isFirstPush;
@end

@interface PushHandler : NSObject
@property (atomic, strong) void (^handler)(UNNotificationContent* _Nonnull);
@property (atomic, strong) monal_void_block_t _Nullable expirationTimer;
@end


@implementation PushHandler

-(instancetype) initWithHandler:(void (^)(UNNotificationContent* _Nonnull)) handler andExpirationTimer:(monal_void_block_t) expirationTimer
{
    self = [super init];
    self.handler = handler;
    self.expirationTimer = expirationTimer;
    return self;
}

-(void) feed
{
    @synchronized(self) {
        if(self.expirationTimer)
            self.expirationTimer();
        if(self.handler)
            self.handler([UNMutableNotificationContent new]);
        self.expirationTimer = nil;
        self.handler = nil;
    }
}

-(void) dealloc
{
    @synchronized(self) {
        MLAssert(self.expirationTimer == nil && self.handler == nil, @"Deallocating PushHandler while encapsulated timer or handler still active", (@{
            @"expirationTimer": self.expirationTimer == nil ? @"nil" : @"non-nil",
            @"handler": self.handler == nil ? @"nil" : @"non-nil",
        }));
    }
}

@end


@implementation PushSingleton

+(id) instance
{
    static PushSingleton* sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [PushSingleton new];
    });
    return sharedInstance;
}

-(instancetype) init
{
    self = [super init];
    DDLogInfo(@"Initializing push singleton");
    self.handlerList = [NSMutableArray new];
    self.isFirstPush = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(incomingIPC:) name:kMonalIncomingIPC object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:kMonalUpdateUnread object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleIncomingVoipCall:) name:kMonalIncomingVoipCall object:nil];
    return self;
}

-(void) dealloc
{
    DDLogError(@"Deallocating push singleton");
    [DDLog flushLog];
}

-(BOOL) checkAndUpdateFirstPush:(BOOL) value
{
    BOOL retval;
    @synchronized(self) {
        retval = self.isFirstPush;
        self.isFirstPush = value;
    }
    return retval;
}

-(BOOL) checkForNewPushes
{
    @synchronized(self.handlerList) {
        return self.handlerList.count > 0;
    }
}

-(BOOL) checkForLastHandler
{
    @synchronized(self.handlerList) {
        return self.handlerList.count <= 1;
    }
}

-(void) killAppex
{
    //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
    DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
    
    [NotificationService setAppexCleanShutdownStatus:YES];
    
    DDLogInfo(@"Now killing appex process, goodbye...");
    [HelperTools flushLogsWithTimeout:0.100];
    exit(0);
}

-(BOOL) feedNextHandler
{
    PushHandler* entry = nil;
    @synchronized(self.handlerList) {
        //return NO if there isn't a single handler left in our list
        if(self.handlerList.count == 0)
            return NO;
        
        entry = [self.handlerList firstObject];
        [self.handlerList removeObject:entry];
    }
    
    //cancel expiration timer if still running and feed our handler with empty content to silence it
    DDLogDebug(@"Feeding next handler");
    [entry feed];
    
    //return NO if this was the last handler and YES if not
    return [self checkForLastHandler];
}

-(void) handleIncomingVoipCall:(NSNotification*) notification
{
    DDLogInfo(@"Got incoming VOIP call");
    if(@available(iOS 14.5, macCatalyst 14.5, *))
    {
        //disconnect while still being in the receive queue to make sure we don't process any other stanza after this jmi one
        //(we don't want to handle a second jmi stanza for example: that could confuse tie-breaking and other parts of our call handling)
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:notification.userInfo[@"accountNo"]];
        [account disconnect];
        
        //now disconnect all other accounts, post the voip push and kill the appex
        //do this in an extra thread to avoid deadlocks via: receive_queue -> disconnect_thread -> receive_queue
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //directly disconnect without handling any possibly queued stanzas (they will be handled in mainapp once we wake it up)
            [self disconnectAndFeedAllWaitingHandlers];
        
            DDLogInfo(@"Dispatching voip call to mainapp...");
            NSString* payload = [HelperTools encodeBase64WithData:[HelperTools serializeObject:notification.userInfo]];
            [CXProvider reportNewIncomingVoIPPushPayload:@{@"base64Payload": payload} completion:^(NSError* _Nullable error) {
                if(error != nil)
                    DDLogError(@"Got error for reportNewIncomingVoIPPushPayload: %@", error);
                else
                    DDLogInfo(@"Successfully called reportNewIncomingVoIPPushPayload");
                [self killAppex];
            }];
        });
    }
    else
        DDLogError(@"iOS < 14.5 detected, ignoring incoming call!");
}

-(void) disconnectAndFeedAllWaitingHandlers
{
    DDLogInfo(@"Disconnecting all accounts and feeding all pending handlers: %lu", [self.handlerList count]);
    
    //this has to be synchronous because we only want to continue if all accounts are completely disconnected
    [[MLXMPPManager sharedInstance] disconnectAll];
    
    //we posted all notifications and disconnected, technically we're not running anymore
    //(even though our containing process will still be running for a few more seconds)
    [MLProcessLock unlock];
    
    //feed all waiting handlers with empty notifications to silence them
    //this will terminate/freeze the app extension afterwards
    while([self feedNextHandler])
        ;
}

-(void) incomingPush:(void (^)(UNNotificationContent* _Nullable)) contentHandler
{
    //we set the contentHandler to nil if the push was alreay handled but we want to retrigger the first push logic in here
    if(contentHandler)
    {
        DDLogInfo(@"Got incoming push");
        PushHandler* handler = [[PushHandler alloc] initWithHandler:contentHandler andExpirationTimer:createTimer(25.0, ^{ [self pushExpired]; })];
        @synchronized(self.handlerList) {
            [self.handlerList addObject:handler];
        }
    }
    else
        //use warn loglevel to make this rare circumstance more visible in (udp) log
        DDLogWarn(@"Got a new push while disconnecting, handling it as if it were the first push");     //see [self pushExpired] for explanation
    
    //first incoming push? --> ping mainapp
    //all pushes not being the first one should do nothing (despite extending our runtime)
    if([self checkAndUpdateFirstPush:NO])
    {
        DDLogInfo(@"First push, pinging main app");
        if([MLProcessLock checkRemoteRunning:@"MainApp"])
        {
            //this will make sure we still run if we get triggered immediately after the mainapp disconnected but before its process got freezed
            DDLogDebug(@"Main app already in foreground, sleeping for 5 seconds and trying again");
            usleep(5000000);
            DDLogDebug(@"Pinging main app again");
            if([MLProcessLock checkRemoteRunning:@"MainApp"])
            {
                DDLogInfo(@"NOT connecting accounts, main app already running in foreground, terminating immediately instead");
                [DDLog flushLog];
                [self disconnectAndFeedAllWaitingHandlers];
                [self killAppex];
            }
            else
                DDLogDebug(@"Main app not in foreground anymore, handling first push now");
        }
        
        DDLogDebug(@"locking process and connecting accounts");
        [DDLog flushLog];
        [MLProcessLock lock];
        
        //handle message notifications by initializing the MLNotificationManager
        [MLNotificationManager sharedInstance];
        
        //initialize the xmpp manager (used for connectivity checks etc.)
        //we initialize it here to make sure the connectivity check is complete when using it later
        [MLXMPPManager sharedInstance];
        usleep(100000);     //wait for initial connectivity check (100ms)
        
        //now connect all enabled accounts
        [[MLXMPPManager sharedInstance] connectIfNecessary];
        
        //this will delay the delivery of such notifications until 60 seconds after our last sync attempt failed
        //rather than being delivered 60 seconds after our first sync attempt failed
        [HelperTools removePendingSyncErrorNotifications];
    }
}

-(void) pushExpired
{
    DDLogInfo(@"Handling expired push: %lu", (unsigned long)[self.handlerList count]);
    
    BOOL isLastHandler = [self checkForLastHandler];
    if(isLastHandler)
    {
        DDLogInfo(@"This was the last handler, freezing all parse queues and posting sync errors...");
        
        //we have to freeze all incoming streams until we know if this handler feeding leads to the termination of our appex or not
        //we MUST do this before feeding the last handler because after feeding the last one apple does not allow us to
        //post any new notifications --> not freezing would lead to lost notifications
        [self freezeAllParseQueues];
        
        //post sync errors for all accounts still not idle now (e.g. have stanzas in our freezed pase queue or stanzas waiting for smacks acks etc.)
        //we MUST do this here because apple des not allow us to post any new notifications after feeding the last handler
        [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
    }
    
    //after this we (potentially) can not post any new notifications until the next push comes in (if it comes in at all)
    [self feedNextHandler];
    
    //check if this was the last handler (ignore if we got a new one in between our call to checkForLastHandler and feedNextHandler, this case will be handled below anyways)
    if(isLastHandler)
    {
        DDLogInfo(@"Last push expired shutting down in 500ms if no new push comes in in the meantime");
        //wait 500ms to allow other pushed already queued on the device (but not yet delivered to us) to be delivered to us
        //after the last push expired we have ~5 seconds run time left to do the clean disconnect
        //--> waiting 500ms before checking if this was the last push that expired (e.g. no new push came in) does not do any harm here
        //WARNING: we have to closely watch apple...if they remove this 5 second gap between this call to the expiration handler and the actual
        //appex freeze, this sleep will no longer be harmless and could even cause smacks state corruption (by not diconnecting cleanly and having stanzas
        //still in the TCP queue delivered on next appex unfreeze even if they have been handled by the mainapp already)
        usleep(500000);
        
        //this returns YES if we got new pushes in the meantime --> do nothing if so
        if(![self checkForNewPushes])
        {
            DDLogInfo(@"Shutting down appex now");
            
            //don't post sync errors here, already did so above (see explanation there)
            
            //schedule a new BGProcessingTaskRequest to process this further as soon as possible, if we are not idle
            [HelperTools scheduleBackgroundTask:![[MLXMPPManager sharedInstance] allAccountsIdle]];
            
            //this was the last push in the pipeline --> disconnect to prevent double handling of incoming stanzas
            //that could be handled in mainapp and later again in NSE on next NSE wakeup (because still queued in the freezed NSE)
            //and kill the appex afterwards to get a clean run next time
            [self disconnectAndFeedAllWaitingHandlers];
            
            //check if we got a new push in the meantime (e.g. while disconnecting) and kill ourselves if not
            //(this returns YES if we got new pushes in the meantime)
            if([self checkForNewPushes])
            {
                DDLogInfo(@"Okay, not shutting down appex: got a last minute push in the meantime");
                //we got a new push but our firstPush flag was NO for that one --> set self.firstPush to YES and
                //do the same things we would do for the (really) first push (e.g. connect our accounts)
                //NOTE: because we can only reach this code if at least one push already came in and triggered the expiration timer, the following should never happen
                MLAssert(![self checkAndUpdateFirstPush:YES], @"first push was already YES, that should never happen");
                
                //retrigger the first push logic
                [self incomingPush:nil];
            }
            else
                [self killAppex];
        }
        else
        {
            DDLogInfo(@"Got next push, not shutting down appex");
            //we can unfreeze our incoming streams because we got another push
            [self unfreezeAllParseQueues];
        }
    }
}

-(void) incomingIPC:(NSNotification*) notification
{
    NSDictionary* message = notification.userInfo;
    if([message[@"name"] isEqualToString:@"Monal.disconnectAll"])
    {
        DDLogInfo(@"Got disconnectAll IPC message");
        [self disconnectAndFeedAllWaitingHandlers];
        [self killAppex];
    }
    else if([message[@"name"] isEqualToString:@"Monal.connectIfNecessary"])
    {
        DDLogInfo(@"Got connectIfNecessary IPC message --> IGNORING!");
        //(re)connect all accounts
        //[[MLXMPPManager sharedInstance] connectIfNecessary];
    }
}

-(void) freezeAllParseQueues
{
    DDLogInfo(@"Freezing all incoming streams until we know if we are either terminating or got another push");
    dispatch_queue_t queue = dispatch_queue_create("im.monal.freezeAllParseQueues", DISPATCH_QUEUE_CONCURRENT);
    for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
    {
        //disconnect to prevent endless loops trying to connect
        dispatch_async(queue, ^{
            DDLogVerbose(@"freezeAllParseQueues: %@", account);
            [account freezeParseQueue];
            DDLogVerbose(@"freezeAllParseQueues: %@", account);
        });
    }
    dispatch_barrier_sync(queue, ^{
        DDLogVerbose(@"freezeAllParseQueues done (inside barrier)");
    });
    DDLogInfo(@"All parse queues frozen now");
}

-(void) unfreezeAllParseQueues
{
    DDLogInfo(@"Unfreezing all incoming streams again, we got another push");
    for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
        [account unfreezeParseQueue];
    DDLogInfo(@"All parse queues operational again");
}

-(void) updateUnread
{
    DDLogVerbose(@"updating app badge via updateUnread");
    UNMutableNotificationContent* content = [UNMutableNotificationContent new];
    
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    NSInteger unread = 0;
    if(unreadMsgCnt != nil)
        unread = [unreadMsgCnt integerValue];
    DDLogVerbose(@"Raw badge value: %lu", (long)unread);
    DDLogDebug(@"Adding badge value: %lu", (long)unread);
    content.badge = [NSNumber numberWithInteger:unread];
    
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:@"badge_update" content:content trigger:nil];
    NSError* error = [HelperTools postUserNotificationRequest:request];
    if(error)
        DDLogError(@"Error posting local badge_update notification: %@", error);
    else
        DDLogVerbose(@"Unread badge updated successfully");
}

-(void) nowIdle:(NSNotification*) notification
{
    DDLogInfo(@"### SOME ACCOUNT CHANGED TO IDLE STATE ###");
    [HelperTools updateSyncErrorsWithDeleteOnly:YES andWaitForCompletion:NO];
}

@end


static NSMutableArray* handlers;;
static BOOL warnUnclean = NO;

@implementation NotificationService

+(void) initialize
{
    [HelperTools initSystem];
    
    handlers = [NSMutableArray new];
    
    //init IPC
    [IPC initializeForProcess:@"NotificationServiceExtension"];
    [MLProcessLock initializeForProcess:@"NotificationServiceExtension"];
    
    //log startup
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    NSString* buildDate = [NSString stringWithUTF8String:__DATE__];
    NSString* buildTime = [NSString stringWithUTF8String:__TIME__];
    
    warnUnclean = ![NotificationService getAppexCleanShutdownStatus];
    if(warnUnclean)
        DDLogError(@"detected unclean appex shutdown!");
    
    //mark this appex as unclean (will be cleared directly before calling exit(0))
    [NotificationService setAppexCleanShutdownStatus:NO];
    
    DDLogInfo(@"Notification Service Extension started: %@", [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@ %@ UTC)", @ ""), version, buildDate, buildTime]);
    [DDLog flushLog];
}

+(BOOL) getAppexCleanShutdownStatus
{
    //we use the defaultsDB to avoid write transaction to the main DB which would kill the main app while running in the background
    //(use the standardUserDefaults of the appex instead of the shared one exposed by our HelperTools to reduce kills due to locking even further)
    NSNumber* wasClean = [[NSUserDefaults standardUserDefaults] objectForKey:@"clean_appex_shutdown"];
    return wasClean == nil || wasClean.boolValue;
}

+(void) setAppexCleanShutdownStatus:(BOOL) shutdownStatus
{
    //we use the defaultsDB to avoid write transaction to the main DB which would kill the main app while running in the background
    //(use the standardUserDefaults of the appex instead of the shared one exposed by our HelperTools to reduce kills due to locking even further)
    [[NSUserDefaults standardUserDefaults] setBool:shutdownStatus forKey:@"clean_appex_shutdown"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(id) init
{
    DDLogInfo(@"Initializing notification service extension class");
    self = [super init];
    return self;
}

-(void) dealloc
{
    DDLogInfo(@"Deallocating notification service extension class");
    [DDLog flushLog];
}

-(void) didReceiveNotificationRequest:(UNNotificationRequest*) request withContentHandler:(void (^)(UNNotificationContent* _Nonnull)) contentHandler
{
    DDLogInfo(@"Notification handler called (request id: %@)", request.identifier);
    DDLogInfo(@"Push userInfo: %@", request.content.userInfo);
    [handlers addObject:contentHandler];
    
    //only show this notification once a day at maximum (and if a build number was given in our push)
    NSDate* lastAppVersionAlert = [[HelperTools defaultsDB] objectForKey:@"lastAppVersionAlert"];
    if((lastAppVersionAlert == nil || [[NSDate date] timeIntervalSinceDate:lastAppVersionAlert] > 86400) && request.content.userInfo[@"firstGoodBuildNumber"] != nil)
    {
        NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
        long buildNumber = ((NSString*)[infoDict objectForKey:@"CFBundleVersion"]).integerValue;
        long firstGoodBuildNumber = ((NSNumber*)request.content.userInfo[@"firstGoodBuildNumber"]).integerValue;
        BOOL isKnownGoodBuild = NO;
        for(NSNumber* allowed in request.content.userInfo[@"knownGoodBuildNumber"])
            if(buildNumber == allowed.integerValue)
                isKnownGoodBuild = YES;
        DDLogDebug(@"current build number: %ld, firstGoodBuildNumber: %ld, isKnownGoodBuild: %@", buildNumber, firstGoodBuildNumber, bool2str(isKnownGoodBuild));
        if(buildNumber < firstGoodBuildNumber && !isKnownGoodBuild)
        {
            UNMutableNotificationContent* tooOldContent = [UNMutableNotificationContent new];
            tooOldContent.title = NSLocalizedString(@"Very old app version", @"");
            tooOldContent.subtitle = NSLocalizedString(@"Please update!", @"");
            tooOldContent.body = NSLocalizedString(@"This app is too old and can contain security bugs as well as suddenly cease operation. Please Upgrade!", @"");
            tooOldContent.sound = [UNNotificationSound defaultSound];
            UNNotificationRequest* errorRequest = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:tooOldContent trigger:nil];
            NSError* error = [HelperTools postUserNotificationRequest:errorRequest];
            if(error)
                DDLogError(@"Error posting local app-too-old notification: %@", error);
            [[HelperTools defaultsDB] setObject:[NSDate now] forKey:@"lastAppVersionAlert"];
            [[HelperTools defaultsDB] synchronize];
        }
    }
    
#ifdef DEBUG
    if(warnUnclean)
    {
        UNMutableNotificationContent* errorContent = [UNMutableNotificationContent new];
        errorContent.title = NSLocalizedString(@"Unclean appex shutown", @"");
        errorContent.body = NSLocalizedString(@"This should never happen, please contact the developers and provide a logfile!", @"");
        errorContent.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest* errorRequest = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:errorContent trigger:nil];
        NSError* error = [HelperTools postUserNotificationRequest:errorRequest];
        if(error)
            DDLogError(@"Error posting local appex unclean shutdown error notification: %@", error);
        else
            warnUnclean = NO;       //try again on error
    }
#endif
    
    //proxy to push singleton
    DDLogDebug(@"proxying to incomingPush");
    [DDLog flushLog];
    [[PushSingleton instance] incomingPush:contentHandler];
    DDLogDebug(@"incomingPush proxy completed");
    [DDLog flushLog];
}

-(void) serviceExtensionTimeWillExpire
{
    DDLogError(@"notification handler expired, that should never happen!");
    
/*
#ifdef DEBUG
    UNMutableNotificationContent* errorContent = [UNMutableNotificationContent new];
    errorContent.title = @"Unexpected appex expiration";
    errorContent.body = @"This should never happen, please contact the developers and provide a logfile!";
    errorContent.sound = [UNNotificationSound defaultSound];
    UNNotificationRequest* errorRequest = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:errorContent trigger:nil];
    NSError* error = [HelperTools postUserNotificationRequest:errorRequest];
    if(error)
        DDLogError(@"Error posting local appex expiration error notification: %@", error);
#endif
    
    //It seems the iOS induced deadlock unlocks itself after this expiration handler got called and even new pushes
    //can come in while this handler is still running
    //--> we just wait for 1.8 seconds to make sure the unlocking can happen
    //    (this should be greater than the 1.5 seconds waiting time on last pushes and possibly smaller than 2 seconds,
    //    cause that could be the time apple will kill us after)
    //NOTE: the unlocking of our deadlock will feed this expired handler and no killing should occur
    //WARNING: if it's a real deadlock not unlocking itself, apple will kill us nontheless,
    //         but that's not different to us committing suicide like in the old code commented below
    usleep(1800000);
*/

#ifdef DEBUG
    if([handlers count] > 0)
    {
        //we don't want two error notifications for the user
        [NotificationService setAppexCleanShutdownStatus:YES];
        
        //we feed all handlers, these shouldn't be silenced already, because we wouldn't see this expiration
        for(void (^_handler)(UNNotificationContent* _Nonnull) in handlers)
        {
            DDLogError(@"Feeding handler with error notification: %@", _handler);
            UNMutableNotificationContent* errorContent = [UNMutableNotificationContent new];
            errorContent.title = NSLocalizedString(@"Unexpected appex expiration", @"");
            errorContent.body = NSLocalizedString(@"This should never happen, please contact the developers and provide a logfile!", @"");
            errorContent.sound = [UNNotificationSound defaultSound];
            _handler(errorContent);
        }
    }
    else
        [NotificationService setAppexCleanShutdownStatus:NO];
#else
    if([handlers count] > 0)
    {
        //we don't want two error notifications for the user
        [NotificationService setAppexCleanShutdownStatus:YES];
        
        //we feed all handlers, these shouldn't be silenced already, because we wouldn't see this expiration
        for(void (^_handler)(UNNotificationContent* _Nonnull) in handlers)
        {
            DDLogError(@"Feeding handler with silent notification: %@", _handler);
            UNMutableNotificationContent* emptyContent = [UNMutableNotificationContent new];
            _handler(emptyContent);
        }
    }
    else
        [NotificationService setAppexCleanShutdownStatus:NO];
#endif

    DDLogInfo(@"Committing suicide...");
    [DDLog flushLog];
    exit(0);

/*
    //proxy to push singleton
    DDLogDebug(@"proxying to pushExpired");
    [DDLog flushLog];
    [[PushSingleton instance] pushExpired];
    DDLogDebug(@"pushExpired proxy completed");
    [DDLog flushLog];
*/

}

@end
