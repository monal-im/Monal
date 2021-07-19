//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import <BackgroundTasks/BackgroundTasks.h>

#import "MonalAppDelegate.h"
#import "CallViewController.h"
#import "MLConstants.h"
#import "HelperTools.h"
#import "MLNotificationManager.h"
#import "DataLayer.h"
#import "MLImageManager.h"
#import "ActiveChatsViewController.h"
#import "IPC.h"
#import "MLProcessLock.h"
#import "MLFiletransfer.h"
#import "xmpp.h"
#import "MLNotificationQueue.h"
#import "MLSettingsAboutViewController.h"

@import NotificationBannerSwift;

#import "MLXMPPManager.h"
#import "UIColor+Theme.h"

#import <AVKit/AVKit.h>

#define GRACEFUL_TIMEOUT 20.0

typedef void (^pushCompletion)(UIBackgroundFetchResult result);
static NSString* kBackgroundFetchingTask = @"im.monal.fetch";

@interface MonalAppDelegate()
{
    NSMutableDictionary* _wakeupCompletions;
    UIBackgroundTaskIdentifier _bgTask;
    API_AVAILABLE(ios(13.0)) BGTask* _bgFetch;
    monal_void_block_t _backgroundTimer;
}
@property (nonatomic, weak) ActiveChatsViewController* activeChats;
@end

@implementation MonalAppDelegate

-(id) init
{
    self = [super init];
    _bgTask = UIBackgroundTaskInvalid;
    _wakeupCompletions = [[NSMutableDictionary alloc] init];
    return self;
}

#pragma mark -  APNS notificaion

-(void) application:(UIApplication*) application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*) deviceToken
{
    NSString* token = [HelperTools stringFromToken:deviceToken];
    DDLogInfo(@"APNS token string: %@", token);
    [[MLXMPPManager sharedInstance] setPushToken:token];
}

-(void) application:(UIApplication*) application didFailToRegisterForRemoteNotificationsWithError:(NSError*) error
{
    DDLogError(@"push reg error %@", error);
}

#pragma mark - VOIP notification

#if !TARGET_OS_MACCATALYST

-(void) voipRegistration
{
    PKPushRegistry* voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    voipRegistry.delegate = self;
    voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

// Handle updated APNS tokens
-(void) pushRegistry:(PKPushRegistry*) registry didUpdatePushCredentials:(PKPushCredentials*) credentials forType:(NSString*) type
{
    NSString* token = [HelperTools stringFromToken:credentials.token];
    DDLogInfo(@"APNS voip token string: %@", token);
    [[MLXMPPManager sharedInstance] setPushToken:token];
}

-(void) pushRegistry:(PKPushRegistry*) registry didInvalidatePushTokenForType:(NSString*) type
{
    DDLogInfo(@"didInvalidatePushTokenForType called (and ignored, TODO: disable push on server?)");
}

// Handle incoming pushes
-(void) pushRegistry:(PKPushRegistry*) registry didReceiveIncomingPushWithPayload:(PKPushPayload*) payload forType:(PKPushType) type withCompletionHandler:(void (^)(void)) completion
{
    DDLogInfo(@"incoming voip push notfication: %@", [payload dictionaryPayload]);
    if([UIApplication sharedApplication].applicationState == UIApplicationStateActive)
        return;
    if(@available(iOS 13.0, *))
        DDLogError(@"Voip push shouldnt arrive on ios13.");
    else
        [self incomingWakeupWithCompletionHandler:^(UIBackgroundFetchResult result) {
            completion();
        }];
}

#endif

#pragma mark - notification actions

-(void) showCallScreen:(NSNotification*) userInfo
{
//    dispatch_async(dispatch_get_main_queue(),
//                   ^{
//                       NSDictionary* contact=userInfo.object;
//                       CallViewController *callScreen= [[CallViewController alloc] initWithContact:contact];
//
//
//
//                       [self.tabBarController presentModalViewController:callNav animated:YES];
//                   });
}

-(void) updateUnread
{
    //make sure unread badge matches application badge
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger unread = 0;
        if(unreadMsgCnt)
            unread = [unreadMsgCnt integerValue];
        DDLogInfo(@"Updating unread badge to: %ld", (long)unread);
        [UIApplication sharedApplication].applicationIconBadgeNumber = unread;
    });
}

#pragma mark - app life cycle

-(BOOL) application:(UIApplication*) application willFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    [HelperTools activityLog];
    
    //migrate defaults db to shared app group
    if(![[HelperTools defaultsDB] boolForKey:@"DefaulsMigratedToAppGroup"])
    {
        DDLogInfo(@"Migrating [NSUserDefaults standardUserDefaults] to app group container...");
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"ChatBackgrounds"] forKey:@"ChatBackgrounds"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowGeoLocation"] forKey:@"ShowGeoLocation"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"Sound"] forKey:@"Sound"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"SetDefaults"] forKey:@"SetDefaults"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeenIntro"] forKey:@"HasSeenIntro"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeenLogin"] forKey:@"HasSeenLogin"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowImages"] forKey:@"ShowImages"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasUpgradedPushiOS13"] forKey:@"HasUpgradedPushiOS13"];
        [[HelperTools defaultsDB] setObject:[[NSUserDefaults standardUserDefaults] objectForKey:@"BackgroundImage"] forKey:@"BackgroundImage"];
        [[HelperTools defaultsDB] setObject:[[NSUserDefaults standardUserDefaults] objectForKey:@"AlertSoundFile"] forKey:@"AlertSoundFile"];
        
        [[HelperTools defaultsDB] setBool:YES forKey:@"DefaulsMigratedToAppGroup"];
        [[HelperTools defaultsDB] synchronize];
        DDLogInfo(@"Migration complete and written to disk");
    }
    DDLogInfo(@"App launching with options: %@", launchOptions);
    
    //init IPC and ProcessLock
    [IPC initializeForProcess:@"MainApp"];
    
    //lock process and disconnect an already running NotificationServiceExtension
    [MLProcessLock lock];
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    
    //do MLFiletransfer cleanup tasks (do this in a new thread to parallelize it with our ping to the appex and don't slow down app startup)
    //this will also migrate our old image cache to new MLFiletransfer cache
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [MLFiletransfer doStartupCleanup];
    });
    
    //only proceed with launching if the NotificationServiceExtension is *not* running
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension" withLoopHandler:^{
            [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        }];
    }
    
    return YES;
}

- (BOOL)application:(UIApplication*) application didFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    //this will use the cached values in defaultsDB, if possible
    [[MLXMPPManager sharedInstance] setPushToken:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleBackgroundFetchingTask) name:kScheduleBackgroundFetchingTask object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(filetransfersNowIdle:) name:kMonalFiletransfersIdle object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showConnectionStatus:) name:kXMPPError object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:kMonalUpdateUnread object:nil];
    
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    
    //create notification categories with actions
    UNNotificationAction* replyAction = [UNTextInputNotificationAction
        actionWithIdentifier:@"REPLY_ACTION"
        title:NSLocalizedString(@"Reply", @"")
        options:UNNotificationActionOptionNone
        textInputButtonTitle:NSLocalizedString(@"Send", @"")
        textInputPlaceholder:NSLocalizedString(@"Your answer", @"")
    ];
    UNNotificationAction* markAsReadAction = [UNNotificationAction
        actionWithIdentifier:@"MARK_AS_READ_ACTION"
        title:NSLocalizedString(@"Mark as read", @"")
        options:UNNotificationActionOptionNone
    ];
    UNNotificationCategory* messageCategory;
    UNAuthorizationOptions authOptions = UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionCriticalAlert;
    if(@available(iOS 13.0, *))
    {
        messageCategory = [UNNotificationCategory
            categoryWithIdentifier:@"message"
            actions:@[replyAction, markAsReadAction]
            intentIdentifiers:@[]
            options:UNNotificationCategoryOptionAllowAnnouncement
        ];
        
        //ios 13 has support for UNAuthorizationOptionAnnouncement
        authOptions = authOptions | UNAuthorizationOptionAnnouncement;
    }
    else
    {
        messageCategory = [UNNotificationCategory
            categoryWithIdentifier:@"message"
            actions:@[replyAction, markAsReadAction]
            intentIdentifiers:@[]
            options:UNNotificationCategoryOptionNone
        ];
    }
    //request auth to show notifications and register our notification categories created above
    [center requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError *error) {
        DDLogInfo(@"Got local notification authorization response: granted=%@, error=%@", granted ? @"YES" : @"NO", error);
        
        //activate push
        if(@available(iOS 13.0, *))
        {
            DDLogInfo(@"Registering for APNS...");
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] registerForRemoteNotifications];
            });
        }
        else
        {
#if !TARGET_OS_MACCATALYST
            DDLogInfo(@"Registering for VoIP APNS...");
            [self voipRegistration];
#endif
        }
    }];
    [center setNotificationCategories:[NSSet setWithObjects:messageCategory, nil]];

    if (@available(iOS 13.0, *))
    {
        UINavigationBarAppearance* appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = [UIColor systemBackgroundColor];
        
        [[UINavigationBar appearance] setScrollEdgeAppearance:appearance];
        [[UINavigationBar appearance] setStandardAppearance:appearance];
#if TARGET_OS_MACCATALYST
        self.window.windowScene.titlebar.titleVisibility = UITitlebarTitleVisibilityHidden;
#else
        [[UITabBar appearance] setTintColor:[UIColor monaldarkGreen]];
        [[UINavigationBar appearance] setTintColor:[UIColor monalGreen]];
#endif
    }
    [[UINavigationBar appearance] setPrefersLargeTitles:YES];

    //handle message notifications by initializing the MLNotificationManager
    [MLNotificationManager sharedInstance];
    
    //register BGTask
    if(@available(iOS 13.0, *))
    {
        DDLogInfo(@"calling MonalAppDelegate configureBackgroundFetchingTask");
        [self configureBackgroundFetchingTask];
    }
    // Play audio even if phone is in silent mode
    NSError* audioSessionError;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&audioSessionError];
    if(audioSessionError != nil)
    {
        DDLogWarn(@"Couldn't set AVAudioSession to AVAudioSessionCategoryPlayback: %@", audioSessionError);
    }

    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    NSString* buildDate = [NSString stringWithUTF8String:__DATE__];
    NSString* buildTime = [NSString stringWithUTF8String:__TIME__];
    DDLogInfo(@"App started: %@", [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@ %@ UTC)", @""), version, buildDate, buildTime]);
    
    //init background/foreground status
    //this has to be done here to make sure we have the correct state when he app got started through notification quick actions
    if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
        [[MLXMPPManager sharedInstance] nowBackgrounded];
    else
        [[MLXMPPManager sharedInstance] nowForegrounded];
    
    //should any accounts connect?
    [self connectIfNecessary];
    
    //handle IPC messages (this should be done *after* calling connectIfNecessary to make sure any disconnectAll messages are handled properly
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(incomingIPC:) name:kMonalIncomingIPC object:nil];
    
#if TARGET_OS_MACCATALYST
    //handle catalyst foregrounding/backgrounding of window
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowHandling:) name:@"NSWindowDidResignKeyNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowHandling:) name:@"NSWindowDidBecomeKeyNotification" object:nil];
#endif

    return YES;
}

#if TARGET_OS_MACCATALYST
-(void) windowHandling:(NSNotification*) notification
{
    if([notification.name isEqualToString:@"NSWindowDidResignKeyNotification"])
    {
        DDLogInfo(@"Window lost focus (key window)...");
        [self updateUnread];
        if(NSProcessInfo.processInfo.isLowPowerModeEnabled)
        {
            DDLogInfo(@"LowPoderMode is active: nowBackgrounded to reduce power consumption");
            [self addBackgroundTask];
            [[MLXMPPManager sharedInstance] nowBackgrounded];
            [self checkIfBackgroundTaskIsStillNeeded];
        }
        else
        {
            [[MLXMPPManager sharedInstance] nowNoLongerInFocus];
        }
    }
    else if([notification.name isEqualToString:@"NSWindowDidBecomeKeyNotification"])
    {
        DDLogInfo(@"Window got focus (key window)...");
        [self addBackgroundTask];
        [[MLXMPPManager sharedInstance] nowForegrounded];
    }
}
#endif

-(void) incomingIPC:(NSNotification*) notification
{
    NSDictionary* message = notification.userInfo;
    //another process tells us to disconnect all accounts
    //this could happen if we are connecting (or even connected) in the background and the NotificationServiceExtension got started
    //BUT: only do this if we are in background (we should never receive this if we are foregrounded)
    if([message[@"name"] isEqualToString:@"Monal.disconnectAll"])
    {
        DDLogInfo(@"Got disconnectAll IPC message");
        NSAssert([HelperTools isInBackground]==YES, @"Got 'Monal.disconnectAll' while in foreground. This should NEVER happen!");
        //disconnect all (currently connecting or already connected) accounts
        [[MLXMPPManager sharedInstance] disconnectAll];
    }
    else if([message[@"name"] isEqualToString:@"Monal.connectIfNecessary"])
    {
        DDLogInfo(@"Got connectIfNecessary IPC message");
        //(re)connect all accounts
        [self connectIfNecessary];
    }
}

-(void) applicationDidBecomeActive:(UIApplication*) application
{
    //[UIApplication sharedApplication].applicationIconBadgeNumber=0;
}

-(void) setActiveChatsController: (UIViewController*) activeChats
{
    self.activeChats = (ActiveChatsViewController*)activeChats;
}

#pragma mark - handling urls

/**
 xmpp:romeo@montague.net?message;subject=Test%20Message;body=Here%27s%20a%20test%20message
          or
 xmpp:coven@chat.shakespeare.lit?join;password=cauldronburn
         
 @link https://xmpp.org/extensions/xep-0147.html
 */
-(void) handleURL:(NSURL *) url {
    //TODO just uses fist account. maybe change in the future
    xmpp* account = [[MLXMPPManager sharedInstance].connectedXMPP firstObject];
    if(account) {
        NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSString* mucJid = components.path;
        BOOL isGroup = NO;
        
        for(NSURLQueryItem* item in components.queryItems)
        {
            if([item.name isEqualToString:@"join"])
                isGroup = YES;
        }
        
        if(isGroup)
            [account joinMuc:mucJid];
        
        [[DataLayer sharedInstance] addActiveBuddies:mucJid forAccount:account.accountNo];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            MLContact* contact = [MLContact createContactFromJid:mucJid andAccountNo:account.accountNo];
            [(ActiveChatsViewController*)self.activeChats presentChatWithContact:contact];
            [(ActiveChatsViewController*)self.activeChats refreshDisplay];
        });
    }
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    if([url.scheme isEqualToString:@"xmpp"])        //for xmpp uris
    {
        [self handleURL:url];
        return YES;
    }
    return NO;
}




#pragma mark  - user notifications

-(void) application:(UIApplication*) application didReceiveRemoteNotification:(NSDictionary*) userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result)) completionHandler
{
    DDLogVerbose(@"got didReceiveRemoteNotification: %@", userInfo);
    [self incomingWakeupWithCompletionHandler:completionHandler];
}

- (void)userNotificationCenter:(UNUserNotificationCenter*) center willPresentNotification:(UNNotification*) notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options)) completionHandler;
{
    DDLogInfo(@"userNotificationCenter:willPresentNotification:withCompletionHandler called");
    //show local notifications while the app is open and ignore remote pushes
    if([notification.request.trigger isKindOfClass:[UNPushNotificationTrigger class]]) {
        completionHandler(UNNotificationPresentationOptionNone);
    } else {
        completionHandler(UNNotificationPresentationOptionAlert);
    }
}

-(void) userNotificationCenter:(UNUserNotificationCenter*) center didReceiveNotificationResponse:(UNNotificationResponse*) response withCompletionHandler:(void (^)(void)) completionHandler
{
    if([response.notification.request.content.categoryIdentifier isEqualToString:@"message"])
    {
        DDLogVerbose(@"notification action triggered for %@", response.notification.request.content.userInfo);
        [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        //add our completion handler to handler queue
        [self incomingWakeupWithCompletionHandler:^(UIBackgroundFetchResult result) {
            completionHandler();
        }];
        
        MLContact* fromContact = [MLContact createContactFromJid:response.notification.request.content.userInfo[@"fromContactJid"] andAccountNo:response.notification.request.content.userInfo[@"fromContactAccountId"]];
        NSString* messageId = response.notification.request.content.userInfo[@"messageId"];
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:fromContact.accountId];
        NSAssert(fromContact, @"fromContact should not be nil");
        NSAssert(messageId, @"messageId should not be nil");
        NSAssert(account, @"account should not be nil");
        if([response.actionIdentifier isEqualToString:@"REPLY_ACTION"])
        {
            DDLogInfo(@"REPLY_ACTION triggered...");
            UNTextInputNotificationResponse* textResponse = (UNTextInputNotificationResponse*) response;
            if(!textResponse.userText.length)
            {
                DDLogWarn(@"User tried to send empty text response!");
                return;
            }
            
            //mark messages as read because we are replying
            [[DataLayer sharedInstance] markMessagesAsReadForBuddy:fromContact.contactJid andAccount:fromContact.accountId tillStanzaId:messageId wasOutgoing:NO];
            [self updateUnread];
            
            BOOL encrypted = [[DataLayer sharedInstance] shouldEncryptForJid:fromContact.contactJid andAccountNo:fromContact.accountId];
            [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:textResponse.userText toContact:fromContact isEncrypted:encrypted isUpload:NO withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                DDLogInfo(@"REPLY_ACTION success=%@, messageIdSentObject=%@", successSendObject ? @"YES" : @"NO", messageIdSentObject);
            }];
        }
        else if([response.actionIdentifier isEqualToString:@"MARK_AS_READ_ACTION"])
        {
            DDLogInfo(@"MARK_AS_READ_ACTION triggered...");
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:fromContact.contactJid andAccount:fromContact.accountId tillStanzaId:messageId wasOutgoing:NO];
            DDLogDebug(@"Marked as read: %@", unread);
            
            //remove notifications of all remotely read messages (indicated by sending a response message)
            for(MLMessage* msg in unread)
            {
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessageNotice object:account userInfo:@{@"message":msg}];
                [account sendDisplayMarkerForMessage:msg];
            }
            
            //update unread count in active chats list
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": fromContact
            }];
            
            [self updateUnread];
        }
    }
    else
    {
        //all completion handler directly (we did not handle anything and no connectIfNecessary was called)
        if(completionHandler)
            completionHandler();
    }
}



#pragma mark - memory
-(void) applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    [[MLImageManager sharedInstance] purgeCache];
}

#pragma mark - backgrounding

-(void) startBackgroundTimer
{
    //cancel old background timer if still running and start a new one
    //this timer will fire after GRACEFUL_TIMEOUT seconds in background and disconnect gracefully (e.g. when fully idle the next time)
    if(_backgroundTimer)
        _backgroundTimer();
    _backgroundTimer = createTimer(GRACEFUL_TIMEOUT, ^{
        //mark timer as *not* running
        _backgroundTimer = nil;
        //retry background check (now handling idle state because no running background timer is blocking it)
        [self checkIfBackgroundTaskIsStillNeeded];
    });
}

-(void) stopBackgroundTimer
{
    if(_backgroundTimer)
        _backgroundTimer();
    _backgroundTimer = nil;
}

-(void) applicationWillEnterForeground:(UIApplication *)application
{
    DDLogInfo(@"Entering FG");
    
    //TODO: show "loading..." animation/modal
    
    //only proceed with foregrounding if the NotificationServiceExtension is not running
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension" withLoopHandler:^{
            [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        }];
    }
    
    //trigger view updates (this has to be done because the NotificationServiceExtension could have updated the database some time ago)
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:self userInfo:nil];
    
    //cancel already running background timer, we are now foregrounded again
    [self stopBackgroundTimer];
    
    [self addBackgroundTask];
    [[MLXMPPManager sharedInstance] nowForegrounded];
}

-(void) applicationWillResignActive:(UIApplication *)application
{
    NSArray<MLContact*>* activeContacts = [[DataLayer sharedInstance] activeContactDict];
    if(!activeContacts)
        return;

    NSError* err;
    NSData* archive = [NSKeyedArchiver archivedDataWithRootObject:activeContacts requiringSecureCoding:YES error:&err];
    NSAssert(err == nil, @"%@", err);
    [[HelperTools defaultsDB] setObject:archive forKey:@"recipients"];
    [[HelperTools defaultsDB] synchronize];
    
    [[HelperTools defaultsDB] setObject:[[DataLayer sharedInstance] enabledAccountList] forKey:@"accounts"];
    [[HelperTools defaultsDB] synchronize];
}

-(void) applicationDidEnterBackground:(UIApplication*) application
{
    UIApplicationState state = [application applicationState];
    if(state == UIApplicationStateInactive)
        DDLogInfo(@"Screen lock / incoming call");
    else if(state == UIApplicationStateBackground)
        DDLogInfo(@"Entering BG");
    
    [self updateUnread];
    [self addBackgroundTask];
    [[MLXMPPManager sharedInstance] nowBackgrounded];
    
    [self startBackgroundTimer];
    [self checkIfBackgroundTaskIsStillNeeded];
}

-(void) applicationWillTerminate:(UIApplication *)application
{
    DDLogWarn(@"|~~| T E R M I N A T I N G |~~|");
    [self updateUnread];
    DDLogInfo(@"|~~| 25%% |~~|");
    [[HelperTools defaultsDB] synchronize];
    DDLogInfo(@"|~~| 50%% |~~|");
    [[MLXMPPManager sharedInstance] nowBackgrounded];
    DDLogInfo(@"|~~| 75%% |~~|");
    [self scheduleBackgroundFetchingTask];        //make sure delivery will be attempted, if needed
    DDLogInfo(@"|~~| T E R M I N A T E D |~~|");
    [DDLog flushLog];
    //give the server some more time to send smacks acks (it doesn't matter if we get killed because of this, we're terminating anyways)
    usleep(1000000);
}

#pragma mark - error feedback

-(void) showConnectionStatus:(NSNotification*) notification
{
    //this will show an error banner but only if our app is foregrounded
    if(![HelperTools isNotInFocus])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            xmpp* xmppAccount = notification.object;
            if(![notification.userInfo[@"isSevere"] boolValue])
                DDLogError(@"Minor XMPP Error(%@): %@", xmppAccount.connectionProperties.identity.jid, notification.userInfo[@"message"]);
            NotificationBanner* banner = [[NotificationBanner alloc] initWithTitle:xmppAccount.connectionProperties.identity.jid subtitle:notification.userInfo[@"message"] leftView:nil rightView:nil style:([notification.userInfo[@"isSevere"] boolValue] ? BannerStyleDanger : BannerStyleWarning) colors:nil];
            banner.duration = 10.0;     //show for 10 seconds to make sure users can read it
            NotificationBannerQueue* queue = [[NotificationBannerQueue alloc] initWithMaxBannersOnScreenSimultaneously:2];
            [banner showWithQueuePosition:QueuePositionBack bannerPosition:BannerPositionTop queue:queue on:nil];
        });
    }
}

#pragma mark - mac menu
- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder
{
    [super buildMenuWithBuilder:builder];
    if (@available(iOS 13.0, *)) {
        //monal
        UIKeyCommand* preferencesCommand = [UIKeyCommand commandWithTitle:@"Preferences..." image:nil action:@selector(showSettings) input:@"," modifierFlags:UIKeyModifierCommand propertyList:nil];

        UIMenu* preferencesMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.preferences" options:UIMenuOptionsDisplayInline children:@[preferencesCommand]];
        [builder insertSiblingMenu:preferencesMenu afterMenuForIdentifier:UIMenuAbout];

        //file
        UIKeyCommand* newCommand = [UIKeyCommand commandWithTitle:@"New Message" image:nil action:@selector(showNew) input:@"N" modifierFlags:UIKeyModifierCommand propertyList:nil];

        UIMenu* newMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.new" options:UIMenuOptionsDisplayInline children:@[newCommand]];
        [builder insertChildMenu:newMenu atStartOfMenuForIdentifier:UIMenuFile];

        UIKeyCommand* detailsCommand = [UIKeyCommand commandWithTitle:@"Details..." image:nil action:@selector(showDetails) input:@"I" modifierFlags:UIKeyModifierCommand propertyList:nil];

        UIMenu* detailsMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.detail" options:UIMenuOptionsDisplayInline children:@[detailsCommand]];
        [builder insertSiblingMenu:detailsMenu afterMenuForIdentifier:@"im.monal.new"];

        UIKeyCommand* deleteCommand = [UIKeyCommand commandWithTitle:@"Delete Conversation" image:nil action:@selector(deleteConversation) input:@"\b" modifierFlags:UIKeyModifierCommand propertyList:nil];

        UIMenu* deleteMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.delete" options:UIMenuOptionsDisplayInline children:@[deleteCommand]];
        [builder insertSiblingMenu:deleteMenu afterMenuForIdentifier:@"im.monal.detail"];

        [builder removeMenuForIdentifier:UIMenuHelp];

        [builder replaceChildrenOfMenuForIdentifier:UIMenuAbout fromChildrenBlock:^NSArray<UIMenuElement *> * _Nonnull(NSArray<UIMenuElement *> * _Nonnull items) {
            UICommand* itemCommand = (UICommand*)items.firstObject;
            UICommand* aboutCommand = [UICommand commandWithTitle:itemCommand.title image:nil action:@selector(aboutWindow) propertyList:nil];
            NSArray* menuItems = @[aboutCommand];
            return menuItems;
        }];
    }
}

-(void) aboutWindow
{
    UIStoryboard* settingStoryBoard = [UIStoryboard storyboardWithName:@"Settings" bundle:nil];
    MLSettingsAboutViewController* settingAboutViewController = [settingStoryBoard instantiateViewControllerWithIdentifier:@"SettingsAboutViewController"];
    UINavigationController* navigationController = [[UINavigationController alloc] initWithRootViewController:settingAboutViewController];
    [self.window.rootViewController presentViewController:navigationController animated:NO completion:nil];
}

-(void) showNew
{
    [self.activeChats showContacts];
}

-(void) deleteConversation
{
    [self.activeChats deleteConversation];
}

-(void) showSettings
{
    [self.activeChats showSettings];
}

-(void) showDetails
{
    [self.activeChats showDetails];
}

#pragma mark - background tasks

-(void) nowIdle:(NSNotification*) notification
{
    DDLogInfo(@"### SOME ACCOUNT CHANGED TO IDLE STATE ###");
    [self checkIfBackgroundTaskIsStillNeeded];
}

-(void) filetransfersNowIdle:(NSNotification*) notification
{
    DDLogInfo(@"### FILETRANSFERS CHANGED TO IDLE STATE ###");
    [self checkIfBackgroundTaskIsStillNeeded];
}

-(void) checkIfBackgroundTaskIsStillNeeded
{
    if([[MLXMPPManager sharedInstance] allAccountsIdle] && [MLFiletransfer isIdle])
    {
        DDLogInfo(@"### ALL ACCOUNTS IDLE AND FILETRANSFERS COMPLETE NOW ###");
        [HelperTools updateSyncErrorsWithDeleteOnly:YES];
        
        //use a synchronized block to disconnect only once
        @synchronized(self) {
            if(_backgroundTimer != nil || [_wakeupCompletions count] > 0)
            {
                DDLogInfo(@"### ignoring idle state because background timer or wakeup completion timers are still running ###");
                return;
            }
            
            DDLogInfo(@"### checking if background is still needed ###");
            BOOL background = [HelperTools isInBackground];
            if(background)
            {
                DDLogInfo(@"### All accounts idle, disconnecting and stopping all background tasks ###");
                [DDLog flushLog];
                [[MLXMPPManager sharedInstance] disconnectAll];       //disconnect all accounts to prevent TCP buffer leaking
                [HelperTools dispatchSyncReentrant:^{
                    BOOL stopped = NO;
                    if(_bgTask != UIBackgroundTaskInvalid)
                    {
                        DDLogDebug(@"stopping UIKit _bgTask");
                        [DDLog flushLog];
                        [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
                        _bgTask = UIBackgroundTaskInvalid;
                        stopped = YES;
                    }
                    if(_bgFetch)
                    {
                        DDLogDebug(@"stopping backgroundFetchingTask");
                        [DDLog flushLog];
                        [_bgFetch setTaskCompletedWithSuccess:YES];
                        _bgFetch = nil;
                        stopped = YES;
                    }
                    if(!stopped)
                        DDLogDebug(@"no background tasks running, nothing to stop");
                    [DDLog flushLog];
                    
                    //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                } onQueue:dispatch_get_main_queue()];
            }
        }
    }
}

-(void) addBackgroundTask
{
    [HelperTools dispatchSyncReentrant:^{
        if(_bgTask == UIBackgroundTaskInvalid)
        {
            //indicate we want to do work even if the app is put into background
            _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
                DDLogWarn(@"BG WAKE EXPIRING");
                [DDLog flushLog];
                
                //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
                [HelperTools updateSyncErrorsWithDeleteOnly:NO];
                
                //disconnect all accounts to prevent TCP buffer leaking
                [[MLXMPPManager sharedInstance] disconnectAll];
                
                //schedule a BGProcessingTaskRequest to process this further as soon as possible
                if(@available(iOS 13.0, *))
                {
                    DDLogInfo(@"calling scheduleBackgroundFetchingTask");
                    [self scheduleBackgroundFetchingTask];
                }
                
                [DDLog flushLog];
                [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
                _bgTask = UIBackgroundTaskInvalid;
                
                //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
            }];
        }
    } onQueue:dispatch_get_main_queue()];
}

-(void) handleBackgroundFetchingTask:(BGTask*) task API_AVAILABLE(ios(13.0))
{
    DDLogInfo(@"RUNNING BGTASK");
    
    _bgFetch = task;
    weakify(task);
    task.expirationHandler = ^{
        DDLogWarn(@"*** BGTASK EXPIRED ***");
        strongify(task);
        _bgFetch = nil;
        
        //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
        [HelperTools updateSyncErrorsWithDeleteOnly:NO];
        
        //disconnect all accounts to prevent TCP buffer leaking
        [[MLXMPPManager sharedInstance] disconnectAll];
        
        [task setTaskCompletedWithSuccess:NO];
        [self scheduleBackgroundFetchingTask];      //schedule new one
        [DDLog flushLog];
        
        //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
    };
    
    if([[MLXMPPManager sharedInstance] hasConnectivity])
    {
        for(xmpp* xmppAccount in [[MLXMPPManager sharedInstance] connectedXMPP])
        {
            //try to send a ping. if it fails, it will reconnect
            DDLogVerbose(@"app delegate pinging");
            [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        }
    }
    else
        DDLogWarn(@"BGTASK has *no* connectivity? That's strange!");
    
    //log bgtask ticks (and stop when the task expires)
    unsigned long tick = 0;
    while(_bgFetch != nil)
    {
        DDLogVerbose(@"BGTASK TICK: %lu", tick++);
        [DDLog flushLog];
        [NSThread sleepForTimeInterval:1.000];
    }
}

-(void) configureBackgroundFetchingTask
{
    if(@available(iOS 13.0, *))
    {
        [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBackgroundFetchingTask usingQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) launchHandler:^(BGTask *task) {
            DDLogDebug(@"RUNNING BGTASK LAUNCH HANDLER");
            if(![HelperTools isInBackground])
            {
                DDLogDebug(@"Already in foreground, stopping bgtask");
                [_bgFetch setTaskCompletedWithSuccess:YES];
            }
            else
                [self handleBackgroundFetchingTask:task];
        }];
    } else {
        // No fallback unfortunately
    }
}

-(void) scheduleBackgroundFetchingTask
{
    if(@available(iOS 13.0, *))
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
            request.earliestBeginDate = nil;
            //request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:40];        //begin nearly immediately (if we have network connectivity)
            BOOL success = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
            if(!success) {
                // Errorcodes https://stackoverflow.com/a/58224050/872051
                DDLogError(@"Failed to submit BGTask request: %@", error);
            } else {
                DDLogVerbose(@"Success submitting BGTask request %@", request);
            }
        } onQueue:dispatch_get_main_queue()];
    }
    else
    {
        // No fallback unfortunately
        DDLogError(@"BGTask needed but NOT supported!");
    }
}

-(void) connectIfNecessary
{
    [self addBackgroundTask];
    [[MLXMPPManager sharedInstance] connectIfNecessary];
}

-(void) incomingWakeupWithCompletionHandler:(void (^)(UIBackgroundFetchResult result)) completionHandler
{
    if(![HelperTools isInBackground])
    {
        DDLogError(@"Ignoring incomingWakeupWithCompletionHandler: because app is in FG!");
        completionHandler(UIBackgroundFetchResultNoData);
        return;
    }
    
    NSString* completionId = [[NSUUID UUID] UUIDString];
    DDLogInfo(@"got incomingWakeupWithCompletionHandler with ID %@", completionId);
    
    //don't use *self* connectIfNecessary] because we already have a background task here
    //that gets stopped once we call the completionHandler
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
    //register push completion handler and associated timer (use the GRACEFUL_TIMEOUT here, too)
    @synchronized(self) {
        _wakeupCompletions[completionId] = @{
            @"handler": completionHandler,
            @"timer": createTimer(GRACEFUL_TIMEOUT, (^{
                DDLogWarn(@"### Wakeup timer triggered for ID %@ ###", completionId);
                dispatch_async(dispatch_get_main_queue(), ^{
                    @synchronized(self) {
                        if([_wakeupCompletions objectForKey:completionId] != nil)
                        {
                            DDLogInfo(@"Handling wakeup completion %@", completionId);
                            
                            //remove this handler from list
                            [_wakeupCompletions removeObjectForKey:completionId];
                            
                            //retry background check (now handling idle state because no running background timer is blocking it)
                            [self checkIfBackgroundTaskIsStillNeeded];
                            
                            //call completion (should be done *after* the idle state check because it could freeze the app)
                            DDLogInfo(@"Calling wakeup completion handler...");
                            completionHandler(UIBackgroundFetchResultFailed);
                        }
                        else
                            DDLogWarn(@"Wakeup completion %@ got already handled and was removed from list!", completionId);
                    }
                });
            }))
        };
        DDLogInfo(@"Added timer %@ to wakeup completion list...", completionId);
    }
}

@end

