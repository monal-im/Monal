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

typedef void (^monal_pubsub_handler_t)(NSDictionary* _Nonnull items, NSString* _Nonnull jid);
typedef void (^monal_pubsub_fetch_completion_t)(BOOL success, XMPPIQ* _Nonnull rawResponse);

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
-(void) forceRefreshForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid withCompletion:(monal_pubsub_fetch_completion_t _Nullable) completion;
-(void) publish:(NSArray* _Nonnull) items onNode:(NSString* _Nonnull) node;

//methods internal to our framework
-(NSDictionary*) getInternalData;
-(void) setInternalData:(NSDictionary* _Nonnull) data;
-(void) invalidateCache;
-(void) handleHeadlineMessage:(XMPPMessage* _Nonnull) messageNode;

@end

NS_ASSUME_NONNULL_END
