//
//  SworIMAppDelegate.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Appirater.h"
#import "DataLayer.h"
#import "MLTabBarController.h"




@interface MonalAppDelegate : UIResponder <UIApplicationDelegate, UISplitViewControllerDelegate > {
    
    UIBackgroundTaskIdentifier _backgroundTask;
  
}

@property (nonatomic, strong) UIWindow* window;
@property (nonatomic, strong) UINavigationController* chatNav;
@property (nonatomic, strong) MLTabBarController* tabBarController;
@property (nonatomic, strong) UISplitViewController* splitViewController;


-(void) updateUnread;

@end

