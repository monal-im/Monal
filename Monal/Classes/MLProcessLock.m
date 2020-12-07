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
    DDLogVerbose(@"Pinging %@", processName);
    [[IPC sharedInstance] sendMessage:@"MLProcessLock.ping" withData:nil to:processName withResponseHandler:^(NSDictionary* response) {
        DDLogVerbose(@"Got ping response from %@", processName);
        //wake up other thread
        [condition signal];
    }];
    //wait for response blocking this thread for 1 second
    BOOL timedOut = ![condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    DDLogVerbose(@"checkRemoteRunning:%@ returning %@", processName, !timedOut ? @"YES" : @"NO");
    return !timedOut;
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
