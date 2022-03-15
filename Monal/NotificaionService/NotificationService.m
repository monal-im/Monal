//
//  NotificationService.m
//  NotificaionService
//
//  Created by Anurodh Pokharel on 9/16/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <BackgroundTasks/BackgroundTasks.h>

#import "NotificationService.h"
#import "MLConstants.h"
#import "HelperTools.h"
#import "IPC.h"
#import "MLProcessLock.h"
#import "MLXMPPManager.h"
#import "MLNotificationManager.h"
#import "MLFiletransfer.h"
#import "xmpp.h"

static NSString* kBackgroundFetchingTask = @"im.monal.fetch";

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
            self.handler([[UNMutableNotificationContent alloc] init]);
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


@interface PushSingleton : NSObject
@property (atomic, strong) NSMutableArray* handlerList;
@property (atomic) BOOL isFirstPush;
@end

@implementation PushSingleton

+(id) instance
{
    static PushSingleton* sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PushSingleton alloc] init];
    });
    return sharedInstance;
}

-(instancetype) init
{
    self = [super init];
    DDLogInfo(@"Initializing push singleton");
    self.handlerList = [[NSMutableArray alloc] init];
    self.isFirstPush = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(incomingIPC:) name:kMonalIncomingIPC object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:kMonalUpdateUnread object:nil];
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
        return self.handlerList.count != 0;
    }
}

-(void) killAppex
{
    //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
    
    [[DataLayer sharedInstance] setAppexCleanShutdownStatus:YES];
    
    DDLogInfo(@"Now killing appex process, goodbye...");
    [DDLog flushLog];
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
        if([MLProcessLock checkRemoteRunning:@"MainApp" withTimeout:2.0])
        {
            //this will make sure we still run if we get triggered immediately after the mainapp disconnected but before its process got freezed
            DDLogDebug(@"Main app already in foreground, sleeping for 5 seconds and trying again");
            usleep(5000000);
            DDLogDebug(@"Pinging main app again");
            if([MLProcessLock checkRemoteRunning:@"MainApp" withTimeout:2.0])       //use a high timeout to make sure the mainapp isn't running, even if the mainthread is heavily busy
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
        [[MLXMPPManager sharedInstance] connectIfNecessary];
    }
}

-(void) pushExpired
{
    DDLogInfo(@"Handling expired push: %lu", (unsigned long)[self.handlerList count]);
    
    BOOL isLastHandler = [self checkForLastHandler];
    if(isLastHandler)
    {
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
        DDLogInfo(@"Last push expired shutting down in 1500ms if no new push comes in in the meantime");
        //wait 1500ms to allow other pushed already queued on the device (but not yet delivered to us) to be delivered to us
        //after the last push expired we have ~5 seconds run time left to do the clean disconnect
        //--> waiting 1500ms before checking if this was the last push that expired (e.g. no new push came in) does not do any harm here
        //WARNING: we have to closely watch apple...if they remove this 5 second gap between this call to the expiration handler and the actual
        //appex freeze, this sleep will no longer be harmless and could even cause smacks state corruption (by not diconnecting cleanly and having stanzas
        //still in the TCP queue delivered on next appex unfreeze even if they have been handled by the mainapp already)
        usleep(1500000);
        
        //this returns YES if we got new pushes in the meantime --> do nothing if so
        if(![self checkForNewPushes])
        {
            DDLogInfo(@"Shutting down appex now");
            
            //don't post sync errors here, already did so above (see explanation there)
            
            //check idle state and schedule a background task (handled in the main app) if not idle
            if(![[MLXMPPManager sharedInstance] allAccountsIdle])
                [self scheduleBackgroundFetchingTask];
            
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
    for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
        [account freezeParseQueue];
}

-(void) unfreezeAllParseQueues
{
    DDLogInfo(@"Unfreezing all incoming streams again, we got another push");
    for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
        [account unfreezeParseQueue];
}

-(void) updateUnread
{
    DDLogVerbose(@"updating app badge via updateUnread");
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    
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

-(void) scheduleBackgroundFetchingTask
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
        //assume there will be one next push incoming shortly and add an extra of 10 seconds on top of its handling time
        request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:40];
        BOOL success = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
        if(!success) {
            // Errorcodes https://stackoverflow.com/a/58224050/872051
            DDLogError(@"Failed to submit BGTask request %@, error: %@", request, error);
        } else {
            DDLogVerbose(@"Success submitting BGTask request %@, error: %@", request, error);
        }
    } onQueue:dispatch_get_main_queue()];
}

@end


@interface NotificationService ()
@end

static NSMutableArray* handlers;;
static BOOL warnUnclean = NO;

@implementation NotificationService

+(void) initialize
{
    handlers = [[NSMutableArray alloc] init];
    
    [HelperTools configureLogging];
    [DDLog flushLog];
    
    //log unhandled exceptions
    NSSetUncaughtExceptionHandler(&logException);
    
    [HelperTools activityLog];
    
    //init IPC
    [IPC initializeForProcess:@"NotificationServiceExtension"];
    
    //handle message notifications by initializing the MLNotificationManager
    [MLNotificationManager sharedInstance];
    
    //initialize the xmppmanager (used later for connectivity checks etc.)
    //we initialize it here to make sure the connectivity check is complete when using it later
    [MLXMPPManager sharedInstance];
    
    //log startup
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    NSString* buildDate = [NSString stringWithUTF8String:__DATE__];
    NSString* buildTime = [NSString stringWithUTF8String:__TIME__];
    usleep(100000);     //wait for initial connectivity check (100ms)
    
#ifdef DEBUG
    BOOL shutdownStatus = [[DataLayer sharedInstance] getAppexCleanShutdownStatus];
    warnUnclean = !shutdownStatus;
    if(warnUnclean)
        DDLogError(@"detected unclean appex shutdown!");
#endif
    
    //mark this appex as unclean (will be cleared directly before calling exit(0))
    [[DataLayer sharedInstance] setAppexCleanShutdownStatus:NO];
    
    DDLogInfo(@"Notification Service Extension started: %@", [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@ %@ UTC)", @ ""), version, buildDate, buildTime]);
    [DDLog flushLog];
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
    [handlers addObject:contentHandler];
    
    if(warnUnclean)
    {
        UNMutableNotificationContent* errorContent = [[UNMutableNotificationContent alloc] init];
        errorContent.title = @"Unclean appex shutown";
        errorContent.body = @"This should never happen, please contact the developers and provide a logfile!";
        errorContent.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest* errorRequest = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:errorContent trigger:nil];
        NSError* error = [HelperTools postUserNotificationRequest:errorRequest];
        if(error)
            DDLogError(@"Error posting local appex unclean shutdown error notification: %@", error);
        else
            warnUnclean = NO;       //try again on error
    }
    
    //just "ignore" this push if we have not migrated our defaults db already (this needs a normal app start to happen)
    if(![[HelperTools defaultsDB] boolForKey:@"DefaulsMigratedToAppGroup"])
    {
        DDLogWarn(@"defaults not migrated to app group, ignoring push and posting notification as coming from the appserver (a dummy one)");
        contentHandler([request.content mutableCopy]);
        return;
    }
    
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
    UNMutableNotificationContent* errorContent = [[UNMutableNotificationContent alloc] init];
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
        [[DataLayer sharedInstance] setAppexCleanShutdownStatus:YES];
        
        //we feed all handlers, these shouldn't be silenced already, because we wouldn't see this expiration
        for(void (^_handler)(UNNotificationContent* _Nonnull) in handlers)
        {
            DDLogError(@"Feeding handler with error notification: %@", _handler);
            UNMutableNotificationContent* errorContent = [[UNMutableNotificationContent alloc] init];
            errorContent.title = @"Unexpected appex expiration";
            errorContent.body = @"This should never happen, please contact the developers and provide a logfile!";
            errorContent.sound = [UNNotificationSound defaultSound];
            _handler(errorContent);
        }
    }
    else
        [[DataLayer sharedInstance] setAppexCleanShutdownStatus:NO];
#else
    if([handlers count] > 0)
    {
        //we don't want two error notifications for the user
        [[DataLayer sharedInstance] setAppexCleanShutdownStatus:YES];
        
        //we feed all handlers, these shouldn't be silenced already, because we wouldn't see this expiration
        for(void (^_handler)(UNNotificationContent* _Nonnull) in handlers)
        {
            DDLogError(@"Feeding handler with silent notification: %@", _handler);
            UNMutableNotificationContent* emptyContent = [[UNMutableNotificationContent alloc] init];
            _handler(emptyContent);
        }
    }
    else
        [[DataLayer sharedInstance] setAppexCleanShutdownStatus:NO];
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
