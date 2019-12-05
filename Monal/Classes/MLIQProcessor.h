//
//  MLIQProcessor.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ParseIq.h"
#import "MLSignalStore.h"
#import "SignalContext.h"
#import "MLXMPPConnection.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLIQProcessor : NSObject

-(MLIQProcessor *) initWithAccount:(NSString *) accountNo connection:(MLXMPPConnection *) connection signalContex:(SignalContext *)signalContext andSignalStore:(MLSignalStore *) monalSignalStore;

/**
 Process a iq, persist any changes and post notifications
 */
-(void) processIq:(ParseIq *) messageNode;

@end

NS_ASSUME_NONNULL_END
