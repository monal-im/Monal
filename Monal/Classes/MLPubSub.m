//
//  MLPubSub.m
//  monalxmpp
//
//  Created by Thilo Molitor on 20.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPubSub.h"
#import "xmpp.h"
#import "XMPPDataForm.h"

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
            @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Trying to register data handler for node '%@', but no interest was registered for this node using 'registerInterestForNode:withPersistentCaching:' first!" userInfo:@{
                @"node": node,
                @"jid": jid
            }];
        }
    }
    
    //save handler
    if(!_handlers[node])
        _handlers[node] = [[NSMutableDictionary alloc] init];
    _handlers[node][jid] = handler;
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

-(void) forceRefreshForPersistentNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid andItemsList:(NSArray* _Nonnull) itemsList
{
    //check if the node cache is persistent and throw an error if not (use forceRefreshForNode:andBareJid:withCompletion: in this case)
    if(!_configuredNodes[node] || ![_configuredNodes[node] boolValue])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"forceRefreshForPersistentNode:andBareJid:andItemsList: can not be used on non-persistent nodes! Use forceRefreshForNode:andBareJid:andItemsList:withCompletion: instead." userInfo:@{
            @"node": node,
            @"jid": jid,
            @"itemsList": itemsList
        }];
    
    //clear old cache before querying (new) data
    @synchronized(_cache) {
        if(_cache[node])
        {
            if(![itemsList count])
                _cache[node][@"data"][jid] = [[NSMutableDictionary alloc] init];
            else if(_cache[node][@"data"][jid])
                for(NSString* itemId in itemsList)
                    [_cache[node][@"data"][jid] removeObjectForKey:itemId];
        }
    }
    
    //build list of items to query (empty list means all items)
    NSMutableArray* queryItems = [[NSMutableArray alloc] init];
    for(NSString* itemId in itemsList)
        [queryItems addObject:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil]];
    
    //build query
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:jid];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handleRefreshResultFor:withIqNode:andUpdated:andNode:andJid:andQueryItems:) andAdditionalArguments:@[[NSNumber numberWithBool:NO], jid, queryItems]];
}

-(void) forceRefreshForNode:(NSString* _Nonnull) node andBareJid:(NSString* _Nonnull) jid andItemsList:(NSArray* _Nonnull) itemsList withCompletion:(monal_pubsub_fetch_completion_t _Nullable) completion
{
    //check if the node cache is persistent and throw an error if so (use forceRefreshForPersistentNode:andBareJid:andItemsList: in this case)
    if(_configuredNodes[node] && [_configuredNodes[node] boolValue])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"forceRefreshForNode:andBareJid:andItemsList:withCompletion: can not be used on persistent nodes! Use forceRefreshForPersistentNode:andBareJid:andItemsList: instead (and the new data handler called by it instead of a completion handler)." userInfo:@{
            @"node": node,
            @"jid": jid,
            @"itemsList": itemsList
        }];
    
    //build list of items to query (empty list means all items)
    NSMutableArray* queryItems = [[NSMutableArray alloc] init];
    for(NSString* itemId in itemsList)
        [queryItems addObject:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil]];
    
    //build query
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:jid];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil]
    ] andData:nil]];
    
    __block BOOL firstResult = YES;
    __block BOOL updated = NO;
    __block monal_iq_handler_t errorHandler = ^(XMPPIQ* error) {
        DDLogWarn(@"Got error iq for pubsub request: %@", error);
        if(completion)
            completion(NO, error);
    };
    __block monal_iq_handler_t resultHandler = ^(XMPPIQ* result) {
        //remove possibly updated data and not when doing the query to keep the cache intact in case the app gets killed/diconnected
        //after sending the query but before getting the (new) results
        if(firstResult)
        {
            firstResult = NO;
            
            //clear old cache before processing (new) data
            @synchronized(_cache) {
                if(_cache[node])
                {
                    if(![itemsList count])
                        _cache[node][@"data"][jid] = [[NSMutableDictionary alloc] init];
                    else if(_cache[node][@"data"][jid])
                        for(NSString* itemId in itemsList)
                            [_cache[node][@"data"][jid] removeObjectForKey:itemId];
                }
            }
        }
        
        //check for rsm paging
        NSString* first = [result findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/first#"];
        NSString* last = [result findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/last#"];
        if(!last || [last isEqualToString:first])       //no rsm at all or reached end of rsm --> process data *and* inform handlers of new data
        {
            updated = [self handleItems:[result findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:result.fromUser updated:updated informHandlers:YES];
            if(completion)
                completion(YES, [NSNumber numberWithBool:updated]);
        }
        else if(first && last)
        {
            //only process data but *don't* inform handlers of new data because it is still partial
            updated = [self handleItems:[result findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:result.fromUser updated:updated informHandlers:NO];
            
            XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:jid];
            [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil],
                [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"after" withAttributes:@{} andChildren:@[] andData:last]
                ] andData:nil]
            ] andData:nil]];
            [_account sendIq:query withResponseHandler:resultHandler andErrorHandler:errorHandler];
        }
    };
    [_account sendIq:query withResponseHandler:resultHandler andErrorHandler:errorHandler];
}

-(void) publishItems:(NSArray* _Nonnull) items onNode:(NSString* _Nonnull) node withAccessModel:(NSString* _Nullable) accessModel
{
    if(!accessModel || ![@[@"open", @"presence", @"roster", @"authorize", @"whitelist"] containsObject:accessModel])
        accessModel = @"whitelist";     //default to private
    NSMutableSet* itemsList = [[NSMutableSet alloc] init];
    for(MLXMLNode* item in items)
        [itemsList addObject:[item findFirst:@"/@id"]];
    DDLogDebug(@"Publishing items on node '%@': %@", node, itemsList);
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"publish" withAttributes:@{@"node": node} andChildren:items andData:nil],
        [[MLXMLNode alloc] initWithElement:@"publish-options" withAttributes:@{} andChildren:@[
            [[XMPPDataForm alloc] initWithType:@"submit" formType:@"http://jabber.org/protocol/pubsub#publish-options" andDictionary:@{
                @"pubsub#persist_items": @"true",
                @"pubsub#access_model": accessModel
            }]
        ] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withResponseHandler:^(XMPPIQ* result) {
        //ignore publish result
    } andErrorHandler:^(XMPPIQ* error) {
        DDLogError(@"Publish failed: %@", error);
    }];
}

-(void) retractItemsWithIds:(NSArray* _Nonnull) itemIds onNode:(NSString* _Nonnull) node
{
    DDLogDebug(@"Deleting items on node '%@': %@", node, [NSSet setWithArray:itemIds]);
    NSMutableArray* queryItems = [[NSMutableArray alloc] init];
    for(NSString* itemId in itemIds)
        [queryItems addObject:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil]];
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"retract" withAttributes:@{@"node": node} andChildren:queryItems andData:nil]
    ] andData:nil]];
    [_account sendIq:query withResponseHandler:^(XMPPIQ* result) {
        //ignore delete result
    } andErrorHandler:^(XMPPIQ* error){
        DDLogError(@"Retract failed: %@", error);
    }];
}

-(void) purgeNode:(NSString* _Nonnull) node
{
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"purge" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withResponseHandler:^(XMPPIQ* result) {
        //ignore purge result
    } andErrorHandler:^(XMPPIQ* error){
        DDLogError(@"Purge failed: %@", error);
    }];
}

-(void) deleteNode:(NSString* _Nonnull) node
{
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"delete" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withResponseHandler:^(XMPPIQ* result) {
        //ignore delete result
    } andErrorHandler:^(XMPPIQ* error){
        DDLogError(@"Delete failed: %@", error);
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
    //handle node deletion or purge
    if(
        [messageNode check:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/delete"] ||
        [messageNode check:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/purge"]
    )
    {
        NSString* node = [messageNode findFirst:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/{*}*@node"];
        if(!node)
        {
            DDLogWarn(@"Got pubsub data without node attribute!");
            return;
        }
        if(_cache[node])
            _cache[node][@"data"] = [[NSMutableDictionary alloc] init];
        [self callHandlersForNode:node andJid:messageNode.fromUser andChangedIdList:[[NSSet alloc] init]];
        return;     //we are done here (no items node for purge or delete)
    }
    
    MLXMLNode* items = [messageNode findFirst:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/items"];
    if(!items)
    {
        DDLogWarn(@"Got pubsub event data without items node, ignoring!");
        return;
    }
    //handle xep-0060 6.5.6 (check if payload is included or if it has to be fetched separately)
    if([items check:@"item/{*}*"])
        [self handleItems:items fromJid:messageNode.fromUser updated:NO informHandlers:YES];
    else
    {
        NSString* node = [items findFirst:@"/@node"];
        if(!node)
        {
            DDLogWarn(@"Got pubsub data without node attribute!");
            return;
        }
        if(_configuredNodes[node] && [_configuredNodes[node] boolValue])
            [self forceRefreshForPersistentNode:node andBareJid:messageNode.fromUser andItemsList:[items find:@"item@id"]];
        else
            [self forceRefreshForNode:node andBareJid:messageNode.fromUser andItemsList:[items find:@"item@id"] withCompletion:nil];
    }
    //handle item deletion
    if([items check:@"retract"])
        [self handleRetraction:items fromJid:messageNode.fromUser updated:NO informHandlers:YES];
}

+(void) handleRefreshResultFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode andUpdated:(NSNumber*) updated andNode:(NSString*) node andJid:(NSString*) jid andQueryItems:(NSMutableArray*) queryItems
{
    if([iqNode check:@"/<type=error>"])
    {
        DDLogWarn(@"Got error iq for pubsub request: %@", iqNode);
        return;
    }
    
    MLPubSub* me = account.pubsub;
    NSString* first = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/first#"];
    NSString* last = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/last#"];
    //check for rsm paging
    if(!last || [last isEqualToString:first])       //no rsm at all or reached end of rsm --> process data *and* inform handlers of new data
        [me handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser updated:[updated boolValue] informHandlers:YES];
    else if(first && last)
    {
        //only process data but *don't* inform handlers of new data because it is still partial
        BOOL newUpdated = [me handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser updated:[updated boolValue] informHandlers:NO];
        XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:jid];
        [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil],
            [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"after" withAttributes:@{} andChildren:@[] andData:last]
            ] andData:nil]
        ] andData:nil]];
        [account sendIq:query withDelegate:[self class] andMethod:@selector(handleRefreshResultFor:withIqNode:andUpdated:andNode:andJid:andQueryItems:) andAdditionalArguments:@[[NSNumber numberWithBool:newUpdated], jid, queryItems]];
    }
}

//*** internal methods below

//NOTE: this will be called for iq *or* message stanzas carrying pubsub data.
//We don't need to persist our updated cache because xmpp.m will do that automatically after every handled stanza
-(BOOL) handleItems:(MLXMLNode* _Nullable) items fromJid:(NSString* _Nullable) jid updated:(BOOL) updated informHandlers:(BOOL) informHandlers
{
    if(!items)
    {
        DDLogWarn(@"Got pubsub data without items node!");
        return updated;
    }
    
    NSString* node = [items findFirst:@"/@node"];
    if(!node)
    {
        DDLogWarn(@"Got pubsub data without node attribute!");
        return updated;
    }
    DDLogDebug(@"Adding pubsub data from jid '%@' for node '%@' to our cache", jid, node);
    NSMutableSet* idList = [[NSMutableSet alloc] init];
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
                [idList addObject:itemId];
            }
        }
    }

    //only call handlers for this node/jid combination if something has changed (and if we should do so)
    if(informHandlers && updated)
    {
        DDLogDebug(@"Cached data got updated, calling handlers");
        [self callHandlersForNode:node andJid:jid andChangedIdList:idList];
    }
    
    return updated;
}

//NOTE: this will be called for message stanzas carrying pubsub data.
//We don't need to persist our updated cache because xmpp.m will do that automatically after every handled stanza
-(BOOL) handleRetraction:(MLXMLNode* _Nullable) items fromJid:(NSString* _Nullable) jid updated:(BOOL) updated informHandlers:(BOOL) informHandlers
{
    if(!items)
    {
        DDLogWarn(@"Got pubsub data without items node!");
        return updated;
    }
    
    NSString* node = [items findFirst:@"/@node"];
    if(!node)
    {
        DDLogWarn(@"Got pubsub data without node attribute!");
        return updated;
    }
    DDLogDebug(@"Removing some pubsub items from jid '%@' for node '%@' from our cache", jid, node);
    NSMutableSet* idList = [[NSMutableSet alloc] init];
    @synchronized(_cache) {
        if(!_cache[node] || !_cache[node][@"data"][jid])
        {
            DDLogInfo(@"Nothing in cache, nothing to delete");
            return updated;
        }
        for(MLXMLNode* item in [items find:@"retract"])
        {
            NSString* itemId = [item findFirst:@"/@id"];
            if(!itemId)
                itemId = @"";
            if(_cache[node][@"data"][jid][itemId])
            {
                DDLogDebug(@"Deleting pubsub item with id '%@' from jid '%@' for node '%@'", itemId, jid, node);
                updated = YES;
                [_cache[node][@"data"][jid] removeObjectForKey:itemId];
                [idList addObject:itemId];
            }
        }
    }

    //only call handlers for this node/jid combination if something has changed (and if we should do so)
    if(informHandlers && updated)
    {
        DDLogDebug(@"Cached data got updated, calling handlers");
        [self callHandlersForNode:node andJid:jid andChangedIdList:idList];
    }
    
    return updated;
}

-(void) callHandlersForNode:(NSString*) node andJid:(NSString*) jid andChangedIdList:(NSSet*) changedIdList
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
                ((monal_pubsub_handler_t)_handlers[node][jid])([self getCachedDataForNode:node andBareJid:jid], jid, changedIdList);
            if(_handlers[node][@""])
                ((monal_pubsub_handler_t)_handlers[node][@""])([self getCachedDataForNode:node andBareJid:jid], jid, changedIdList);
            DDLogDebug(@"All pubsub handlers called");
        }
    }
}

@end
