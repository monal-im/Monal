//
//  MLMessageProcessor.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/1/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "xmpp.h"
#import "XMPPMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class MLOMEMO;
@class xmpp;

@interface MLMessageProcessor : NSObject

/**
 Process a message, persist it and post relevant notifications
 */
+(void) processMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode forAccount:(xmpp*) account;

@end

NS_ASSUME_NONNULL_END
