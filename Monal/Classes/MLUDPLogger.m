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
#import <Network/Network.h>
#import <zlib.h>
#import "MLUDPLogger.h"
#import "HelperTools.h"
#import "AESGcm.h"


static NSString* _processID;


@interface MLUDPLogger ()
{
    nw_connection_t _connection;
    u_int64_t _counter;
}
@end


@implementation MLUDPLogger

+(void) initialize
{
    u_int32_t i = arc4random();
    _processID = [HelperTools hexadecimalString:[NSData dataWithBytes:&i length:sizeof(i)]];
}

-(void) dealloc
{
}

-(void) didAddLogger
{
    //register freeze handler (this will create a new connection once unfrozen)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(prepareForFreeze:) name:kMonalWillBeFreezed object:nil];
}

-(void) willRemoveLogger
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

//code taken from here: https://stackoverflow.com/a/11389847/3528174
-(NSData*) gzipDeflate:(NSData*) data
{
    if([data length] == 0)
        return data;

    z_stream strm;

    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.total_out = 0;
    strm.next_in = (Bytef*)[data bytes];
    strm.avail_in = (unsigned int)[data length];

    // Compresssion Levels:
    //   Z_NO_COMPRESSION
    //   Z_BEST_SPEED
    //   Z_BEST_COMPRESSION
    //   Z_DEFAULT_COMPRESSION
    if(deflateInit2(&strm, Z_BEST_COMPRESSION, Z_DEFLATED, (15+16), 8, Z_DEFAULT_STRATEGY) != Z_OK)
        return nil;

    NSMutableData* compressed = [NSMutableData dataWithLength:16384];   // 16K chunks for expansion
    do {
        if(strm.total_out >= [compressed length])
            [compressed increaseLengthBy:16384];
        strm.next_out = [compressed mutableBytes] + strm.total_out;
        strm.avail_out = (unsigned int)([compressed length] - strm.total_out);
        deflate(&strm, Z_FINISH);  
    } while(strm.avail_out == 0);
    deflateEnd(&strm);

    [compressed setLength:strm.total_out];
    return compressed;
}

-(void) prepareForFreeze:(NSNotification*) notification
{
    _connection = NULL;
}

-(void) createConnectionIfNeeded
{
    if(_connection == NULL)
    {
        nw_endpoint_t endpoint = nw_endpoint_create_host([[[HelperTools defaultsDB] stringForKey:@"udpLoggerHostname"] cStringUsingEncoding:NSUTF8StringEncoding], [[[HelperTools defaultsDB] stringForKey:@"udpLoggerPort"] cStringUsingEncoding:NSUTF8StringEncoding]);
        nw_parameters_t parameters = nw_parameters_create_secure_udp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        
        _connection = nw_connection_create(endpoint, parameters);
        nw_connection_set_queue(_connection, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
        nw_connection_start(_connection);
    }
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
    
    _counter++;
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
        @"qos": [NSNumber numberWithInteger:logMessage.qos],
        @"_counter": [NSNumber numberWithUnsignedLongLong:_counter],
        @"_processID": _processID,
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
    
    //send log via udp
    [self createConnectionIfNeeded];
    //the call to dispatch_get_main_queue() is a dummy because we are using DISPATCH_DATA_DESTRUCTOR_DEFAULT which is performed inline
    nw_connection_send(_connection, dispatch_data_create(data.bytes, data.length, dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT), NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t  _Nullable error) {
        if(error != NULL)
        {
            //NSError* st_error = (NSError*)CFBridgingRelease(nw_error_copy_cf_error(error));
            NSLog(@"MLUDPLogger error: %@", error);
        }
    });
}

@end
