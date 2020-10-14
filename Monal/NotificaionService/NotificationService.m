//
//  NotificationService.m
//  NotificaionService
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

@interface Push : NSObject
@property (atomic, strong) NSMutableArray* handlerList;
@property (atomic, strong) NSMutableSet* idleAccounts;
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(xmppError:) name:kXMPPError object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(incomingIPC:) name:kMonalIncomingIPC object:nil];
    return self;
}

-(void) dealloc
{
    DDLogError(@"Deallocating push singleton");
    [DDLog flushLog];
}

-(void) incomingPush:(void (^)(UNNotificationContent* _Nonnull)) contentHandler
{
    @synchronized(self) {
        DDLogInfo(@"Handling incoming push");
        BOOL first = NO;
        if(![self.handlerList count])
        {
            DDLogInfo(@"First incoming push");
            self.idleAccounts = [[NSMutableSet alloc] init];
            first = YES;
        }
        
        //add contentHandler to our list
        DDLogVerbose(@"Adding content handler to list: %lu", [self.handlerList count]);
        [self.handlerList addObject:contentHandler];
        
        //terminate appex if the main app is already running
        if([MLProcessLock checkRemoteRunning:@"MainApp"])
        {
            DDLogInfo(@"NOT connecting accounts, main app already running in foreground, terminating immediately instead");
            [DDLog flushLog];
            [self feedAllWaitingHandlers];
            return;
        }
        
        if(first)      //first incoming push --> connect to servers
        {
            DDLogVerbose(@"locking process and connecting accounts");
            [DDLog flushLog];
            [MLProcessLock lock];
            [[MLXMPPManager sharedInstance] connectIfNecessary];
        }
        else
            ;       //do nothing if not the first call (MLXMPPManager is already connecting)
    }
}

-(void) pushExpired
{
    @synchronized(self) {
        DDLogInfo(@"Handling expired push");
        
        if([self.handlerList count]==1)
            [HelperTools postSendingErrorNotification];
        
        //post a single silent notification using the next handler (that must have been the expired one because handlers expire in order)
        if([self.handlerList count])
        {
            void (^handler)(UNNotificationContent*) = [self.handlerList firstObject];
            [self.handlerList removeObject:handler];
            [self callHandler:handler];
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
        DDLogInfo(@"Got connectIfNecessary IPC message");
        //(re)connect all accounts
        [[MLXMPPManager sharedInstance] connectIfNecessary];
    }
}

-(void) callHandler:(void (^)(UNNotificationContent*)) handler
{
    //this is used with special extension filtering entitlement which does not show notifications with empty body, title and subtitle
    //but: app badge updates are still performed: use this to make sure the badge is up to date, even if a message got marked as read (by XEP-0333 etc.)
    UNMutableNotificationContent* emptyContent = [[UNMutableNotificationContent alloc] init];
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    DDLogInfo(@"Updating unread badge to: %@", unreadMsgCnt);
    emptyContent.badge = unreadMsgCnt;
    handler(emptyContent);
}

-(void) feedAllWaitingHandlers
{
    //dispatch in another thread to avoid blocking the thread calling this method (most probably the receiveQueue), which could result in a deadlock
    //without this dispatch a deadlock could also occur when this method tries to enter the receiveQueue (disconnectAll) while the receive queue
    //is waiting for the @synchronized(self) block in this method
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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
                DDLogVerbose(@"Feeding handler");
                void (^handler)(UNNotificationContent*) = [self.handlerList firstObject];
                [self.handlerList removeObject:handler];
                [self callHandler:handler];
            }
        }
    });
}

-(void) listNotifications
{
    [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
        for(UNNotificationRequest* request in requests)
        {
            DDLogInfo(@"listNotifications: pending notification %@ --> %@: %@", request.identifier, request.content.title, request.content.body);
        }
    }];
    [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
        for(UNNotification* notification in notifications)
        {
            DDLogInfo(@"listNotifications: delivered notification %@ --> %@: %@", notification.request.identifier, notification.request.content.title, notification.request.content.body);
        }
    }];
}

-(void) nowIdle:(NSNotification*) notification
{
    //this method will be called inside the receive queue or send queue and immediately disconnect the account
    //this is needed to not leak incoming stanzas while no instance of the NotificaionService class is active
    xmpp* xmppAccount = (xmpp*)notification.object;
    
    //ignore repeated idle notifications for already idle accounts
    @synchronized(self.idleAccounts) {
        if([self.idleAccounts containsObject:xmppAccount])
        {
            DDLogVerbose(@"Ignoring already idle account: %@", xmppAccount.connectionProperties.identity.jid);
            return;
        }
        [self.idleAccounts addObject:xmppAccount];
    }
    
    DDLogInfo(@"notification handler: some account idle: %@", xmppAccount.connectionProperties.identity.jid);
    [xmppAccount disconnect];
    
    if([[MLXMPPManager sharedInstance] allAccountsIdle])
    {
        DDLogInfo(@"notification handler: all accounts idle --> terminating extension");
        [self feedAllWaitingHandlers];
    }
}

-(void) xmppError:(NSNotification*) notification
{
    DDLogInfo(@"notification handler: got xmpp error");
    //dispatch in another thread to avoid blocking the thread posting this notification (most probably the receiveQueue)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //display an error notification and disconnect this account, leaving the extension running until all accounts are idle
        //(disconnected accounts count as idle)
        DDLogInfo(@"notification handler: account error --> publishing this as error notification and disconnecting this account");
        //extract error contents and disconnect the account
        NSArray* payload = [notification.object copy];
        NSString* message = payload[1];
        xmpp* xmppAccount = payload.firstObject;
        DDLogVerbose(@"error(%@): %@", xmppAccount.connectionProperties.identity.jid, message);
        //this will result in an idle notification for this account ultimately leading to the termination of this app extension
        [xmppAccount disconnect];
        
        //display error notification
        NSString* idval = xmppAccount.connectionProperties.identity.jid;        //use this to only show the newest error notification per account
        UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
        content.title = xmppAccount.connectionProperties.identity.jid;
        content.body = message;
        content.sound = [UNNotificationSound defaultSound];
        UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:nil];
        [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
            if(error)
                DDLogError(@"Error posting xmppError notification: %@", error);
        }];
    });
}

@end

@interface NotificationService ()
@end

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
    usleep(100000);     //wait for initial connectivity check
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
    
    //just "ignore" this push if we have not migrated our defaults db already (this needs a normal app start to happen)
    if(![[HelperTools defaultsDB] boolForKey:@"DefaulsMigratedToAppGroup"])
    {
        DDLogInfo(@"defaults not migrated to app group, ignoring push and posting notification as coming from the appserver (a dummy one)");
        contentHandler([request.content mutableCopy]);
        return;
    }
    
    //proxy to push singleton
    DDLogVerbose(@"proxying to incomingPush");
    [DDLog flushLog];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[Push instance] incomingPush:contentHandler];
    });
    DDLogVerbose(@"incomingPush proxy completed");
    [DDLog flushLog];
}

-(void) serviceExtensionTimeWillExpire
{
    DDLogInfo(@"notification handler expired");
    [DDLog flushLog];
    
    //proxy to push singleton
    DDLogVerbose(@"proxying to pushExpired");
    [DDLog flushLog];
    [[Push instance] pushExpired];
    DDLogVerbose(@"pushExpired proxy completed");
    [DDLog flushLog];
}

@end
