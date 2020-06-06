//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MonalAppDelegate.h"

#import "CallViewController.h"

#import "MLNotificationManager.h"
#import "DataLayer.h"
#import "MLPush.h"
#import "MLImageManager.h"
#import "ActiveChatsViewController.h"

#if !TARGET_OS_MACCATALYST
@import Crashlytics;
@import Fabric;
#endif

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
                [[MLXMPPManager sharedInstance] logoutAllKeepStreamWithCompletion:nil];
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
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSInteger unread = 0;
            if(result) {
                unread = [result integerValue];
            }
            
            if(unread>0) {
                [UIApplication sharedApplication].applicationIconBadgeNumber = unread;
            }
            else {
                [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
            }
        });
    }];
}

#pragma mark - app life cycle

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler;
{
    completionHandler(UNNotificationPresentationOptionAlert);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [DDLog addLogger:[DDOSLogger sharedInstance]];
    
#ifdef  DEBUG
    
#ifndef TARGET_IPHONE_SIMULATOR
    self.fileLogger = [[DDFileLogger alloc] init];
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    self.fileLogger.maximumFileSize=1024 * 500;
    [DDLog addLogger:self.fileLogger];
#endif
    
#endif
    
    [UNUserNotificationCenter currentNotificationCenter].delegate=self;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateState:) name:kMLHasConnectedNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showConnectionStatus:) name:kXMPPError object:nil];
    
    //ios8 register for local notifications and badges
    if([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)])
    {
        NSSet *categories;
        
        UIMutableUserNotificationAction *replyAction = [[UIMutableUserNotificationAction alloc] init];
        replyAction.activationMode = UIUserNotificationActivationModeBackground;
        replyAction.title = @"Reply";
        replyAction.identifier = @"ReplyButton";
        replyAction.destructive = NO;
        replyAction.authenticationRequired = NO;
        replyAction.behavior = UIUserNotificationActionBehaviorTextInput;
        
        UIMutableUserNotificationCategory *actionCategory = [[UIMutableUserNotificationCategory alloc] init];
        actionCategory.identifier = @"Reply";
        [actionCategory setActions:@[replyAction] forContext:UIUserNotificationActionContextDefault];
        
        UIMutableUserNotificationCategory *extensionCategory = [[UIMutableUserNotificationCategory alloc] init];
        extensionCategory.identifier = @"Extension";
        
        categories = [NSSet setWithObjects:actionCategory,extensionCategory,nil];
        
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeSound|UIUserNotificationTypeBadge categories:nil];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    }
    
    //register for voip push using pushkit
    if([UIApplication sharedApplication].applicationState!=UIApplicationStateBackground) {
        // if we are launched in the background, it was from a push. dont do this again.
        if (@available(iOS 13.0, *)) {
            //no more voip mode after ios 13
            if(![[NSUserDefaults standardUserDefaults] boolForKey:@"HasUpgradedPushiOS13"]) {
                MLPush *push = [[MLPush alloc] init];
                [push unregisterVOIPPush];
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HasUpgradedPushiOS13"];
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
        [MLXMPPManager sharedInstance].pushNode = [[NSUserDefaults standardUserDefaults] objectForKey:@"pushNode"];
        [MLXMPPManager sharedInstance].pushSecret=[[NSUserDefaults standardUserDefaults] objectForKey:@"pushSecret"];
        [MLXMPPManager sharedInstance].hasAPNSToken=YES;
        NSLog(@"push node %@", [MLXMPPManager sharedInstance].pushNode);
    }
    
    [self setUISettings];

    // should any accounts connect?
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
#if !TARGET_OS_MACCATALYST
    BOOL optout = [[NSUserDefaults standardUserDefaults] boolForKey:@"CrashlyticsOptOut"];
    if(!optout) {
        [Fabric with:@[[Crashlytics class]]];
    }
#endif
    
    //update logs if needed
    if(! [[NSUserDefaults standardUserDefaults] boolForKey:@"Logging"])
    {
        [[DataLayer sharedInstance] messageHistoryCleanAll];
    }
    
    DDLogInfo(@"App started");
    return YES;
}

-(void) applicationDidBecomeActive:(UIApplication *)application
{
    //  [UIApplication sharedApplication].applicationIconBadgeNumber=0;
}

-(void) setActiveChatsController: (UIViewController *) activeChats
{
    self.activeChats=activeChats;
}

#pragma mark - handling urls

-(BOOL) openFile:(NSURL *) file {
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
    xmpp *account=[[MLXMPPManager sharedInstance].connectedXMPP.firstObject objectForKey:@"xmppAccount"];;
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
                [(ActiveChatsViewController *) self.activeChats  refreshDisplay];
            });
        }];
    }
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    if([url.scheme isEqualToString:@"file"]) // for airdrop
    {
        return [self openFile:url];
    }
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
    DDLogVerbose(@"entering app with %@", notification);
    
    //iphone
    //make sure tab 0 for chat
    if([notification.userInfo objectForKey:@"from"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalPresentChat object:nil  userInfo:notification.userInfo];
        
    }
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

-(void) updateState:(NSNotification *) notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplicationState state = [[UIApplication sharedApplication] applicationState];
        if (state == UIApplicationStateInactive || state == UIApplicationStateBackground) {
            [[MLXMPPManager sharedInstance] setClientsInactive];
        } else {
             [[MLXMPPManager sharedInstance] setClientsActive];
        }
    });
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    DDLogVerbose(@"Entering FG");
 
    [[MLXMPPManager sharedInstance] resetForeground];
    [[MLXMPPManager sharedInstance] setClientsActive];
    [[MLXMPPManager sharedInstance] sendMessageForConnectedAccounts];
}

-(void)applicationWillResignActive:(UIApplication *)application
{
     NSUserDefaults *groupDefaults= [[NSUserDefaults alloc] initWithSuiteName:@"group.monal"];

    [[DataLayer sharedInstance] activeContactDictWithCompletion:^(NSMutableArray *cleanActive) {
        NSError* err;
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:cleanActive requiringSecureCoding:YES error:&err];
        NSAssert(err == nil, @"%@", err);
        [groupDefaults setObject:archive forKey:@"recipients"];
        [groupDefaults synchronize];
    }];
    
    [groupDefaults setObject:[[DataLayer sharedInstance] enabledAccountList] forKey:@"accounts"];
    [groupDefaults synchronize];
}

-(void) applicationDidEnterBackground:(UIApplication *)application
{
    UIApplicationState state = [application applicationState];
    if (state == UIApplicationStateInactive) {
        DDLogVerbose(@"Screen lock");
    } else if (state == UIApplicationStateBackground) {
        DDLogVerbose(@"Entering BG");
    }
    
    [self updateUnread];
    [[MLXMPPManager sharedInstance] setClientsInactive];

}

-(void)applicationWillTerminate:(UIApplication *)application
{
    [self updateUnread];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - error feedback

-(void) showConnectionStatus:(NSNotification *) notification
{
    NSArray *payload= [notification.object copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        if(([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
           || ([UIApplication sharedApplication].applicationState==UIApplicationStateInactive ))
        {
            DDLogDebug(@"not surfacing errors in the background because they are super common");
        } else  {
            NSString *message = payload[1]; // this is just the way i set it up a dic might better
            xmpp *xmppAccount= payload.firstObject;

            NotificationBanner *banner =[[NotificationBanner alloc] initWithTitle:xmppAccount.connectionProperties.identity.jid subtitle:message leftView:nil rightView:nil style:BannerStyleInfo colors:nil];
           
            NotificationBannerQueue *queue = [[NotificationBannerQueue alloc] initWithMaxBannersOnScreenSimultaneously:2];
            
            [banner showWithQueuePosition:QueuePositionFront bannerPosition:BannerPositionTop queue:queue on:nil];
            
        }
    });
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

