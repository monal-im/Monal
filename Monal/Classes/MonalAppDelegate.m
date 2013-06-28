//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MonalAppDelegate.h"



// tab bar
#import "ContactsViewController.h"
#import "ActiveChatsViewController.h"
#import "SettingsViewController.h"
#import "AccountsViewController.h"
#import "ChatLogsViewController.h"
#import "GroupChatViewController.h"
#import "SearchUsersViewController.h"
#import "HelpViewController.h"
#import "AboutViewController.h"

@implementation MonalAppDelegate

-(void) createRootInterface
{
    self.window=[[UIWindow alloc] init];
    self.window.screen=[UIScreen mainScreen];
    
    _tabBarController=[[UITabBarController alloc] init];
    ContactsViewController* contactsVC = [[ContactsViewController alloc] init];
    
    ActiveChatsViewController* activeChatsVC = [[ActiveChatsViewController alloc] init];
    UINavigationController* activeChatNav=[[UINavigationController alloc] initWithRootViewController:activeChatsVC];
    activeChatNav.navigationBar.tintColor=[UIColor blackColor];
    activeChatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Active Chats",@"") image:[UIImage imageNamed:@"active"] tag:0];
    
    SettingsViewController* settingsVC = [[SettingsViewController alloc] init];
    UINavigationController* settingsNav=[[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.navigationBar.tintColor=[UIColor blackColor];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Settings",@"") image:[UIImage imageNamed:@"status"] tag:0];
    
    AccountsViewController* accountsVC = [[AccountsViewController alloc] init];
    UINavigationController* accountsNav=[[UINavigationController alloc] initWithRootViewController:accountsVC];
    accountsNav.navigationBar.tintColor=[UIColor blackColor];
    accountsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Accounts",@"") image:[UIImage imageNamed:@"accounts"] tag:0];
    
    ChatLogsViewController* chatLogVC = [[ChatLogsViewController alloc] init];
    UINavigationController* chatLogNav=[[UINavigationController alloc] initWithRootViewController:chatLogVC];
    chatLogNav.navigationBar.tintColor=[UIColor blackColor];
    chatLogNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Chat Logs",@"") image:[UIImage imageNamed:@"chatlog"] tag:0];
    
    SearchUsersViewController* searchUsersVC = [[SearchUsersViewController alloc] init];
    UINavigationController* searchUsersNav=[[UINavigationController alloc] initWithRootViewController:searchUsersVC];
    searchUsersNav.navigationBar.tintColor=[UIColor blackColor];
    searchUsersNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Search Users",@"") image:[UIImage imageNamed:@"search"] tag:0];
    
    GroupChatViewController* groupChatVC = [[GroupChatViewController alloc] init];
    UINavigationController* groupChatNav=[[UINavigationController alloc] initWithRootViewController:groupChatVC];
    groupChatNav.navigationBar.tintColor=[UIColor blackColor];
    groupChatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Group Chat",@"") image:[UIImage imageNamed:@"joingroup"] tag:0];
    
    HelpViewController* helpVC = [[HelpViewController alloc] init];
    UINavigationController* helpNav=[[UINavigationController alloc] initWithRootViewController:helpVC];
    helpNav.navigationBar.tintColor=[UIColor blackColor];
    helpNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Help",@"") image:[UIImage imageNamed:@"help"] tag:0];
    
    AboutViewController* aboutVC = [[AboutViewController alloc] init];
    UINavigationController* aboutNav=[[UINavigationController alloc] initWithRootViewController:aboutVC];
    aboutNav.navigationBar.tintColor=[UIColor blackColor];
    aboutNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"About",@"") image:[UIImage imageNamed:@"about"] tag:0];
    
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        
        _chatNav=[[UINavigationController alloc] initWithRootViewController:contactsVC];
        _chatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Contacts",@"") image:[UIImage imageNamed:@"Buddies"] tag:0];
        
        _tabBarController.viewControllers=[NSArray arrayWithObjects:_chatNav,activeChatNav, settingsNav,  accountsNav, chatLogNav, groupChatNav, searchUsersNav, helpNav, aboutNav, nil];
        
        self.window.rootViewController=_tabBarController;
        
    }
    else
    {
        
        //this is a dummy nav controller not really used for anything
        UINavigationController* navigationControllerContacts=[[UINavigationController alloc] initWithRootViewController:contactsVC];
        navigationControllerContacts.navigationBar.tintColor=[UIColor blackColor];
        
        _chatNav=activeChatNav;
        _splitViewController=[[UISplitViewController alloc] init];
        self.window.rootViewController=_splitViewController;
        
        _tabBarController.viewControllers=[NSArray arrayWithObjects: activeChatNav,  settingsNav, accountsNav, chatLogNav, groupChatNav, searchUsersNav,  helpNav, aboutNav, nil];
        
        _splitViewController.viewControllers=[NSArray arrayWithObjects:navigationControllerContacts, _tabBarController,nil];
        _splitViewController.delegate=self;
    }
    
    _chatNav.navigationBar.tintColor=[UIColor blackColor];
    _tabBarController.moreNavigationController.navigationBar.tintColor=[UIColor blackColor];
    
    [self.window makeKeyAndVisible];
}

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
 [self createRootInterface];

    //rating
    [Appirater setAppId:@"317711500"];
    [Appirater setDaysUntilPrompt:5];
    [Appirater setUsesUntilPrompt:10];
    [Appirater setSignificantEventsUntilPrompt:5];
    [Appirater setTimeBeforeReminding:2];
    //[Appirater setDebug:YES];
    [Appirater appLaunched:YES];
    
    [[[Reachability alloc] init] startNotifer];
    
    
}

#pragma mark splitview controller delegate
- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    return NO;
}

@end

