//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MonalAppDelegate.h"
#import "ContactsViewController.h"

@implementation MonalAppDelegate


- (void)applicationDidFinishLaunching:(UIApplication *)application
{
    
    self.window=[[UIWindow alloc] init];
    self.window.screen=[UIScreen mainScreen];

    _tabBarController=[[UITabBarController alloc] init];
    ContactsViewController* contactsVC = [[ContactsViewController alloc] init];
    
 if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
 {
     
     _navigationController=[[UINavigationController alloc] initWithRootViewController:contactsVC];
     _navigationController.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Contacts",@"") image:nil tag:0];
     _tabBarController.viewControllers=[NSArray arrayWithObjects:_navigationController, nil];
    
     _navigationController.navigationBarHidden=NO;
    self.window.rootViewController=_tabBarController;
     
 }
 else
 {
     
     UINavigationController* navigationControllerContacts=[[UINavigationController alloc] initWithRootViewController:contactsVC];
     
     _navigationController=[[UINavigationController alloc] init];
     _splitViewController=[[UISplitViewController alloc] init];
     self.window.rootViewController=_splitViewController;
     _splitViewController.viewControllers=[NSArray arrayWithObjects:navigationControllerContacts, _navigationController,nil];
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

