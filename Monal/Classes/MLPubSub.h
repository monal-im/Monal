//
//  MLPubSub.h
//  monalxmpp
//
//  Created by Thilo Molitor on 20.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@class xmpp;
@class XMPPMessage;
@class MLXMLNode;

@interface MLPubSub : NSObject
{
}

//activate/deactivate automatic data updates
-(void) registerForNode:(NSString*) node withHandler:(NSDictionary*) handler;
-(void) unregisterHandler:(NSDictionary*) handler forNode:(NSString*) node;

//fetch data
-(void) fetchNode:(NSString*) node from:(NSString*) jid withItemsList:(NSArray* _Nullable) itemsList andHandler:(NSDictionary*) handler;

//configure node
-(void) configureNode:(NSString*) node withConfigOptions:(NSDictionary*) configOptions andHandler:(NSDictionary* _Nullable) handler;

//publish/retract/truncate data
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions;
-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node;
-(void) purgeNode:(NSString*) node;

//delete whole node
-(void) deleteNode:(NSString*) node;

@end

NS_ASSUME_NONNULL_END
