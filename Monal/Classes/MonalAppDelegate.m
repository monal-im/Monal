//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MonalAppDelegate.h"

@implementation MonalAppDelegate


- (void)applicationDidFinishLaunching:(UIApplication *)application
{
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.screen=[UIScreen mainScreen];
    
   
    _tabBarController=[[UITabBarController alloc] init];
  
    
 if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
 {
     _navigationController=[[UINavigationController alloc] initWithRootViewController:_tabBarController];
    self.window.rootViewController=_navigationController;
 }
 else
 {
     _navigationController=[[UINavigationController alloc] init];
     _splitViewController=[[UISplitViewController alloc] init];
     self.window.rootViewController=_splitViewController;
     _splitViewController.viewControllers=[NSArray arrayWithObjects:_navigationController,_tabBarController,nil];
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

