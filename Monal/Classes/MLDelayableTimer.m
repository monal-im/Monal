//
//  MLDelayableTimer.m
//  monalxmpp
//
//  Created by Thilo Molitor on 24.06.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import "MLConstants.h"
#import "HelperTools.h"
#import "MLDelayableTimer.h"

@interface MLDelayableTimer()
{
    NSTimer* _wrappedTimer;
    monal_timer_block_t _Nullable _cancelHandler;
    NSString* _Nullable _description;
    NSTimeInterval _timeout;
    NSTimeInterval _remainingTime;
    NSUUID* _uuid;
}
@end

@implementation MLDelayableTimer

-(instancetype) initWithHandler:(monal_timer_block_t) handler andCancelHandler:(monal_timer_block_t _Nullable) cancelHandler timeout:(NSTimeInterval) timeout tolerance:(NSTimeInterval) tolerance andDescription:(NSString* _Nullable) description
{
    self = [super init];
    _wrappedTimer = [NSTimer timerWithTimeInterval:timeout repeats:NO block:^(NSTimer* _) {
        handler(self);
    }];
    _cancelHandler = cancelHandler;
    _timeout = timeout;
    _wrappedTimer.tolerance = tolerance;
    _description = description;
    _remainingTime = 0;
    _uuid = [NSUUID UUID];
    return self;
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"%@(%G|%G) %@", [_uuid UUIDString], _timeout, _wrappedTimer.fireDate.timeIntervalSinceNow, _description];
}

-(void) start
{
    @synchronized(self) {
        if(!_wrappedTimer.valid)
        {
            showErrorOnAlpha(nil, @"Could not start already fired timer: %@", self);
            return;
        }
        DDLogDebug(@"Starting timer: %@", self);
        [[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierTimer] addTimer:_wrappedTimer forMode:NSRunLoopCommonModes];
    }
}

-(void) trigger
{
    @synchronized(self) {
        if(!_wrappedTimer.valid)
        {
            showErrorOnAlpha(nil, @"Could not trigger already fired timer: %@", self);
            return;
        }
        DDLogDebug(@"Triggering timer: %@", self);
        [_wrappedTimer fire];
    }
}

-(void) pause
{
    @synchronized(self) {
        if(!_wrappedTimer.valid)
        {
            DDLogWarn(@"Tried to pause already fired timer: %@", self);
            return;
        }
        DDLogDebug(@"Pausing timer: %@", self);
        _remainingTime = _wrappedTimer.fireDate.timeIntervalSinceNow;
        _wrappedTimer.fireDate = NSDate.distantFuture;      //postpone timer virtually indefinitely
    }
}

-(void) resume
{
    @synchronized(self) {
        if(!_wrappedTimer.valid)
        {
            DDLogWarn(@"Tried to resume already fired timer: %@", self);
            return;
        }
        DDLogDebug(@"Resuming timer: %@", self);
        _wrappedTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:_remainingTime];
        _remainingTime = 0;
    }
}

-(void) cancel
{
    @synchronized(self) {
        if(!_wrappedTimer.valid)
        {
            DDLogWarn(@"Tried to cancel already fired timer: %@", self);
            return;
        }
        DDLogDebug(@"Canceling timer: %@", self);
        [self invalidate];
    }
    _cancelHandler(self);
}

-(void) invalidate
{
    @synchronized(self) {
        if(!_wrappedTimer.valid)
        {
            DDLogWarn(@"Could not invalidate already invalid timer: %@", self);
            return;
        }
        //DDLogVerbose(@"Invalidating timer: %@", self);
        [_wrappedTimer invalidate];
    }
}

@end
