//
//  SworIMAppDelegate.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

@import UIKit;
@import PushKit;

#import "DataLayer.h"
#import "MLProcessLock.h"

@import UserNotifications;


#if !TARGET_OS_MACCATALYST
@interface MonalAppDelegate : UIResponder <UIApplicationDelegate, PKPushRegistryDelegate, UNUserNotificationCenterDelegate >
#else
@interface MonalAppDelegate : UIResponder <UIApplicationDelegate, UNUserNotificationCenterDelegate >
#endif

@property (nonatomic, strong) UIWindow* window;

-(void) updateUnread;
-(void) handleURL:(NSURL *) url;
-(void) setActiveChatsController: (UIViewController *) activeChats;

@end

