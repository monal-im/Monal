//
//  NotificationService.m
//  NotificaionService
//
//  Created by Anurodh Pokharel on 9/16/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "NotificationService.h"
@import CocoaLumberjack;
#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
static const DDLogLevel ddLogLevel = DDLogLevelInfo;
#endif

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;

@end

@implementation NotificationService

+(void) initialize
{
    [DDLog addLogger:[DDOSLogger sharedInstance]];
    
    DDLogInfo(@"*~*~*~*~*~*~*~*~* notification handler INIT");
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:@"group.monal"];
    id<DDLogFileManager> logFileManager = [[DDLogFileManagerDefault alloc] initWithLogsDirectory:[containerUrl path]];
    DDFileLogger* fileLogger = [[DDFileLogger alloc] initWithLogFileManager:logFileManager];
    fileLogger.rollingFrequency = 60 * 60 * 24;    // 24 hour rolling
    fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    fileLogger.maximumFileSize=1024 * 1024 * 64;
    [DDLog addLogger:fileLogger];
    
    DDLogInfo(@"*~*~*~*~*~*~*~*~* Logfile dir: %@", [containerUrl path]);
}

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {
    DDLogInfo(@"*~*~*~*~*~*~*~*~* notification handler called");
    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    
    // Modify the notification content here...
    self.bestAttemptContent.title = @"New Message"; //[NSString stringWithFormat:@"New Message %@", self.bestAttemptContent.title];
    self.bestAttemptContent.body = @"Open app to view";
    self.bestAttemptContent.badge = @1;
    //self.contentHandler(self.bestAttemptContent);
    
    NSString* idval = [[NSUUID UUID] UUIDString];
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Notification incoming";
    content.body = @"Please wait 30 seconds to see it...";
    content.sound = [UNNotificationSound defaultSound];
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNNotificationRequest* new_request = [UNNotificationRequest requestWithIdentifier:idval content:content trigger:nil];
    [center addNotificationRequest:new_request withCompletionHandler:^(NSError * _Nullable error) {
        DDLogInfo(@"*~*~*~*~*~*~*~*~* second notification request completed: %@", error);
    }];
}

- (void)serviceExtensionTimeWillExpire {
    DDLogInfo(@"*~*~*~*~*~*~*~*~* notification handler expired");
    // Called just before the extension will be terminated by the system.
    // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
    self.contentHandler(self.bestAttemptContent);
}

@end
