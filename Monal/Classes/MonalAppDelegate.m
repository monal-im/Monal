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

-(void) setUISettings
{
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
}

#pragma mark -  APNS notificaion

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken{
    
    NSString *token=[MLPush stringFromToken:deviceToken];
     [MLXMPPManager sharedInstance].hasAPNSToken=YES;
    DDLogInfo(@"APNS token string: %@", token);
    [[[MLPush alloc] init] postToPushServer:token];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    DDLogError(@"push reg error %@", error);
    
}

#pragma mark - VOIP notification
#if !TARGET_OS_MACCATALYST
-(void) voipRegistration
{
    DDLogInfo(@"registering for voip APNS...");
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    PKPushRegistry * voipRegistry = [[PKPushRegistry alloc] initWithQueue: mainQueue];
    voipRegistry.delegate = self;
    voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

// Handle updated APNS tokens
-(void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials: (PKPushCredentials *)credentials forType:(NSString *)type
{
    NSString *token=[MLPush stringFromToken:credentials.token];
     [MLXMPPManager sharedInstance].hasAPNSToken=YES;
    DDLogInfo(@"APNS voip token string: %@", token);
    [[[MLPush alloc] init] postToPushServer:token];
}

-(void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(NSString *)type
{
    DDLogInfo(@"didInvalidatePushTokenForType called (and ignored, TODO: disable push on server?)");
}

// Handle incoming pushes
-(void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type
{
    DDLogInfo(@"incoming voip push notfication: %@", [payload dictionaryPayload]);
    if([UIApplication sharedApplication].applicationState==UIApplicationStateActive) return;
    if (@available(iOS 13.0, *)) {
        DDLogError(@"Voip push shouldnt arrive on ios13.");
    }
    else  {
        dispatch_async(dispatch_get_main_queue(), ^{
            __block UIBackgroundTaskIdentifier tempTask= [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
                DDLogInfo(@"voip push wake expiring");
                [[UIApplication sharedApplication] endBackgroundTask:tempTask];
                tempTask=UIBackgroundTaskInvalid;
            }];
            
            [[MLXMPPManager sharedInstance] connectIfNecessary];
            DDLogInfo(@"voip push wake complete");
        });
    }
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
        [UIApplication sharedApplication].applicationIconBadgeNumber = unread;
    } onQueue:dispatch_get_main_queue()];
}

#pragma mark - app life cycle

- (BOOL)application:(UIApplication*) application willFinishLaunchingWithOptions:(NSDictionary*) launchOptions
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
}

- (BOOL)application:(UIApplication*) application didFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    [UNUserNotificationCenter currentNotificationCenter].delegate=self;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showConnectionStatus:) name:kXMPPError object:nil];
    
    //register for local notifications and badges
    UIMutableUserNotificationAction* replyAction = [[UIMutableUserNotificationAction alloc] init];
    replyAction.activationMode = UIUserNotificationActivationModeBackground;
    replyAction.title = NSLocalizedString(@"Reply", @"");
    replyAction.identifier = NSLocalizedString(@"ReplyButton", @"");
    replyAction.destructive = NO;
    replyAction.authenticationRequired = NO;
    replyAction.behavior = UIUserNotificationActionBehaviorTextInput;
    
    UIMutableUserNotificationCategory* actionCategory = [[UIMutableUserNotificationCategory alloc] init];
    actionCategory.identifier = NSLocalizedString(@"Reply", @"");
    [actionCategory setActions:@[replyAction] forContext:UIUserNotificationActionContextDefault];
    
    UIUserNotificationSettings* settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeSound|UIUserNotificationTypeBadge categories:[NSSet setWithObjects:actionCategory,nil]];
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    
    //register for voip push using pushkit
    if([UIApplication sharedApplication].applicationState!=UIApplicationStateBackground) {
        // if we are launched in the background, it was from a push. dont do this again.
        if (@available(iOS 13.0, *)) {
            //no more voip mode after ios 13
            if(![[HelperTools defaultsDB] boolForKey:@"HasUpgradedPushiOS13"]) {
                MLPush *push = [[MLPush alloc] init];
                [push unregisterVOIPPush];
                [[HelperTools defaultsDB] setBool:YES forKey:@"HasUpgradedPushiOS13"];
            }
            
            [[UIApplication sharedApplication] registerForRemoteNotifications];
        }
        else {
#if !TARGET_OS_MACCATALYST
            [self voipRegistration];
#endif
        }
    }
    else  {
        [MLXMPPManager sharedInstance].pushNode = [[HelperTools defaultsDB] objectForKey:@"pushNode"];
        [MLXMPPManager sharedInstance].pushSecret=[[HelperTools defaultsDB] objectForKey:@"pushSecret"];
        [MLXMPPManager sharedInstance].hasAPNSToken=YES;
        DDLogInfo(@"push node %@", [MLXMPPManager sharedInstance].pushNode);
    }
    
    [self setUISettings];

    //update logs if needed
    if(![[HelperTools defaultsDB] boolForKey:@"Logging"])
    {
        [[DataLayer sharedInstance] messageHistoryCleanAll];
    }
    
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
    self.activeChats = activeChats;
}

#pragma mark - handling urls

-(BOOL) openFile:(NSURL*) file
{
    NSData *data = [NSData dataWithContentsOfURL:file];
    [[MLXMPPManager sharedInstance] parseMessageForData:data];
    return data?YES:NO;
}

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
        
        [[DataLayer sharedInstance] addActiveBuddies:contact.contactJid forAccount:contact.accountId withCompletion:^(BOOL success) {
            //no success may mean its already there
            dispatch_async(dispatch_get_main_queue(), ^{
                [(ActiveChatsViewController *) self.activeChats presentChatWithRow:contact];
                [(ActiveChatsViewController *) self.activeChats refreshDisplay];
            });
        }];
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

-(void) application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    DDLogVerbose(@"did register for local notifications");
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    DDLogVerbose(@"entering app with didReceiveLocalNotification: %@", notification);
    
    //iphone
    //make sure tab 0 for chat
    if([notification.userInfo objectForKey:@"from"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalPresentChat object:nil  userInfo:notification.userInfo];
        
    }
}

-(void) application:(UIApplication*) application didReceiveRemoteNotification:(NSDictionary*) userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result)) completionHandler
{
    DDLogVerbose(@"got didReceiveRemoteNotification: %@", userInfo);
    [[MLXMPPManager sharedInstance] incomingPushWithCompletionHandler:completionHandler];
}

- (void)userNotificationCenter:(UNUserNotificationCenter*) center willPresentNotification:(UNNotification*) notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options)) completionHandler;
{
    DDLogInfo(@"userNotificationCenter:willPresentNotification:withCompletionHandler called");
    //show local notifications while the app is open
    completionHandler(UNNotificationPresentationOptionAlert);
}

-(void) application:(UIApplication *)application handleActionWithIdentifier:(nullable NSString *)identifier forLocalNotification:(nonnull UILocalNotification *)notification withResponseInfo:(nonnull NSDictionary *)responseInfo completionHandler:(nonnull void (^)(void))completionHandler
{
    if ([notification.category isEqualToString:@"Reply"]) {
        if ([identifier isEqualToString:@"ReplyButton"]) {
            NSString *message = responseInfo[UIUserNotificationActionResponseTypedTextKey];
            if (message.length > 0) {
                
                if([notification.userInfo objectForKey:@"from"]) {
                    
                    NSString *replyingAccount = [notification.userInfo objectForKey:@"to"];
                    
                    NSString *messageID =[[NSUUID UUID] UUIDString];
                    
                    BOOL encryptChat =[[DataLayer sharedInstance] shouldEncryptForJid:[notification.userInfo objectForKey:@"from"] andAccountNo:[notification.userInfo objectForKey:@"accountNo"]];
                    
                    [[DataLayer sharedInstance] addMessageHistoryFrom:replyingAccount to:[notification.userInfo objectForKey:@"from"] forAccount:[notification.userInfo objectForKey:@"accountNo"] withMessage:message actuallyFrom:replyingAccount withId:messageID encrypted:encryptChat withCompletion:^(BOOL success, NSString *messageType) {
                        
                    }];
                    
                    [[MLXMPPManager sharedInstance] sendMessage:message toContact:[notification.userInfo objectForKey:@"from"] fromAccount:[notification.userInfo objectForKey:@"accountNo"] isEncrypted:encryptChat isMUC:NO isUpload:NO messageId:messageID  withCompletionHandler:^(BOOL success, NSString *messageId) {
                        
                    }];
                    
                    [[DataLayer sharedInstance] markAsReadBuddy:[notification.userInfo objectForKey:@"from"] forAccount:[notification.userInfo objectForKey:@"accountNo"]];
                    [self updateUnread];
                    
                }
                
                
            }
        }
    }
    if(completionHandler) completionHandler();
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
    
    //trigger view updates (this has to be done because a NotificationServiceExtension could have updated the database some time ago)
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalRefresh object:self userInfo:nil];
    
    [[MLXMPPManager sharedInstance] setClientsActive];
    [[MLXMPPManager sharedInstance] sendMessageForConnectedAccounts];
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

