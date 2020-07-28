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
#import "MLProcessLock.h"
#import "MLXMPPManager.h"
#import "MLNotificationManager.h"

static void logException(NSException* exception)
{
    [DDLog flushLog];
    DDLogError(@"*** CRASH: %@", exception);
    [DDLog flushLog];
    DDLogError(@"*** Stack Trace: %@", [exception callStackSymbols]);
    [DDLog flushLog];
}

@interface NotificationService ()

@property (atomic, strong) void (^contentHandler)(UNNotificationContent* contentToDeliver);
@property (atomic, strong) UNMutableNotificationContent* bestAttemptContent;
@property (atomic, strong) UNNotificationRequest* notificationRequest;

@end

@implementation NotificationService

+(void) initialize
{
    [HelperTools configureLogging];
    
    //log unhandled exceptions
    NSSetUncaughtExceptionHandler(&logException);
    
    [HelperTools activityLog];
    
    //init process lock
    [[MLProcessLock alloc] initWithProcessName:@"NotificationServiceExtension"];
    
    //disconnect all accounts immediately if main app gets started
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [MLProcessLock waitForRemoteStartup:@"MainApp"];
        DDLogWarn(@"Main app is now running, disconnecting all accounts and (hopefully) terminate this extension as soon as possible");
        //disconnected accounts are idle and this extension will be terminated if all accounts are idle in [self nowIdle:]
        [[MLXMPPManager sharedInstance] disconnectAll];
    });
    
    //handle message notifications by initializing the MLNotificationManager
    [MLNotificationManager sharedInstance];
    
    //log startup
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    NSString* buildDate = [NSString stringWithUTF8String:__DATE__];
    NSString* buildTime = [NSString stringWithUTF8String:__TIME__];
    DDLogInfo(@"Notification Service Extension started: %@", [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@ %@ UTC)", @ ""), version, buildDate, buildTime]);
}

-(void) dealloc
{
    DDLogInfo(@"Deallocating notification service extension");
    [DDLog flushLog];
    [self listNotifications];
    DDLogInfo(@"Now leaving dealloc");
    [DDLog flushLog];
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

-(void) postNotification
{
    UNMutableNotificationContent* __block copy;
    //try to find an unpublished notification request we can replace
    [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
        for(UNNotificationRequest* request in requests)
        {
            copy = [request.content mutableCopy];
            DDLogInfo(@"postNotification: replacing pending notification %@ --> %@: %@", request.identifier, request.content.title, request.content.body);
            [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[request.identifier]];
            break;
        }
        if(copy)
            [self addBadgeTo:copy withCompletion:^{
                //use this to make sure that the async removePendingNotificationRequestsWithIdentifiers: call succeeded before contentHandler is called
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.contentHandler(copy);
                });
            }];
        else
        {
            //we could not find such an unpublished notification request --> retry with already published ones
            [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
                for(UNNotification* notification in notifications)
                {
                    copy = [notification.request.content mutableCopy];
                    DDLogInfo(@"postNotification: replacing delivered notification %@ --> %@: %@", notification.request.identifier, notification.request.content.title, notification.request.content.body);
                    [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[notification.request.identifier]];
                    break;
                }
                if(copy)
                    [self addBadgeTo:copy withCompletion:^{
                        //use this to make sure that the async removeDeliveredNotificationsWithIdentifiers: call succeeded before contentHandler is called
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.contentHandler(copy);
                        });
                    }];
                else
                {
                    DDLogInfo(@"Could not find any notification to replace, posting dummy notification instead");
                    [self postDummyNotification];       //we could not even find a published one --> just publish the dummy notification
                }
            }];
        }
    }];
}

-(void) addBadgeTo:(UNMutableNotificationContent*) content withCompletion:(monal_void_block_t) completion
{
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber *result) {
        NSInteger unread = 0;
        if(result)
            unread = [result integerValue];
        content.badge = [NSNumber numberWithInteger:unread];
        DDLogVerbose(@"Adding badge value: %lu", (long)unread);
        completion();
    }];
}

-(void) postDummyNotification
{
    [self addBadgeTo:self.bestAttemptContent withCompletion:^{
        DDLogInfo(@"Posting dummy notification");
        self.contentHandler(self.bestAttemptContent);
    }];
}

- (void)didReceiveNotificationRequest:(UNNotificationRequest*) request withContentHandler:(void (^)(UNNotificationContent* _Nonnull)) contentHandler
{
    DDLogInfo(@"Notification handler called (request id: %@)", request.identifier);
    self.notificationRequest = request;
    self.contentHandler = contentHandler;
    
    //create dummy notification used when no real message can be found
    self.bestAttemptContent = [[UNMutableNotificationContent alloc] init];  //[request.content mutableCopy];
    self.bestAttemptContent.title = NSLocalizedString(@"New Message", @"");
    self.bestAttemptContent.body = NSLocalizedString(@"Open app to view", @"");
    self.bestAttemptContent.badge = @1;
    if([[HelperTools defaultsDB] boolForKey:@"Sound"])
    {
        NSString* filename = [[HelperTools defaultsDB] objectForKey:@"AlertSoundFile"];
        if(filename)
            self.bestAttemptContent.sound = [UNNotificationSound soundNamed:[NSString stringWithFormat:@"AlertSounds/%@.aif",filename]];
        else
            self.bestAttemptContent.sound = [UNNotificationSound defaultSound];
    }
    
    //just "ignore" this push if we have not migrated our defaults db already (this needs a normal app start to happen)
    if(![[HelperTools defaultsDB] boolForKey:@"DefaulsMigratedToAppGroup"])
    {
        DDLogInfo(@"defaults not migrated to app group, ignoring push");
        [self postDummyNotification];
        return;
    }
    
    //just "ignore" this push if the main app is already running
    if([MLProcessLock checkRemoteRunning:@"MainApp"])
    {
        DDLogInfo(@"main app already running, ignoring push");
        [self postNotification];
        return;
    }
    
    NSString* idval = [NSString stringWithFormat:@"%@_%@", @"thirty_seconds_notification", [[NSUUID UUID] UUIDString]];
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Notification incoming";
    content.body = @"Please wait 30 seconds to see it...";
    content.sound = [UNNotificationSound defaultSound];
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNNotificationRequest* new_request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:nil];
    [center addNotificationRequest:new_request withCompletionHandler:^(NSError * _Nullable error) {
        DDLogInfo(@"second notification request completed: %@", error);
    }];
    
    DDLogInfo(@"calling MLXMPPManager");
    [DDLog flushLog];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(xmppError:) name:kXMPPError object:nil];
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    DDLogInfo(@"MLXMPPManager called");
    [DDLog flushLog];
}

- (void)serviceExtensionTimeWillExpire
{
    DDLogInfo(@"notification handler expired");
    [DDLog flushLog];
    [self postDummyNotification];
}

-(void) nowIdle:(NSNotification*) notification
{
    DDLogInfo(@"notification handler: some account idle");
    //dispatch in another thread to avoid blocking the thread posting this notification (most probably the receiveQueue)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if([[MLXMPPManager sharedInstance] allAccountsIdle])
        {
            DDLogInfo(@"notification handler: all accounts idle --> publishing notification and stopping extension");
            [self listNotifications];
            [self postNotification];
        }
    });
}

-(void) xmppError:(NSNotification*) notification
{
    DDLogInfo(@"notification handler: got xmpp error");
    //dispatch in another thread to avoid blocking the thread posting this notification (most probably the receiveQueue)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if([[MLXMPPManager sharedInstance] allAccountsIdle])
        {
            DDLogInfo(@"notification handler: account error --> publishing DUMMY notification and stopping extension");
            [self listNotifications];
            [self postDummyNotification];
            [DDLog flushLog];
        }
    });
}

@end
