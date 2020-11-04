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
@class MLHandler;

@interface MLPubSub : NSObject
{
}

//activate/deactivate automatic data updates, handler: $$handler(xxx, $ID(xmpp*, account), $ID(NSString*, node), $ID(NSString*, jid), $ID(NSString*, type), $ID(NSDictionary*, data))
-(void) registerForNode:(NSString*) node withHandler:(MLHandler*) handler;
-(void) unregisterHandler:(MLHandler*) handler forNode:(NSString*) node;

//fetch data, handler: $$handler(xxx, $ID(xmpp*, account), $ID(NSString*, jid), $ID(MLXMLNode*, errorIq), $ID(NSDictionary*, data))
-(void) fetchNode:(NSString*) node from:(NSString*) jid withItemsList:(NSArray* _Nullable) itemsList andHandler:(MLHandler*) handler;

//configure node, handler: $$handler(xxx, $ID(xmpp*, account), $BOOL(success))
-(void) configureNode:(NSString*) node withConfigOptions:(NSDictionary*) configOptions andHandler:(MLHandler* _Nullable) handler;

//publish, handler: $$handler(xxx, $ID(xmpp*, account), $BOOL(success))
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node;
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions;
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withHandler:(MLHandler* _Nullable) handler;
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions andHandler:(MLHandler* _Nullable) handler;

//retract, handler: $$handler(xxx, $ID(xmpp*, account), $BOOL(success))
-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node;
-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler;

//purge whole node, handler: $$handler(xxx, $ID(xmpp*, account), $BOOL(success))
-(void) purgeNode:(NSString*) node;
-(void) purgeNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler;

//delete whole node, handler: $$handler(xxx, $ID(xmpp*, account), $BOOL(success))
-(void) deleteNode:(NSString*) node;
-(void) deleteNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler;

@end

NS_ASSUME_NONNULL_END
