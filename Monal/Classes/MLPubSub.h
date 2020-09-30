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

typedef void (^monal_pubsub_handler_t)(MLXMLNode* items);
typedef void (^monal_pubsub_fetch_completion_t)(BOOL success, XMPPIQ* rawResponse);

@interface MLPubSub : NSObject
{
}

-(id) initWithAccount:(xmpp* _Nonnull) account;
-(void) registerInterestForNode:(NSString* _Nonnull) node withPersistentCaching:(BOOL) caching;
-(void) unregisterInterestForNode:(NSString* _Nonnull) node;
-(void) registerHandler:(monal_pubsub_handler_t) handler forNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nullable) jid;
-(void) unregisterHandlerForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nullable) jid;
-(NSArray* _Nullable) getCachedDataForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid;
-(void) forceRefreshForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid withCompletion:(monal_pubsub_fetch_completion_t _Nullable) completion;
-(void) publish:(NSArray* _Nonnull) items onNode:(NSString* _Nonnull) node;

//methods internal to our framework
+(NSArray*) getDesiredNodesList;
-(NSDictionary*) getInternalData;
-(void) setInternalData:(NSDictionary*) data;
-(void) invalidateCache;
-(void) handleHeadlineMessage:(XMPPMessage* _Nonnull) messageNode;

@end

NS_ASSUME_NONNULL_END
