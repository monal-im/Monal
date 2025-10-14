//
//  MLDelayableTimer.m
//  monalxmpp
//
//  Created by Thilo Molitor on 24.06.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import <monalxmpp/MLConstants.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLDelayableTimer.h>

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
        //scheduling and unscheduling of a timer must be done from the same thread --> use our runloop
        [self scheduleBlockInRunLoop:^{
            [[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierTimer] addTimer:self->_wrappedTimer forMode:NSRunLoopCommonModes];
        }];
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
        [self scheduleBlockInRunLoop:^{
            [self->_wrappedTimer fire];
        }];
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
        NSTimeInterval remaining = _wrappedTimer.fireDate.timeIntervalSinceNow;
        if(remaining < 0.001)
        {
            DDLogWarn(@"Tried to pause timer the exact second its firing: %@", self);
            return;
        }
        DDLogDebug(@"Pausing timer: %@", self);
        _wrappedTimer.fireDate = NSDate.distantFuture;      //postpone timer virtually indefinitely
        _remainingTime = remaining;
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
        if(_remainingTime == 0)
        {
            DDLogWarn(@"Tried to resume non-paused timer: %@", self);
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
        [self scheduleBlockInRunLoop:^{
            if(self->_cancelHandler != nil)
                self->_cancelHandler(self);
        }];
    }
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
        //scheduling and unscheduling of a timer must be done from the same thread --> use our runloop
        [self scheduleBlockInRunLoop:^{
            [self->_wrappedTimer invalidate];
        }];
    }
}

-(void) scheduleBlockInRunLoop:(monal_void_block_t) block
{
    NSRunLoop* runLoop = [HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierTimer];
//     NSCondition* condition = [NSCondition new];
//     [condition lock];
    CFRunLoopPerformBlock([runLoop getCFRunLoop], (__bridge CFStringRef)NSDefaultRunLoopMode, ^{
//         [condition lock];
        block();
//         [condition signal];
//         [condition unlock];
    });
    CFRunLoopWakeUp([runLoop getCFRunLoop]);    //trigger wakeup of runloop to execute the block as soon as possible
//     //wait for our block to finish executing
//     [condition wait];
//     [condition unlock];
}

@end
