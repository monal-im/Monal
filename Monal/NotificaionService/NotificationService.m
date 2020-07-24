//
//  NotificationService.m
//  NotificaionService
//
//  Created by Anurodh Pokharel on 9/16/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "NotificationService.h"
#import "MLConstants.h"
#import "MLXMPPManager.h"

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;

@end

static void logException(NSException* exception)
{
    [DDLog flushLog];
    DDLogError(@"*** CRASH: %@", exception);
    [DDLog flushLog];
    DDLogError(@"*** Stack Trace: %@", [exception callStackSymbols]);
    [DDLog flushLog];
}

@implementation NotificationService

+(void) initialize
{
    DDDispatchQueueLogFormatter* formatter = [[DDDispatchQueueLogFormatter alloc] init];
    [[DDOSLogger sharedInstance] setLogFormatter:formatter];
    [DDLog addLogger:[DDOSLogger sharedInstance]];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    id<DDLogFileManager> logFileManager = [[MLLogFileManager alloc] initWithLogsDirectory:[containerUrl path]];
    DDFileLogger* fileLogger = [[DDFileLogger alloc] initWithLogFileManager:logFileManager];
    [fileLogger setLogFormatter:formatter];
    fileLogger.rollingFrequency = 60 * 60 * 24;    // 24 hour rolling
    fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    fileLogger.maximumFileSize=1024 * 1024 * 64;
    [DDLog addLogger:fileLogger];
    DDLogInfo(@"*-* Logfile dir: %@", [containerUrl path]);
    
    //log unhandled exceptions
    NSSetUncaughtExceptionHandler(&logException);
    
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    NSString* buildDate = [NSString stringWithUTF8String:__DATE__];
    NSString* buildTime = [NSString stringWithUTF8String:__TIME__];
    DDLogInfo(@"*-* Notification Service Extension started: %@", [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@ %@ UTC)", @ ""), version, buildDate, buildTime]);
}

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {
    DDLogInfo(@"*-* notification handler called");
    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    
    // Modify the notification content here...
    self.bestAttemptContent.title = @"New Message";
    self.bestAttemptContent.body = @"Open app to view";
    self.bestAttemptContent.badge = @1;
    
    //just "ignore" this push if we have not migrated our defaults db already (this needs a normal app start to happen)
    if(![DEFAULTS_DB boolForKey:@"DefaulsMigratedToAppGroup"])
    {
        DDLogInfo(@"*-* defaults not migrated to app group, ignoring push");
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
        DDLogInfo(@"*-* second notification request completed: %@", error);
    }];
    
    DDLogInfo(@"*-* waiting before calling MLXMPPManager");
    [DDLog flushLog];
    [NSThread sleepForTimeInterval:4.000];
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    DDLogInfo(@"*-* MLXMPPManager called");
    [DDLog flushLog];
}

- (void)serviceExtensionTimeWillExpire {
    DDLogInfo(@"*-* notification handler expired");
    // Called just before the extension will be terminated by the system.
    // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
    self.contentHandler(self.bestAttemptContent);
    [DDLog flushLog];
}

@end
