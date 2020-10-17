//
//  MLPubSub.h
//  monalxmpp
//
//  Created by Thilo Molitor on 20.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

@class xmpp;
@class XMPPMessage;
@class XMPPIQ;

typedef void (^monal_pubsub_handler_t)(NSDictionary* _Nonnull items, NSString* _Nonnull jid, NSSet* _Nonnull changedIdList);

@interface MLPubSub : NSObject
{
}

//activate/deactivate automatic data updates and configure caching mode
-(void) registerInterestForNode:(NSString* _Nonnull) node;
-(void) unregisterInterestForNode:(NSString* _Nonnull) node;

//register data handlers
-(void) registerForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nullable) jid withHandler:(monal_pubsub_handler_t _Nonnull) handler;
-(void) unregisterForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nullable) jid;

//manually get cached data or force refresh it
-(NSDictionary* _Nonnull) getCachedDataForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid;
-(void) forceRefreshForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid andItemsList:(NSArray* _Nonnull) itemsList withDelegate:(id _Nullable) delegate andMethod:(SEL _Nullable) method andAdditionalArguments:(NSArray* _Nullable) args;

//publish/retract/delete/truncate data
-(void) publishItems:(NSArray* _Nonnull) items onNode:(NSString* _Nonnull) node withAccessModel:(NSString* _Nullable) accessModel;
-(void) retractItemsWithIds:(NSArray* _Nonnull) itemIds onNode:(NSString* _Nonnull) node;
-(void) purgeNode:(NSString* _Nonnull) node;
-(void) deleteNode:(NSString* _Nonnull) node;


//methods internal to our framework
-(id _Nonnull) initWithAccount:(xmpp* _Nonnull) account;
-(NSDictionary* _Nonnull) getInternalData;
-(void) setInternalData:(NSDictionary* _Nonnull) data;
-(void) invalidateCache;
-(void) handleHeadlineMessage:(XMPPMessage* _Nonnull) messageNode;
+(void) handleRefreshResultFor:(xmpp* _Nonnull) account withIqNode:(XMPPIQ* _Nonnull) iqNode andUpdated:(NSNumber* _Nonnull) updated andNode:(NSString* _Nonnull) node andJid:(NSString* _Nonnull) jid andQueryItems:(NSMutableArray* _Nonnull) queryItems andHandler:(NSDictionary* _Nonnull) handler;

@end
