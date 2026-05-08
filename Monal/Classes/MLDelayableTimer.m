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
}
@property (atomic, strong) NSTimer* wrappedTimer;
@property (atomic, strong, nullable) monal_timer_block_t cancelHandler;
@property (atomic, strong, nullable) NSString* descriptionSuffix;
@property (atomic) NSTimeInterval timeout;
@property (atomic) NSTimeInterval remainingTime;
@property (atomic, strong) NSUUID* uuid;
@end

@implementation MLDelayableTimer

-(instancetype) initWithHandler:(monal_timer_block_t) handler andCancelHandler:(monal_timer_block_t _Nullable) cancelHandler timeout:(NSTimeInterval) timeout tolerance:(NSTimeInterval) tolerance andDescription:(NSString* _Nullable) description
{
    self = [super init];
    self.wrappedTimer = [NSTimer timerWithTimeInterval:timeout repeats:NO block:^(NSTimer* _) {
        handler(self);
    }];
    self.cancelHandler = cancelHandler;
    self.timeout = timeout;
    self.wrappedTimer.tolerance = tolerance;
    self.descriptionSuffix = description;
    self.remainingTime = 0;
    self.uuid = [NSUUID UUID];
    return self;
}

-(void) dealloc
{
    //invalidate wrapped NSTimer
    [self invalidate];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"%@(%G|%G) %@", [self.uuid UUIDString], self.timeout, self.wrappedTimer.fireDate.timeIntervalSinceNow, self.descriptionSuffix];
}

-(void) start
{
    @synchronized(self) {
        if(!self.wrappedTimer.valid)
        {
            showErrorOnAlpha(nil, @"Could not start already fired timer: %@", self);
            return;
        }
        DDLogDebug(@"Starting timer: %@", self);
        //scheduling and unscheduling of a timer must be done from the same thread --> use our runloop
        [self scheduleBlockInRunLoop:^{
            [[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierTimer] addTimer:self.wrappedTimer forMode:NSRunLoopCommonModes];
        }];
    }
}

-(void) trigger
{
    @synchronized(self) {
        if(!self.wrappedTimer.valid)
        {
            showErrorOnAlpha(nil, @"Could not trigger already fired timer: %@", self);
            return;
        }
        DDLogDebug(@"Triggering timer: %@", self);
        [self scheduleBlockInRunLoop:^{
            [self.wrappedTimer fire];
        }];
    }
}

-(void) pause
{
    @synchronized(self) {
        if(!self.wrappedTimer.valid)
        {
            DDLogWarn(@"Tried to pause already fired timer: %@", self);
            return;
        }
        NSTimeInterval remaining = self.wrappedTimer.fireDate.timeIntervalSinceNow;
        if(remaining < self.wrappedTimer.tolerance)
        {
            DDLogWarn(@"Tried to pause timer the exact second its firing: %@", self);
            return;
        }
        self.wrappedTimer.fireDate = NSDate.distantFuture;      //postpone timer virtually indefinitely
        self.remainingTime = remaining;
        DDLogDebug(@"Paused timer: %@ (remaining time: %@)", self, @(self.remainingTime));
    }
}

-(void) resume
{
    @synchronized(self) {
        if(!self.wrappedTimer.valid)
        {
            DDLogWarn(@"Tried to resume already fired timer: %@", self);
            return;
        }
        if(self.remainingTime == 0)
        {
            DDLogWarn(@"Tried to resume non-paused timer: %@", self);
            return;
        }
        self.wrappedTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:self.remainingTime];
        self.remainingTime = 0;
        DDLogDebug(@"Resumed timer: %@ (remaining time: %@)", self, @(self.remainingTime));
    }
}

-(void) cancel
{
    @synchronized(self) {
        if(!self.wrappedTimer.valid)
        {
            DDLogWarn(@"Tried to cancel already fired timer: %@", self);
            return;
        }
        DDLogDebug(@"Canceling timer: %@", self);
        [self invalidate];
        [self scheduleBlockInRunLoop:^{
            if(self.cancelHandler != nil)
                self.cancelHandler(self);
        }];
    }
}

-(void) invalidate
{
    @synchronized(self) {
        if(!self.wrappedTimer.valid)
        {
            DDLogWarn(@"Could not invalidate already invalid timer: %@", self);
            return;
        }
        //DDLogVerbose(@"Invalidating timer: %@", self);
        //scheduling and unscheduling of a timer must be done from the same thread --> use our runloop
        [self scheduleBlockInRunLoop:^{
            [self.wrappedTimer invalidate];
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
