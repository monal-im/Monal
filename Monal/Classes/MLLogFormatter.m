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

DDQualityOfServiceName const DDQualityOfServiceUserInteractive = @"UI";
DDQualityOfServiceName const DDQualityOfServiceUserInitiated   = @"IN";
DDQualityOfServiceName const DDQualityOfServiceDefault         = @"DF";
DDQualityOfServiceName const DDQualityOfServiceUtility         = @"UT";
DDQualityOfServiceName const DDQualityOfServiceBackground      = @"BG";
DDQualityOfServiceName const DDQualityOfServiceUnspecified     = @"UN";

static DDQualityOfServiceName _qos_name(NSUInteger qos) {
    switch ((qos_class_t) qos) {
        case QOS_CLASS_USER_INTERACTIVE: return DDQualityOfServiceUserInteractive;
        case QOS_CLASS_USER_INITIATED:   return DDQualityOfServiceUserInitiated;
        case QOS_CLASS_DEFAULT:          return DDQualityOfServiceDefault;
        case QOS_CLASS_UTILITY:          return DDQualityOfServiceUtility;
        case QOS_CLASS_BACKGROUND:       return DDQualityOfServiceBackground;
        default:                         return DDQualityOfServiceUnspecified;
    }
}

@interface MLLogFormatter ()

@end


@implementation MLLogFormatter

-(NSString*) formatLogMessage:(DDLogMessage*) logMessage
{
    NSString *timestamp = [self stringFromDate:(logMessage->_timestamp)];
    NSString *queueThreadLabel = [self queueThreadLabelForLogMessage:logMessage];

#if TARGET_OS_SIMULATOR
    return [NSString stringWithFormat:@"%@ [%@ (QOS:%@)] %@", [HelperTools isAppExtension] ? @"*appex*" : @"mainapp", queueThreadLabel, _qos_name(logMessage->_qos), logMessage->_message];
#else
    return [NSString stringWithFormat:@"%@ %@ [%@ (QOS:%@)] %@", timestamp, [HelperTools isAppExtension] ? @"APP EXT" : @"mainapp", queueThreadLabel, _qos_name(logMessage->_qos), logMessage->_message];
#endif
}

@end
