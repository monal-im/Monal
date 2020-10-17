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

typedef void (^monal_pubsub_handler_t)(NSDictionary* items, NSString* jid, NSSet* changedIdList);

@interface MLPubSub : NSObject
{
}

//activate/deactivate automatic data updates and configure caching mode
-(void) registerInterestForNode:(NSString*) node;
-(void) unregisterInterestForNode:(NSString*) node;

//register data handlers
-(void) registerForNode:(NSString*) node andBareJid:(NSString* _Nullable) jid withHandler:(monal_pubsub_handler_t) handler;
-(void) unregisterForNode:(NSString*) node andBareJid:(NSString* _Nullable) jid;

//manually get cached data or force refresh it
-(NSDictionary*) getCachedDataForNode:(NSString*) node andBareJid:(NSString*) jid;
-(void) forceRefreshForNode:(NSString*) node andBareJid:(NSString*) jid andItemsList:(NSArray*) itemsList withDelegate:(id _Nullable) delegate andMethod:(SEL _Nullable) method andAdditionalArguments:(NSArray* _Nullable) args;

//publish/retract/delete/truncate data
-(void) configureNode:(NSString*) node withAccessModel:(NSString* _Nullable) accessModel withDelegate:(id _Nullable) delegate andMethod:(SEL _Nullable) method andAdditionalArguments:(NSArray* _Nullable) args;
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withAccessModel:(NSString* _Nullable) accessModel;
-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node;
-(void) purgeNode:(NSString*) node;
-(void) deleteNode:(NSString*) node;


//methods internal to our framework
-(id) initWithAccount:(xmpp*) account;
-(NSDictionary*) getInternalData;
-(void) setInternalData:(NSDictionary*) data;
-(void) invalidateCache;
-(void) handleHeadlineMessage:(XMPPMessage*) messageNode;

@end

NS_ASSUME_NONNULL_END
