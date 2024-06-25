//
//  MLDelayableTimer.h
//  monalxmpp
//
//  Created by Thilo Molitor on 24.06.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef MLDelayableTimer_h
#define MLDelayableTimer_h

NS_ASSUME_NONNULL_BEGIN

@class MLDelayableTimer;
typedef void (^monal_timer_block_t)(MLDelayableTimer* _Nonnull) NS_SWIFT_UNAVAILABLE("To be redefined in swift.");

@interface MLDelayableTimer : NSObject

-(instancetype) initWithHandler:(monal_timer_block_t) handler andCancelHandler:(monal_timer_block_t _Nullable) cancelHandler timeout:(NSTimeInterval) timeout tolerance:(NSTimeInterval) tolerance andDescription:(NSString* _Nullable) description;

-(void) start;
-(void) trigger;
-(void) pause;
-(void) resume;
-(void) cancel;

@end

NS_ASSUME_NONNULL_END

#endif /* MLDelayableTimer_h */
