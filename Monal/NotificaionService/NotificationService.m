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
    DDLogError(@"*** CRASH: %@", exception);
    [DDLog flushLog];
    DDLogError(@"*** Stack Trace: %@", [exception callStackSymbols]);
    [DDLog flushLog];
}

@interface NotificationService ()

@property (atomic, strong) void (^contentHandler)(UNNotificationContent* contentToDeliver);
@property (atomic, strong) UNMutableNotificationContent* bestAttemptContent;
@property (atomic, strong) NSMutableSet* idleAccounts;

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
    self = [super init];
    [MLProcessLock lock];
    return self;
}
-(void) dealloc
{
    DDLogInfo(@"Deallocating notification service extension");
    [DDLog flushLog];
    [self publishLastNotification];      //make sure nothing is left behind
    [MLProcessLock unlock];
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
    //for debugging
    [self listNotifications];
    
    //Use the last notification created by MLNotificationManager (the last one is unpublished) and publish it using our contentHandler()
    UNMutableNotificationContent* lastNotification = [MLNotificationManager sharedInstance].lastNotification;
    if(lastNotification)
    {
        DDLogVerbose(@"Using last notification from MLNotificationManager: %@", lastNotification.body);
        [MLNotificationManager sharedInstance].lastNotification = nil;      //just to make sure
        [self addBadgeTo:lastNotification withCompletion:^{
            [self callContentHandler:lastNotification];
        }];
        return;
    }
    
    //If this Notification Service Extension run did not yield new notifications, we have to go another route to be user friendly because
    //of the following quirk in apple's implementation of the extension:
    //If multiple push notifications are queued this extension's didReceiveNotificationRequest:withContentHandler: is only called for the
    //next push, if the previous one got delivered (by calling contentHandler()).
    //This makes it impossible for those following pushes (e.g. pushes that have been queued already because they got received by the device
    //with only a few seconds between them [and before this extension had a chance to connect to the xmpp server to receive the actual content])
    //to use the actual content when calling the contentHandler(), because those content was already fetched and displayed by the previous push.
    //We thus implement another approach: use the last displayed notification, delete it and replace it by calling contentHandler() with the original
    //content of the notification (cloned by [request.content mutableCopy] or [notification.request.content mutableCopy]).
    //As Last resort (if no notifications are already displayed and this push didn't receive any content from the server, too, we just display
    //a dummy notification to make the user open the app to retrieve the actual message.
    //Important:
    //In the "bad network connectivity" case or the "xmpp account has error" case an error notification will be displayed to the user
    //to alert her that something is wrong and afterwards this method will be called (silencing the possibly waiting dummy notification).
    //In the "no network connectivity case" a dummy notification will be displayed to alert the user that something is waiting for her
    //and this method will *not* be called.
    UNMutableNotificationContent* __block copy;
    
    //try to find an unpublished notification request we can replace
    DDLogVerbose(@"try to find an unpublished notification request we can replace");
    [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray* requests) {
        for(UNNotificationRequest* request in requests)
        {
            copy = [request.content mutableCopy];
            DDLogVerbose(@"postNotification: replacing pending notification %@ --> %@: %@", request.identifier, request.content.title, request.content.body);
            [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[request.identifier]];
            break;
        }
        if(copy)
            [self addBadgeTo:copy withCompletion:^{
                [self callContentHandler:copy];
            }];
        else
        {
            //we could not find such an unpublished notification request --> retry with already published ones
            DDLogVerbose(@"we could not find such an unpublished notification request --> retry with already published ones");
            [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray* notifications) {
                for(UNNotification* notification in notifications)
                {
                    copy = [notification.request.content mutableCopy];
                    DDLogVerbose(@"postNotification: replacing delivered notification %@ --> %@: %@", notification.request.identifier, notification.request.content.title, notification.request.content.body);
                    [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[notification.request.identifier]];
                    break;
                }
                if(copy)
                    [self addBadgeTo:copy withCompletion:^{
                        [self callContentHandler:copy];
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

-(void) callContentHandler:(UNMutableNotificationContent*) content
{
    //check if notification was already posted (we don't want to post multiple notifications when multiple accounts simultaneously go idle
    if(!self.bestAttemptContent)
        return;
    //use this to make sure that the async removeDeliveredNotificationsWithIdentifiers: call succeeded before contentHandler is called
    dispatch_async(dispatch_get_main_queue(), ^{
        usleep(100000);
        self.contentHandler(content);
        self.bestAttemptContent = nil;
    });
}

-(void) postDummyNotification
{
    //check if notification was already posted (we don't want to post multiple notifications when multiple accounts simultaneously go idle
    if(!self.bestAttemptContent)
        return;
    [self publishLastNotification];      //make sure nothing is left behind
    
    DDLogInfo(@"Posting dummy notification");
    //dont use the badge counter from db here (we did not receive any message, let this notification automatically increase the badge by one)
    self.contentHandler(self.bestAttemptContent);
    self.bestAttemptContent = nil;
}

-(void) publishLastNotification
{
    //make sure no pending notification is left behind
    UNMutableNotificationContent* lastNotification = [MLNotificationManager sharedInstance].lastNotification;
    if(lastNotification)
    {
        DDLogVerbose(@"Publishing last MLNotificationManager notification accidentally left behind: %@", lastNotification.body);
        [self addBadgeTo:lastNotification withCompletion:^{
            [[MLNotificationManager sharedInstance] publishLastNotification];
        }];
    }
}

-(void) addBadgeTo:(UNMutableNotificationContent*) content withCompletion:(monal_void_block_t) completion
{
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber *result) {
        NSInteger unread = 0;
        if(result)
            unread = [result integerValue];
        DDLogVerbose(@"Adding badge value: %lu", (long)unread);
        content.badge = [NSNumber numberWithInteger:unread];
        completion();
    }];
}

-(void) didReceiveNotificationRequest:(UNNotificationRequest*) request withContentHandler:(void (^)(UNNotificationContent* _Nonnull)) contentHandler
{
    DDLogInfo(@"Notification handler called (request id: %@)", request.identifier);
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
        DDLogInfo(@"defaults not migrated to app group, ignoring push and posting dummy notification");
        [self postDummyNotification];
        return;
    }
    
    //just "ignore" this push if the main app is already running
    if([MLProcessLock checkRemoteRunning:@"MainApp"])
    {
        DDLogInfo(@"main app already running, ignoring push and posting dummy notification");
        [self postDummyNotification];
        return;
    }
    
    if(![[MLXMPPManager sharedInstance] hasConnectivity])
    {
        DDLogInfo(@"no connectivity, just posting dummy notification.");
        return;
    }
    
    if([MLProcessLock checkRemoteRunning:@"MainApp"])
    {
        DDLogInfo(@"NOT calling MLXMPPManager, main app already running");
        [DDLog flushLog];
        [self postDummyNotification];
        return;
    }
    else
    {
        DDLogVerbose(@"calling MLXMPPManager");
        [DDLog flushLog];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(xmppError:) name:kXMPPError object:nil];
        [[MLXMPPManager sharedInstance] connectIfNecessary];
        DDLogVerbose(@"MLXMPPManager called");
        [DDLog flushLog];
        
        //disconnect all accounts immediately if main app gets started
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [MLProcessLock waitForRemoteStartup:@"MainApp"];
            DDLogWarn(@"Main app is now running, disconnecting all accounts and (hopefully) terminate this extension as soon as possible");
            //disconnected accounts are idle and this extension will be terminated if all accounts are idle in [self nowIdle:]
            [[MLXMPPManager sharedInstance] disconnectAll];
        });
    }
}

-(void) serviceExtensionTimeWillExpire
{
    DDLogInfo(@"notification handler expired");
    [DDLog flushLog];
    //we did not receive *everything* --> display dummy notification to alert the user about this condition
    [[MLXMPPManager sharedInstance] disconnectAll];
    [self postDummyNotification];
}

-(void) nowIdle:(NSNotification*) notification
{
    //this method will be called inside the receive queue or send queue and immediately disconnect the account
    //this is needed to not leak incoming stanzas while this class is being destructed
    xmpp* xmppAccount = (xmpp*)notification.object;
    
    //ignore repeated idle notifications for already idle accounts
    if([self.idleAccounts containsObject:xmppAccount])
        return;
    [self.idleAccounts addObject:xmppAccount];
    
    DDLogInfo(@"notification handler: some account idle: %@", xmppAccount.connectionProperties.identity.jid);
    [xmppAccount disconnect];
    
    if([[MLXMPPManager sharedInstance] allAccountsIdle])
    {
        DDLogInfo(@"notification handler: all accounts idle --> publishing notification and stopping extension");
        [[MLXMPPManager sharedInstance] disconnectAll];
        [self postNotification];
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
        //this will result in an idle notification ultimately leading to a dummy notification
        //(or a notification from another account in multi account scenarios)
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
