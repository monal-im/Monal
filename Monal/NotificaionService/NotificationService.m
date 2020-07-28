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

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent* contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent* bestAttemptContent;

@end

@implementation NotificationService

+(void) initialize
{
    [HelperTools configureLogging];
    
    //log unhandled exceptions
    NSSetUncaughtExceptionHandler(&logException);
    
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
    [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[@"remote-push"]];
    [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[@"remote-push"]];
    DDLogInfo(@"cleared dummy notifications");
    [DDLog flushLog];
    [NSThread sleepForTimeInterval:1.000];
    DDLogInfo(@"now leaving dealloc");
    [DDLog flushLog];
}

- (void)didReceiveNotificationRequest:(UNNotificationRequest*) request withContentHandler:(void (^)(UNNotificationContent* _Nonnull)) contentHandler
{
    DDLogInfo(@"notification handler called (ID=%@)", request.identifier);
    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    
    // Modify the notification content here...
    self.bestAttemptContent.title = @"New Message";
    self.bestAttemptContent.body = @"Open app to view";
    self.bestAttemptContent.badge = @1;
    
    //just "ignore" this push if we have not migrated our defaults db already (this needs a normal app start to happen)
    if(![DEFAULTS_DB boolForKey:@"DefaulsMigratedToAppGroup"])
    {
        DDLogInfo(@"defaults not migrated to app group, ignoring push");
        self.contentHandler(self.bestAttemptContent);
        return;
    }
    
    //just "ignore" this push if the main app is already running
    if([MLProcessLock checkRemoteRunning:@"MainApp"])
    {
        DDLogInfo(@"main app already running, ignoring push");
        self.contentHandler(self.bestAttemptContent);
        return;
    }
    
    NSString* idval = [[NSUUID UUID] UUIDString];
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
    //self.contentHandler(self.bestAttemptContent);
    //TODO: use getDeliveredNotificationsWithCompletionHandler: and removeDeliveredNotificationsWithIdentifiers:
    //TODO: to remove old notifications and use their contents for this push, if no messages are pending on the xmpp channel
    DDLogInfo(@"MLXMPPManager called");
    [DDLog flushLog];
}

- (void)serviceExtensionTimeWillExpire
{
    DDLogInfo(@"notification handler expired");
    // Called just before the extension will be terminated by the system.
    // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
    self.contentHandler(self.bestAttemptContent);
    [DDLog flushLog];
}

-(void) nowIdle:(NSNotification*) notification
{
    DDLogInfo(@"notification handler: some account idle");
    //dispatch in another thread to avoid blocking the thread posting this notification (most probably the receiveQueue)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if([[MLXMPPManager sharedInstance] allAccountsIdle])
        {
            DDLogInfo(@"notification handler: all accounts idle --> publishing notification and stopping extension");
            self.contentHandler(self.bestAttemptContent);
            [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[@"remote-push"]];
            [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[@"remote-push"]];
            [DDLog flushLog];
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
            DDLogInfo(@"notification handler: all accounts idle --> publishing notification and stopping extension");
            self.contentHandler(self.bestAttemptContent);
            [DDLog flushLog];
        }
    });
}

@end
