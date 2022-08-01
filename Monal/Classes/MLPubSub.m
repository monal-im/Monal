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

#define CURRENT_PUBSUB_DATA_VERSION @4

@interface MLPubSub ()
{
    __weak xmpp* _account;
    NSMutableDictionary* _registeredHandlers;
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
    _registeredHandlers = [[NSMutableDictionary alloc] init];
    return self;
}

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, node), $$ID(NSString*, jid), $$ID(NSString*, type), $$ID(NSDictionary*, data))
-(void) registerForNode:(NSString*) node withHandler:(MLHandler*) handler
{
    DDLogInfo(@"Adding PEP handler %@ for node %@", handler, node);
    @synchronized(_registeredHandlers) {
        if(!_registeredHandlers[node])
            _registeredHandlers[node] = [[NSMutableDictionary alloc] init];
        _registeredHandlers[node][handler.id] = handler;
        [_account setPubSubNotificationsForNodes:[_registeredHandlers allKeys] persistState:YES];
    }
}

//handler --> $$instance_handler given to registerForNode:withHandler:
-(void) unregisterHandler:(MLHandler*) handler forNode:(NSString*) node
{
    DDLogInfo(@"Removing PEP handler %@ for node %@", handler, node);
    @synchronized(_registeredHandlers) {
        if(!_registeredHandlers[node])
            return;
        [_registeredHandlers[node] removeObjectForKey:handler.id];
        [_account setPubSubNotificationsForNodes:[_registeredHandlers allKeys] persistState:YES];
    }
}

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), , $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID(NSDictionary*, data))
-(void) fetchNode:(NSString*) node from:(NSString*) jid withItemsList:(NSArray*) itemsList andHandler:(MLHandler*) handler
{
    DDLogInfo(@"Fetching node '%@' at jid '%@' using callback %@...", node, jid, handler);
    xmpp* account = _account;
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@' and jid '%@'!", node, jid);
        return;
    }
    
    //build list of items to query (empty list means all items)
    if(!itemsList)
        itemsList = @[];
    NSMutableArray* queryItems = [[NSMutableArray alloc] init];
    for(NSString* itemId in itemsList)
        [queryItems addObject:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil]];
    
    //build query
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:jid];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil]
    ] andData:nil]];

    [account sendIq:query withHandler:$newHandler(self, handleFetch, 
        $ID(node),
        $ID(queryItems),
        $ID(data, [[NSMutableDictionary alloc] init]),
        $HANDLER(handler),
    )];
}

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) subscribeToNode:(NSString*) node onJid:(NSString*) jid withHandler:(MLHandler*) handler
{
    DDLogInfo(@"Subscribing to node '%@' at jid '%@' using callback %@...", node, jid, handler);
    xmpp* account = _account;
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@' and jid '%@'!", node, jid);
        return;
    }
    
    //build subscription request
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType to:jid];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"subscribe" withAttributes:@{
            @"node": node,
            @"jid": account.connectionProperties.identity.jid,
        } andChildren:@[] andData:nil]
    ] andData:nil]];

    [account sendIq:query withHandler:$newHandler(self, handleSubscribe,
        $ID(node),
        $ID(jid),
        $HANDLER(handler),
    )];
}

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$ID(NSString*, jid), $$BOOL(success), , $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) unsubscribeFromNode:(NSString*) node forJid:(NSString*) jid withHandler:(MLHandler* _Nullable) handler
{
    DDLogInfo(@"Unsubscribing from node '%@' at jid '%@' using callback %@...", node, jid, handler);
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@' and jid '%@'!", node, jid);
        return;
    }
    //build subscription request
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType to:jid];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"unsubscribe" withAttributes:@{
            @"node": node,
            @"jid": _account.connectionProperties.identity.jid,
        } andChildren:@[] andData:nil]
    ] andData:nil]];

    [_account sendIq:query withHandler:$newHandler(self, handleUnsubscribe,
        $ID(node),
        $ID(jid),
        $HANDLER(handler),
    )];
}

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) configureNode:(NSString*) node withConfigOptions:(NSDictionary*) configOptions andHandler:(MLHandler* _Nullable) handler
{
    xmpp* account = _account;
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandler(self, handleConfigFormResult,
        $ID(node),
        $ID(configOptions),
        $HANDLER(handler)
    )];
}

-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node
{
    [self publishItem:item onNode:node withConfigOptions:nil andHandler:nil];
}

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withHandler:(MLHandler* _Nullable) handler
{
    [self publishItem:item onNode:node withConfigOptions:nil andHandler:handler];
}

-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions
{
    [self publishItem:item onNode:node withConfigOptions:configOptions andHandler:nil];
}

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions andHandler:(MLHandler* _Nullable) handler
{
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

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler
{
    xmpp* account = _account;
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    DDLogDebug(@"Retracting item '%@' on node '%@'", itemId, node);
    MLXMLNode* item = [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil];
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"retract" withAttributes:@{@"node": node} andChildren:@[item] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandler(self, handleRetractResult,
        $ID(node),
        $ID(itemId),
        $HANDLER(handler)
    )];
}

-(void) purgeNode:(NSString*) node
{
    [self purgeNode:node andHandler:nil];
}

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) purgeNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler
{
    xmpp* account = _account;
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"purge" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandler(self, handlePurgeOrDeleteResult,
        $ID(node),
        $HANDLER(handler)
    )];
}

-(void) deleteNode:(NSString*) node
{
    [self deleteNode:node andHandler:nil];
}

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) deleteNode:(NSString*) node andHandler:(MLHandler* _Nullable) handler
{
    xmpp* account = _account;
    if(!account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChildNode:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"delete" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandler(self, handlePurgeOrDeleteResult,
        $ID(node),
        $HANDLER(handler)
    )];
}

//*** framework methods below

-(NSDictionary*) getInternalData
{
    @synchronized(_registeredHandlers) {
        return @{
            @"version": CURRENT_PUBSUB_DATA_VERSION,
            @"handlers": _registeredHandlers
        };
    }
}

-(void) setInternalData:(NSDictionary*) data
{
    DDLogDebug(@"Loading internal pubsub data");
    @synchronized(_registeredHandlers) {
        if(!data[@"version"] || ![data[@"version"] isEqualToNumber:CURRENT_PUBSUB_DATA_VERSION])
            return;     //ignore old data
        _registeredHandlers = data[@"handlers"];
        //update caps hash according to our new _registeredHandlers dictionary
        //but don't persist state again (it was just read from persistent storage)
        [_account setPubSubNotificationsForNodes:[_registeredHandlers allKeys] persistState:NO];
    }
}

-(void) handleHeadlineMessage:(XMPPMessage*) messageNode
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for headline message: %@", messageNode);
        return;
    }
    NSString* node = [messageNode findFirst:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event/{*}*@node"];
    if(!node)
    {
        DDLogWarn(@"Got pubsub data without node attribute!");
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
        NSMutableDictionary* data = [self handleRetraction:items fromJid:messageNode.fromUser withData:[[NSMutableDictionary alloc] init]];
        if(data)        //ignore unexpected/wrong data
            [self callHandlersForNode:node andJid:messageNode.fromUser withType:@"retract" andData:data];
    }
    
    //handle xep-0060 6.5.6 (check if payload is included or if it has to be fetched separately)
    if([items check:@"item/{*}*"])
    {
        DDLogDebug(@"Handling publish");
        NSMutableDictionary* data = [self handleItems:items fromJid:messageNode.fromUser withData:[[NSMutableDictionary alloc] init]];
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
    [_account sendIq:query withHandler:$newHandler(self, handlePublishResult,
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
            $ID(account, account),
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

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, jid), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
$$instance_handler(handleSubscribe, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSString*, jid), $$HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub subscribe request: %@", iqNode);
        //call subscribe callback (if given) with error iq node
        $call(handler,
            $ID(account, account),
            $BOOL(success, NO),
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
            $ID(account, account),
            $BOOL(success, YES),
            $ID(jid, iqNode.fromUser)
        );
    }
    else
    {
        DDLogError(@"Could not subscribe to node '%@' on jid '%@' for '%@': %@", node, iqNode.fromUser, account.connectionProperties.identity.jid, iqNode);
        
        //call subscribe callback (if given) with error iq node
        $call(handler,
            $ID(account, account),
            $BOOL(success, NO),
            $ID(jid, iqNode.fromUser),
            $ID(errorReason, @"Unexpected iq result (wrong node or jid)!")
        );
    }
$$

//handler --> $$class_handler(xxx, $$ID(xmpp*, account), $$BOOL(success), $$ID(NSString*, jid), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
$$instance_handler(handleUnsubscribe, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSString*, jid), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq from pubsub unsubscribe request: %@", iqNode);
        //call unsubscribe callback (if given) with error iq node
        $call(handler,
            $ID(account, _account),
            $BOOL(success, NO),
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
            $ID(account, _account),
            $BOOL(success, YES),
            $ID(jid, iqNode.fromUser)
        );
    }
    else
    {
        DDLogError(@"Could not unsubscribe from node '%@' on jid '%@': %@", node, iqNode.fromUser, iqNode);

        //call unsubscribe callback (if given) with error iq node
        $call(handler,
            $ID(account, _account),
            $BOOL(success, NO),
            $ID(jid, iqNode.fromUser),
            $ID(errorReason, @"Unexpected iq result (wrong node or jid)!")
        );
    }
$$

$$instance_handler(handleFetch, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSMutableArray*, queryItems), $$ID(NSMutableDictionary*, data), $$HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub fetch request: %@", iqNode);
        //call fetch callback (if given) with error iq node
        $call(handler,
            $ID(account, account),
            $BOOL(success, NO),
            $ID(jid, iqNode.fromUser),
            $ID(errorIq, iqNode)
        );
        return;
    }
    
    NSString* first = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/first#"];
    NSString* last = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/last#"];
    //check for rsm paging
    if(!last || [last isEqualToString:first])       //no rsm at all or reached end of rsm --> process data *and* inform handlers of new data
    {
        [self handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser withData:data];
        //call fetch callback (if given)
        $call(handler,
            $ID(account, account),
            $BOOL(success, YES),
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
        [account sendIq:query withHandler:$newHandler(self, handleFetch,
            $ID(node),
            $ID(queryItems),
            $ID(data),
            $HANDLER(handler)
        )];
    }
$$

$$instance_handler(handleInternalFetch, account.pubsub, $$ID(xmpp*, account), $$ID(NSString*, node), $$BOOL(success), $$ID(NSString*, jid), $$ID(NSDictionary*, data))
    if(success == NO)        //ignore errors
        [self callHandlersForNode:node andJid:jid withType:@"publish" andData:data];
$$


$$instance_handler(handleConfigFormResult, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub configure request 1: %@", iqNode);
        //signal error if a handler was given
        $call(handler, $ID(account, account), $BOOL(success, NO), $ID(errorIq, iqNode));
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
        $call(handler, $ID(account, account), $BOOL(success, NO), $ID(errorReason, NSLocalizedString(@"Unexpected server response: invalid PEP config form", @"")));
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
            $call(handler, $ID(account, account), $BOOL(success, NO), $ID(errorReason, NSLocalizedString(@"Unexpected server response: missing required fields in PEP config form", @"")));
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
    [account sendIq:query withHandler:$newHandler(self, handleConfigureResult,
        $HANDLER(handler)
    )];
$$

$$instance_handler(handleConfigureResult, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub configure request 2: %@", iqNode);
        //signal error if a handler was given
        $call(handler, $ID(account, account), $BOOL(success, NO), $ID(errorIq, iqNode));
        return;
    }
    //inform handler of successful completion of config request
    $call(handler, $ID(account, account), $BOOL(success, YES));
$$

$$instance_handler(handlePublishAgain, account.pubsub, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $$ID(MLXMLNode*, item), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    if(!success)
    {
        DDLogError(@"Publish failed for node '%@' even after configuring it!", node);
        $call(handler, $ID(account, account), $BOOL(success, NO), $ID(errorIq), $ID(errorReason));
        return;
    }
    
    //try again
    [self internalPublishItem:item onNode:node withConfigOptions:configOptions andHandler:handler];
$$

$$instance_handler(handleConfigureAfterPublish, account.pubsub, $$ID(xmpp*, account), $$BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    if(!success)
    {
        DDLogError(@"Second publish attempt failed again for node '%@', not configuring it!", node);
        $call(handler, $ID(account, account), $BOOL(success, NO), $ID(errorIq), $ID(errorReason));
        return;
    }
    
    //configure node after publishing it
    [self configureNode:node withConfigOptions:configOptions andHandler:handler];
$$

$$instance_handler(handlePublishResult, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(MLXMLNode*, item), $$ID(NSString*, node), $$ID(NSDictionary*, configOptions), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        //NOTE: workaround for old ejabberd versions <= 21.07 only supporting two special settings as preconditions
        if([@"http://www.process-one.net/en/ejabberd/" isEqualToString:account.connectionProperties.serverIdentity] && [configOptions count] > 0 && [iqNode check:@"error<type=wait>/{urn:ietf:params:xml:ns:xmpp-stanzas}resource-constraint"])
        {
            DDLogWarn(@"ejabberd (~21.07) workaround for old preconditions handling active for node: %@", node);
            
            //make sure we don't try all preconditions from configOptions again: only these two listed preconditions are safe to use with ejabberd
            NSMutableDictionary* publishPreconditions = [[NSMutableDictionary alloc] init];
            if(configOptions[@"pubsub#persist_items"])
                publishPreconditions[@"pubsub#persist_items"] = configOptions[@"pubsub#persist_items"];
            if(configOptions[@"pubsub#persist_items"])
                publishPreconditions[@"pubsub#access_model"] = configOptions[@"pubsub#access_model"];
            
            [self internalPublishItem:item onNode:node withConfigOptions:publishPreconditions andHandler:$newHandler(self, handleConfigureAfterPublish,
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
            [self configureNode:node withConfigOptions:configOptions andHandler:$newHandler(self, handlePublishAgain,
                $ID(item),
                $ID(node),
                $ID(configOptions),      //modern servers support XEP-0060 Version 1.15.0 (2017-12-12) --> all node config options are allowed as preconditions
                $HANDLER(handler)
            )];
            return;
        }
        $call(handler, $ID(account, account), $BOOL(success, NO), $ID(errorIq, iqNode));
        return;
    }
    $call(handler, $ID(account, account), $BOOL(success, YES));
$$

$$instance_handler(handleRetractResult, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $$ID(NSString*, itemId), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Retract for item '%@' of node '%@' failed: %@", itemId, node, iqNode);
        $call(handler, $ID(account, account), $BOOL(success, NO), $ID(errorIq, iqNode));
        return;
    }
    $call(handler, $ID(account, account), $BOOL(success, YES));
$$

$$instance_handler(handlePurgeOrDeleteResult, account.pubsub, $$ID(xmpp*, account), $$ID(XMPPIQ*, iqNode), $$ID(NSString*, node), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Purge/Delete of node '%@' failed: %@", node, iqNode);
        $call(handler, $ID(account, account), $BOOL(success, NO), $ID(errorIq, iqNode));
        return;
    }
    $call(handler, $ID(account, account), $BOOL(success, YES));
$$

@end
