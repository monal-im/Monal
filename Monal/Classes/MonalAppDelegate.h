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
#import "ActiveChatsViewController.h"

@import UserNotifications;


@interface MonalAppDelegate : UIResponder <UIApplicationDelegate, PKPushRegistryDelegate, UNUserNotificationCenterDelegate >

@property (nonatomic, weak) ActiveChatsViewController* activeChats;
@property (nonatomic, strong) DDFileLogger *fileLogger;

-(void) updateUnread;

@end

