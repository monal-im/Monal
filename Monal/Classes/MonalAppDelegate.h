//
//  SworIMAppDelegate.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MLConstants.h"

@import UIKit;
@import PushKit;
@import CallKit;
@import UserNotifications;
@import WebRTC;

@class ActiveChatsViewController;
@class MLContact;

@interface MonalAppDelegate : UIResponder <UIApplicationDelegate, UNUserNotificationCenterDelegate, PKPushRegistryDelegate, CXProviderDelegate>

@property (nonatomic, strong) UIWindow* _Nullable window;
@property (nonatomic, weak) ActiveChatsViewController* _Nullable activeChats;
@property (nonatomic, strong) CXProvider* _Nullable cxprovider;

-(void) updateUnread;
-(void) handleXMPPURL:(NSURL* _Nonnull) url;
-(void) openChatOfContact:(MLContact* _Nullable) contact;
-(void) openChatOfContact:(MLContact* _Nullable) contact withCompletion:(monal_id_block_t _Nullable) completion;

@end

