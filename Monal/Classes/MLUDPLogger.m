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
#import <CommonCrypto/CommonDigest.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <zlib.h>
#import "MLUDPLogger.h"
#import "HelperTools.h"
#import "AESGcm.h"


@interface MLUDPLogger ()
{
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
}

-(void) willRemoveLogger
{
}

//code taken from here: https://stackoverflow.com/a/11389847/3528174
-(NSData*) gzipDeflate:(NSData*) data
{
    if ([data length] == 0) return data;

    z_stream strm;

    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.total_out = 0;
    strm.next_in=(Bytef *)[data bytes];
    strm.avail_in = (unsigned int)[data length];

    // Compresssion Levels:
    //   Z_NO_COMPRESSION
    //   Z_BEST_SPEED
    //   Z_BEST_COMPRESSION
    //   Z_DEFAULT_COMPRESSION

    if (deflateInit2(&strm, Z_BEST_COMPRESSION, Z_DEFLATED, (15+16), 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;

    NSMutableData *compressed = [NSMutableData dataWithLength:16384];  // 16K chunks for expansion

    do {

        if (strm.total_out >= [compressed length])
            [compressed increaseLengthBy: 16384];

        strm.next_out = [compressed mutableBytes] + strm.total_out;
        strm.avail_out = (unsigned int)([compressed length] - strm.total_out);

        deflate(&strm, Z_FINISH);  

    } while (strm.avail_out == 0);

    deflateEnd(&strm);

    [compressed setLength: strm.total_out];
    return [NSData dataWithData:compressed];
}

-(void) logMessage:(DDLogMessage*) logMessage
{
    //early return if deactivated
    if(![[HelperTools defaultsDB] boolForKey: @"udpLoggerEnabled"])
        return;
    
    //calculate formatted log message
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
        @"tag": logMessage.representedObject ? logMessage.representedObject : [NSNull null],
        @"options": [NSNumber numberWithInteger:logMessage.options],
        @"timestamp": [[[NSISO8601DateFormatter alloc] init] stringFromDate:logMessage.timestamp],
        @"threadID": logMessage.threadID,
        @"threadName": logMessage.threadName,
        @"queueLabel": logMessage.queueLabel,
        @"qos": [NSNumber numberWithInteger:logMessage.qos]
    };
    NSError* writeError = nil; 
    NSData* rawData = [NSJSONSerialization dataWithJSONObject:msgDict options:NSJSONWritingPrettyPrinted error:&writeError];
    if(writeError)
    {
        NSLog(@"MLUDPLogger json encode error: %@", writeError);
        return;
    }
    
    //you have to uncomment the following line to send only the formatted logline
    //rawData = [logMsg dataUsingEncoding:NSUTF8StringEncoding];
    
    //compress data to account for udp size limits
    rawData = [self gzipDeflate:rawData];
    
    //hash raw key string with sha256 to get the correct 256 bit length needed for AES-256
    //WARNING: THIS DOES NOT ENHANCE ENTROPY!! PLEASE MAKE SURE TO USE A KEY WITH PROPER ENTROPY!!
    NSData* rawKey = [[[HelperTools defaultsDB] stringForKey:@"udpLoggerKey"] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData* key = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(rawKey.bytes, (unsigned int)rawKey.length, key.mutableBytes);
    
    //encrypt rawData using the "derived" key (see warning above!)
    MLEncryptedPayload* payload = [AESGcm encrypt:rawData withKey:key];
    NSMutableData* data  = [NSMutableData dataWithData:payload.iv];
    [data appendData:payload.authTag];
    [data appendData:payload.body];
    
    //calculate remote addr
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len            = sizeof(addr);
    addr.sin_family         = AF_INET;
    addr.sin_port           = htons([[[HelperTools defaultsDB] stringForKey:@"udpLoggerPort"] integerValue]);
    addr.sin_addr.s_addr    = inet_addr([[[HelperTools defaultsDB] stringForKey:@"udpLoggerHostname"] UTF8String]);
    
    if(!CFSocketIsValid(_cfsocketout))
    {
        CFSocketInvalidate(_cfsocketout);       //just to make sure
        //release old socket object and create new one
        CFRelease(_cfsocketout);
        _cfsocketout = CFSocketCreate(
            kCFAllocatorDefault,
            PF_INET,
            SOCK_DGRAM,
            IPPROTO_UDP,
            kCFSocketNoCallBack,
            NULL,
            NULL
        );
    }
    //send log via udp
    CFSocketError error = CFSocketSendData(_cfsocketout, (__bridge CFDataRef)[NSData dataWithBytes:(const UInt8*)&addr length:sizeof(addr)], (__bridge CFDataRef)data, 0);
    if(error)
        NSLog(@"MLUDPLogger CFSocketSendData error: %ld", (long)error);
}

@end
