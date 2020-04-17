//
//  MLMessageProcessor.h
//  Monal
//
//  Created by Anurodh Pokharel on 9/1/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ParseMessage.h"
#import "MLSignalStore.h"
#import "SignalContext.h"
#import "MLXMPPConnection.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^messageCompletion)(BOOL success, BOOL encrypted, BOOL showAlert,  NSString *body, NSString *newMessageType);
typedef void (^signalCompletion)(void);
typedef void (^nodeCompletion)( MLXMLNode  * _Nullable nodeResponse);

@interface MLMessageProcessor : NSObject
@property (nonatomic, strong) messageCompletion postPersistAction;
@property (nonatomic, strong) signalCompletion signalAction;
@property (nonatomic, strong) nodeCompletion sendStanza;

-(MLMessageProcessor *) initWithAccount:(NSString *) accountNo jid:(NSString *) jid connection:(MLXMPPConnection *) connection   signalContex:(SignalContext *)signalContext andSignalStore:(MLSignalStore *) monalSignalStore;
-(MLMessageProcessor *) initWithAccount:(NSString *) accountNo jid:(NSString *) jid connection:(MLXMPPConnection *) connection;

/**
 Process a message, persist it and post relevant notifications
 */
-(void) processMessage:(ParseMessage *) messageNode;

@end

NS_ASSUME_NONNULL_END
