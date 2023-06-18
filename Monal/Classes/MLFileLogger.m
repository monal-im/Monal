//
//  MLFileLogger.m
//  monalxmpp
//
//  Created by Thilo Molitor on 18.06.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLFileLogger.h"
#import "HelperTools.h"

@implementation MLFileLogger

-(NSData*) lt_dataForMessage:(DDLogMessage*) logMessage
{
    static uint64_t counter = 0;
    
    //copy assertion from super implementation
    NSAssert([self isOnInternalLoggerQueue], @"logMessage should only be executed on internal queue.");
    
    //encode log message
    NSError* error;
    NSData* rawData = [HelperTools convertLogmessageToJsonData:logMessage usingFormatter:_logFormatter counter:&counter andError:&error];
    if(error != nil || rawData == nil)
    {
        NSLog(@"Error jsonifying log message: %@, logMessage: %@", error, logMessage);
        return [NSData new];        //return empty data, e.g. write nothing
    }
    
    //add 32bit length prefix
    NSAssert(rawData.length < (NSUInteger)1<<32, @"LogMessage is longer than 1<<32 bytes!");
    uint32_t length = CFSwapInt32HostToBig((uint32_t)rawData.length);
    NSMutableData* data = [[NSMutableData alloc] initWithBytes:&length length:sizeof(length)];
    [data appendData:rawData];
    
    //return length_prefix + json_encoded_data
    return data;
}

@end
