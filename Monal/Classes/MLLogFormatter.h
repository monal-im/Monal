//
//  MLLogFormatter.h
//  monalxmpp
//
//  Created by Thilo Molitor on 27.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <CocoaLumberjack/DDDispatchQueueLogFormatter.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLLogFormatter : DDDispatchQueueLogFormatter

-(NSString*) formatLogMessage:(DDLogMessage*) logMessage;

@end

NS_ASSUME_NONNULL_END
