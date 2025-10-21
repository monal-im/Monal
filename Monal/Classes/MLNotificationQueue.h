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

+(instancetype) currentQueue;
-(void) postNotificationName:(NSNotificationName) notificationName object:(id _Nullable) notificationObject userInfo:(id _Nullable) notificationUserInfo NS_SWIFT_NAME(post(name:object:userInfo:));
-(void) postNotificationName:(NSNotificationName) notificationName object:(id _Nullable) notificationObject NS_SWIFT_NAME(post(name:object:));
-(void) postNotification:(NSNotification* _Nonnull) notification NS_SWIFT_NAME(post(name:));

@property (readonly, strong) NSString* name;
-(NSString*) description;

@end

NS_ASSUME_NONNULL_END
