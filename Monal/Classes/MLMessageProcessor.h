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

NS_ASSUME_NONNULL_BEGIN

@interface MLMessageProcessor : NSObject
-(MLMessageProcessor *) initWithAccount:(NSString *) accountNo jid:(NSString *) jid signalContex:(SignalContext *)signalContext andSignalStore:(MLSignalStore *) monalSignalStore;

/**
 Process a message, persist it and post relevant notifications
 */
-(void) processMessage:(ParseMessage *) messageNode;

@end

NS_ASSUME_NONNULL_END
