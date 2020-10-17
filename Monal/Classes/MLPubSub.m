//
//  MLPubSub.m
//  monalxmpp
//
//  Created by Thilo Molitor on 20.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPubSub.h"
#import "xmpp.h"
#import "MLXMLNode.h"
#import "XMPPDataForm.h"
#import "XMPPStanza.h"
#import "XMPPIQ.h"
#import "XMPPMessage.h"

@interface MLPubSub ()
{
    xmpp* _account;
    NSMutableDictionary* _handlers;
    NSMutableDictionary* _cache;
    NSMutableSet* _configuredNodes;
}
@end

@implementation MLPubSub

-(id) initWithAccount:(xmpp*) account
{
    self = [super init];
    _account = account;
    _handlers = [[NSMutableDictionary alloc] init];
    _cache = [[NSMutableDictionary alloc] init];
    _configuredNodes = [[NSMutableSet alloc] init];
    return self;
}

-(void) registerInterestForNode:(NSString*) node
{
    //we are using @synchronized(_cache) for _configuredNodes here because all other parts accessing _configuredNodes are already synchronized via _cache, too
    @synchronized(_cache) {
        [_configuredNodes addObject:node];
        [_account setPubSubNotificationsForNodes:_configuredNodes persistState:YES];
    }
}

-(void) unregisterInterestForNode:(NSString*) node
{
    @synchronized(_cache) {
        //clear cache for node (can be refilled again by force refresh or by registering an interest again)
        if(_cache[node])
            [_cache removeObjectForKey:node];
        [_configuredNodes removeObject:node];
        [_account setPubSubNotificationsForNodes:_configuredNodes persistState:YES];
    }
}

-(void) registerForNode:(NSString*) node andBareJid:(NSString* _Nullable) jid withHandler:(monal_pubsub_handler_t) handler
{
    //empty jid means "all jids"
    if(!jid)
        jid = @"";
    
    //sanity check
    //we are using @synchronized(_cache) for _configuredNodes here because all other parts accessing _configuredNodes are already synchronized via _cache, too
    @synchronized(_cache) {
        if(![_configuredNodes containsObject:node])
            DDLogWarn(@"POSSIBLE IMPLEMENTATION ERROR: Trying to register data handler for node '%@', but no interest was registered for this node using 'registerInterestForNode:withPersistentCaching:' first. This handler will only be called on manual data update!", node);
    }
    
    //save handler
    if(!_handlers[node])
        _handlers[node] = [[NSMutableDictionary alloc] init];
    _handlers[node][jid] = handler;
}

-(void) unregisterForNode:(NSString*) node andBareJid:(NSString* _Nullable) jid
{
    //empty jid means "all jids"
    if(!jid)
        jid = @"";
    
    if(!_handlers[node])
        return;
    [_handlers[node] removeObjectForKey:jid];
}

-(NSDictionary*) getCachedDataForNode:(NSString*) node andBareJid:(NSString*) jid
{
    @synchronized(_cache) {
        if(_cache[node] && _cache[node][@"data"][jid])
            return [[NSDictionary alloc] initWithDictionary:_cache[node][@"data"][jid] copyItems:YES];
        return [[NSDictionary alloc] init];
    }
}

-(void) forceRefreshForNode:(NSString*) node andBareJid:(NSString*) jid andItemsList:(NSArray*) itemsList withDelegate:(id _Nullable) delegate andMethod:(SEL _Nullable) method andAdditionalArguments:(NSArray* _Nullable) args
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
        return;
    }
    
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
    
    DDLogInfo(@"Force refreshing node '%@' at jid '%@' using callback [%@ %@]...", node, jid, NSStringFromClass(delegate), NSStringFromSelector(method));
    NSDictionary* handler = @{};
    if(delegate && method)
        handler = @{
            @"delegate": NSStringFromClass(delegate),
            @"method": NSStringFromSelector(method),
            @"arguments": (args ? args : @[])
        };
    
    //build list of items to query (empty list means all items)
    NSMutableArray* queryItems = [[NSMutableArray alloc] init];
    for(NSString* itemId in itemsList)
        [queryItems addObject:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil]];
    
    //build query
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:jid];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handleRefreshResultFor:withIqNode:andUpdated:andNode:andQueryItems:andIdList:andHandler:) andAdditionalArguments:@[[NSNumber numberWithBool:NO], node, queryItems, [[NSMutableSet alloc] init], handler]];
}

-(void) configureNode:(NSString*) node withAccessModel:(NSString* _Nullable) accessModel withDelegate:(id _Nullable) delegate andMethod:(SEL _Nullable) method andAdditionalArguments:(NSArray* _Nullable) args
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
        return;
    }
    if(!accessModel || ![@[@"open", @"presence", @"roster", @"authorize", @"whitelist"] containsObject:accessModel])
        accessModel = @"whitelist";     //default to private
    NSDictionary* handler = @{};
    if(delegate && method)
        handler = @{
            @"delegate": NSStringFromClass(delegate),
            @"method": NSStringFromSelector(method),
            @"arguments": (args ? args : @[])
        };
    
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handleConfigureResult1For:withIqNode:node:accessModel:andHandler:) andAdditionalArguments:@[node, accessModel, handler]];
}

-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withAccessModel:(NSString* _Nullable) accessModel
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
        return;
    }
    if(!accessModel || ![@[@"open", @"presence", @"roster", @"authorize", @"whitelist"] containsObject:accessModel])
        accessModel = @"whitelist";     //default to private
    DDLogDebug(@"Publishing item on node '%@'(%@): %@", node, accessModel, item);
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"publish" withAttributes:@{@"node": node} andChildren:@[item] andData:nil],
        [[MLXMLNode alloc] initWithElement:@"publish-options" withAttributes:@{} andChildren:@[
            [[XMPPDataForm alloc] initWithType:@"submit" formType:@"http://jabber.org/protocol/pubsub#publish-options" andDictionary:@{
                @"pubsub#persist_items": @"true",
                @"pubsub#access_model": accessModel
            }]
        ] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handlePublishResultFor:withIqNode:item:node:andAccessModel:) andAdditionalArguments:@[item, node, accessModel]];
}

-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
        return;
    }
    DDLogDebug(@"Retracting item '%@' on node '%@'", itemId, node);
    MLXMLNode* item = [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil];
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"retract" withAttributes:@{@"node": node} andChildren:@[item] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handleRetractResultFor:withIqNode:andNode:andItemId:) andAdditionalArguments:@[node, itemId]];
}

-(void) purgeNode:(NSString*) node
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
        return;
    }
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"purge" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handlePurgeOrDeleteResultFor:withIqNode:andNode:) andAdditionalArguments:@[node]];
}

-(void) deleteNode:(NSString*) node
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
        return;
    }
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"delete" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handlePurgeOrDeleteResultFor:withIqNode:andNode:) andAdditionalArguments:@[node]];
}

//*** framework methods below

-(NSDictionary*) getInternalData
{
    @synchronized(_cache) {
        return @{
            @"cache": _cache,
            @"interest": _configuredNodes,
            @"version": @1
        };
    }
}

-(void) setInternalData:(NSDictionary*) data
{
    @synchronized(_cache) {
        if(!data[@"version"] || ![data[@"version"] isEqualToNumber:@1])
            return;     //ignore old data
        _cache = data[@"cache"];
        _configuredNodes = data[@"interest"];
        //update caps hash according to our new _configuredNodes dictionary
        //but don't persist state again that was just read from persistent storage
        [_account setPubSubNotificationsForNodes:_configuredNodes persistState:NO];
    }
}

-(void) invalidateCache
{
    @synchronized(_cache) {
        //only invalidate non-persistent items in cache
        for(NSString* node in [_cache allKeys])
        {
            DDLogInfo(@"Invalidating pubsub cache entry for node '%@'", node);
            [_cache removeObjectForKey:node];
        }
    }
}

-(void) handleHeadlineMessage:(XMPPMessage*) messageNode
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
        return;
    }
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
        NSSet* purgedIds = [[NSSet alloc] init];
        if(_cache[node] && _cache[node][@"data"][messageNode.fromUser])
        {
            purgedIds = [NSSet setWithArray:[_cache[node][@"data"][messageNode.fromUser] allKeys]];
            _cache[node][@"data"][messageNode.fromUser] = [[NSMutableDictionary alloc] init];
        }
        [self callHandlersForNode:node andJid:messageNode.fromUser andChangedIdList:purgedIds];
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
        [self handleItems:items fromJid:messageNode.fromUser updated:NO informHandlers:YES idList:[[NSMutableSet alloc] init]];
    else
    {
        NSString* node = [items findFirst:@"/@node"];
        if(!node)
        {
            DDLogWarn(@"Got pubsub data without node attribute!");
            return;
        }
        [self forceRefreshForNode:node andBareJid:messageNode.fromUser andItemsList:[items find:@"item@id"] withDelegate:nil andMethod:nil andAdditionalArguments:nil];
    }
    //handle item deletion
    if([items check:@"retract"])
        [self handleRetraction:items fromJid:messageNode.fromUser updated:NO informHandlers:YES idList:[[NSMutableSet alloc] init]];
}

//*** internal methods below

//NOTE: this will be called for iq *or* message stanzas carrying pubsub data.
//We don't need to persist our updated cache because xmpp.m will do that automatically after every handled stanza
-(BOOL) handleItems:(MLXMLNode* _Nullable) items fromJid:(NSString* _Nullable) jid updated:(BOOL) updated informHandlers:(BOOL) informHandlers idList:(NSMutableSet*) idList
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
    DDLogDebug(@"Adding pubsub data from jid '%@' for node '%@' to our cache (informHandlers: %@)", jid, node, informHandlers ? @"YES" : @"NO");
    @synchronized(_cache) {
        if(!_cache[node])
        {
            _cache[node] = [[NSMutableDictionary alloc] init];
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
    else
        DDLogDebug(@"Cached data did not get updated (or informHandlers was NO)");
    
    return updated;
}

//NOTE: this will be called for message stanzas carrying pubsub data.
//We don't need to persist our updated cache because xmpp.m will do that automatically after every handled stanza
-(BOOL) handleRetraction:(MLXMLNode* _Nullable) items fromJid:(NSString* _Nullable) jid updated:(BOOL) updated informHandlers:(BOOL) informHandlers idList:(NSMutableSet*) idList
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
    DDLogDebug(@"Removing some pubsub items from jid '%@' for node '%@' from our cache (informHandlers: %@)", jid, node, informHandlers ? @"YES" : @"NO");
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
    else
        DDLogDebug(@"Cached data did not get updated (or informHandlers was NO)");
    
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

+(void) callStaticHandler:(NSDictionary*) handler withDefaultArguments:(NSArray*) defaultArgs
{
    if(handler[@"delegate"] && handler[@"method"])
    {
        id cls = NSClassFromString(handler[@"delegate"]);
        SEL sel = NSSelectorFromString(handler[@"method"]);
        DDLogVerbose(@"Calling force refresh callback [%@ %@] with error...", handler[@"delegate"], handler[@"method"]);
        NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[cls methodSignatureForSelector:sel]];
        [inv setTarget:cls];
        [inv setSelector:sel];
        //arguments 0 and 1 are self and _cmd respectively, automatically set by NSInvocation
        NSInteger idx = 2;
        NSObject* nilArgument = nil;
        //default arguments of the caller
        for(id _Nonnull arg in defaultArgs)
            if(arg == [NSNull null])
                [inv setArgument:&nilArgument atIndex:idx++];
            else
                [inv setArgument:(void* _Nonnull)&arg atIndex:idx++];
        //additional arguments bound to the handler
        for(id _Nonnull arg in handler[@"arguments"])
            [inv setArgument:(void* _Nonnull)&arg atIndex:idx++];
        [inv invoke];
    }
}

+(void) handleRefreshResultFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode andUpdated:(NSNumber*) updated andNode:(NSString*) node andQueryItems:(NSMutableArray*) queryItems andIdList:(NSMutableSet*) idList andHandler:(NSDictionary*) handler
{
    MLPubSub* me = account.pubsub;
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub refresh request: %@", iqNode);
        
        //remove all partially cached data
        for(NSString* itemId in idList)
            if(me->_cache[node] && me->_cache[node][@"data"][iqNode.fromUser])
                [me->_cache[node][@"data"][iqNode.fromUser] removeObjectForKey:itemId];
        
        //call force refresh callback (if given) with error
        [self callStaticHandler:handler withDefaultArguments:@[account, iqNode.fromUser, iqNode]];
        
        return;
    }
    
    NSString* first = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/first#"];
    NSString* last = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/last#"];
    //check for rsm paging
    if(!last || [last isEqualToString:first])       //no rsm at all or reached end of rsm --> process data *and* inform handlers of new data
    {
        [me handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser updated:[updated boolValue] informHandlers:YES idList:idList];
        
        //call force refresh callback (if given) *after* calling data handlers
        [self callStaticHandler:handler withDefaultArguments:@[account, iqNode.fromUser, [NSNull null]]];       //nil for third arg means "no error"
    }
    else if(first && last)
    {
        //only process data but *don't* inform handlers of new data because it is still partial
        BOOL newUpdated = [me handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser updated:[updated boolValue] informHandlers:NO idList:idList];
        XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:iqNode.fromUser];
        [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil],
            [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"after" withAttributes:@{} andChildren:@[] andData:last]
            ] andData:nil]
        ] andData:nil]];
        [account sendIq:query withDelegate:self andMethod:@selector(handleRefreshResultFor:withIqNode:andUpdated:andNode:andQueryItems:andIdList:andHandler:) andAdditionalArguments:@[[NSNumber numberWithBool:newUpdated], node, queryItems, idList, handler]];
    }
}

+(void) handleConfigureResult1For:(xmpp*) account withIqNode:(XMPPIQ*) iqNode node:(NSString*) node accessModel:(NSString*) accessModel andHandler:(NSDictionary*) handler
{
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub configure request 1: %@", iqNode);
        //signal error
        [self callStaticHandler:handler withDefaultArguments:@[account, iqNode]];
        return;
    }
    
    XMPPDataForm* dataForm = [[iqNode findFirst:@"{http://jabber.org/protocol/pubsub#owner}pubsub/configure/{jabber:x:data}x"] copy];
    if(!dataForm)
    {
        DDLogError(@"Server returned invalid config form, aborting!");
        //abort config operation
        XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
        [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[
                [[XMPPDataForm alloc] initWithType:@"cancel" andFormType:@"http://jabber.org/protocol/pubsub#node_config"]
            ] andData:nil]
        ] andData:nil]];
        [account send:query];
        //signal error
        [self callStaticHandler:handler withDefaultArguments:@[account, iqNode]];
        return;
    }
    if(!dataForm[@"pubsub#persist_items"] || !dataForm[@"pubsub#access_model"] || ![dataForm getField:@"pubsub#access_model"][@"options"][accessModel])
    {
        DDLogError(@"Server returned config form not containing the required fields or options, aborting!");
        //abort config operation
        XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
        [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[
                [[XMPPDataForm alloc] initWithType:@"cancel" andFormType:@"http://jabber.org/protocol/pubsub#node_config"]
            ] andData:nil]
        ] andData:nil]];
        [account send:query];
        //signal error
        [self callStaticHandler:handler withDefaultArguments:@[account, iqNode]];
        return;
    }
    
    //change requested values
    dataForm[@"pubsub#persist_items"] = @"true";
    dataForm[@"pubsub#access_model"] = accessModel;
    
    //reconfigure the node
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[dataForm] andData:nil]
    ] andData:nil]];
    [account sendIq:query withDelegate:self andMethod:@selector(handleConfigureResult2For:withIqNode:andHandler:) andAdditionalArguments:@[handler]];
}

+(void) handleConfigureResult2For:(xmpp*) account withIqNode:(XMPPIQ*) iqNode andHandler:(NSDictionary*) handler
{
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub configure request 2: %@", iqNode);
        //signal error
        [self callStaticHandler:handler withDefaultArguments:@[account, iqNode]];
        return;
    }
    
    //inform handler of successful completion of config request
    [self callStaticHandler:handler withDefaultArguments:@[account, [NSNull null]]];
}

+(void) handlePublishAgainFor:(xmpp*) account withError:(MLXMLNode*) error item:(MLXMLNode*) item node:(NSString*) node andAccessModel:(NSString*) accessModel
{
    MLPubSub* me = account.pubsub;
    
    if(error)
    {
        DDLogError(@"Publish failed for node '%@' even after configuring it: %@", node, error);
        return;
    }
    
    //try again
    [me publishItem:item onNode:node withAccessModel:accessModel];
}

+(void) handlePublishResultFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode item:(MLXMLNode*) item node:(NSString*) node andAccessModel:(NSString*) accessModel
{
    MLPubSub* me = account.pubsub;
    
    if([iqNode check:@"/<type=error>"])
    {
        //check if this node is already present and configured --> reconfigure it according to our access-model
        if([iqNode check:@"error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}conflict/{http://jabber.org/protocol/pubsub#errors}precondition-not-met"])
        {
            DDLogWarn(@"Node precondition not met, reconfiguring node %@", node);
            [me configureNode:node withAccessModel:accessModel withDelegate:self andMethod:@selector(handlePublishAgainFor:withError:item:node:andAccessModel:) andAdditionalArguments:@[item, node, accessModel]];
        }
        return;
    }
    
    //update local cache of own data
    NSString* itemId = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/publish/item@id"];
    if(!itemId)
    {
        DDLogWarn(@"Item id should not be empty! Check your server!");
        return;     //ignore those buggy stuff
    }
    MLXMLNode* cacheEntry = [item copy];        //make sure we don't change the original
    cacheEntry.attributes[@"id"] = itemId;      //add/update id attribute
    MLXMLNode* itemsNode = [[MLXMLNode alloc] initWithElement:@"items" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{
        @"node": [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/publish@node"]
    } andChildren:@[cacheEntry] andData:nil];
    //update our cache
    [me handleItems:itemsNode fromJid:iqNode.fromUser updated:NO informHandlers:YES idList:[[NSMutableSet alloc] init]];
}

+(void) handleRetractResultFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode andNode:(NSString*) node andItemId:(NSString*) itemId
{
    MLPubSub* me = account.pubsub;
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Retract failed: %@", iqNode);
        return;
    }
    
    MLXMLNode* itemsNode = [[MLXMLNode alloc] initWithElement:@"items" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{@"node": node} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"retract" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil]
    ] andData:nil];
    //update our cache
    [me handleRetraction:itemsNode fromJid:iqNode.fromUser updated:NO informHandlers:YES idList:[[NSMutableSet alloc] init]];
}

+(void) handlePurgeOrDeleteResultFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode andNode:(NSString*) node
{
    MLPubSub* me = account.pubsub;
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Purge/Delete failed: %@", iqNode);
        return;
    }
    
    //purge/delete locally, too
    NSSet* purgedIds = [[NSSet alloc] init];
    if(me->_cache[node] && me->_cache[node][@"data"][iqNode.fromUser])
    {
        purgedIds = [NSSet setWithArray:[me->_cache[node][@"data"][iqNode.fromUser] allKeys]];
        me->_cache[node][@"data"][iqNode.fromUser] = [[NSMutableDictionary alloc] init];
    }
    [me callHandlersForNode:node andJid:iqNode.fromUser andChangedIdList:purgedIds];
}

@end
