//
//  MLLogFormatter.m
//  monalxmpp
//
//  Created by Thilo Molitor on 27.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/qos.h>
#import "MLConstants.h"
#import "MLLogFormatter.h"
#import "HelperTools.h"

static DDQualityOfServiceName _qos_name(NSUInteger qos) {
    switch ((qos_class_t) qos) {
        case QOS_CLASS_USER_INTERACTIVE: return @"UI";
        case QOS_CLASS_USER_INITIATED:   return @"IN";
        case QOS_CLASS_DEFAULT:          return @"DF";
        case QOS_CLASS_UTILITY:          return @"UT";
        case QOS_CLASS_BACKGROUND:       return @"BG";
        default:                         return @"UN";
    }
}

static inline NSString* _loglevel_name(NSUInteger flag) {
    if(flag & DDLogLevelOff)
        return @"  OFF";
    else if(flag & DDLogLevelError)
        return @"ERROR";
    else if(flag & DDLogLevelWarning)
        return @" WARN";
    else if(flag & DDLogLevelInfo)
        return @" INFO";
    else if(flag & DDLogLevelDebug)
        return @"DEBUG";
    else if(flag & DDLogLevelVerbose)
        return @" VERB";
    else if(flag & DDLogLevelAll)
        return @"  ALL";
    return @" UNKN";
}

@implementation MLLogFormatter

-(NSString*) formatLogMessage:(DDLogMessage*) logMessage
{
    NSArray* filePathComponents = [logMessage.file pathComponents];
    NSString* file = logMessage.file;
    if([filePathComponents count]>1)
        file = [NSString stringWithFormat:@"%@/%@", filePathComponents[[filePathComponents count]-2], filePathComponents[[filePathComponents count]-1]];
    NSString* timestamp = [self stringFromDate:logMessage.timestamp];
    NSString* queueThreadLabel = [HelperTools getQueueThreadLabelFor:logMessage];

    //append the mach thread id if not already present
    if(![queueThreadLabel isEqualToString:logMessage.threadID])
        queueThreadLabel = [NSString stringWithFormat:@"%@:%@", logMessage.threadID, queueThreadLabel];
    
    return [NSString stringWithFormat:@"%@ [%@] %@ [%@ (QOS:%@)] %@ at %@:%lu: %@", timestamp, _loglevel_name(logMessage.flag), [HelperTools isAppExtension] ? @"*appex*" : @"mainapp", queueThreadLabel, _qos_name(logMessage.qos), logMessage.function, file, (unsigned long)logMessage.line, logMessage.message];
}

@end
