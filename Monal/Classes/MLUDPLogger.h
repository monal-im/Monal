//
//  MLUDPLogger.h
//  monalxmpp
//
//  Created by Thilo Molitor on 17.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLUDPLogger : DDAbstractLogger <DDLogger>

+(void) flushWithTimeout:(double) timeout;

@end

NS_ASSUME_NONNULL_END
