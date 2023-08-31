//
//  MLLogFileManager.m
//  monalxmpp
//
//  Created by Thilo Molitor on 21.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLLogFileManager.h"

@interface MLLogFileManager ()

@end

static NSString* appName = @"Monal";

@implementation MLLogFileManager

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
