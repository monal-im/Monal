//
//  MLPubSub.m
//  monalxmpp
//
//  Created by Thilo Molitor on 20.09.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPubSub.h"
#import "MLHandler.h"
#import "xmpp.h"
#import "MLXMLNode.h"
#import "XMPPDataForm.h"
#import "XMPPStanza.h"
#import "XMPPIQ.h"
#import "XMPPMessage.h"
#import "HelperTools.h"

#define CURRENT_PUBSUB_DATA_VERSION @6

@interface MLPubSub ()
{
    __weak xmpp* _account;
    NSMutableDictionary* _registeredHandlers;
    NSMutableArray* _queue;
}
@end

@implementation MLPubSub

static NSDictionary* _defaultOptions;

+(void) initialize
{
    _defaultOptions = @{
        @"pubsub#notify_retract": @"true",
        @"pubsub#notify_delete": @"true"
    };
}

-(id) initWithAccount:(xmpp*) account
{
    self = [super init];
    _account = account;
    _registeredHandlers = [NSMutableDictionary new];
    _queue = [NSMutableArray new];
    //retry our pubsub operation as soon as possible
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAccountDiscoReady:) name:kMonalAccountDiscoDone object:nil];
    return self;
}

-(void) registerForNode:(NSString*) node withHandler:(MLHandler*) handler
{
    DDLogInfo(@"Adding PEP handler %@ for node %@", handler, node);
    @synchronized(_registeredHandlers) {
        if(!_registeredHandlers[node])
            _registeredHandlers[node] = [NSMutableDictionary new];
        _registeredHandlers[node][handler.id] = handler;
        [_account setPubSubNotificationsForNodes:[_registeredHandlers allKeys] persistState:NO];
    }
}

-(void) unregisterHandler:(MLHandler*) handler forNode:(NSString*) node
{
    DDLogInfo(@"Removing PEP handler %@ for node %@", handler, node);
    @synchronized(_registeredHandlers) {
        if(!_registeredHandlers[node])
            return;
        [_registeredHandlers[node] removeObjectForKey:handler.id];
        [_account setPubSubNotificationsForNodes:[_registeredHandlers allKeys] persistState:NO];
    }
}

-(void) handleAccountDiscoReady:(NSNotification*) notification
{
    if(_account.accountNo.intValue != ((xmpp*)notification.object).accountNo.intValue)
        return;
    //we clear the queue so that the invalidation handlers can't get called twice:
    //once as invalidation of the queued operation handler and once as the invalidation of an iq handler of this operation
    //note: these are two different handler object, hence the double invalidation would *not* be catched by the handler framework!
    NSArray* queue;
    @synchronized(_queue) {
        queue = [_queue copy];
        _queue = [NSMutableArray new];
    }
    for(MLHandler* handler in queue)
        $call(handler, $ID(account, _account));
}

$$instance_handler(queuedFetchNodeHandler, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $_ID(NSArray*, itemsList), $$HANDLER(handler))
    [self fetchNode:node from:jid withItemsList:itemsList andHandler:handler];
$$
-(void) fetchNode:(NSString*) node from:(NSString*) jid withItemsList:(NSArray* _Nullable) itemsList andHandler:(MLHandler*) handler
{
    DDLogInfo(@"Fetching node '%@' at jid '%@' using callback %@...", node, jid, handler);
    xmpp* account = _account;
    
    if(!account.connectionProperties.accountDiscoDone)
    {
        DDLogWarn(@"Queueing pubsub call until account disco is resolved...");
        [_queue addObject:$newHandlerWithInvalidation(self, queuedFetchNodeHandler, handleFetchInvalidation, $ID(node), $ID(jid), $ID(itemsList), $HANDLER(handler))];
        return;
    }

    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@' and jid '%@'!", node, jid);
        return;
    }
    if(jid != nil)
    {
        NSDictionary* splitJid = [HelperTools splitJid:jid];
        MLAssert(splitJid[@"resource"] == nil, @"Jid MUST be a bare jid, not full jid!");
    }
    
    //build list of items to query (empty list means all items)
    if(!itemsList)
        itemsList = @[];
    NSMutableArray* queryItems = [NSMutableArray new];
    for(NSString* itemId in itemsList)
        [queryItems addObject:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil]];
    
    //build query
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:jid];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil]
    ] andData:nil]];

    [account sendIq:query withHandler:$newHandlerWithInvalidation(self, handleFetch, handleFetchInvalidation,
        $ID(node),
        $ID(jid),
        $ID(queryItems),
        $ID(data, [NSMutableDictionary new]),
        $HANDLER(handler),
    )];
}

$$instance_handler(queuedSubscribeToNodeHandler, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$HANDLER(handler))
    [self subscribeToNode:node onJid:jid withHandler:handler];
$$
-(void) subscribeToNode:(NSString*) node onJid:(NSString*) jid withHandler:(MLHandler*) handler
{
    DDLogInfo(@"Subscribing to node '%@' at jid '%@' using callback %@...", node, jid, handler);
    xmpp* account = _account;
    
    if(!account.connectionProperties.accountDiscoDone)
    {
        DDLogWarn(@"Queueing pubsub call until account disco is resolved...");
        [_queue addObject:$newHandlerWithInvalidation(self, queuedSubscribeToNodeHandler, handleSubscribeInvalidation, $ID(node), $ID(jid), $HANDLER(handler))];
        return;
    }
    
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@' and jid '%@'!", node, jid);
        return;
    }
    if(jid != nil)
    {
        NSDictionary* splitJid = [HelperTools splitJid:jid];
        MLAssert(splitJid[@"resource"] == nil, @"Jid MUST be a bare jid, not full jid!");
    }
    
    //build subscription request
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType to:jid];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"subscribe" withAttributes:@{
            @"node": node,
            @"jid": account.connectionProperties.identity.jid,
        } andChildren:@[] andData:nil]
    ] andData:nil]];

    [account sendIq:query withHandler:$newHandlerWithInvalidation(self, handleSubscribe, handleSubscribeInvalidation,
        $ID(node),
        $ID(jid),
        $HANDLER(handler),
    )];
}

$$instance_handler(queuedUnsubscribeFromNodeHandler, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $_HANDLER(handler))
    [self unsubscribeFromNode:node forJid:jid withHandler:handler];
$$
-(void) unsubscribeFromNode:(NSString*) node forJid:(NSString*) jid withHandler:(MLHandler* _Nullable) handler
{
    DDLogInfo(@"Unsubscribing from node '%@' at jid '%@' using callback %@...", node, jid, handler);
    
    if(!_account.connectionProperties.accountDiscoDone)
    {
        DDLogWarn(@"Queueing pubsub call until account disco is resolved...");
        [_queue addObject:$newHandlerWithInvalidation(self, queuedUnsubscribeFromNodeHandler, handleUnsubscribeInvalidation, $ID(node), $ID(jid), $HANDLER(handler))];
        return;
    }
    
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@' and jid '%@'!", node, jid);
        return;
    }
    
    if(jid != nil)
    {
        NSDictionary* splitJid = [HelperTools splitJid:jid];
        MLAssert(splitJid[@"resource"] == nil, @"Jid MUST be a bare jid, not full jid!");
    }
    
    //build subscription request
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType to:jid];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"unsubscribe" withAttributes:@{
            @"node": node,
            @"jid": _account.connectionProperties.identity.jid,
        } andChildren:@[] andData:nil]
    ] andData:nil]];

    [_account sendIq:query withHandler:$newHandlerWithInvalidation(self, handleUnsubscribe, handleUnsubscribeInvalidation,
        $ID(node),
        $ID(jid),
        $HANDLER(handler),
    )];
}

$$instance_handler(queuedConfigureNodeHandler, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    [self configureNode:node withConfigOptions:configOptions andHandler:handler];
$$
-(void) configureNode:(NSString*) node withConfigOptions:(NSDictionary*) configOptions andHandler:(MLHandler* _Nullable) handler
{
    xmpp* account = _account;
    
    if(!account.connectionProperties.accountDiscoDone)
    {
        DDLogWarn(@"Queueing pubsub call until account disco is resolved...");
        [_queue addObject:$newHandlerWithInvalidation(self, queuedConfigureNodeHandler, handleConfigFormResultInvalidation, $ID(node), $ID(configOptions), $HANDLER(handler))];
        return;
    }
    
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandlerWithInvalidation(self, handleConfigFormResult, handleConfigFormResultInvalidation,
        $ID(node),
        $ID(configOptions),
        $HANDLER(handler)
    )];
}

-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node
{
    [self publishItem:item onNode:node withConfigOptions:nil andHandler:nil];
}

-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withHandler:(MLHandler* _Nullable) handler
{
    [self publishItem:item onNode:node withConfigOptions:nil andHandler:handler];
}

-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions
{
    [self publishItem:item onNode:node withConfigOptions:configOptions andHandler:nil];
}

$$instance_handler(queuedPublishItemHandler, account.pubsub, $$ID(xmpp*, account), $$ID(MLXMLNode*, item), $$ID(NSString*, node), $_ID(NSDictionary*, configOptions), $_HANDLER(handler))
    [self publishItem:item onNode:node withConfigOptions:configOptions andHandler:handler];
$$
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions andHandler:(MLHandler* _Nullable) handler
{
    if(!_account.connectionProperties.accountDiscoDone)
    {
        DDLogWarn(@"Queueing pubsub call until account disco is resolved...");
        [_queue addObject:$newHandlerWithInvalidation(self, queuedPublishItemHandler, handlePublishResultInvalidation, $ID(item), $ID(node), $ID(configOptions), $HANDLER(handler))];
        return;
    }
    
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    if(!configOptions)
        configOptions = @{};
    
    //update config options with our own defaults if not already present
    configOptions = [self copyDefaultNodeOptions:_defaultOptions forConfigForm:nil into:configOptions];
    
    [self internalPublishItem:item onNode:node withConfigOptions:configOptions andHandler:handler];
}

-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node
{
    [self retractItemWithId:itemId onNode:node andHandler:nil];
}

$$instance_handler(queuedRetractItemWithIdHandler, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, itemId), $$ID(NSString*, node), $_HANDLER(handler))
    [self retractItemWithId:itemId onNode:node andHandler:handler];
$$
-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler
{
    xmpp* account = _account;
    
    if(!account.connectionProperties.accountDiscoDone)
    {
        DDLogWarn(@"Queueing pubsub call until account disco is resolved...");
        [_queue addObject:$newHandlerWithInvalidation(self, queuedRetractItemWithIdHandler, handleRetractResultInvalidation, $ID(itemId), $ID(node), $HANDLER(handler))];
        return;
    }
    
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    DDLogDebug(@"Retracting item '%@' on node '%@'", itemId, node);
    MLXMLNode* item = [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil];
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"retract" withAttributes:@{@"node": node, @"notify": @"true"} andChildren:@[item] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandlerWithInvalidation(self, handleRetractResult, handleRetractResultInvalidation,
        $ID(node),
        $ID(itemId),
        $HANDLER(handler)
    )];
}

-(void) purgeNode:(NSString*) node
{
    [self purgeNode:node andHandler:nil];
}

$$instance_handler(queuedPurgeNodeNodeHandler, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $_HANDLER(handler))
    [self purgeNode:node andHandler:handler];
$$
-(void) purgeNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler
{
    xmpp* account = _account;
    
    if(!account.connectionProperties.accountDiscoDone)
    {
        DDLogWarn(@"Queueing pubsub call until account disco is resolved...");
        [_queue addObject:$newHandlerWithInvalidation(self, queuedPurgeNodeNodeHandler, handlePurgeOrDeleteResultInvalidation, $ID(node), $HANDLER(handler))];
        return;
    }
    
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"purge" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandlerWithInvalidation(self, handlePurgeOrDeleteResult, handlePurgeOrDeleteResultInvalidation,
        $ID(node),
        $HANDLER(handler)
    )];
}

-(void) deleteNode:(NSString*) node
{
    [self deleteNode:node andHandler:nil];
}

$$instance_handler(queuedDeleteNodeHandler, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $_HANDLER(handler))
    [self deleteNode:node andHandler:handler];
$$
-(void) deleteNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler
{
    xmpp* account = _account;
    
    if(!account.connectionProperties.accountDiscoDone)
    {
        DDLogWarn(@"Queueing pubsub call until account disco is resolved...");
        [_queue addObject:$newHandlerWithInvalidation(self, queuedDeleteNodeHandler, handlePurgeOrDeleteResultInvalidation, $ID(node), $HANDLER(handler))];
        return;
    }
    
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"delete" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandlerWithInvalidation(self, handlePurgeOrDeleteResult, handlePurgeOrDeleteResultInvalidation,
        $ID(node),
        $HANDLER(handler)
    )];
}

//*** framework methods below

-(NSDictionary*) getInternalData
{
    @synchronized(_queue) {
        return @{
            @"version": CURRENT_PUBSUB_DATA_VERSION,
            @"queue": [_queue copy],
        };
    }
}

-(void) setInternalData:(NSDictionary*) data
{
    DDLogDebug(@"Loading internal pubsub data");
    @synchronized(_queue) {
        if(!data[@"version"] || ![data[@"version"] isEqualToNumber:CURRENT_PUBSUB_DATA_VERSION])
            return;     //ignore old data
        _queue = [data[@"queue"] mutableCopy];
    }
}

-(void) invalidateQueue
{
    //we clear the queue so that the invalidation handlers can't get called twice:
    //once as invalidation of the queued operation handler and once as the invalidation of an iq handler of this operation
    //note: these are two different handler object, hence the double invalidation would *not* be catched by the handler framework!
    NSArray* queue;
    @synchronized(_queue) {
        queue = [_queue copy];
        _queue = [NSMutableArray new];
    }
    for(MLHandler* handler in queue)
        $invalidate(handler, $ID(account, _account));
}

-(void) handleHeadlineMessage:(XMPPMessage*) messageNode
{
    NSString* node = [messageNode findFirst:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/{*}*@node"];
    if(!node)
    {
        DDLogWarn(@"Got pubsub data without node attribute!");
        return;
    }
    
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogError(@"Pubsub not supported, ignoring this call for headline message (THIS SHOULD NEVER HAPPEN): %@", messageNode);
        return;
    }
    
    DDLogDebug(@"Handling pubsub data for node '%@'", node);
    
    //handle node purge
    if([messageNode check:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/purge"])
    {
        DDLogDebug(@"Handling purge");
        [self callHandlersForNode:node andJid:messageNode.fromUser withType:@"purge" andData:nil];
        return;     //we are done here (no items element for purge events)
    }
    
    //handle node delete
    if([messageNode check:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/delete"])
    {
        DDLogDebug(@"Handling delete");
        [self callHandlersForNode:node andJid:messageNode.fromUser withType:@"delete" andData:nil];
        return;     //we are done here (no items element for delete events)
    }
    
    //handle published items
    MLXMLNode* items = [messageNode findFirst:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/items"];
    if(!items)
    {
        DDLogWarn(@"Got pubsub event data without items node, ignoring!");
        return;
    }
    
    //handle item delete
    if([items check:@"retract"])
    {
        DDLogDebug(@"Handling retract");
        NSMutableDictionary* data = [self handleRetraction:items fromJid:messageNode.fromUser withData:[NSMutableDictionary new]];
        if(data)        //ignore unexpected/wrong data
            [self callHandlersForNode:node andJid:messageNode.fromUser withType:@"retract" andData:data];
    }
    
    //handle xep-0060 6.5.6 (check if payload is included or if it has to be fetched separately)
    if([items check:@"item/{*}*"])
    {
        DDLogDebug(@"Handling publish");
        NSMutableDictionary* data = [self handleItems:items fromJid:messageNode.fromUser withData:[NSMutableDictionary new]];
        if(data)        //ignore unexpected/wrong data
            [self callHandlersForNode:node andJid:messageNode.fromUser withType:@"publish" andData:data];
    }
    else
    {
        DDLogDebug(@"Handling truncated publish");
        [self fetchNode:node from:messageNode.fromUser withItemsList:[items find:@"item@id"] andHandler:$newHandler(self, handleInternalFetch, $ID(node))];
    }
}

//*** internal methods below

-(void) internalPublishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary*) configOptions andHandler:(MLHandler* _Nullable) handler
{
    DDLogDebug(@"Publishing item on node '%@': %@", node, item);
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"publish" withAttributes:@{@"node": node} andChildren:@[item] andData:nil]
    ] andData:nil]];
    //only add publish-options if present
    if([configOptions count] > 0)
        [(MLXMLNode*)[query findFirst:@"{http://jabber.org/protocol/pubsub}pubsub"] addChildNode:[[MLXMLNode alloc] initWithElement:@"publish-options" withAttributes:@{} andChildren:@[
            [[XMPPDataForm alloc] initWithType:@"submit" formType:@"http://jabber.org/protocol/pubsub#publish-options" andDictionary:configOptions]
        ] andData:nil]];
    [_account sendIq:query withHandler:$newHandlerWithInvalidation(self, handlePublishResult, handlePublishResultInvalidation,
        $ID(item),
        $ID(node),
        $ID(configOptions),
        $HANDLER(handler)
    )];
}

//NOTE: this will be called for iq *or* message stanzas carrying pubsub data.
-(NSMutableDictionary*) handleItems:(MLXMLNode* _Nullable) items fromJid:(NSString* _Nullable) jid withData:(NSMutableDictionary*) data
{
    if(!items)
    {
        DDLogWarn(@"Got pubsub data without items node!");
        return nil;
    }
    
    NSString* node = [items findFirst:@"/@node"];
    if(!node)
    {
        DDLogWarn(@"Got pubsub data without node attribute!");
        return nil;
    }
    DDLogDebug(@"Processing pubsub data from jid '%@' for node '%@'", jid, node);
    for(MLXMLNode* item in [items find:@"item"])
    {
        NSString* itemId = [item findFirst:@"/@id"];
        if(!itemId)
            itemId = @"";
        data[itemId] = [item copy];     //make a copy to make sure the original iq stanza won't be changed by a handler modifying the items
    }
    return data;
}

//NOTE: this will be called for message stanzas carrying pubsub data.
-(NSMutableDictionary*) handleRetraction:(MLXMLNode* _Nullable) items fromJid:(NSString* _Nullable) jid withData:(NSMutableDictionary*) data
{
    if(!items)
    {
        DDLogWarn(@"Got pubsub retraction without items node!");
        return nil;
    }
    
    NSString* node = [items findFirst:@"/@node"];
    if(!node)
    {
        DDLogWarn(@"Got pubsub data without node attribute!");
        return nil;
    }
    DDLogDebug(@"Removing some pubsub items from jid '%@' for node '%@'", jid, node);
    for(MLXMLNode* item in [items find:@"retract"])
    {
        NSString* itemId = [item findFirst:@"/@id"];
        if(!itemId)
            itemId = @"";
        DDLogDebug(@"Deleting pubsub item with id '%@' from jid '%@' for node '%@'", itemId, jid, node);
        data[itemId] = @YES;
    }
    return data;
}

-(void) callHandlersForNode:(NSString*) node andJid:(NSString*) jid withType:(NSString*) type andData:(NSDictionary*) data
{
    xmpp* account = _account;
    DDLogInfo(@"Calling pubsub handlers for node '%@' (and jid '%@')", node, jid);
    NSDictionary* handlers;
    @synchronized(_registeredHandlers) {
        handlers = [[NSDictionary alloc] initWithDictionary:_registeredHandlers[node] copyItems:YES];
    }
    for(NSString* handlerId in handlers)
        $call(handlers[handlerId],
            $ID(account),
            $ID(node),
            $ID(jid),
            $ID(type),
            $ID(data)
        );
    DDLogDebug(@"All pubsub handlers called");
}

-(NSDictionary*) copyDefaultNodeOptions:(NSDictionary*) defaultOptions forConfigForm:(XMPPDataForm* _Nullable) configForm into:(NSDictionary*) configOptions
{
    NSMutableDictionary* retval = [configOptions mutableCopy];
    for(NSString* option in defaultOptions)
        if((configForm == nil || configForm[option] != nil) && retval[option] == nil)
            retval[option] = defaultOptions[option];
    return retval;
}

$$instance_handler(handleSubscribeInvalidation, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$HANDLER(handler))
    //invalidate our user handler
    $invalidate(handler,
        $ID(account),
        $BOOL(success, NO),
        $ID(node),
        $ID(jid),
    );
$$

$$instance_handler(handleSubscribe, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSString*, jid), $$HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub subscribe request: %@", iqNode);
        //call subscribe callback (if given) with error iq node
        $call(handler,
            $ID(account),
            $BOOL(success, NO),
            $ID(node),
            $ID(jid, iqNode.fromUser),
            $ID(errorIq, iqNode)
        );
        return;
    }
    
    if([iqNode check:@"{http://jabber.org/protocol/pubsub}pubsub/subscription<node=%@><jid=%@><subscription=subscribed>", node, account.connectionProperties.identity.jid])
    {
        DDLogDebug(@"Successfully subscribed to node '%@' on jid '%@' for '%@'...", node, iqNode.fromUser, account.connectionProperties.identity.jid);
        
        //call subscribe callback (if given)
        $call(handler,
            $ID(account),
            $BOOL(success, YES),
            $ID(node),
            $ID(jid, iqNode.fromUser)
        );
    }
    else
    {
        DDLogError(@"Could not subscribe to node '%@' on jid '%@' for '%@': %@", node, iqNode.fromUser, account.connectionProperties.identity.jid, iqNode);
        
        //call subscribe callback (if given) with error iq node
        $call(handler,
            $ID(account),
            $BOOL(success, NO),
            $ID(node),
            $ID(jid, iqNode.fromUser),
            $ID(errorReason, @"Unexpected iq result (wrong node or jid)!")
        );
    }
$$

$$instance_handler(handleUnsubscribeInvalidation, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $_HANDLER(handler))
    //invalidate our user handler
    $invalidate(handler,
        $ID(account),
        $BOOL(success, NO),
        $ID(node),
        $ID(jid)
    );
$$

$$instance_handler(handleUnsubscribe, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSString*, jid), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq from pubsub unsubscribe request: %@", iqNode);
        //call unsubscribe callback (if given) with error iq node
        $call(handler,
            $ID(account),
            $BOOL(success, NO),
            $ID(node),
            $ID(jid, iqNode.fromUser),
            $ID(errorIq, iqNode)
        );
        return;
    }

    if([iqNode check:@"{http://jabber.org/protocol/pubsub}pubsub/subscription<node=%@><jid=%@><subscription=none>", node, jid])
    {
        DDLogDebug(@"Successfully unsubscribed from node '%@' on jid '%@'...", node, iqNode.fromUser);

        //call unsubscribe callback (if given)
        $call(handler,
            $ID(account),
            $BOOL(success, YES),
            $ID(node),
            $ID(jid, iqNode.fromUser)
        );
    }
    else
    {
        DDLogError(@"Could not unsubscribe from node '%@' on jid '%@': %@", node, iqNode.fromUser, iqNode);

        //call unsubscribe callback (if given) with error iq node
        $call(handler,
            $ID(account),
            $BOOL(success, NO),
            $ID(node),
            $ID(jid, iqNode.fromUser),
            $ID(errorReason, @"Unexpected iq result (wrong node or jid)!")
        );
    }
$$

$$instance_handler(handleFetchInvalidation, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$HANDLER(handler))
    //invalidate user handler
    $invalidate(handler,
        $ID(account),
        $BOOL(success, NO),
        $ID(node),
        $ID(jid)
    );
$$

$$instance_handler(handleFetch, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSString*, jid), $$ID(NSMutableArray*, queryItems), $$ID(NSMutableDictionary*, data), $$HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub fetch request: %@", iqNode);
        //call fetch callback (if given) with error iq node
        $call(handler,
            $ID(account),
            $BOOL(success, NO),
            $ID(node),
            $ID(jid, iqNode.fromUser),
            $ID(errorIq, iqNode)
        );
        return;
    }
    
    NSString* first = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/first#"];
    NSString* last = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/last#"];
    NSUInteger index = [[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/first@index|int"] unsignedIntegerValue];
    NSUInteger total_count = [[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/count#|int"] unsignedIntegerValue];
    NSUInteger items_count = [[iqNode find:@"{http://jabber.org/protocol/pubsub}pubsub/items/item"] count];
    //check for rsm paging
    if(
        !last ||                                //no rsm at all
        [last isEqualToString:first] ||         //reached end of rsm (only one element, e.g. last==first)
        index + items_count == total_count      //reached end of rsm per rsm xep (this is a SHOULD)
    ) {
        //--> process data *and* inform handlers of new data
        [self handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser withData:data];
        //call fetch callback (if given)
        $call(handler,
            $ID(account),
            $BOOL(success, YES),
            $ID(node),
            $ID(jid, iqNode.fromUser),
            $ID(data)
        );
    }
    else if(first && last)
    {
        //only process data but *don't* call fetch callback because the data is still partial
        [self handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser withData:data];
        XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:iqNode.fromUser];
        [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil],
            [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"after" withAttributes:@{} andChildren:@[] andData:last]
            ] andData:nil]
        ] andData:nil]];
        [account sendIq:query withHandler:$newHandlerWithInvalidation(self, handleFetch, handleFetchInvalidation,
            $ID(node),
            $ID(jid, iqNode.fromUser),
            $ID(queryItems),
            $ID(data),
            $HANDLER(handler)
        )];
    }
$$

$$instance_handler(handleInternalFetch, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$BOOL(success), $$ID(NSString*, jid), $_ID(NSDictionary*, data))
    if(success != NO && data != nil)        //ignore errors (--> ignore invalidations, too)
        [self callHandlersForNode:node andJid:jid withType:@"publish" andData:data];
$$

$$instance_handler(handleConfigFormResultInvalidation, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $_HANDLER(handler))
    //invalidate user handler
    $invalidate(handler, $ID(account), $BOOL(success, NO), $ID(node));
$$

$$instance_handler(handleConfigFormResult, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub configure request 1: %@", iqNode);
        //signal error if a handler was given
        $call(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(errorIq, iqNode));
        return;
    }
    
    XMPPDataForm* dataForm = [[iqNode findFirst:@"{http://jabber.org/protocol/pubsub#owner}pubsub/configure/\\{http://jabber.org/protocol/pubsub#node_config}form\\"] copy];
    if(!dataForm)
    {
        DDLogError(@"Server returned invalid config form, aborting!");
        //abort config operation
        XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
        [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[
                [[XMPPDataForm alloc] initWithType:@"cancel" andFormType:@"http://jabber.org/protocol/pubsub#node_config"]
            ] andData:nil]
        ] andData:nil]];
        [account send:query];
        //signal error if a handler was given
        $call(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(errorReason, NSLocalizedString(@"Unexpected server response: invalid PEP config form", @"")));
        return;
    }
    
    //update config options with our own defaults if not already present
    configOptions = [self copyDefaultNodeOptions:_defaultOptions forConfigForm:dataForm into:configOptions];
    
    for(NSString* option in configOptions)
    {
        if(!dataForm[option])
        {
            DDLogError(@"Server returned config form not containing the required fields or options, aborting! Required field: %@", option);
            //abort config operation
            XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
            [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[
                    [[XMPPDataForm alloc] initWithType:@"cancel" andFormType:@"http://jabber.org/protocol/pubsub#node_config"]
                ] andData:nil]
            ] andData:nil]];
            [account send:query];
            //signal error if a handler was given
            $call(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(errorReason, NSLocalizedString(@"Unexpected server response: missing required fields in PEP config form", @"")));
            return;
        }
        else
            dataForm[option] = configOptions[option];       //change requested value
    }
    
    //reconfigure the node
    dataForm.type = @"submit";
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[dataForm] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandlerWithInvalidation(self, handleConfigureResult, handleConfigureResultInvalidation,
        $ID(node),
        $HANDLER(handler)
    )];
$$

$$instance_handler(handleConfigureResultInvalidation, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $_HANDLER(handler))
    //invalidate user handler
    $invalidate(handler, $ID(account), $BOOL(success, NO), $ID(node));
$$

$$instance_handler(handleConfigureResult, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(XMPPIQ*, iqNode), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub configure request 2: %@", iqNode);
        //signal error if a handler was given
        $call(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(errorIq, iqNode));
        return;
    }
    //inform handler of successful completion of config request
    $call(handler, $ID(account), $BOOL(success, YES), $ID(node));
$$

//this is a user handler for configureNode: called from handlePublishResult
$$instance_handler(handlePublishAgainInvalidation, account.pubsub, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node), $_HANDLER(handler))
    //invalidate user handler
    $invalidate(handler, $ID(account), $BOOL(success), $ID(node));
$$

//this is a user handler for configureNode: called from handlePublishResult
$$instance_handler(handlePublishAgain, account.pubsub, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $$ID(MLXMLNode*, item), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    if(!success)
    {
        DDLogError(@"Publish failed for node '%@' even after configuring it!", node);
        $call(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(errorIq), $ID(errorReason));
        return;
    }
    
    //try again
    [self internalPublishItem:item onNode:node withConfigOptions:configOptions andHandler:handler];
$$

//this is a user handler for internalPublishItem: called from handlePublishResult
$$instance_handler(handleConfigureAfterPublishInvalidation, account.pubsub, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, node), $_HANDLER(handler))
    //invalidate user handler
    $invalidate(handler, $ID(account), $BOOL(success), $ID(node));
$$

//this is a user handler for internalPublishItem: called from handlePublishResult
$$instance_handler(handleConfigureAfterPublish, account.pubsub, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    if(!success)
    {
        DDLogError(@"Second publish attempt failed again for node '%@', not configuring it!", node);
        $call(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(errorIq), $ID(errorReason));
        return;
    }
    
    //configure node after publishing it
    [self configureNode:node withConfigOptions:configOptions andHandler:handler];
$$

$$instance_handler(handlePublishResultInvalidation, account.pubsub, $$ID(xmpp*, account), $$ID(MLXMLNode*, item), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    //invalidate user handler
    $invalidate(handler, $ID(account), $BOOL(success, NO), $ID(node));
$$

$$instance_handler(handlePublishResult, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(MLXMLNode*, item), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        //NOTE: workaround for old ejabberd versions <= 21.07 only supporting two special settings as preconditions
        if([@"http://www.process-one.net/en/ejabberd/" isEqualToString:account.connectionProperties.serverIdentity] && [configOptions count] > 0 && [iqNode check:@"error<type=wait>/{urn:ietf:params:xml:ns:xmpp-stanzas}resource-constraint"])
        {
            DDLogWarn(@"ejabberd (~21.07) workaround for old preconditions handling active for node: %@", node);
            
            //make sure we don't try all preconditions from configOptions again: only these two listed preconditions are safe to use with ejabberd
            NSMutableDictionary* publishPreconditions = [NSMutableDictionary new];
            if(configOptions[@"pubsub#persist_items"])
                publishPreconditions[@"pubsub#persist_items"] = configOptions[@"pubsub#persist_items"];
            if(configOptions[@"pubsub#persist_items"])
                publishPreconditions[@"pubsub#access_model"] = configOptions[@"pubsub#access_model"];
            
            [self internalPublishItem:item onNode:node withConfigOptions:publishPreconditions andHandler:$newHandlerWithInvalidation(self, handleConfigureAfterPublish, handleConfigureAfterPublishInvalidation,
                $ID(node),
                $ID(configOptions),
                $HANDLER(handler)
            )];
            return;
        }
        
        //check if this node is already present and configured --> reconfigure it according to our access-model
        if([iqNode check:@"error<type=cancel>/{http://jabber.org/protocol/pubsub#errors}precondition-not-met"])
        {
            DDLogWarn(@"Node precondition not met, reconfiguring node: %@", node);
            [self configureNode:node withConfigOptions:configOptions andHandler:$newHandlerWithInvalidation(self, handlePublishAgain, handlePublishAgainInvalidation,
                $ID(item),
                $ID(node),
                $ID(configOptions),      //modern servers support XEP-0060 Version 1.15.0 (2017-12-12) --> all node config options are allowed as preconditions
                $HANDLER(handler)
            )];
            return;
        }
        
        //all other errors are real errors --> inform user handler
        $call(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(errorIq, iqNode));
        return;
    }
    
    //no errors means everything worked out as expected
    $call(handler, $ID(account), $BOOL(success, YES), $ID(node));
$$

$$instance_handler(handleRetractResultInvalidation, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, itemId), $_HANDLER(handler))
    //invalidate user handler
    $invalidate(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(itemId));
$$

$$instance_handler(handleRetractResult, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSString*, itemId), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Retract for item '%@' of node '%@' failed: %@", itemId, node, iqNode);
        $call(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(itemId), $ID(errorIq, iqNode));
        return;
    }
    $call(handler, $ID(account), $BOOL(success, YES), $ID(node), $ID(itemId));
$$

$$instance_handler(handlePurgeOrDeleteResultInvalidation, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $_HANDLER(handler))
    //invalidate user handler
    $invalidate(handler, $ID(account), $BOOL(success, NO), $ID(node));
$$

$$instance_handler(handlePurgeOrDeleteResult, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Purge/Delete of node '%@' failed: %@", node, iqNode);
        $call(handler, $ID(account), $BOOL(success, NO), $ID(node), $ID(errorIq, iqNode));
        return;
    }
    $call(handler, $ID(account), $BOOL(success, YES), $ID(node));
$$

@end
