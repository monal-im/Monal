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
    __block NSCondition* condition = [[NSCondition alloc] init];
    __block BOOL response_received = NO;
    
    //lock condition object (needs to be locked for [condition signal] and [condition waitUntilDate:] to work correctly)
    [condition lock];
    
    //send out ping and handle response
    DDLogVerbose(@"Pinging %@", processName);
    [[IPC sharedInstance] sendMessage:@"MLProcessLock.ping" withData:nil to:processName withResponseHandler:^(NSDictionary* response) {
        DDLogVerbose(@"Got ping response from %@: %@", processName, response);
        //lock condition, change response_received to YES and wake up other thread
        [condition lock];
        response_received = YES;
        [condition signal];
        [condition unlock];
    }];
    
    //wait for response blocking this thread for 1 second
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while(!response_received && [timeout timeIntervalSinceNow] > 0)
        [condition waitUntilDate:timeout];
    
    //get state and unlock condition object
    BOOL remote_running = response_received;
    [condition unlock];
    
    DDLogVerbose(@"checkRemoteRunning:%@ returning %@", processName, remote_running ? @"YES" : @"NO");
    return remote_running;
}

+(void) waitForRemoteStartup:(NSString*) processName
{
    while(![[NSThread currentThread] isCancelled] && ![self checkRemoteRunning:processName])
        usleep(50000);      //checkRemoteRunning did already wait for its timeout, don't wait too long here
}

+(void) waitForRemoteTermination:(NSString*) processName
{
    while(![[NSThread currentThread] isCancelled] && [self checkRemoteRunning:processName])
        usleep(1000000);    //checkRemoteRunning did not wait for its timeout, wait here
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

@end
