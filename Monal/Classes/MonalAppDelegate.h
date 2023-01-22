//
//  SworIMAppDelegate.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@import UIKit;
@import UserNotifications;

@class ActiveChatsViewController;
@class MLContact;
@class MLVoIPProcessor;

@interface MonalAppDelegate : UIResponder <UIApplicationDelegate, UNUserNotificationCenterDelegate>

@property (nonatomic, strong) UIWindow* _Nullable window;
@property (nonatomic, weak) ActiveChatsViewController* _Nullable activeChats;
@property (nonatomic, strong) MLVoIPProcessor* _Nullable voipProcessor;

-(UIViewController*) getTopViewController;
-(void) updateUnread;
-(void) handleXMPPURL:(NSURL* _Nonnull) url;
-(void) openChatOfContact:(MLContact* _Nullable) contact;
-(void) openChatOfContact:(MLContact* _Nullable) contact withCompletion:(monal_id_block_t _Nullable) completion;
-(void) incomingWakeupWithCompletionHandler:(void (^)(UIBackgroundFetchResult result)) completionHandler;

@end

NS_ASSUME_NONNULL_END
