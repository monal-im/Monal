//
//  MLPubSub.m
//  monalxmpp
//
//  Created by Thilo Molitor on 20.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPubSub.h"
#import "xmpp.h"


@interface MLPubSub ()
{
    xmpp* _account;
    NSMutableDictionary* _handlers;
    NSMutableDictionary* _cache;
    NSMutableDictionary* _configuredNodes;
}
@end


@implementation MLPubSub

-(id) initWithAccount:(xmpp* _Nonnull) account
{
    self = [super init];
    _account = account;
    _handlers = [[NSMutableDictionary alloc] init];
    _cache = [[NSMutableDictionary alloc] init];
    _configuredNodes = [[NSMutableDictionary alloc] init];
    return self;
}

-(void) registerInterestForNode:(NSString* _Nonnull) node
{
    [self registerInterestForNode:node withPersistentCaching:NO];
}

-(void) registerInterestForNode:(NSString* _Nonnull) node withPersistentCaching:(BOOL) caching
{
    @synchronized(_cache) {
        _configuredNodes[node] = caching ? @YES : @NO;
        if(_cache[node])
            _cache[node][@"persistentCache"] = _configuredNodes[node];
        [_account setPubSubNotificationsForNodes:[_configuredNodes allKeys]];
    }
}

-(void) unregisterInterestForNode:(NSString* _Nonnull) node
{
    @synchronized(_cache) {
        //deactivate persistent cache but keep cached data (we always cache data, even for nodes not registered for automatic refres through "+notify")
        if(_cache[node])
            _cache[node][@"persistentCache"] = @NO;
        [_configuredNodes removeObjectForKey:node];
        [_account setPubSubNotificationsForNodes:[_configuredNodes allKeys]];
    }
}

-(void) registerForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nullable) jid withHandler:(monal_pubsub_handler_t) handler
{
    //empty jid means "all jids"
    if(!jid)
        jid = @"";
    
    //sanity check
    //we are using @synchronized(_cache) for _configuredNodes here because all other parts accessing _configuredNodes are already synchronized via _cache, too
    @synchronized(_cache) {
        if(_configuredNodes[node] == nil)
        {
            DDLogWarn(@"Trying to register data handler for node '%@', but no interest was registered for this node using 'registerInterestForNode:withPersistentCaching:' first! Registering interest for this node with non-persistent cache setting.", node);
            [self registerInterestForNode:node withPersistentCaching:NO];
        }
    }
    
    //save handler
    if(!_handlers[node])
        _handlers[node] = [[NSMutableDictionary alloc] init];
    _handlers[node][jid] = handler;
    
    //call handlers directly (will only be done if we already have some cached data available)
    if(_cache[node])
        for(NSString* jidEntry in _cache[node][@"data"])
            [self callHandlersForNode:node andJid:jidEntry];
}

-(void) unregisterForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nullable) jid
{
    //empty jid means "all jids"
    if(!jid)
        jid = @"";
    
    if(!_handlers[node])
        return;
    [_handlers[node] removeObjectForKey:jid];
}

-(NSDictionary* _Nonnull) getCachedDataForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid
{
    @synchronized(_cache) {
        if(_cache[node] && _cache[node][@"data"][jid])
            return [[NSDictionary alloc] initWithDictionary:_cache[node][@"data"][jid] copyItems:YES];
        return [[NSDictionary alloc] init];
    }
}

-(void) forceRefreshForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid withCompletion:(monal_pubsub_fetch_completion_t _Nullable) completion
{
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:jid];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withResponseHandler:^(XMPPIQ* result) {
        [self handleItems:[result findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:result.fromUser];
        if(completion)
            completion(YES, result);
    } andErrorHandler:^(XMPPIQ* error) {
        if(completion)
            completion(NO, error);
    }];
}

-(void) publish:(NSArray* _Nonnull) items onNode:(NSString* _Nonnull) node
{
    DDLogDebug(@"Publishing pubsub node '%@'", node);
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"publish" withAttributes:@{@"node": node} andChildren:items andData:nil]
    ] andData:nil]];
    [_account sendIq:query withResponseHandler:^(XMPPIQ* result) {
        //ignore publish result
    } andErrorHandler:^(XMPPIQ* error){
        //ignore publish errors for now
    }];
}

//*** framework methods below

-(NSDictionary*) getInternalData
{
    @synchronized(_cache) {
        return @{
            @"cache": _cache,
            @"interest": _configuredNodes
        };
    }
}

-(void) setInternalData:(NSDictionary* _Nonnull) data
{
    @synchronized(_cache) {
        _cache = data[@"cache"];
        //read _configuredNodes but don't overwrite cache settings of already configured nodes
        for(NSString* entry in [data[@"interest"] allKeys])
            if(_configuredNodes[entry] == nil)
                _configuredNodes[entry] = data[@"interest"][entry];
        //update caps hash according to our new _configuredNodes dictionary
        [_account setPubSubNotificationsForNodes:[_configuredNodes allKeys]];
    }
}

-(void) invalidateCache
{
    @synchronized(_cache) {
        //only invalidate non-persistent items in cache
        for(NSString* node in [_cache allKeys])
            if(!_cache[node][@"persistentCache"] || ![_cache[node][@"persistentCache"] boolValue])
            {
                DDLogInfo(@"Invalidating pubsub cache entry for node '%@'", node);
                [_cache removeObjectForKey:node];
            }
    }
}

-(void) handleHeadlineMessage:(XMPPMessage* _Nonnull) messageNode
{
    //TODO: handle node deletion as well
    [self handleItems:[messageNode findFirst:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/items"] fromJid:messageNode.fromUser];
}

//*** internal methods below

//NOTE: this will be called for iq or message stanzas carrying pubsub data.
//We don't need to persist our updated cache because xmpp.m will do that automatically after every handled stanza
-(void) handleItems:(MLXMLNode* _Nullable) items fromJid:(NSString* _Nullable) jid
{
    if(!items)
    {
        DDLogWarn(@"Got pubsub data without any items!");
        return;
    }
    
    NSString* node = [items findFirst:@"/@node"];
    BOOL updated = NO;
    DDLogDebug(@"Adding pubsub data from jid '%@' for node '%@' to our cache", jid, node);
    @synchronized(_cache) {
        if(!_cache[node])
        {
            _cache[node] = [[NSMutableDictionary alloc] init];
            _cache[node][@"persistentCache"] = _configuredNodes[node] && [_configuredNodes[node] boolValue] ? @YES : @NO;
            _cache[node][@"data"] = [[NSMutableDictionary alloc] init];
        }
        if(!_cache[node][@"data"][jid])
            _cache[node][@"data"][jid] = [[NSMutableDictionary alloc] init];
        for(MLXMLNode* item in [items find:@"item"])
        {
            NSString* itemId = [item findFirst:@"/@id"];
            if(!itemId)
                itemId = @"";
            if(!_cache[node][@"data"][jid][itemId] || ![[_cache[node][@"data"][jid][itemId] XMLString] isEqualToString:[item XMLString]])
            {
                updated = YES;
                _cache[node][@"data"][jid][itemId] = item;
            }
        }
    }
    
    //only call handlers for this node/jid combination if something has changed
    if(updated)
    {
        DDLogDebug(@"cached data got updated, calling handlers");
        [self callHandlersForNode:node andJid:jid];
    }
}

-(void) callHandlersForNode:(NSString*) node andJid:(NSString*) jid
{
    DDLogInfo(@"Calling pubsub handlers for node '%@' (and jid '%@')", node, jid);
    @synchronized(_cache) {
        if(!_cache[node] || !_cache[node][@"data"][jid])
        {
            DDLogWarn(@"Pubsub cache empty: %@", _cache);
            return;
        }
        
        if(_handlers[node])
        {
            DDLogDebug(@"Calling pubsub handlers: %@", _handlers[node]);
            if(_handlers[node][jid])
                ((monal_pubsub_handler_t)_handlers[node][jid])([self getCachedDataForNode:node andBareJid:jid], jid);
            if(_handlers[node][@""])
                ((monal_pubsub_handler_t)_handlers[node][@""])([self getCachedDataForNode:node andBareJid:jid], jid);
            DDLogDebug(@"All pubsub handlers called");
        }
    }
}

@end
