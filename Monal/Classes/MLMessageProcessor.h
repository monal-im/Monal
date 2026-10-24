//
//  MLMessageProcessor.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/1/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/xmpp.h>
#import "XMPPMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class MLOMEMO;
@class xmpp;

@interface MLMessageProcessor : NSObject

/**
 Process a message, persist it and post relevant notifications
 */
+(MLMessage* _Nullable) processMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode forAccount:(xmpp*) account;
+(MLMessage* _Nullable) processMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode forAccount:(xmpp*) account withHistoryId:(NSNumber* _Nullable) historyId;

@end

NS_ASSUME_NONNULL_END
