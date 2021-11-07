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

//handler --> $$handler(xxx, $_ID(xmpp*, account), $_ID(NSString*, node), $_ID(NSString*, jid), $_ID(NSString*, type), $_ID(NSDictionary*, data))
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

//handler --> $$handler(xxx, $_ID(xmpp*, account), $_ID(NSString*, node), $_ID(NSString*, jid), $_ID(NSString*, type), $_ID(NSDictionary*, data))
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

//handler --> $$handler(xxx, $_ID(xmpp*, account), $_ID(NSString*, jid), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID(NSDictionary*, data))
-(void) fetchNode:(NSString*) node from:(NSString*) jid withItemsList:(NSArray*) itemsList andHandler:(MLHandler*) handler
{
    DDLogInfo(@"Fetching node '%@' at jid '%@' using callback %@...", node, jid, handler);
    if(!_account.connectionProperties.supportsPubSub)
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
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"items" withAttributes:@{@"node": node} andChildren:queryItems andData:nil]
    ] andData:nil]];

    [_account sendIq:query withHandler:$newHandler(self, handleFetch, 
        $ID(node),
        $ID(queryItems),
        $ID(data, [[NSMutableDictionary alloc] init]),
        $ID(handler),
    )];
}

//handler --> $$handler(xxx, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) configureNode:(NSString*) node withConfigOptions:(NSDictionary*) configOptions andHandler:(MLHandler*) handler
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withHandler:$newHandler(self, handleConfigFormResult,
        $ID(node),
        $ID(configOptions),
        $ID(handler)
    )];
}

-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node
{
    [self publishItem:item onNode:node withConfigOptions:nil andHandler:nil];
}

//handler --> $$handler(xxx, $_ID(xmpp*, account), $_BOOL(success))
-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withHandler:(MLHandler* _Nullable) handler
{
    [self publishItem:item onNode:node withConfigOptions:nil andHandler:handler];
}

-(void) publishItem:(MLXMLNode*) item onNode:(NSString*) node withConfigOptions:(NSDictionary* _Nullable) configOptions
{
    [self publishItem:item onNode:node withConfigOptions:configOptions andHandler:nil];
}

//handler --> $$handler(xxx, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
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
    configOptions = [[self class] copyDefaultNodeOptions:_defaultOptions forConfigForm:nil into:configOptions];
    
    [self internalPublishItem:item onNode:node withConfigOptions:configOptions andHandler:handler];
}

-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node
{
    [self retractItemWithId:itemId onNode:node andHandler:nil];
}

//handler --> $$handler(xxx, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) retractItemWithId:(NSString*) itemId onNode:(NSString*) node andHandler:(MLHandler*) handler
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    DDLogDebug(@"Retracting item '%@' on node '%@'", itemId, node);
    MLXMLNode* item = [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": itemId} andChildren:@[] andData:nil];
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"retract" withAttributes:@{@"node": node} andChildren:@[item] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withHandler:$newHandler(self, handleRetractResult,
        $ID(node),
        $ID(itemId),
        $ID(handler)
    )];
}

-(void) purgeNode:(NSString*) node
{
    [self purgeNode:node andHandler:nil];
}

//handler --> $$handler(xxx, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) purgeNode:(NSString*) node andHandler:(MLHandler*) handler
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"purge" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withHandler:$newHandler(self, handlePurgeOrDeleteResult,
        $ID(node),
        $ID(handler)
    )];
}

-(void) deleteNode:(NSString*) node
{
    [self deleteNode:node andHandler:nil];
}

//handler --> $$handler(xxx, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason))
-(void) deleteNode:(NSString*) node andHandler:(MLHandler*) handler
{
    if(!_account.connectionProperties.supportsPubSub)
    {
        DDLogWarn(@"Pubsub not supported, ignoring this call for node '%@'!", node);
        return;
    }
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"delete" withAttributes:@{@"node": node} andChildren:@[] andData:nil]
    ] andData:nil]];
    [_account sendIq:query withHandler:$newHandler(self, handlePurgeOrDeleteResult,
        $ID(node),
        $ID(handler)
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
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"publish" withAttributes:@{@"node": node} andChildren:@[item] andData:nil]
    ] andData:nil]];
    //only add publish-options if present
    if([configOptions count] > 0)
        [[query findFirst:@"{http://jabber.org/protocol/pubsub}pubsub"] addChild:[[MLXMLNode alloc] initWithElement:@"publish-options" withAttributes:@{} andChildren:@[
            [[XMPPDataForm alloc] initWithType:@"submit" formType:@"http://jabber.org/protocol/pubsub#publish-options" andDictionary:configOptions]
        ] andData:nil]];
    [_account sendIq:query withHandler:$newHandler(self, handlePublishResult,
        $ID(item),
        $ID(node),
        $ID(configOptions),
        $ID(handler)
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
    DDLogInfo(@"Calling pubsub handlers for node '%@' (and jid '%@')", node, jid);
    NSDictionary* handlers;
    @synchronized(_registeredHandlers) {
        handlers = [[NSDictionary alloc] initWithDictionary:_registeredHandlers[node] copyItems:YES];
    }
    for(NSString* handlerId in handlers)
        $call(handlers[handlerId],
            $ID(account, _account),
            $ID(node),
            $ID(jid),
            $ID(type),
            $ID(data)
        );
    DDLogDebug(@"All pubsub handlers called");
}

+(NSDictionary*) copyDefaultNodeOptions:(NSDictionary*) defaultOptions forConfigForm:(XMPPDataForm* _Nullable) configForm into:(NSDictionary*) configOptions
{
    NSMutableDictionary* retval = [configOptions mutableCopy];
    for(NSString* option in defaultOptions)
        if((configForm == nil || configForm[option] != nil) && retval[option] == nil)
            retval[option] = defaultOptions[option];
    return retval;
}

$$handler(handleFetch, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode), $_ID(NSString*, node), $_ID(NSMutableArray*, queryItems), $_ID(NSMutableDictionary*, data), $_HANDLER(handler))
    MLPubSub* me = account.pubsub;
    
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub fetch request: %@", iqNode);
        //call fetch callback (if given) with error iq node
        $call(handler,
            $ID(account),
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
        [me handleItems:[iqNode findFirst:@"{http://jabber.org/protocol/pubsub}pubsub/items"] fromJid:iqNode.fromUser withData:data];
        //call fetch callback (if given)
        $call(handler,
            $ID(account),
            $BOOL(success, YES),
            $ID(jid, iqNode.fromUser),
            $ID(data)
        );
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
        [account sendIq:query withHandler:$newHandler(self, handleFetch,
            $ID(node),
            $ID(queryItems),
            $ID(data),
            $ID(handler)
        )];
    }
$$

$$handler(handleInternalFetch, $_ID(xmpp*, account), $_ID(NSString*, node), $_ID(NSString*, jid), $_ID(NSDictionary*, data))
    MLPubSub* me = account.pubsub;
    
    if(data)        //ignore errors or unexpected/wrong data
        [me callHandlersForNode:node andJid:jid withType:@"publish" andData:data];
$$


$$handler(handleConfigFormResult, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode), $_ID(NSString*, node), $_ID(NSDictionary*, configOptions), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub configure request 1: %@", iqNode);
        //signal error
        $call(handler, $ID(account), $BOOL(success, NO), $ID(errorIq, iqNode));
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
        $call(handler, $ID(account), $BOOL(success, NO), $ID(errorReason, NSLocalizedString(@"Unexpected server response: invalid PEP config form", @"")));
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
            [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[
                    [[XMPPDataForm alloc] initWithType:@"cancel" andFormType:@"http://jabber.org/protocol/pubsub#node_config"]
                ] andData:nil]
            ] andData:nil]];
            [account send:query];
            //signal error
            $call(handler, $ID(account), $BOOL(success, NO), $ID(errorReason, NSLocalizedString(@"Unexpected server response: missing required fields in PEP config form", @"")));
            return;
        }
        else
            dataForm[option] = configOptions[option];       //change requested value
    }
    
    //reconfigure the node
    dataForm.type = @"submit";
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query addChild:[[MLXMLNode alloc] initWithElement:@"pubsub" andNamespace:@"http://jabber.org/protocol/pubsub#owner" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"configure" withAttributes:@{@"node": node} andChildren:@[dataForm] andData:nil]
    ] andData:nil]];
    [account sendIq:query withHandler:$newHandler(self, handleConfigureResult,
        $ID(handler)
    )];
$$

$$handler(handleConfigureResult, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Got error iq for pubsub configure request 2: %@", iqNode);
        //signal error
        $call(handler, $ID(account), $BOOL(success, NO), $ID(errorIq, iqNode));
        return;
    }
    //inform handler of successful completion of config request
    $call(handler, $ID(account), $BOOL(success, YES));
$$

$$handler(handlePublishAgain, $_ID(xmpp*, account), $_BOOL(success), $_ID(XMPPIQ*, errorIq), $_ID(NSString*, errorReason), $_ID(MLXMLNode*, item), $_ID(NSString*, node), $_ID(NSDictionary*, configOptions), $_HANDLER(handler))
    MLPubSub* me = account.pubsub;
    
    if(!success)
    {
        DDLogError(@"Publish failed for node '%@' even after configuring it!", node);
        $call(handler, $ID(account), $BOOL(success, NO), $ID(errorIq), $ID(errorReason));
        return;
    }
    
    //try again
    [me internalPublishItem:item onNode:node withConfigOptions:configOptions andHandler:handler];
$$

$$handler(handlePublishResult, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode), $_ID(MLXMLNode*, item), $_ID(NSString*, node), $_ID(NSDictionary*, configOptions), $_HANDLER(handler))
    MLPubSub* me = account.pubsub;
    
    if([iqNode check:@"/<type=error>"])
    {
        //check if this node is already present and configured --> reconfigure it according to our access-model
        if([iqNode check:@"error<type=cancel>/{http://jabber.org/protocol/pubsub#errors}precondition-not-met"])
        {
            DDLogWarn(@"Node precondition not met, reconfiguring node: %@", node);
            [me configureNode:node withConfigOptions:configOptions andHandler:$newHandler(self, handlePublishAgain,
                $ID(item),
                $ID(node),
                $ID(configOptions),      //modern servers support XEP-0060 Version 1.15.0 (2017-12-12) --> all node config options are allowed as preconditions
                $HANDLER(handler)
            )];
            return;
        }
        $call(handler, $ID(account), $BOOL(success, NO), $ID(errorIq, iqNode));
        return;
    }
    $call(handler, $ID(account), $BOOL(success, YES));
$$

$$handler(handleRetractResult, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode), $_ID(NSString*, node), $_ID(NSString*, itemId), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Retract for item '%@' of node '%@' failed: %@", itemId, node, iqNode);
        $call(handler, $ID(account), $BOOL(success, NO), $ID(errorIq, iqNode));
        return;
    }
    $call(handler, $ID(account), $BOOL(success, YES));
$$

$$handler(handlePurgeOrDeleteResult, $_ID(xmpp*, account), $_ID(XMPPIQ*, iqNode), $_ID(NSString*, node), $_HANDLER(handler))
    if([iqNode check:@"/<type=error>"])
    {
        DDLogError(@"Purge/Delete of node '%@' failed: %@", node, iqNode);
        $call(handler, $ID(account), $BOOL(success, NO), $ID(errorIq, iqNode));
        return;
    }
    $call(handler, $ID(account), $BOOL(success, YES));
$$

@end
