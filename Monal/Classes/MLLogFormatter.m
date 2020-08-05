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

static NSString* _loglevel_name(NSUInteger flag) {
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

@interface MLLogFormatter ()

@end


@implementation MLLogFormatter

-(NSString*) formatLogMessage:(DDLogMessage*) logMessage
{
    NSString* timestamp = [self stringFromDate:(logMessage->_timestamp)];
    NSString* queueThreadLabel = [self queueThreadLabelForLogMessage:logMessage];

    if(![queueThreadLabel isEqualToString:logMessage->_threadID])
        queueThreadLabel = [NSString stringWithFormat:@"%@:%@", logMessage->_threadID, queueThreadLabel];

#if TARGET_OS_SIMULATOR
    return [NSString stringWithFormat:@"[%@] %@ [%@ (QOS:%@)] %@", _loglevel_name(logMessage->_flag), [HelperTools isAppExtension] ? @"*appex*" : @"mainapp", queueThreadLabel, _qos_name(logMessage->_qos), logMessage->_message];
#else
    return [NSString stringWithFormat:@"[%@] %@ %@ [%@ (QOS:%@)] %@", _loglevel_name(logMessage->_flag), timestamp, [HelperTools isAppExtension] ? @"*appex*" : @"mainapp", queueThreadLabel, _qos_name(logMessage->_qos), logMessage->_message];
#endif
}

@end
