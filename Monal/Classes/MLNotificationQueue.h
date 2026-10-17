//
//  MLNotificationQueue.h
//  Monal
//
//  Created by Thilo Molitor on 03.04.21.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLNotificationQueue : NSObject

+(void) queueNotificationsInBlock:(monal_void_block_t) block onQueue:(NSString*) queueName;
-(NSUInteger) flush;
-(NSUInteger) clear;

+(id) currentQueue;
-(void) postNotificationName:(NSNotificationName) notificationName object:(id _Nullable) notificationObject userInfo:(id _Nullable) notificationUserInfo;
-(void) postNotificationName:(NSNotificationName) notificationName object:(id _Nullable) notificationObject;
-(void) postNotification:(NSNotification* _Nonnull) notification;

@property (readonly, strong) NSString* name;
-(NSString*) description;

@end

NS_ASSUME_NONNULL_END
