//
//  MLMessageProcessor.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/1/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLXMPPConnection.h"
#import "xmpp.h"
#import "MLOMEMO.h"
#import "XMPPMessage.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^messageCompletion)(XMPPMessage* messageNode, XMPPMessage* outerMessageNode, BOOL success, BOOL encrypted, BOOL showAlert, NSString* body, NSString* newMessageType, NSString* actualFrom);
typedef void (^signalCompletion)(void);
typedef void (^nodeCompletion)(MLXMLNode* _Nullable nodeResponse);

@class MLOMEMO;
@class xmpp;

@interface MLMessageProcessor : NSObject
@property (nonatomic, strong) messageCompletion postPersistAction;
@property (nonatomic, strong) nodeCompletion sendStanza;

-(MLMessageProcessor*) initWithAccount:(xmpp*) account jid:(NSString*) jid connection:(MLXMPPConnection*) connection omemo:(MLOMEMO*) omemo;

/**
 Process a message, persist it and post relevant notifications
 */
-(void) processMessage:(XMPPMessage*) messageNode andOuterMessage:(XMPPMessage*) outerMessageNode;

@end

NS_ASSUME_NONNULL_END
