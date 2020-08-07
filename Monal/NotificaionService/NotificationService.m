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

static void logException(NSException* exception)
{
    [DDLog flushLog];
    DDLogError(@"*** CRASH(%@): %@", [exception name], [exception reason]);
    [DDLog flushLog];
    DDLogError(@"*** UserInfo: %@", [exception userInfo]);
    DDLogError(@"*** Stack Trace: %@", [exception callStackSymbols]);
    [DDLog flushLog];
}

@interface Push : NSObject
@property (atomic, strong) NSMutableArray* contentList;
@property (atomic, strong) NSMutableArray* handlerList;
@property (atomic, strong) NSMutableSet* idleAccounts;
@end

@implementation Push

+(id) instance
{
    Push* __block sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Push alloc] init];
    });
    return sharedInstance;
}

-(id) init
{
    DDLogInfo(@"Initializing push singleton");
    self.contentList = [[NSMutableArray alloc] init];
    self.handlerList = [[NSMutableArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewNotification:) name:kMonalNewMessageNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(xmppError:) name:kXMPPError object:nil];
    return self;
}

-(void) incomingPush:(void (^)(UNNotificationContent* _Nonnull)) contentHandler
{
    @synchronized(self) {
        DDLogInfo(@"Handling incoming push");
        BOOL first = NO;
        if(![self.contentList count])
        {
            DDLogInfo(@"First incoming push, locking process and connecting accounts");
            self.idleAccounts = [[NSMutableSet alloc] init];
            [MLProcessLock lock];
            first = YES;
        }
        
        //add contentHandler to our list
        DDLogVerbose(@"Adding content handler to list");
        [self.handlerList addObject:contentHandler];
        
        if([MLProcessLock checkRemoteRunning:@"MainApp"])
        {
            DDLogInfo(@"NOT calling MLXMPPManager, main app already running, posting *all* waiting dummy notifications instead");
            [DDLog flushLog];
            [self postAllPendingNotifications];
            return;
        }
        else if(first)      //first incoming push --> connect to servers
        {
            DDLogVerbose(@"calling MLXMPPManager");
            [DDLog flushLog];
            [[MLXMPPManager sharedInstance] connectIfNecessary];
            DDLogVerbose(@"MLXMPPManager called");
            [DDLog flushLog];
            
            /*//disconnect all accounts immediately if main app gets started
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [MLProcessLock waitForRemoteStartup:@"MainApp"];
                DDLogWarn(@"Main app is now running, disconnecting all accounts and (hopefully) terminate this extension as soon as possible");
                //disconnected accounts are idle and this extension will be terminated if all accounts are idle in [self nowIdle:]
                [[MLXMPPManager sharedInstance] disconnectAll];
            });*/
        }
        else
            ;       //do nothing if not the first call (MLXMPPManager is already connecting)
    }
}

-(void) pushExpired
{
    @synchronized(self) {
        DDLogInfo(@"Handling expired push");
        //post a single notification using the next handler (that must have been the expired one because handlers expire in order)
        if([self.handlerList count]>1)
            [self postNextNotification];        //this could be a dummy if we did not receive anything via xmpp yet
        else
        {
            //the last handler expired, post all pending notifications
            [self postAllPendingNotifications];
        }
    }
}

-(void) handleNewNotification:(NSNotification*) notification
{
    UNMutableNotificationContent* content = notification.object;
    @synchronized(self) {
        DDLogVerbose(@"Adding notification content to list: %@", content.body);
        [self.contentList addObject:content];
    }
}

-(void) postAllPendingNotifications
{
    //repeated calls to this method will do nothing (every handler will already be used and every content will already be posted)
    @synchronized(self) {
        DDLogInfo(@"Disconnecting all accounts and posting all pending notifications");
        [[MLXMPPManager sharedInstance] disconnectAll];
        
        //for debugging
        [self listNotifications];
        
        //use all pending handlers (except the last one)
        while([self.handlerList count]>1)
            [self postNextNotification];
        
        //post all notifications not having a handler (all pending ones except the last one)
        UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
        while([self.contentList count]>1)
        {
            UNMutableNotificationContent* content = [self.contentList firstObject];
            [self.contentList removeObject:content];
            UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:content trigger:nil];
            [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {}];
        }
        
        //post the last one using the last push handler (if one is left)
        if([self.handlerList count])
            [self postNextNotification];
        
        //we posted all notifications and disconnected, technically we're not running anymore
        //(even though our containing process will still be running for a few more seconds)
        [MLProcessLock unlock];
    }
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

-(void) postNextNotification
{
    //this method should only be called if we have at least one content handler waiting
    DDLogInfo(@"Posting next notification");
    
    //get notification content we want to push
    UNMutableNotificationContent* __block content;
    if([self.contentList count])
    {
        content = [self.contentList firstObject];
        [self.contentList removeObject:content];
        //THIS SQL QUERY HAS TO BE SYNCRONOUS
        [self addBadgeTo:content withCompletion:^{
            void (^handler)(UNNotificationContent* contentToDeliver) = [self.handlerList firstObject];
            [self.handlerList removeObject:handler];
            handler(content);
        }];
    }
    else
    {
        //TODO: echtes handling wieder einkommentieren
        [self postNextDummyNotification];
        /*
        //If this Notification Service Extension run did not yield enough notifications, we have to go another route to be user friendly,
        //because we could have received more apns pushes than xmpp messages waiting (or we have bad network connectivity making it impossible
        //to retrieve all xmpp messages in time)
        //We thus implement another approach: use the last displayed notification, delete it and replace it by calling contentHandler() with the original
        //content of the notification (cloned by [request.content mutableCopy] or [notification.request.content mutableCopy]).
        //As Last resort (if no notifications are already displayed), we just display a dummy notification to make the user open the app
        //to retrieve the actual message.
        //Important:
        //In the "xmpp account has error" case an error notification will be displayed to the user to alert her that something is wrong
        //and afterwards this method will be called (silencing the possibly waiting dummy notification).
        
        //try to find an unpublished notification request we can replace
        DDLogVerbose(@"try to find an unpublished notification request we can replace");
        [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
            for(UNNotificationRequest* request in requests)
            {
                content = [request.content mutableCopy];
                DDLogVerbose(@"postNextNotification: replacing pending notification %@ --> %@: %@", request.identifier, request.content.title, request.content.body);
                [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[request.identifier]];
                break;
            }
            if(content)
                [self addBadgeTo:content withCompletion:^{
                    [self callDelayedContentHandler:content];
                }];
            else
            {
                //we could not find such an unpublished notification request --> retry with already published ones
                DDLogVerbose(@"we could not find such an unpublished notification request --> retry with already published ones");
                [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
                    for(UNNotification* notification in notifications)
                    {
                        content = [notification.request.content mutableCopy];
                        DDLogVerbose(@"postNextNotification: replacing delivered notification %@ --> %@: %@", notification.request.identifier, notification.request.content.title, notification.request.content.body);
                        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[notification.request.identifier]];
                        break;
                    }
                    if(content)
                        [self addBadgeTo:content withCompletion:^{
                            [self callDelayedContentHandler:content];
                        }];
                    else
                    {
                        DDLogInfo(@"Could not find any notification to replace, posting dummy notification instead");
                        [self postNextDummyNotification];       //we could not even find a published one --> just publish the dummy notification
                    }
                }];
            }
        }];
        */
    }
}

-(void) callDelayedContentHandler:(UNMutableNotificationContent*) content
{
    //use this to make sure that the async removeDeliveredNotificationsWithIdentifiers: call succeeded before contentHandler is called
    dispatch_async(dispatch_get_main_queue(), ^{
        usleep(50000);
        @synchronized(self) {
            void (^handler)(UNNotificationContent* contentToDeliver) = [self.handlerList firstObject];
            [self.handlerList removeObject:handler];
            handler(content);
        }
    });
}

-(void) postNextDummyNotification
{
    //dont use the badge counter from db here (we did not receive any message, let this notification automatically increase the badge by one)
    //create dummy notification used when no real message can be found
    UNMutableNotificationContent* dummyContent = [[UNMutableNotificationContent alloc] init];
    dummyContent.title = NSLocalizedString(@"New Message", @"");
    dummyContent.body = NSLocalizedString(@"Open app to view", @"");
    if([[HelperTools defaultsDB] boolForKey:@"Sound"])
    {
        NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
        if(filename)
            dummyContent.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif",filename]];
        else
            dummyContent.sound = [UNNotificationSound defaultSound];
    }
    
    //this will add a badge having a minimum of 1 to make sure people see that something happened (even after swiping away all notifications)
    [self addBadgeTo:dummyContent withCompletion:^{
        @synchronized(self) {
            DDLogInfo(@"Posting dummy notification");
            void (^handler)(UNNotificationContent* contentToDeliver) = [self.handlerList firstObject];
            [self.handlerList removeObject:handler];
            handler(dummyContent);
        }
    }];
}

-(void) addBadgeTo:(UNMutableNotificationContent*) content withCompletion:(monal_void_block_t) completion
{
    //this will add a badge having a minimum of 1 to make sure people see that something happened (even after swiping away all notifications)
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber *result) {
        NSInteger unread = 0;
        if(result)
            unread = [result integerValue];
        DDLogVerbose(@"Raw badge value: %lu", (long)unread);
        if(!unread)
            unread = 1;     //use this as fallback to always show a badge if a notification is shown
        DDLogInfo(@"Adding badge value: %lu", (long)unread);
        content.badge = [NSNumber numberWithInteger:unread];
        completion();
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
        DDLogInfo(@"notification handler: all accounts idle --> publishing all pending notifications");
        [self postAllPendingNotifications];
    }
}

-(void) xmppError:(NSNotification*) notification
{
    DDLogInfo(@"notification handler: got xmpp error");
    //dispatch in another thread to avoid blocking the thread posting this notification (most probably the receiveQueue)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //display an error notification and disconnect this account, leaving the extension running until all accounts are idle
        //(disconnected accounts count as idle)
        //if no account receives any messages, a dummy notification will be displayed, too.
        DDLogInfo(@"notification handler: account error --> publishing this as error notifications and disconnecting this account");
        //extract error contents and disconnect the account
        NSArray* payload = [notification.object copy];
        NSString* message = payload[1];
        xmpp* xmppAccount = payload.firstObject;
        DDLogVerbose(@"error(%@): %@", xmppAccount.connectionProperties.identity.jid, message);
        //this will result in an idle notification for this account ultimately leading to a dummy push notification
        //(or a push notification for a real message coming from another account if we are in a multi account scenario)
        [xmppAccount disconnect];
        
        //display error notification
        NSString* idval = xmppAccount.connectionProperties.identity.jid;        //use this to only show one error notification per account
        UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
        content.title = xmppAccount.connectionProperties.identity.jid;
        content.body = message;
        content.sound = [UNNotificationSound defaultSound];
        UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
        UNNotificationRequest* new_request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:nil];
        [center addNotificationRequest:new_request withCompletionHandler:^(NSError * _Nullable error) { }];
    });
}

@end

@interface NotificationService ()
@end

@implementation NotificationService

+(void) initialize
{
    [HelperTools configureLogging];
    
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
    [[Push instance] incomingPush:contentHandler];
}

-(void) serviceExtensionTimeWillExpire
{
    DDLogInfo(@"notification handler expired");
    [DDLog flushLog];
    
    //proxy to push singleton
    [[Push instance] pushExpired];
}

@end
