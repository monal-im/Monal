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

@interface Push : NSObject
@property (atomic, strong) NSMutableArray* handlerList;
@property (atomic, strong) NSMutableSet* idleAccounts;
@property (atomic) BOOL incomingPushWaiting;
@end

@implementation Push

+(id) instance
{
    static Push* sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Push alloc] init];
    });
    return sharedInstance;
}

-(id) init
{
    self = [super init];
    DDLogInfo(@"Initializing push singleton");
    self.handlerList = [[NSMutableArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(filetransfersNowIdle:) name:kMonalFiletransfersIdle object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(xmppError:) name:kXMPPError object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:kMonalUpdateUnread object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(incomingIPC:) name:kMonalIncomingIPC object:nil];
    return self;
}

-(void) dealloc
{
    DDLogError(@"Deallocating push singleton");
    [DDLog flushLog];
}

-(void) killAppex
{
    @synchronized(self) {
        [[DataLayer sharedInstance] setAppexCleanShutdownStatus:NO];
        DDLogInfo(@"Now killing appex process, goodbye...");
        [DDLog flushLog];
        exit(0);
    }
}

-(void) incomingPush:(void (^)(UNNotificationContent* _Nonnull)) contentHandler
{
    DDLogInfo(@"Got incoming push");
    createTimer(25.0, (^{
        [self pushExpired];
    }));
    
    //make sure the rest of this class knows that we got one more push to be handled, even if it isn't added to self.handlerList yet because we want to ping the mainapp first
    @synchronized(self) {
        self.incomingPushWaiting = YES;
    }
    
    //terminate appex if the main app is already running (use a high timeout to make sure the mainapp isn't running, even if the mainthread is heavily busy)
    //EXPLANATION: the mainapp uses the main thread for UI stuff, which sometimes can block the main thread for more than 250ms
    //             --> that would make the ping *NOT* succeed and in turn erroneously tell the appex that the mainapp was not running
    //             the appex on the other side does not use its main thread --> a ping coming from the mainapp will almost always
    //             be answered in only a few milliseconds
    DDLogInfo(@"Pinging main app");
    if([MLProcessLock checkRemoteRunning:@"MainApp" withTimeout:2.0])
    {
        //this will make sure we still run if we get triggered immediately after the mainapp disconnected but before its process got freezed
        DDLogDebug(@"Main app already in foreground, sleeping for 5 seconds and trying again");
        createTimer(5.0, (^{
            DDLogDebug(@"Pinging main app again");
            if([MLProcessLock checkRemoteRunning:@"MainApp" withTimeout:2.0])       //use a high timeout to make sure the mainapp isn't running, even if the mainthread is heavily busy
            {
                DDLogInfo(@"NOT connecting accounts, main app already running in foreground, terminating immediately instead");
                [DDLog flushLog];
                [self feedAllWaitingHandlersWithCompletion:^{
                    //now call this new handler we did not add to our handlerList (don't update unread badge, because this needs the database potentially locked by mainapp)
                    DDLogInfo(@"Feeding last handler...");
                    [self generateNotificationForHandler:contentHandler];
                    
                    //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                    [self killAppex];
                }];
            }
            else
            {
                DDLogDebug(@"Main app not in foreground anymore, handling push now");
                [self handlePushForReal:contentHandler];
            }
        }));
    }
    else
    {
        DDLogDebug(@"Main app not in foreground, handling push now");
        [self handlePushForReal:contentHandler];
    }
}

-(void) handlePushForReal:(void (^)(UNNotificationContent* _Nonnull)) contentHandler
{
    @synchronized(self) {
        DDLogInfo(@"Now handling incoming push");
        BOOL first = NO;
        if(![self.handlerList count])
        {
            DDLogInfo(@"First incoming push");
            self.idleAccounts = [[NSMutableSet alloc] init];
            first = YES;
        }
        
        //add contentHandler to our list
        DDLogDebug(@"Adding content handler to list: %lu", [self.handlerList count]);
        [self.handlerList addObject:contentHandler];
        self.incomingPushWaiting = NO;     //the incoming push was added to self.handlerList now
        
        if(first)       //first incoming push --> connect to servers
        {
            DDLogDebug(@"locking process and connecting accounts");
            [DDLog flushLog];
            [MLProcessLock lock];
            [[MLXMPPManager sharedInstance] connectIfNecessary];
        }
        else            //second, third etc. incoming push --> reconnect already idle accounts and check connectivity for already connected ones
        {
            for(xmpp* account in self.idleAccounts)
                [[MLXMPPManager sharedInstance] connectAccount:account.accountNo];
            self.idleAccounts = [[NSMutableSet alloc] init];        //we now don't have idle accounts anymore
        }
    }
}

-(void) pushExpired
{
    @synchronized(self) {
        DDLogInfo(@"Handling expired push: %lu", (unsigned long)[self.handlerList count]);
        
        //disconnect if this was the last handler and no new push comes in in the next 1500ms
        if([self.handlerList count] <= 1 && !self.incomingPushWaiting)
        {
            DDLogInfo(@"Last push expired and currently no new push pending, shutting down in 1500ms");
            
            //post a single silent notification using the next handler (that must have been the expired one because handlers expire in order)
            void (^handler)(UNNotificationContent*) = [self.handlerList firstObject];
            [self.handlerList removeObject:handler];
            [self generateNotificationForHandler:handler];
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                //wait 1500ms to allow other pushed already queued on the device (but not yet delivered to us) to be delivered to us
                //after a push expired we have ~5 seconds run time left to do the clean disconnect
                //--> waiting 1500ms before checking if this was the last push that expired (e.g. no new push came in) does not do any harm here
                //WARNING: we have to closely watch apple...if they remove this 5 second gap between this call to the expiration handler and the actual
                //appex freeze, this sleep will no longer be harmless and could even cause smacks state corruption (by not diconnecting cleanly and having stanzas
                //still in the TCP queue delivered on next appex unfreeze even if they have been handled by the mainapp already)
                DDLogInfo(@"Waiting 1500ms for next push before shutting down");
                usleep(1500000);
                
                @synchronized(self) {
                    //we don't want to post any sync error notifications if the xmpp channel is idle and we're only downloading filetransfers
                    //(e.g. [MLFiletransfer isIdle] is not YES)
                    if([self.handlerList count] <= 1 && !self.incomingPushWaiting)
                    {
                        DDLogInfo(@"Shutting down appex now");
                        
                        //post sync errors for all accounts still not idle now
                        [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                        
                        //check idle state and schedule a background task (handled in the main app) if not idle
                        if(![[MLXMPPManager sharedInstance] allAccountsIdle])
                            [self scheduleBackgroundFetchingTask];
                        
                        //this was the last push in the pipeline --> disconnect to prevent double handling of incoming stanzas
                        //that could be handled in mainapp and later again in NSE on next NSE wakeup (because still queued in the freezed NSE)
                        //NOTICE: this call will disconnect and feed the handler afterwards
                        [self feedAllWaitingHandlersWithCompletion:^{
                            //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                            [self killAppex];
                        }];
                    }
                    else
                        DDLogInfo(@"NOT shutting down appex: got new pipelined incomng push");
                }
            });
        }
        else
        {
            //post a single silent notification using the next handler (that must have been the expired one because handlers expire in order)
            void (^handler)(UNNotificationContent*) = [self.handlerList firstObject];
            [self.handlerList removeObject:handler];
            [self generateNotificationForHandler:handler];
        }
    }
}

-(void) incomingIPC:(NSNotification*) notification
{
    NSDictionary* message = notification.userInfo;
    if([message[@"name"] isEqualToString:@"Monal.disconnectAll"])
    {
        DDLogInfo(@"Got disconnectAll IPC message");
        [self feedAllWaitingHandlers];
    }
    else if([message[@"name"] isEqualToString:@"Monal.connectIfNecessary"])
    {
        DDLogInfo(@"Got connectIfNecessary IPC message --> IGNORING!");
        //(re)connect all accounts
        //[[MLXMPPManager sharedInstance] connectIfNecessary];
    }
}

//sadly we are not allowed to post notifications while our runtime gets extended --> useless for our purposes 
-(void) extendRuntime
{
    __block BOOL running = NO;
    [[NSProcessInfo processInfo] performExpiringActivityWithReason:@"could not synchronize" usingBlock:^(BOOL expired) {
        if(expired)
        {
            if(running)
                DDLogDebug(@"Execution time elapsed, terminating!");
            else
                DDLogWarn(@"Could not request more execution time, terminating!");
            
            //post sync errors for all accounts still not idle now
            [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
            
            //check idle state and schedule a background task (handled in the main app) if not idle
            if(![[MLXMPPManager sharedInstance] allAccountsIdle])
                [self scheduleBackgroundFetchingTask];
            
            //use feedAllWaitingHandlersWithCompletion: instead of feedAllWaitingHandlers, because feedAllWaitingHandlers
            //would async-dispatch to a new thread --> that would not block this thread and therefore freeze the appex
            //NOTICE: this call will disconnect and feed the handler afterwards
            [self feedAllWaitingHandlersWithCompletion:^{
                //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                [self killAppex];
            }];
            
            running = NO;       //only needed to log the warning below
        }
        else
        {
            running = YES;
            while(running)
                usleep(1000000);
            DDLogError(@"This should be never reached, because we commit suicide before!");
        }
    }];
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

-(UNMutableNotificationContent*) generateNotificationForHandler:(void (^)(UNNotificationContent*)) handler
{
    //this is used with special extension filtering entitlement which does not show notifications with empty body, title and subtitle
    //but: app badge updates are still performed: use this to make sure the badge is up to date, even if a message got marked as read (by XEP-0333 etc.)
    UNMutableNotificationContent* emptyContent = [[UNMutableNotificationContent alloc] init];
    if(handler)
        handler(emptyContent);
    return emptyContent;
}

-(void) feedAllWaitingHandlersWithCompletion:(monal_void_block_t) completion
{
    //repeated calls to this method will do nothing (every handler will already be used and every content will already be posted)
    @synchronized(self) {
        DDLogInfo(@"Disconnecting all accounts and feeding all pending handlers: %lu", [self.handlerList count]);
        
        //this has to be synchronous because we only want to continue if all accounts are completely disconnected
        [[MLXMPPManager sharedInstance] disconnectAll];
        
        //for debugging
        [self listNotifications];
        
        //we posted all notifications and disconnected, technically we're not running anymore
        //(even though our containing process will still be running for a few more seconds)
        [MLProcessLock unlock];
        
        //feed all waiting handlers with empty notifications to silence them
        //this will terminate/freeze the app extension afterwards
        while([self.handlerList count])
        {
            DDLogDebug(@"Feeding next handler");
            void (^handler)(UNNotificationContent*) = [self.handlerList firstObject];
            [self.handlerList removeObject:handler];
            [self generateNotificationForHandler:handler];
        }
    }
    
    if(completion)
        completion();
}

-(void) feedAllWaitingHandlers
{
    //dispatch in another thread to avoid blocking the thread calling this method (most probably the receiveQueue), which could result in a deadlock
    //without this dispatch a deadlock could also occur when this method tries to enter the receiveQueue (disconnectAll) while the receive queue
    //is waiting for the @synchronized(self) block in this method
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @synchronized(self) {
            [self feedAllWaitingHandlersWithCompletion:nil];
            
            //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
            [self killAppex];
        }
    });
}

-(void) listNotifications
{
    DDLogDebug(@"Listing pending notifications");
    [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
        for(UNNotificationRequest* request in requests)
        {
            DDLogDebug(@"Pending notification %@ --> %@: %@", request.identifier, request.content.title, request.content.body);
        }
    }];
    /*
    [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
        for(UNNotification* notification in notifications)
        {
            DDLogDebug(@"listNotifications: delivered notification %@ --> %@: %@", notification.request.identifier, notification.request.content.title, notification.request.content.body);
        }
    }];
    DDLogVerbose(@"done listing notifications...");
    */
}

-(void) nowIdle:(NSNotification*) notification
{
    //delete sync errors of all now idle accounts
    [HelperTools updateSyncErrorsWithDeleteOnly:YES andWaitForCompletion:NO];
    
    //use as much appex background time as possible (disconnect when the last push handler expires instead of when all accounts become idle)
    /*
    //this method will be called inside the receive queue and immediately disconnect the account
    //this is needed to not leak incoming stanzas while no instance of the NotificaionService class is active
    xmpp* xmppAccount = (xmpp*)notification.object;
    
    //ignore repeated idle notifications for already idle accounts
    @synchronized(self.idleAccounts) {
        if([self.idleAccounts containsObject:xmppAccount])
        {
            DDLogDebug(@"Ignoring already idle account: %@", xmppAccount.connectionProperties.identity.jid);
            return;
        }
        [self.idleAccounts addObject:xmppAccount];
    }
    
    DDLogInfo(@"notification handler: some account idle: %@", xmppAccount.connectionProperties.identity.jid);
    [xmppAccount disconnect];
    [HelperTools updateSyncErrorsWithDeleteOnly:YES andWaitForCompletion:NO];
    
    [self checkIfEverythingIsIdle];
    */
}

-(void) filetransfersNowIdle:(NSNotification*) notification
{
    //delete sync errors of all now idle accounts
    [HelperTools updateSyncErrorsWithDeleteOnly:YES andWaitForCompletion:NO];
    
    //use as much appex background time as possible (disconnect when the last push handler expires instead of when all accounts become idle)
    /*
    DDLogDebug(@"notification handler: all filetransfers complete now");
    [self checkIfEverythingIsIdle];
    */
}

-(void) checkIfEverythingIsIdle
{
    if([[MLXMPPManager sharedInstance] allAccountsIdle] && [MLFiletransfer isIdle])
    {
        DDLogInfo(@"notification handler: all accounts idle and filetransfers complete --> terminating extension");
        
        //remove syncError notifications because all accounts are idle and fully synced now
        [HelperTools updateSyncErrorsWithDeleteOnly:YES andWaitForCompletion:YES];
        
        [self feedAllWaitingHandlers];
    }
}

-(void) xmppError:(NSNotification*) notification
{
    DDLogInfo(@"notification handler: got xmpp error");
    if([notification.userInfo[@"isSevere"] boolValue])
    {
        //dispatch in another thread to avoid blocking the thread posting this notification (most probably the receiveQueue)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            //disconnect this account and make sure the account is marked as idle afterwards
            //(which will ultimately lead to the termination of this app extension)
            DDLogWarn(@"notification handler: severe account error --> disconnecting this account");
            [notification.object disconnect];
            [self nowIdle:notification];
        });
    }
}

-(void) updateUnread
{
    DDLogVerbose(@"updating app badge via updateUnread");
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    UNMutableNotificationContent* content = [self generateNotificationForHandler:nil];
    
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    NSInteger unread = 0;
    if(unreadMsgCnt != nil)
        unread = [unreadMsgCnt integerValue];
    DDLogVerbose(@"Raw badge value: %lu", (long)unread);
    DDLogDebug(@"Adding badge value: %lu", (long)unread);
    content.badge = [NSNumber numberWithInteger:unread];
    
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:@"badge_update" content:content trigger:nil];
    [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if(error)
            DDLogError(@"Error posting local badge_update notification: %@", error);
    }];
}

@end

@interface NotificationService () {
    NSMutableArray* _handlers;
}
@end

static BOOL warnUnclean = NO;

@implementation NotificationService

+(void) initialize
{
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
    DDLogInfo(@"Notification Service Extension started: %@", [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@ %@ UTC)", @ ""), version, buildDate, buildTime]);
    [DDLog flushLog];
    usleep(100000);     //wait for initial connectivity check (100ms)
    
#ifdef DEBUG
    BOOL shutdownStatus = [[DataLayer sharedInstance] getAppexCleanShutdownStatus];
    warnUnclean = shutdownStatus;
    if(shutdownStatus)
        DDLogError(@"detected unclean appex shutdown!");
#endif
    
    //mark this appex as unclean (will be cleared directly before calling exit(0))
    [[DataLayer sharedInstance] setAppexCleanShutdownStatus:YES];
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
    [_handlers addObject:contentHandler];
    
    if(warnUnclean)
    {
        UNMutableNotificationContent* errorContent = [[UNMutableNotificationContent alloc] init];
        errorContent.title = @"Unclean appex shutown";
        errorContent.body = @"This should never happen, please contact the developers and provide a logfile!";
        errorContent.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest* errorRequest = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:errorContent trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:errorRequest withCompletionHandler:^(NSError * _Nullable error) {
            if(error)
                DDLogError(@"Error posting local appex unclean shutdown error notification: %@", error);
            else
                warnUnclean = NO;       //try again on error
        }];
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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[Push instance] incomingPush:contentHandler];
    });
    DDLogDebug(@"incomingPush proxy completed");
    [DDLog flushLog];
}

-(void) serviceExtensionTimeWillExpire
{
    DDLogError(@"notification handler expired, that should never happen!");
    
#ifdef IS_ALPHA
    if([_handlers count] > 0)
    {
        //we feed all handlers with an error message, even if already silenced by the normal system, just to make sure
        for(void (^_handler)(UNNotificationContent* _Nonnull) in _handlers)
        {
            UNMutableNotificationContent* errorContent = [[UNMutableNotificationContent alloc] init];
            errorContent.title = @"Unexpected error";
            errorContent.body = @"This should never happen, please contact the developers and provide a logfile!";
            errorContent.sound = [UNNotificationSound defaultSound];
            _handler(errorContent);
        }
    }
#else
    if([_handlers count] > 0)
    {
        //we feed all handlers, even if already done by the normal system,just to make sure
        for(void (^_handler)(UNNotificationContent* _Nonnull) in _handlers)
        {
            UNMutableNotificationContent* emptyContent = [[UNMutableNotificationContent alloc] init];
            _handler(emptyContent);
        }
    }
#endif

    [[DataLayer sharedInstance] setAppexCleanShutdownStatus:NO];
    DDLogInfo(@"Committing suicide...");
    [DDLog flushLog];
    exit(0);
    
    /*
    //proxy to push singleton
    DDLogDebug(@"proxying to pushExpired");
    [DDLog flushLog];
    [[Push instance] pushExpired];
    DDLogDebug(@"pushExpired proxy completed");
    [DDLog flushLog];
    */
}

@end
