//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MonalAppDelegate.h"

#import "CallViewController.h"
#import "MLConstants.h"
#import "HelperTools.h"
#import "MLNotificationManager.h"
#import "DataLayer.h"
#import "MLPush.h"
#import "MLImageManager.h"
#import "ActiveChatsViewController.h"
#import "IPC.h"
#import "MLProcessLock.h"

@import NotificationBannerSwift;

#import "MLXMPPManager.h"
#import "UIColor+Theme.h"

@interface MonalAppDelegate()
@property (nonatomic, weak) ActiveChatsViewController* activeChats;
@end

@implementation MonalAppDelegate

#pragma mark -  APNS notificaion

-(void) application:(UIApplication*) application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*) deviceToken
{
    NSString* token = [MLPush stringFromToken:deviceToken];
    DDLogInfo(@"APNS token string: %@", token);
    [[[MLPush alloc] init] postToPushServer:token];
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
    NSString* token = [MLPush stringFromToken:credentials.token];
    DDLogInfo(@"APNS voip token string: %@", token);
    [[[MLPush alloc] init] postToPushServer:token];
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
        [[MLXMPPManager sharedInstance] incomingPushWithCompletionHandler:^(UIBackgroundFetchResult result) {
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
    [HelperTools dispatchSyncReentrant:^{
        NSInteger unread = 0;
        if(unreadMsgCnt)
            unread = [unreadMsgCnt integerValue];
        DDLogInfo(@"Updating unread badge to: %ld", (long)unread);
        [UIApplication sharedApplication].applicationIconBadgeNumber = unread;
    } onQueue:dispatch_get_main_queue()];
}

#pragma mark - app life cycle

-(BOOL) application:(UIApplication*) application willFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    self.fileLogger = [HelperTools configureLogging];
    
    //log unhandled exceptions
    NSSetUncaughtExceptionHandler(&logException);
    
    [HelperTools activityLog];
    
    //migrate defaults db to shared app group
    if(![[HelperTools defaultsDB] boolForKey:@"DefaulsMigratedToAppGroup"])
    {
        DDLogInfo(@"Migrating [NSUserDefaults standardUserDefaults] to app group container...");
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"MessagePreview"] forKey:@"MessagePreview"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"ChatBackgrounds"] forKey:@"ChatBackgrounds"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowGeoLocation"] forKey:@"ShowGeoLocation"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"Sound"] forKey:@"Sound"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"SetDefaults"] forKey:@"SetDefaults"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeenIntro"] forKey:@"HasSeenIntro"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeeniOS13Message"] forKey:@"HasSeeniOS13Message"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeenLogin"] forKey:@"HasSeenLogin"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"SortContacts"] forKey:@"SortContacts"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"] forKey:@"OfflineContact"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"Logging"] forKey:@"Logging"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowImages"] forKey:@"ShowImages"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"Away"] forKey:@"Away"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasUpgradedPushiOS13"] forKey:@"HasUpgradedPushiOS13"];
        [[HelperTools defaultsDB] setObject:[[NSUserDefaults standardUserDefaults] objectForKey:@"StatusMessage"] forKey:@"StatusMessage"];
        [[HelperTools defaultsDB] setObject:[[NSUserDefaults standardUserDefaults] objectForKey:@"BackgroundImage"] forKey:@"BackgroundImage"];
        [[HelperTools defaultsDB] setObject:[[NSUserDefaults standardUserDefaults] objectForKey:@"AlertSoundFile"] forKey:@"AlertSoundFile"];
        [[HelperTools defaultsDB] setObject:[[NSUserDefaults standardUserDefaults] objectForKey:@"pushSecret"] forKey:@"pushSecret"];
        [[HelperTools defaultsDB] setObject:[[NSUserDefaults standardUserDefaults] objectForKey:@"pushNode"] forKey:@"pushNode"];
        
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
    
    //only proceed with launching if the NotificationServiceExtension is *not* running
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension"];
    }
    
    return YES;
}

- (BOOL)application:(UIApplication*) application didFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    //this will use the cached values in defaultsDB, if possible
    [[MLXMPPManager sharedInstance] setPushNode:nil andSecret:nil];
    
    //activate push
    if(@available(iOS 13.0, *))
    {
        //no more voip mode after ios 13
        if(![[HelperTools defaultsDB] boolForKey:@"HasUpgradedPushiOS13"]) {
            MLPush *push = [[MLPush alloc] init];
            [push unregisterVOIPPush];
            [[HelperTools defaultsDB] setBool:YES forKey:@"HasUpgradedPushiOS13"];
        }
        
        DDLogInfo(@"Registering for APNS...");
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    }
    else
    {
#if !TARGET_OS_MACCATALYST
        DDLogInfo(@"Registering for VoIP APNS...");
        [self voipRegistration];
#endif
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showConnectionStatus:) name:kXMPPError object:nil];
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
    }];
    [center setNotificationCategories:[NSSet setWithObjects:messageCategory, nil]];
    
    UIColor *monalGreen = [UIColor monalGreen];
    UIColor *monaldarkGreen =[UIColor monaldarkGreen];
    [[UINavigationBar appearance] setTintColor:monalGreen];
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor=[UIColor systemBackgroundColor];
        
        [[UINavigationBar appearance] setScrollEdgeAppearance:appearance];
        [[UINavigationBar appearance] setStandardAppearance:appearance];
#if TARGET_OS_MACCATALYST
        self.window.windowScene.titlebar.titleVisibility=UITitlebarTitleVisibilityHidden;
#endif
    }
    [[UINavigationBar appearance] setPrefersLargeTitles:YES];
    [[UITabBar appearance] setTintColor:monaldarkGreen];

    //update logs if needed
    if(![[HelperTools defaultsDB] boolForKey:@"Logging"])
        [[DataLayer sharedInstance] messageHistoryCleanAll];
    
    //handle message notifications by initializing the MLNotificationManager
    [MLNotificationManager sharedInstance];
    
    //register BGTask
    if(@available(iOS 13.0, *))
    {
        DDLogInfo(@"calling MLXMPPManager configureBackgroundFetchingTask");
        [[MLXMPPManager sharedInstance] configureBackgroundFetchingTask];
    }
    
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    NSString* buildDate = [NSString stringWithUTF8String:__DATE__];
    NSString* buildTime = [NSString stringWithUTF8String:__TIME__];
    DDLogInfo(@"App started: %@", [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@ %@ UTC)", @ ""), version, buildDate, buildTime]);
    
    //should any accounts connect?
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
    //handle IPC messages (this should be done *after* calling connectIfNecessary to make sure any disconnectAll messages are handled properly
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(incomingIPC:) name:kMonalIncomingIPC object:nil];
    
    return YES;
}

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
        [[MLXMPPManager sharedInstance] connectIfNecessary];
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
    xmpp *account=[[MLXMPPManager sharedInstance].connectedXMPP firstObject];
    if(account) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        __block MLContact *contact = [[MLContact alloc] init];
        contact.contactJid= components.path;
        contact.accountId=account.accountNo;
        __block NSString *mucPassword;
        
        [components.queryItems enumerateObjectsUsingBlock:^(NSURLQueryItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if([obj.name isEqualToString:@"join"]) {
                contact.isGroup=YES;
            }
            if([obj.name isEqualToString:@"password"]) {
                mucPassword=obj.value;
            }
        }];
        
        if(contact.isGroup) {
            //TODO maybe default nick once we have defined one
            [[MLXMPPManager sharedInstance] joinRoom:contact.contactJid withNick:account.connectionProperties.identity.user andPassword:mucPassword forAccounId:contact.accountId];
        }
        
        [[DataLayer sharedInstance] addActiveBuddies:contact.contactJid forAccount:contact.accountId];
        //no success may mean its already there
        dispatch_async(dispatch_get_main_queue(), ^{
            [(ActiveChatsViewController *) self.activeChats presentChatWithRow:contact];
            [(ActiveChatsViewController *) self.activeChats refreshDisplay];
        });
    }
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    if([url.scheme isEqualToString:@"xmpp"]) //for links
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
    [[MLXMPPManager sharedInstance] incomingPushWithCompletionHandler:completionHandler];
}

- (void)userNotificationCenter:(UNUserNotificationCenter*) center willPresentNotification:(UNNotification*) notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options)) completionHandler;
{
    DDLogInfo(@"userNotificationCenter:willPresentNotification:withCompletionHandler called");
    //show local notifications while the app is open
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
        [[MLXMPPManager sharedInstance] connectIfNecessary];
        
        NSString* from = response.notification.request.content.userInfo[@"from"];
        NSString* accountId = response.notification.request.content.userInfo[@"accountId"];
        NSString* messageId = response.notification.request.content.userInfo[@"messageId"];
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:accountId];
        NSAssert(from, @"from should not be nil");
        NSAssert(accountId, @"accountId should not be nil");
        NSAssert(messageId, @"messageId should not be nil");
        NSAssert(account, @"account should not be nil");
        if([response.actionIdentifier isEqualToString:@"REPLY_ACTION"])
        {
            DDLogInfo(@"REPLY_ACTION triggered...");
            UNTextInputNotificationResponse* textResponse = (UNTextInputNotificationResponse*) response;
            if(!textResponse.userText.length)
            {
                DDLogWarn(@"User tried to send empty text response!");
                if(completionHandler)
                    completionHandler();
                return;
            }
            
            //mark messages as read because we are replying
            [[DataLayer sharedInstance] markMessagesAsReadForBuddy:from andAccount:accountId tillStanzaId:messageId wasOutgoing:NO];
            [self updateUnread];
            
            BOOL encrypted = [[DataLayer sharedInstance] shouldEncryptForJid:from andAccountNo:accountId];
            BOOL isMuc = [[DataLayer sharedInstance] isBuddyMuc:from forAccount:accountId];
            [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:textResponse.userText toContact:from fromAccount:accountId isEncrypted:encrypted isMUC:isMuc isUpload:NO withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                DDLogInfo(@"REPLY_ACTION success=%@, messageIdSentObject=%@", successSendObject ? @"YES" : @"NO", messageIdSentObject);
            }];
        }
        else if([response.actionIdentifier isEqualToString:@"MARK_AS_READ_ACTION"])
        {
            DDLogInfo(@"MARK_AS_READ_ACTION triggered...");
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:from andAccount:accountId tillStanzaId:messageId wasOutgoing:NO];
            DDLogDebug(@"Marked as read: %@", unread);
            
            //remove notifications of all remotely read messages (indicated by sending a response message)
            for(MLMessage* msg in unread)
            {
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalDisplayedMessageNotice object:account userInfo:@{@"message":msg}];
                [account sendDisplayMarkerForId:msg.messageId to:msg.from];
            }
            
            //update unread count in active chats list
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": [[DataLayer sharedInstance] contactForUsername:from forAccount:accountId]
            }];
            
            [self updateUnread];
        }
    }
    if(completionHandler)
        completionHandler();
}



#pragma mark - memory
-(void) applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    [[MLImageManager sharedInstance] purgeCache];
}

#pragma mark - backgrounding

- (void) applicationWillEnterForeground:(UIApplication *)application
{
    DDLogVerbose(@"Entering FG");
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    
    //only proceed with foregrounding if the NotificationServiceExtension is not running
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension"];
    }
    
    //trigger view updates (this has to be done because the NotificationServiceExtension could have updated the database some time ago)
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalRefresh object:self userInfo:nil];
    
    [[MLXMPPManager sharedInstance] setClientsActive];
}

-(void) applicationWillResignActive:(UIApplication *)application
{
    NSMutableArray* activeContacts = [[DataLayer sharedInstance] activeContactDict];
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
        DDLogVerbose(@"Screen lock / incoming call");
    else if(state == UIApplicationStateBackground)
        DDLogVerbose(@"Entering BG");
    
    [self updateUnread];
    [[MLXMPPManager sharedInstance] setClientsInactive];
}

-(void) applicationWillTerminate:(UIApplication *)application
{
    DDLogWarn(@"|~~| T E R M I N A T I N G |~~|");
    [self updateUnread];
    DDLogVerbose(@"|~~| 25%% |~~|");
    [[HelperTools defaultsDB] synchronize];
    DDLogVerbose(@"|~~| 50%% |~~|");
    [[MLXMPPManager sharedInstance] setClientsInactive];
    DDLogVerbose(@"|~~| 75%% |~~|");
    [[MLXMPPManager sharedInstance] scheduleBackgroundFetchingTask];        //make sure delivery will be attempted, if needed
    DDLogVerbose(@"|~~| T E R M I N A T E D |~~|");
    [DDLog flushLog];
    //give the server some more time to send smacks acks (it doesn't matter if we get killed because of this, we're terminating anyways)
    usleep(1000000);
}

#pragma mark - error feedback

-(void) showConnectionStatus:(NSNotification*) notification
{
    if([HelperTools isInBackground])
        DDLogDebug(@"not surfacing errors in the background because they are super common");
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray* payload = [notification.object copy];
            NSString* message = payload[1];     // this is just the way i set it up a dic might better
            xmpp *xmppAccount = payload.firstObject;
            NotificationBanner* banner = [[NotificationBanner alloc] initWithTitle:xmppAccount.connectionProperties.identity.jid subtitle:message leftView:nil rightView:nil style:BannerStyleInfo colors:nil];
            NotificationBannerQueue* queue = [[NotificationBannerQueue alloc] initWithMaxBannersOnScreenSimultaneously:2];
            [banner showWithQueuePosition:QueuePositionFront bannerPosition:BannerPositionTop queue:queue on:nil];
        });
    }
}

#pragma mark - mac menu
- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder
{
    [super buildMenuWithBuilder:builder];
    if (@available(iOS 13.0, *)) {
        
        //monal
        UIKeyCommand *preferencesCommand = [UIKeyCommand commandWithTitle:@"Preferences..." image:nil action:@selector(showSettings) input:@"," modifierFlags:UIKeyModifierCommand propertyList:nil];
        
        UIMenu * preferencesMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.preferences" options:UIMenuOptionsDisplayInline children:@[preferencesCommand]];
        [builder insertSiblingMenu:preferencesMenu afterMenuForIdentifier:UIMenuAbout];
        
        //file
        UIKeyCommand *newCommand = [UIKeyCommand commandWithTitle:@"New Message" image:nil action:@selector(showNew) input:@"N" modifierFlags:UIKeyModifierCommand propertyList:nil];
 
        UIMenu *newMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.new" options:UIMenuOptionsDisplayInline children:@[newCommand]];
        [builder insertChildMenu:newMenu atStartOfMenuForIdentifier:UIMenuFile];
        
        UIKeyCommand *detailsCommand = [UIKeyCommand commandWithTitle:@"Details..." image:nil action:@selector(showDetails) input:@"I" modifierFlags:UIKeyModifierCommand propertyList:nil];
        
        UIMenu *detailsMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.detail" options:UIMenuOptionsDisplayInline children:@[detailsCommand]];
        [builder insertSiblingMenu:detailsMenu afterMenuForIdentifier:@"im.monal.new"];
        
        
       UIKeyCommand *deleteCommand = [UIKeyCommand commandWithTitle:@"Delete Conversation" image:nil action:@selector(deleteConversation) input:@"\b" modifierFlags:UIKeyModifierCommand propertyList:nil];
        
        UIMenu *deleteMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.delete" options:UIMenuOptionsDisplayInline children:@[deleteCommand]];
        [builder insertSiblingMenu:deleteMenu afterMenuForIdentifier:@"im.monal.detail"];
        
       [builder removeMenuForIdentifier:UIMenuHelp];
    }
}


-(void) showNew {
    [self.activeChats showNew];
}

-(void) deleteConversation {
    [self.activeChats deleteConversation];
}

-(void) showSettings {
    [self.activeChats showSettings];
}

-(void) showDetails {
    [self.activeChats showDetails];
}

@end

