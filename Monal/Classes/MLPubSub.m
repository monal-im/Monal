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

#define CURRENT_PUBSUB_DATA_VERSION @4

@interface MLPubSub ()
{
    xmpp* _account;
    NSMutableDictionary* _registeredHandlers;
}
@end

@implementation MLPubSub

-(id) initWithAccount:(xmpp*) account
{
    self = [super init];
    _account = account;
    _registeredHandlers = [[NSMutableDictionary alloc] init];
    return self;
}

-(void) registerForNode:(NSString*) node withHandler:(NSDictionary*) handler
{
    NSString* handlerId = [HelperTools staticHandlerToId:handler];
    DDLogInfo(@"Adding PEP handler %@ for node %@", handlerId, node);
    @synchronized(_registeredHandlers) {
        if(!_registeredHandlers[node])
            _registeredHandlers[node] = [[NSMutableDictionary alloc] init];
        _registeredHandlers[node][handlerId] = handler;
        [_account setPubSubNotificationsForNodes:[_registeredHandlers allKeys] persistState:YES];
    }
}

-(void) unregisterHandler:(NSDictionary*) handler forNode:(NSString*) node
{
    NSString* handlerId = [HelperTools staticHandlerToId:handler];
    DDLogInfo(@"Removing PEP handler %@ for node %@", handlerId, node);
    @synchronized(_registeredHandlers) {
        if(!_registeredHandlers[node])
            return;
        [_registeredHandlers[node] removeObjectForKey:handlerId];
        [_account setPubSubNotificationsForNodes:[_registeredHandlers allKeys] persistState:YES];
    }
}

-(void) fetchNode:(NSString*) node from:(NSString*) jid withItemsList:(NSArray*) itemsList andHandler:(NSDictionary*) handler
{
    DDLogInfo(@"Fetching node '%@' at jid '%@' using callback %@...", node, jid, [HelperTools staticHandlerToString:handler]);
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
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
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handleFetchFor:withIqNode:andNode:andQueryItems:andData:andHandler:) andAdditionalArguments:@[node, queryItems, [[NSMutableDictionary alloc] init], handler]];
}

-(void) configureNode:(NSString*) node withConfigOptions:(NSDictionary*) configOptions andHandler:(NSDictionary*) handler
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
        return;
    }
    if(!handler)
        handler = @{};
    
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handleConfigureResult1For:withIqNode:node:configOptions:andHandler:) andAdditionalArguments:@[node, configOptions, handler]];
}

-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
        return;
    }
    if(!configOptions)
        configOptions = @{};
    DDLogDebug(@"Publishing item on node '%@': %@", node, item);
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"publish" withAttributes:@{@"node": node} andChildren:@[item] andData:nil],
        [[MLXMLNode alloc] initWithElement:@"publish-options" withAttributes:@{} andChildren:@[
            [[XMPPDataForm alloc] initWithType:@"submit" formType:@"http://jabber.org/protocol/pubsub#publish-options" andDictionary:configOptions]
        ] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withDelegate:[self class] andMethod:@selector(handlePublishResultFor:withIqNode:item:node:andConfigOptions:) andAdditionalArguments:@[item, node, configOptions]];
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
    @synchronized(_registeredHandlers) {
        return @{
            @"version": CURRENT_PUBSUB_DATA_VERSION,
            @"handlers": _registeredHandlers
        };
    }
}

-(void) setInternalData:(NSDictionary*) data
{
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
        DDLogWarn(@"Pubsub not supported, ignoring this call!");
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
        [self fetchNode:node from:messageNode.fromUser withItemsList:[items find:@"item@id"] andHandler:[HelperTools createStaticHandlerWithDelegate:[self class] andMethod:@selector(handleInternalFetchFor:andJid:withErrorIq:data:andNode:) andAdditionalArguments:@[node]]];
    }
}

//*** internal methods below

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
        data[itemId] = item;
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
    DDLogInfo(@"Calling pubsub handlers for node '%@' (and jid '%@')", node, jid);
    NSDictionary* handlers;
    @synchronized(_registeredHandlers) {
        handlers = [[NSDictionary alloc] initWithDictionary:_registeredHandlers[node] copyItems:YES];
    }
    for(NSString* handlerId in handlers)
        [HelperTools callStaticHandler:handlers[handlerId] withDefaultArguments:@[_account, node, jid, type, data ? data : [NSNull null]]];
    DDLogDebug(@"All pubsub handlers called");
}

+(void) handleInternalFetchFor:(xmpp*) account andJid:(NSString*) jid withErrorIq:(XMPPIQ*) errorIq data:(NSDictionary*) data andNode:(NSString*) node
{
    MLPubSub* me = account.pubsub;
    
    if(data)        //ignore errors or unexpected/wrong data
        [me callHandlersForNode:node andJid:jid withType:@"publish" andData:data];
}

+(void) handleFetchFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode andNode:(NSString*) node andQueryItems:(NSMutableArray*) queryItems andData:(NSMutableDictionary*) data andHandler:(NSDictionary*) handler
{
    MLPubSub* me = account.pubsub;
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub fetch request: %@", iqNode);
        //call fetch callback (if given) with error (nil as fourth argument means "no data because of error")
        [HelperTools callStaticHandler:handler withDefaultArguments:@[account, iqNode.fromUser, iqNode, [NSNull null]]];
        return;
    }
    
    NSString* first = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/first#"];
    NSString* last = [iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/{http://jabber.org/protocol/rsm}set/last#"];
    //check for rsm paging
    if(!last || [last isEqualToString:first])       //no rsm at all or reached end of rsm --> process data *and* inform handlers of new data
    {
        [me handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser withData:data];
        //call fetch callback (if given) (nil for third arg means "no error")
        [HelperTools callStaticHandler:handler withDefaultArguments:@[account, iqNode.fromUser, [NSNull null], data]];
    }
    else if(first && last)
    {
        //only process data but *don't* call fetch callback because the data is still partial
        [me handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser withData:data];
        XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType to:iqNode.fromUser];
        [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil],
            [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"after" withAttributes:@{} andChildren:@[] andData:last]
            ] andData:nil]
        ] andData:nil]];
        [account sendIq:query withDelegate:self andMethod:@selector(handleFetchFor:withIqNode:andNode:andQueryItems:andData:andHandler:) andAdditionalArguments:@[node, queryItems, data, handler]];
    }
}

+(void) handleConfigureResult1For:(xmpp*) account withIqNode:(XMPPIQ*) iqNode node:(NSString*) node configOptions:(NSDictionary*) configOptions andHandler:(NSDictionary*) handler
{
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub configure request 1: %@", iqNode);
        //signal error
        [HelperTools callStaticHandler:handler withDefaultArguments:@[account, iqNode]];
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
        [HelperTools callStaticHandler:handler withDefaultArguments:@[account, iqNode]];
        return;
    }
    
    for(NSString* option in configOptions)
    {
        if(!dataForm[option])
        {
            DDLogError(@"Server returned config form not containing the required fields or options, aborting! Required field: %@", option);
            //abort config operation
            XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
            [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[
                    [[XMPPDataForm alloc] initWithType:@"cancel" andFormType:@"http://jabber.org/protocol/pubsub#node_config"]
                ] andData:nil]
            ] andData:nil]];
            [account send:query];
            //signal error
            [HelperTools callStaticHandler:handler withDefaultArguments:@[account, iqNode]];
            return;
        }
        else
            dataForm[option] = configOptions[option];       //change requested value
    }
    
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
        [HelperTools callStaticHandler:handler withDefaultArguments:@[account, iqNode]];
        return;
    }
    //inform handler of successful completion of config request
    [HelperTools callStaticHandler:handler withDefaultArguments:@[account, [NSNull null]]];
}

+(void) handlePublishAgainFor:(xmpp*) account withError:(MLXMLNode*) error item:(MLXMLNode*) item node:(NSString*) node andConfigOptions:(NSDictionary*) configOptions
{
    MLPubSub* me = account.pubsub;
    
    if(error)
    {
        DDLogError(@"Publish failed for node '%@' even after configuring it: %@", node, error);
        return;
    }
    
    //try again
    [me publishItem:item onNode:node withConfigOptions:configOptions];
}

+(void) handlePublishResultFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode item:(MLXMLNode*) item node:(NSString*) node andConfigOptions:(NSDictionary*) configOptions
{
    MLPubSub* me = account.pubsub;
    
    if([iqNode check:@"/<type=error>"])
    {
        //check if this node is already present and configured --> reconfigure it according to our access-model
        if([iqNode check:@"error<type=cancel>/{http://jabber.org/protocol/pubsub#errors}precondition-not-met"])
        {
            DDLogWarn(@"Node precondition not met, reconfiguring node %@", node);
            [me configureNode:node withConfigOptions:configOptions andHandler:[HelperTools createStaticHandlerWithDelegate:self andMethod:@selector(handlePublishAgainFor:withError:item:node:andConfigOptions:) andAdditionalArguments:@[item, node, configOptions]]];
        }
        return;
    }
}

+(void) handleRetractResultFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode andNode:(NSString*) node andItemId:(NSString*) itemId
{
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Retract for item '%@' failed: %@", itemId, iqNode);
        return;
    }
}

+(void) handlePurgeOrDeleteResultFor:(xmpp*) account withIqNode:(XMPPIQ*) iqNode andNode:(NSString*) node
{
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Purge/Delete of node '%@' failed: %@", node, iqNode);
        return;
    }
}

@end
