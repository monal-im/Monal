//
//  MLUDPLogger.h
//  monalxmpp
//
//  Created by Thilo Molitor on 17.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT DDLoggerName const DDLoggerNameUDP NS_SWIFT_NAME(DDLoggerName.udp); // MLUDPLogger

@interface MLUDPLogger : DDAbstractLogger <DDLogger>

+(void) flushWithTimeout:(double) timeout;
+(void) directlyWriteLogMessage:(DDLogMessage*) logMessage;
+(instancetype) getCurrentInstance;

@end

NS_ASSUME_NONNULL_END
