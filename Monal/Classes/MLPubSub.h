//
//  MLPubSub.h
//  monalxmpp
//
//  Created by Thilo Molitor on 20.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"
#import "MLXMLNode.h"
#import "XMPPIQ.h"

@class xmpp;
@class XMPPMessage;

NS_ASSUME_NONNULL_BEGIN

typedef void (^monal_pubsub_handler_t)(NSDictionary* _Nonnull items, NSString* _Nonnull jid, NSSet* _Nonnull changedIdList);
typedef void (^monal_pubsub_fetch_completion_t)(BOOL success, id additionalData);

@interface MLPubSub : NSObject
{
}

-(id) initWithAccount:(xmpp* _Nonnull) account;
-(void) registerInterestForNode:(NSString* _Nonnull) node;
-(void) registerInterestForNode:(NSString* _Nonnull) node withPersistentCaching:(BOOL) caching;
-(void) unregisterInterestForNode:(NSString* _Nonnull) node;
-(void) registerForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nullable) jid withHandler:(monal_pubsub_handler_t) handler;
-(void) unregisterForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nullable) jid;

-(NSDictionary* _Nonnull) getCachedDataForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid;
-(void) forceRefreshForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid andItemsList:(NSArray* _Nonnull) itemsList withCompletion:(monal_pubsub_fetch_completion_t _Nullable) completion;
-(void) forceRefreshForPersistentNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid andItemsList:(NSArray* _Nonnull) itemsList;

-(void) publishItems:(NSArray* _Nonnull) items onNode:(NSString* _Nonnull) node withAccessModel:(NSString* _Nullable) accessModel;
-(void) retractItemsWithIds:(NSArray* _Nonnull) itemIds onNode:(NSString* _Nonnull) node;
-(void) purgeNode:(NSString* _Nonnull) node;
-(void) deleteNode:(NSString* _Nonnull) node;


//methods internal to our framework
-(NSDictionary*) getInternalData;
-(void) setInternalData:(NSDictionary* _Nonnull) data;
-(void) invalidateCache;
-(void) handleHeadlineMessage:(XMPPMessage* _Nonnull) messageNode;
+(void) handleRefreshResultFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode andUpdated:(NSNumber*) updated andNode:(NSString*) node andJid:(NSString*) jid andQueryItems:(NSMutableArray*) queryItems;

@end

NS_ASSUME_NONNULL_END
