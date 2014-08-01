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

#import "DDLog.h"
#import "DDASLLogger.h"
#import "DDFileLogger.h"
#import "DDTTYLogger.h"




@interface MonalAppDelegate : UIResponder <UIApplicationDelegate, UISplitViewControllerDelegate >

@property (nonatomic, strong) UIWindow* window;
@property (nonatomic, strong) UINavigationController* chatNav;
@property (nonatomic, strong) MLTabBarController* tabBarController;
@property (nonatomic, strong) UISplitViewController* splitViewController;
@property (nonatomic, strong)  DDFileLogger *fileLogger;

-(void) updateUnread;

@end

