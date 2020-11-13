//
//  MLIQProcessor.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPPIQ.h"
#import "MLXMPPConnection.h"
#import "XMPPIQ.h"
#import "MLXMLNode.h"
#import "xmpp.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^iqCompletion)(MLXMLNode* iq, monal_iq_handler_t resultHandler, monal_iq_handler_t errorHandler);
typedef void (^iqDelegateCompletion)(MLXMLNode* iq, id delegate, SEL method, NSArray* args);
typedef void (^processAction)(void);

@interface MLIQProcessor : NSObject

/**
 Process a iq, persist any changes and post notifications
 */
+(void) processIq:(XMPPIQ*) iqNode forAccount:(xmpp*) account;

@end

NS_ASSUME_NONNULL_END
