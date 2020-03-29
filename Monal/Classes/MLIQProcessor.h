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
#import "XMPPIQ.h"
#import "MLXMLNode.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^iqCompletion)( MLXMLNode  * _Nullable iqResponse);
typedef void (^processAction)(void);

@interface MLIQProcessor : NSObject

@property (nonatomic, strong) iqCompletion sendIq;
@property (nonatomic, strong) processAction initSession;
@property (nonatomic, strong) processAction enablePush;
@property (nonatomic, strong) processAction sendSignalInitialStanzas;
@property (nonatomic, strong) processAction getVcards;

-(MLIQProcessor *) initWithAccount:(NSString *) accountNo connection:(MLXMPPConnection *) connection signalContex:(SignalContext *)signalContext andSignalStore:(MLSignalStore *) monalSignalStore;

/**
 Process a iq, persist any changes and post notifications
 */
-(void) processIq:(ParseIq *) messageNode;

/**
 process a node and send out devices
 */
-(void) processOMEMODevices:(ParseIq *) iqNode;


@end

NS_ASSUME_NONNULL_END
