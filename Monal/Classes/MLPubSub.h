//
//  MLPubSub.h
//  monalxmpp
//
//  Created by Thilo Molitor on 20.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>

NS_ASSUME_NONNULL_BEGIN

@class xmpp;
@class XMPPMessage;
@class MLXMLNode;
@class MLHandler;

@interface MLPubSub : NSObject
{
}

//activate/deactivate automatic data updates
//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$ID(NSString*, type), $$ID(NSDictionary*, data))
-(void) registerForNode:(NSString*) node withHandler:(MLHandler*) handler;
//handler --> $$instance_handler given to registerForNode:withHandler:
-(void) unregisterHandler:(MLHandler*) handler forNode:(NSString*) node;

//fetch data
//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID(NSDictionary*, data))
//invalidation --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$BOOL(success))
-(void) fetchNode:(NSString*) node from:(NSString*) jid withItemsList:(NSArray* _Nullable) itemsList andHandler:(MLHandler*) handler;

//subscribe to node
//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
//invalidation --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$BOOL(success))
-(void) subscribeToNode:(NSString*) node onJid:(NSString*) jid withHandler:(MLHandler*) handler;
//unsubscribe from node
//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$BOOL(success), , $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
//invalidation --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$BOOL(success), , $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) unsubscribeFromNode:(NSString*) node forJid:(NSString*) jid withHandler:(MLHandler* _Nullable) handler;

//configure node
//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
//invalidation --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node))
-(void) configureNode:(NSString*) node withConfigOptions:(NSDictionary*) configOptions andHandler:(MLHandler* _Nullable) handler;

//publish item on node
//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
//invalidation --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node))
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node;
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions;
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withHandler:(MLHandler* _Nullable) handler;
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions andHandler:(MLHandler* _Nullable) handler;

//retract item from node
//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node), $$ID(NSString*, itemId), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
//invalidation --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node), $$ID(NSString*, itemId))
-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node;
-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler;

//purge whole node
//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
//invalidation --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node))
-(void) purgeNode:(NSString*) node;
-(void) purgeNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler;

//delete whole node
//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
//invalidation --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node))
-(void) deleteNode:(NSString*) node;
-(void) deleteNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler;

@end

NS_ASSUME_NONNULL_END
