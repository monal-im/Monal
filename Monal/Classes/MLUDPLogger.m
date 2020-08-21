//
//  MLUDPLogger.m
//  monalxmpp
//
//  Created by Thilo Molitor on 17.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//  Based on this gist: https://gist.github.com/ratulSharker/3b6bce0debe77fd96344e14566b23e06
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import "MLUDPLogger.h"
#import "HelperTools.h"

#define IP      "192.168.11.3"
#define PORT    5555


@interface MLUDPLogger ()
{
    NSData* _addr;
    CFSocketRef _cfsocketout;
}
@end


@implementation MLUDPLogger

-(void) didAddLogger
{
    _cfsocketout = CFSocketCreate(
        kCFAllocatorDefault,
        PF_INET,
        SOCK_DGRAM,
        IPPROTO_UDP,
        kCFSocketNoCallBack,
        NULL,
        NULL
    );
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len            = sizeof(addr);
    addr.sin_family         = AF_INET;
    addr.sin_port           = htons(PORT);
    addr.sin_addr.s_addr    = inet_addr(IP);
    _addr = [NSData dataWithBytes:(const UInt8*)&addr length:sizeof(addr)];
}

-(void) willRemoveLogger
{
}

-(void) logMessage:(DDLogMessage*) logMessage
{
    NSString* logMsg = logMessage.message;
    if(self->_logFormatter)
        logMsg = [NSString stringWithFormat:@"%@\n", [self->_logFormatter formatLogMessage:logMessage]];
    NSDictionary* msgDict = @{
        @"formattedMessage": logMsg,
        @"message": logMessage.message,
        @"level": [NSNumber numberWithInteger:logMessage.level],
        @"flag": [NSNumber numberWithInteger:logMessage.flag],
        @"context": [NSNumber numberWithInteger:logMessage.context],
        @"file": logMessage.file,
        @"fileName": logMessage.fileName,
        @"function": logMessage.function,
        @"line": [NSNumber numberWithInteger:logMessage.line],
        @"tag": logMessage.tag ? logMessage.tag : [NSNull null],
        @"options": [NSNumber numberWithInteger:logMessage.options],
        @"timestamp": [[[NSISO8601DateFormatter alloc] init] stringFromDate:logMessage.timestamp],
        @"threadID": logMessage.threadID, // ID as it appears in NSLog calculated from the machThreadID
        @"threadName": logMessage.threadName,
        @"queueLabel": logMessage.queueLabel,
        @"qos": [NSNumber numberWithInteger:logMessage.qos]
    };
    NSError* writeError = nil; 
    NSData* data = [NSJSONSerialization dataWithJSONObject:msgDict options:NSJSONWritingPrettyPrinted error:&writeError];
    if(writeError)
    {
        NSLog(@"MLUDPLogger json encode error: %@", writeError);
        return;
    }
    //you have to comment the following line to send raw json log data
    data = [logMsg dataUsingEncoding:NSUTF8StringEncoding];
    CFSocketError error = CFSocketSendData(_cfsocketout, (__bridge CFDataRef)_addr, (__bridge CFDataRef)data, 0);
    if(error)
        NSLog(@"MLUDPLogger CFSocketSendData error: %ld", (long)error);
}

@end
