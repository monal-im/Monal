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
#import <sys/socket.h>
//#import <sys/sysctl.h>
#import <sys/un.h>
#import "MLProcessLock.h"
#import "MLConstants.h"


static CFDataRef callback(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info)
{
    NSString* incoming = [[NSString alloc] initWithData:(__bridge NSData*)data encoding:NSUTF8StringEncoding];
    if([@"ping" isEqualToString:incoming])
        return (__bridge CFDataRef)[@"pong" dataUsingEncoding:NSUTF8StringEncoding];
    DDLogWarn(@"Unknown mach message: '%@'", incoming);
    return (__bridge CFDataRef)[@"unknown" dataUsingEncoding:NSUTF8StringEncoding];
}

@interface MLProcessLock()
{
    CFMessagePortRef _port;
}

@end

@implementation MLProcessLock

+(BOOL) checkRemoteRunning:(NSString*) processName
{
    NSString* portname = [NSString stringWithFormat:@"%@.%@", kAppGroup, processName];
    CFStringRef port_name = (__bridge CFStringRef)portname;
    CFMessagePortRef port = CFMessagePortCreateRemote(kCFAllocatorDefault, port_name);
    if(port == NULL)
    {
        DDLogVerbose(@"Creating mach remote port failed");
        DDLogInfo(@"MLProcessLock remote '%@' is NOT running", processName);
        return NO;
    }
    
    SInt32 messageIdentifier = 1;
    CFDataRef messageData = (__bridge CFDataRef)[@"ping" dataUsingEncoding:NSUTF8StringEncoding];

    CFDataRef response = NULL;
    SInt32 status = CFMessagePortSendRequest(port, messageIdentifier, messageData, 2000, 2000, kCFRunLoopDefaultMode, &response);
    if(status != kCFMessagePortSuccess)
    {
        DDLogVerbose(@"Sending mach message failed: %ul", (long)status);
        DDLogInfo(@"MLProcessLock remote '%@' is NOT running", processName);
        return NO;
    }
    
    NSString* incoming = [[NSString alloc] initWithData:(__bridge NSData*)response encoding:NSUTF8StringEncoding];
    DDLogInfo(@"MLProcessLock remote '%@' IS running: %@", processName, incoming);
    return YES;
}

+(void) waitForRemoteStartup:(NSString*) processName
{
    NSString* portname = [NSString stringWithFormat:@"%@.%@", kAppGroup, processName];
    CFStringRef port_name = (__bridge CFStringRef)portname;
    while(YES)
    {
        CFMessagePortRef port = CFMessagePortCreateRemote(kCFAllocatorDefault, port_name);
        if(port == NULL)
        {
            DDLogVerbose(@"Creating mach remote port failed");
            usleep(250000);
            continue;
        }
        SInt32 messageIdentifier = 2;
        CFDataRef messageData = (__bridge CFDataRef)[@"ping" dataUsingEncoding:NSUTF8StringEncoding];
        CFDataRef response = NULL;
        SInt32 status = CFMessagePortSendRequest(port, messageIdentifier, messageData, 500, 500, kCFRunLoopDefaultMode, &response);
        if(status != kCFMessagePortSuccess)
        {
            DDLogVerbose(@"Sending mach message failed: %ul", (long)status);
            usleep(250000);
            continue;
        }
        NSString* incoming = [[NSString alloc] initWithData:(__bridge NSData*)response encoding:NSUTF8StringEncoding];
        DDLogInfo(@"MLProcessLock remote '%@' is now running: %@", processName, incoming);
        break;
    }
}

+(void) waitForRemoteTermination:(NSString*) processName
{
    NSString* portname = [NSString stringWithFormat:@"%@.%@", kAppGroup, processName];
    CFStringRef port_name = (__bridge CFStringRef)portname;
    while(YES)
    {
        CFMessagePortRef port = CFMessagePortCreateRemote(kCFAllocatorDefault, port_name);
        if(port == NULL)
        {
            DDLogVerbose(@"Creating mach remote port failed");
            DDLogInfo(@"MLProcessLock remote '%@' is now stopped", processName);
            break;
        }
        SInt32 messageIdentifier = 3;
        CFDataRef messageData = (__bridge CFDataRef)[@"ping" dataUsingEncoding:NSUTF8StringEncoding];
        CFDataRef response = NULL;
        SInt32 status = CFMessagePortSendRequest(port, messageIdentifier, messageData, 2000, 2000, kCFRunLoopDefaultMode, &response);
        if(status != kCFMessagePortSuccess)
        {
            DDLogVerbose(@"Sending mach message failed: %ul", (long)status);
            DDLogInfo(@"MLProcessLock remote '%@' is now stopped", processName);
            break;
        }
        usleep(250000);
    }
}

-(id) initWithProcessName:(NSString*) processName
{
    [self runServerFor:processName];
    return self;
}

-(void) deinit
{
    DDLogInfo(@"Deallocating MLProcessLock");
    CFMessagePortInvalidate(_port);
}

-(void) runServerFor:(NSString*) processName
{
    NSString* portname = [NSString stringWithFormat:@"%@.%@", kAppGroup, processName];
    DDLogInfo(@"Configuring MLProcessLock mach port %@", portname);
    CFStringRef port_name = (__bridge CFStringRef)portname;
    _port = CFMessagePortCreateLocal(kCFAllocatorDefault, port_name, &callback, NULL, NULL);
    CFMessagePortSetDispatchQueue(_port, dispatch_get_main_queue());
}

@end
