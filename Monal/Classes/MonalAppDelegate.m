//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MonalAppDelegate.h"

#import "MLPortraitNavController.h"
#import "CallViewController.h"

// tab bar
#import "ContactsViewController.h"
#import "ActiveChatsViewController.h"
#import "SettingsViewController.h"
#import "AccountsViewController.h"
#import "ChatLogsViewController.h"
#import "GroupChatViewController.h"
#import "SearchUsersViewController.h"
#import "LogViewController.h"
#import "HelpViewController.h"
#import "AboutViewController.h"
#import "MLNotificationManager.h"
#import "DataLayer.h"

#import <Fabric/Fabric.h>
#import <Crashlytics/Crashlytics.h>


//xmpp
#import "MLXMPPManager.h"

@interface MonalAppDelegate ()

@property (nonatomic, strong)  UITabBarItem* activeTab;

@end

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@implementation MonalAppDelegate

-(void) createRootInterface
{
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showCallScreen:) name:kMonalCallStartedNotice object:nil];
    
   // self.window.screen=[UIScreen mainScreen];
    
    _tabBarController=[[MLTabBarController alloc] init];
    ContactsViewController* contactsVC = [[ContactsViewController alloc] init];
    [MLXMPPManager sharedInstance].contactVC=contactsVC;
    contactsVC.presentationTabBarController=_tabBarController; 
    
    UIBarStyle barColor=UIBarStyleBlackOpaque;
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
         barColor=UIBarStyleDefault;
    }
    
    ActiveChatsViewController* activeChatsVC = [[ActiveChatsViewController alloc] init];
    UINavigationController* activeChatNav=[[UINavigationController alloc] initWithRootViewController:activeChatsVC];
    activeChatNav.navigationBar.barStyle=barColor;
    activeChatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Active Chats",@"") image:[UIImage imageNamed:@"906-chat-3"] tag:0];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:UIApplicationWillEnterForegroundNotification object:nil];
    _activeTab=activeChatNav.tabBarItem;
    
    
    SettingsViewController* settingsVC = [[SettingsViewController alloc] init];
    UINavigationController* settingsNav=[[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.navigationBar.barStyle=barColor;
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Settings",@"") image:[UIImage imageNamed:@"740-gear"] tag:0];
    
    AccountsViewController* accountsVC = [[AccountsViewController alloc] init];
    UINavigationController* accountsNav=[[UINavigationController alloc] initWithRootViewController:accountsVC];
    accountsNav.navigationBar.barStyle=barColor;
    accountsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Accounts",@"") image:[UIImage imageNamed:@"1049-at-sign"] tag:0];
    
    ChatLogsViewController* chatLogVC = [[ChatLogsViewController alloc] init];
    UINavigationController* chatLogNav=[[UINavigationController alloc] initWithRootViewController:chatLogVC];
    chatLogNav.navigationBar.barStyle=barColor;
    chatLogNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Chat Logs",@"") image:[UIImage imageNamed:@"1065-rewind-time-1"] tag:0];
    
//    SearchUsersViewController* searchUsersVC = [[SearchUsersViewController alloc] init];
//    UINavigationController* searchUsersNav=[[UINavigationController alloc] initWithRootViewController:searchUsersVC];
//    searchUsersNav.navigationBar.barStyle=barColor;
//    searchUsersNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Search Users",@"") image:[UIImage imageNamed:@"708-search"] tag:0];
//    
    GroupChatViewController* groupChatVC = [[GroupChatViewController alloc] init];
    UINavigationController* groupChatNav=[[UINavigationController alloc] initWithRootViewController:groupChatVC];
    groupChatNav.navigationBar.barStyle=barColor;
    groupChatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Group Chat",@"") image:[UIImage imageNamed:@"974-users"] tag:0];
    
    HelpViewController* helpVC = [[HelpViewController alloc] init];
    UINavigationController* helpNav=[[UINavigationController alloc] initWithRootViewController:helpVC];
    helpNav.navigationBar.barStyle=barColor;
    helpNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Help",@"") image:[UIImage imageNamed:@"739-question"] tag:0];
    
    AboutViewController* aboutVC = [[AboutViewController alloc] init];
    UINavigationController* aboutNav=[[UINavigationController alloc] initWithRootViewController:aboutVC];
    aboutNav.navigationBar.barStyle=barColor;
    aboutNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"About",@"") image:[UIImage imageNamed:@"724-info"] tag:0];
    
#ifdef DEBUG
    LogViewController* logVC = [[LogViewController alloc] init];
    UINavigationController* logNav=[[UINavigationController alloc] initWithRootViewController:logVC];
    logNav.navigationBar.barStyle=barColor;
    logNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Log",@"") image:nil tag:0];
#endif
    
    
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        
        _chatNav=[[UINavigationController alloc] initWithRootViewController:contactsVC];
        _chatNav.navigationBar.barStyle=barColor;
        contactsVC.currentNavController=_chatNav;
        _chatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Contacts",@"") image:[UIImage imageNamed:@"973-user"] tag:0];
        
    
        _tabBarController.viewControllers=[NSArray arrayWithObjects:_chatNav,activeChatNav, settingsNav,  accountsNav, chatLogNav, groupChatNav, //searchUsersNav,
                                           helpNav, aboutNav,
#ifdef DEBUG
                                           logNav,
#endif
                                           nil];
        
        self.window.rootViewController=_tabBarController;
        
    }
    else
    {
        
        //this is a dummy nav controller not really used for anything
        UINavigationController* navigationControllerContacts=[[UINavigationController alloc] initWithRootViewController:contactsVC];
        navigationControllerContacts.navigationBar.barStyle=barColor;
        
        _chatNav=activeChatNav;
        contactsVC.currentNavController=_chatNav;
        _splitViewController=[[UISplitViewController alloc] init];
        self.window.rootViewController=_splitViewController;
        
        _tabBarController.viewControllers=[NSArray arrayWithObjects: activeChatNav,  settingsNav, accountsNav, chatLogNav, groupChatNav,
                                        //   searchU∫sersNav,
                                           helpNav, aboutNav,
#ifdef DEBUG
                                           logNav,
#endif
                                           nil];
        
        _splitViewController.viewControllers=[NSArray arrayWithObjects:navigationControllerContacts, _tabBarController,nil];
        _splitViewController.delegate=self;
    }
    
    _chatNav.navigationBar.barStyle=barColor;
    _tabBarController.moreNavigationController.navigationBar.barStyle=barColor;
    
    [self.window makeKeyAndVisible];
    
    UIColor *monalGreen =[UIColor colorWithRed:128.0/255 green:203.0/255 blue:182.0/255 alpha:1.0f];
    UIColor *monaldarkGreen =[UIColor colorWithRed:20.0/255 green:138.0/255 blue:103.0/255 alpha:1.0f];

    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        [[UINavigationBar appearance] setBarTintColor:monalGreen];
        [[UINavigationBar appearance] setTintColor:[UIColor whiteColor]];
        [[UINavigationBar appearance] setTitleTextAttributes:@{
                                                               UITextAttributeTextColor: [UIColor darkGrayColor]
                                                               }];
        [[UITabBar appearance] setTintColor:monaldarkGreen];
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    }
   
}


#pragma mark notification actions
-(void) showCallScreen:(NSNotification*) userInfo
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       NSDictionary* contact=userInfo.object;
                       CallViewController *callScreen= [[CallViewController alloc] initWithContact:contact];
                       MLPortraitNavController* callNav = [[MLPortraitNavController alloc] initWithRootViewController:callScreen];
                       callNav.navigationBar.hidden=YES;
                       
                       if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
                       {
                           callNav.modalPresentationStyle=UIModalPresentationFormSheet;
                       }
                       
                       [self.tabBarController presentModalViewController:callNav animated:YES];
                   });
}

-(void) updateUnread
{
    //make sure unread badge matches application badge
    
    [[DataLayer sharedInstance] countUnreadMessagesWithCompletion:^(NSNumber *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            NSInteger unread =0;
            if(result)
            {
                unread= [result integerValue];
            }
            
            if(unread>0)
            {
                _activeTab.badgeValue=[NSString stringWithFormat:@"%ld",(long)unread];
                [UIApplication sharedApplication].applicationIconBadgeNumber =unread;
            }
            else
            {
                _activeTab.badgeValue=nil;
                [UIApplication sharedApplication].applicationIconBadgeNumber =0;
            }
        });
    }];
    
}

#pragma mark app life cycle



- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    
#ifdef  DEBUG
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    self.fileLogger = [[DDFileLogger alloc] init];
    self.fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    self.fileLogger.logFileManager.maximumNumberOfLogFiles = 5;
    self.fileLogger.maximumFileSize=1024 * 500;
    [DDLog addLogger:self.fileLogger];
#endif
    //ios8 register for local notifications and badges
    if([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)])
    {
        NSSet *categories;
        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"9.0")) {
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
            categories = [NSSet setWithObject:actionCategory];
        }
        
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeSound|UIUserNotificationTypeBadge categories:categories];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    }
    
    [self createRootInterface];

    //rating
    [Appirater setAppId:@"317711500"];
    [Appirater setDaysUntilPrompt:5];
    [Appirater setUsesUntilPrompt:10];
    [Appirater setSignificantEventsUntilPrompt:5];
    [Appirater setTimeBeforeReminding:2];
    //[Appirater setDebug:YES];
    [Appirater appLaunched:YES];
    
    [MLNotificationManager sharedInstance].window=self.window;
    
     // should any accounts connect?
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
    [Fabric with:@[[Crashlytics class]]];
    
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

#pragma mark notifiction 
-(void) application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    DDLogVerbose(@"did register for local notifications");
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
  DDLogVerbose(@"entering app with %@", notification);
    
    //iphone
    //make sure tab 0
    if([notification.userInfo objectForKey:@"from"]) {
    [self.tabBarController setSelectedIndex:0];
    [[MLXMPPManager sharedInstance].contactVC presentChatWithName:[notification.userInfo objectForKey:@"from"] account:[notification.userInfo objectForKey:@"accountNo"] ];
    }
}

-(void) application:(UIApplication *)application handleActionWithIdentifier:(nullable NSString *)identifier forLocalNotification:(nonnull UILocalNotification *)notification withResponseInfo:(nonnull NSDictionary *)responseInfo completionHandler:(nonnull void (^)())completionHandler
{
    if ([notification.category isEqualToString:@"Reply"]) {
        NSDictionary *userInfo = notification.userInfo;
        if ([identifier isEqualToString:@"ReplyButton"]) {
            NSString *message = responseInfo[UIUserNotificationActionResponseTypedTextKey];
            if (message.length > 0) {
                
                if([notification.userInfo objectForKey:@"from"]) {
                    
                    NSArray *toParts= [[notification.userInfo objectForKey:@"to"] componentsSeparatedByString:@"/"];
                    if(toParts.count>0) {
                        NSString *replyingAccount = toParts[0];
                        
                        NSUInteger r = arc4random_uniform(NSIntegerMax);
                        NSString *messageID =[NSString stringWithFormat:@"Monal%lu", (unsigned long)r];
                        
                        [[DataLayer sharedInstance] addMessageHistoryFrom:replyingAccount to:[notification.userInfo objectForKey:@"from"] forAccount:[notification.userInfo objectForKey:@"accountNo"] withMessage:message actuallyFrom:replyingAccount withId:messageID withCompletion:^(BOOL success) {
                            
                        }];
                        
                        [[MLXMPPManager sharedInstance] sendMessage:message toContact:[notification.userInfo objectForKey:@"from"] fromAccount:[notification.userInfo objectForKey:@"accountNo"] isMUC:NO messageId:messageID withCompletionHandler:^(BOOL success, NSString *messageId) {
                            
                        }];
                        
                    }
                }
                
                
            }
        }
    }
    if(completionHandler) completionHandler();
}


#pragma mark memory
-(void) applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    [[MLImageManager sharedInstance] purgeCache];
}

#pragma mark backgrounding
- (void)applicationWillEnterForeground:(UIApplication *)application
{
      DDLogVerbose(@"Entering FG");
    [[MLXMPPManager sharedInstance] clearKeepAlive];
    [[MLXMPPManager sharedInstance] resetForeground];
}

-(void) applicationDidEnterBackground:(UIApplication *)application
{
    UIApplicationState state = [application applicationState];
    if (state == UIApplicationStateInactive) {
        DDLogVerbose(@"Screen lock");
    } else if (state == UIApplicationStateBackground) {
        DDLogVerbose(@"Entering BG");
    }
    
    [[MLXMPPManager sharedInstance] setKeepAlivetimer];
}

-(void)applicationWillTerminate:(UIApplication *)application
{
    
       [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark splitview controller delegate
- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    return NO;
}

@end

