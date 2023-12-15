//
//  MLLogFileManager.m
//  monalxmpp
//
//  Created by Thilo Molitor on 21.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HelperTools.h"
#import "MLLogFileManager.h"

@interface DDFileLogMLVMessageSerializer : NSObject <DDFileLogMessageSerializer>
@end

@interface MLLogFileManager ()
@end

static NSString* appName = @"Monal";

@implementation DDFileLogMLVMessageSerializer

-(NSData*) dataForString:(NSString*) string originatingFromMessage:(DDLogMessage*) logMessage
{
    static uint64_t counter = 0;
    
    if(logMessage == nil)
    {
        NSLog(@"Error: logMessage should never be nil when calling dataForString:originatingFromMessage. Given log string: %@", string);
        return [NSData new];        //return empty data, e.g. write nothing
    }
    
    //encode log message
    NSError* error;
    NSData* rawData = [HelperTools convertLogmessageToJsonData:logMessage counter:&counter andError:&error];
    if(error != nil || rawData == nil)
    {
        NSLog(@"Error jsonifying log message: %@, logMessage: %@", error, logMessage);
        return [NSData new];        //return empty data, e.g. write nothing
    }
    
    //add 32bit length prefix
    NSAssert(rawData.length < (NSUInteger)1<<30, @"LogMessage is longer than 1<<30 bytes!");
    uint32_t length = CFSwapInt32HostToBig((uint32_t)rawData.length);
    NSMutableData* data = [[NSMutableData alloc] initWithBytes:&length length:sizeof(length)];
    [data appendData:rawData];
    
    //return length_prefix + json_encoded_data
    return data;
}

@end

@implementation MLLogFileManager

-(instancetype) initWithLogsDirectory:(NSString* _Nullable) dir
{
    self = [super initWithLogsDirectory:dir];
    self.logMessageSerializer = [DDFileLogMLVMessageSerializer new];
    return self;
}

-(NSString*) newLogFileName
{
    NSDateFormatter* dateFormatter = [NSDateFormatter new];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    [dateFormatter setDateFormat: @"yyyy'-'MM'-'dd'--'HH'-'mm'-'ss'-'SSS'"];
    
    NSString* formattedDate = [dateFormatter stringFromDate:[NSDate date]];
    return [NSString stringWithFormat:@"%@ %@.rawlog", appName, formattedDate];
}

-(BOOL) isLogFile:(NSString*) fileName
{
    // We need to add a space to the name as otherwise we could match applications that have the name prefix.
    BOOL hasProperPrefix = [fileName hasPrefix:[appName stringByAppendingString:@" "]];
    BOOL hasProperSuffix = [fileName hasSuffix:@".rawlog"];

    return (hasProperPrefix && hasProperSuffix);
}

@end
