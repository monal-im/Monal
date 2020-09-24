//
//  MLIQProcessor.h
//  Monal
//
//  Created by Anurodh Pokharel on 11/27/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPPIQ.h"
#import "MLOMEMO.h"
#import "MLXMPPConnection.h"
#import "XMPPIQ.h"
#import "MLXMLNode.h"
#import "xmpp.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^iqCompletion)(MLXMLNode* iq, monal_iq_handler_t resultHandler, monal_iq_handler_t errorHandler);
typedef void (^iqDelegateCompletion)(MLXMLNode* iq, id delegate, SEL method, NSArray* args);
typedef void (^processAction)(void);

@class MLOMEMO;

@interface MLIQProcessor : NSObject

@property (nonatomic, strong) iqCompletion sendIq;
@property (nonatomic, strong) iqDelegateCompletion sendIqWithDelegate;
@property (nonatomic, strong) processAction mamFinished;
@property (nonatomic, strong) processAction initSession;
@property (nonatomic, strong) processAction enablePush;
@property (nonatomic, strong) processAction getVcards;

-(MLIQProcessor*) initWithAccount:(NSString*) accountNo connection:(MLXMPPConnection*) connection omemo:(MLOMEMO*) omemo;
-(MLIQProcessor*) initWithAccount:(NSString*) accountNo connection:(MLXMPPConnection*) connection;

/**
 Process a iq, persist any changes and post notifications
 */
-(void) processIq:(XMPPIQ*) messageNode;


@end

NS_ASSUME_NONNULL_END
