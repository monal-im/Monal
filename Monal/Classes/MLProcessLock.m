//
//  MLProcessLock.m
//  monalxmpp
//
//  Created by Thilo Molitor on 26.07.20.
//  Loosely based on https://ddeville.me/2015/02/interprocess-communication-on-ios-with-berkeley-sockets/
//  and https://ddeville.me/2015/02/interprocess-communication-on-ios-with-mach-messages/
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLProcessLock.h"
#import "MLConstants.h"
#import "IPC.h"


@interface MLProcessLock()

@end

@implementation MLProcessLock

+(BOOL) checkRemoteRunning:(NSString*) processName
{
    //default timeout used by mainapp (appex uses a higher timeout)
    //EXPLANATION: the mainapp uses the main thread for UI stuff, which sometimes can block the main thread for more than 250ms
    //             --> that would make the ping *NOT* succeed and in turn erroneously tell the appex that the mainapp was not running
    //             the appex on the other side does not use its main thread --> a ping coming from the mainapp will almost always
    //             be answered in only a few milliseconds
    return [self checkRemoteRunning:processName withTimeout:0.250];
}

+(BOOL) checkRemoteRunning:(NSString*) processName withTimeout:(double) pingTimeout
{
    __block BOOL was_called_in_mainthread = [NSThread isMainThread];
    __block NSCondition* condition = [[NSCondition alloc] init];
    __block NSRunLoop* main_runloop = [NSRunLoop mainRunLoop];
    __block BOOL response_received = NO;
    
    //lock condition object (needs to be locked for [condition signal] and [condition waitUntilDate:] to work correctly)
    //the runloop-based waiting approach does use the lock embedded in this condition, too
    [condition lock];
    
    //send out ping and handle response
    DDLogDebug(@"Pinging %@", processName);
    [[IPC sharedInstance] sendMessage:@"MLProcessLock.ping" withData:nil to:processName withResponseHandler:^(NSDictionary* response) {
        //lock condition, change response_received to YES and wake up other thread
        [condition lock];
        DDLogDebug(@"Got ping response from %@: %@", processName, response);
        response_received = YES;
        //mainthreads need an extra wake up of their runloop while other threads can be woken up using our condition variable
        if(was_called_in_mainthread)
            //this will stop the innermost runloop invocation (done in the while loop below), not the entire runloop
            CFRunLoopStop([main_runloop getCFRunLoop]);
        else
            [condition signal];
        [condition unlock];
    }];
    
    //wait for response blocking this thread for pingTimeout seconds
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow:pingTimeout];
    DDLogVerbose(@"Waiting for %f seconds...", (double)[timeout timeIntervalSinceNow]);
    //we have to repeate the condition wait/runloop polling until we time out if the wakeup was not due to a received ping response
    while(!response_received && [timeout timeIntervalSinceNow] > 0)
    {
        if(was_called_in_mainthread)
        {
            //poll runloop of main thread until the next event occurs or the polling call times out
            //(that can be a received ping that force-stops this call or any other runloop timer/port/... event)
            //the unlock-wait-lock triplet resembles exactly what the condition wait is doing internally
            [condition unlock];
            [main_runloop runMode:[main_runloop currentMode] beforeDate:timeout];
            [condition lock];
            DDLogVerbose(@"Runloop poll returned...");
        }
        else
        {
            [condition waitUntilDate:timeout];
            DDLogVerbose(@"Condition wait returned...");
        }
        if(!response_received && [timeout timeIntervalSinceNow] > 0)
            DDLogVerbose(@"Waiting again for the remaing %f seconds...", (double)[timeout timeIntervalSinceNow]);
    }
    DDLogVerbose(@"waiting returned: response_received=%@, [timeout timeIntervalSinceNow]=%f", response_received ? @"YES" : @"NO", (double)[timeout timeIntervalSinceNow]);
    
    //get state and unlock condition object
    BOOL remote_running = response_received;
    [condition unlock];
    
    DDLogDebug(@"checkRemoteRunning:%@ returning %@", processName, remote_running ? @"YES" : @"NO");
    return remote_running;
}

+(void) waitForRemoteStartup:(NSString*) processName
{
    [self waitForRemoteStartup:processName withLoopHandler:nil];
}

+(void) waitForRemoteStartup:(NSString*) processName withLoopHandler:(monal_void_block_t _Nullable) handler
{
    //we will wait almost 2 seconds (the IPC message timeout)
    while(![[NSThread currentThread] isCancelled] && ![self checkRemoteRunning:processName withTimeout:1.5])
    {
        if(handler)
            handler();
        [self sleep:0.050];     //checkRemoteRunning did already wait for its timeout, because its ping was not answered --> don't wait too long here
    }
}

+(void) waitForRemoteTermination:(NSString*) processName
{
    [self waitForRemoteTermination:processName withLoopHandler:nil];
}

+(void) waitForRemoteTermination:(NSString*) processName withLoopHandler:(monal_void_block_t _Nullable) handler
{
    //wait 500ms (in case this method will be used by the appex to wait for the mainapp in the future)
    //--> we want to make sure the mainapp *really* isn't running anymore while still not waiting too long
    //(this 500ms is a tradeoff, a longer timeout would be safer but could result in long mainapp startup delays or startup kills by iOS)
    //see the explanation of checkRemoteRunning: for further details
    while(![[NSThread currentThread] isCancelled] && [self checkRemoteRunning:processName withTimeout:0.5])
    {
        if(handler)
            handler();
        [self sleep:0.250];    //checkRemoteRunning did not wait for its timeout, because its ping got answered --> wait here
    }
}

+(void) lock
{
    DDLogVerbose(@"Locking process...");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ping:) name:kMonalIncomingIPC object:nil];
}

+(void) unlock
{
    DDLogVerbose(@"Unlocking process...");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+(void) ping:(NSNotification*) notification
{
    NSDictionary* message = notification.userInfo;
    if([message[@"name"] isEqualToString:@"MLProcessLock.ping"])
    {
        DDLogVerbose(@"MLProcessLock responding to ping %@", message[@"id"]);
        [[IPC sharedInstance] respondToMessage:message withData:nil];
    }
}

+(void) sleep:(NSTimeInterval) time
{
    BOOL was_called_in_mainthread = [NSThread isMainThread];
    NSRunLoop* main_runloop = [NSRunLoop mainRunLoop];
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow:time];
    //we have to spin the runloop instead of simply sleeping to not miss incoming IPC messages
    //(pings coming from the appex for example)
    if(was_called_in_mainthread)
        while([timeout timeIntervalSinceNow] > 0)
            [main_runloop runMode:[main_runloop currentMode] beforeDate:timeout];
    else
        [NSThread sleepForTimeInterval:time];
}

@end
