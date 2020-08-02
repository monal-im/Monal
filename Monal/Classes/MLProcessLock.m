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
//#import "IPC.h"


@interface MLProcessLock()

@end

@implementation MLProcessLock

+(BOOL) checkRemoteRunning:(NSString*) processName
{
//     NSDate timeout = [[NSDate date] dateByAddingTimeInterval:1];        //1 second timeout
//     NSCondition* waiter = [[NSCondition alloc] init];
//     [[IPC sharedInstance] sendMessage:@"ping" withData:nil to:processName withResponseHandler:^(NSDictionary* response) {
//         //wake up other thread
//         [waiter lock];
//         [waiter signal];
//         [waiter unlock];
//     }];
//     //wait for response blocking this thread for ~1 second
//     [waiter lock];
//     BOOL timedOut = [waiter waitUntilDate:timeout];
//     [waiter unlock];
//     return timedOut;
    return NO;
}

+(void) waitForRemoteStartup:(NSString*) processName
{
//     while(![self checkRemoteRunning:processName])
//         ;
}

+(void) waitForRemoteTermination:(NSString*) processName
{
//     while([self checkRemoteRunning:processName])
//         ;
}

@end
