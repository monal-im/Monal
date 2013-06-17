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
#import "AccountsViewController.h"
#import "ChatLogsViewController.h"
#import "GroupChatViewController.h"
#import "SearchUsersViewController.h"
#import "HelpViewController.h"
#import "AboutViewController.h"

@implementation MonalAppDelegate


- (void)applicationDidFinishLaunching:(UIApplication *)application
{
    
    self.window=[[UIWindow alloc] init];
    self.window.screen=[UIScreen mainScreen];

    _tabBarController=[[UITabBarController alloc] init];
    ContactsViewController* contactsVC = [[ContactsViewController alloc] init];
    
     ActiveChatsViewController* activeChatsVC = [[ActiveChatsViewController alloc] init];
    UINavigationController* activeChatNav=[[UINavigationController alloc] initWithRootViewController:activeChatsVC];
    
     AccountsViewController* accountsVC = [[AccountsViewController alloc] init];
    UINavigationController* accountsNav=[[UINavigationController alloc] initWithRootViewController:accountsVC];
   
     ChatLogsViewController* chatLogVC = [[ChatLogsViewController alloc] init];
    UINavigationController* chatLogNav=[[UINavigationController alloc] initWithRootViewController:chatLogVC];
    
     GroupChatViewController* groupChatVC = [[GroupChatViewController alloc] init];
    UINavigationController* groupChatNav=[[UINavigationController alloc] initWithRootViewController:groupChatVC];
    
     HelpViewController* helpVC = [[HelpViewController alloc] init];
    UINavigationController* helpNav=[[UINavigationController alloc] initWithRootViewController:helpVC];
    
     AboutViewController* aboutVC = [[AboutViewController alloc] init];
    UINavigationController* aboutNav=[[UINavigationController alloc] initWithRootViewController:aboutVC];
    
    
 if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
 {
     
     _chatNav=[[UINavigationController alloc] initWithRootViewController:contactsVC];
     _chatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Contacts",@"") image:[UIImage imageNamed:@"Buddies"] tag:0];
     
     
     _tabBarController.viewControllers=[NSArray arrayWithObjects:_chatNav,activeChatNav,accountsNav, chatLogNav, groupChatNav,  helpNav, aboutNav, nil];
    
    self.window.rootViewController=_tabBarController;
     
 }
 else
 {
     
     //this is a dummy nav controllre not really used for anything
     UINavigationController* navigationControllerContacts=[[UINavigationController alloc] initWithRootViewController:contactsVC];
     
     _chatNav=[[UINavigationController alloc] init];
     _splitViewController=[[UISplitViewController alloc] init];
     self.window.rootViewController=_splitViewController;
     
     _tabBarController.viewControllers=[NSArray arrayWithObjects:_chatNav, activeChatNav,accountsNav, chatLogNav, groupChatNav,  helpNav, aboutNav, nil];
     
     _splitViewController.viewControllers=[NSArray arrayWithObjects:navigationControllerContacts, _chatNav,nil];
     _splitViewController.delegate=self; 
 }
    
   
    [self.window makeKeyAndVisible];
    
}

#pragma mark splitview controller delegate
- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    return NO;
}

@end

