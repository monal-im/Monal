//
//  XMPPIQ.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMPPIQ.h"
#import "HelperTools.h"
#import "SignalPreKey.h"

#import "MLPush.h"

NSString *const kiqGetType = @"get";
NSString *const kiqSetType = @"set";
NSString *const kiqResultType = @"result";
NSString *const kiqErrorType = @"error";

@implementation XMPPIQ


-(id) initWithId:(NSString*) iqid andType:(NSString*) iqType
{
    self=[super init];
    self.element=@"iq";
    if(iqid && iqType)
    {
        [self setId:iqid];
        [self.attributes setObject:iqType forKey:@"type"];
    }
    return self;
}

-(id) initWithType:(NSString*) iqType
{
    return [self initWithId:[[NSUUID UUID] UUIDString] andType:iqType];
}

-(NSString*) getId
{
    return [self.attributes objectForKey:@"id"];
}

-(void) setId:(NSString*) id
{
    [self.attributes setObject:id forKey:@"id"];
}

#pragma mark iq set
-(void) setPushEnableWithNode:(NSString *)node andSecret:(NSString *)secret
{
    MLXMLNode* enableNode =[[MLXMLNode alloc] init];
    enableNode.element=@"enable";
    [enableNode.attributes setObject:@"urn:xmpp:push:0" forKey:kXMLNS];
    [enableNode.attributes setObject:[MLPush pushServer] forKey:@"jid"];
    [enableNode.attributes setObject:node forKey:@"node"];
    [self.children addObject:enableNode];
    
    MLXMLNode* xNode =[[MLXMLNode alloc] init];
    xNode.element=@"x";
    [xNode.attributes setObject:@"jabber:x:data" forKey:kXMLNS];
    [xNode.attributes setObject:@"submit" forKey:@"type"];
    [enableNode.children addObject:xNode];
    
    MLXMLNode* formTypeFieldNode =[[MLXMLNode alloc] init];
    formTypeFieldNode.element=@"field";
    [formTypeFieldNode.attributes setObject:@"FORM_TYPE" forKey:@"var"];
    MLXMLNode* formTypeValueNode =[[MLXMLNode alloc] init];
    formTypeValueNode.element=@"value";
    formTypeValueNode.data=@"http://jabber.org/protocol/pubsub#publish-options";
    [formTypeFieldNode.children addObject:formTypeValueNode];
    [xNode.children addObject:formTypeFieldNode];
    
    MLXMLNode* secretFieldNode =[[MLXMLNode alloc] init];
    secretFieldNode.element=@"field";
    [secretFieldNode.attributes setObject:@"secret" forKey:@"var"];
    MLXMLNode* secretValueNode =[[MLXMLNode alloc] init];
    secretValueNode.element=@"value";
    secretValueNode.data=secret;
    [secretFieldNode.children addObject:secretValueNode];
    [xNode.children addObject:secretFieldNode];
}

-(void) setPushDisableWithNode:(NSString *)node
{
    MLXMLNode* disableNode =[[MLXMLNode alloc] init];
    disableNode.element=@"disable";
    [disableNode.attributes setObject:@"urn:xmpp:push:0" forKey:kXMLNS];
    [disableNode.attributes setObject:[MLPush pushServer] forKey:@"jid"];
    [disableNode.attributes setObject:node forKey:@"node"];
    [self.children addObject:disableNode];
}

-(void) setBindWithResource:(NSString*) resource
{

    MLXMLNode* bindNode =[[MLXMLNode alloc] initWithElement:@"bind" andNamespace:@"urn:ietf:params:xml:ns:xmpp-bind"];
    MLXMLNode* resourceNode = [[MLXMLNode alloc] initWithElement:@"resource"];
    resourceNode.data = resource;
    [bindNode.children addObject:resourceNode];
    [self.children addObject:bindNode];
}

-(void) setDiscoInfoNode
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"http://jabber.org/protocol/disco#info"];
    [self.children addObject:queryNode];
}

-(void) setDiscoItemNode
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"http://jabber.org/protocol/disco#items"];
    [self.children addObject:queryNode];
}

-(void) setDiscoInfoWithFeaturesAndNode:(NSString*) node
{
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"http://jabber.org/protocol/disco#info"];
    if(node)
        [queryNode.attributes setObject:node forKey:@"node"];
    
    for(NSString* feature in [HelperTools getOwnFeatureSet])
    {
        MLXMLNode* featureNode = [[MLXMLNode alloc] initWithElement:@"feature"];
        featureNode.attributes[@"var"] = feature;
        [queryNode.children addObject:featureNode];
    }
    
    MLXMLNode* identityNode = [[MLXMLNode alloc] initWithElement:@"identity"];
    identityNode.attributes[@"category"] = @"client";
    identityNode.attributes[@"type"] = @"phone";
    identityNode.attributes[@"name"] = [NSString stringWithFormat:@"Monal %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    [queryNode.children addObject:identityNode];
    
    [self.children addObject:queryNode];
}

-(void) setiqTo:(NSString*) to
{
    if(to)
        [self.attributes setObject:to forKey:@"to"];
}

-(void) setPing
{
    MLXMLNode* pingNode = [[MLXMLNode alloc] initWithElement:@"ping" andNamespace:@"urn:xmpp:ping"];
    [self.children addObject:pingNode];
}

#pragma mark - MAM

-(void) mamArchivePref
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"prefs";
    [queryNode.attributes setObject:@"urn:xmpp:mam:2" forKey:kXMLNS];
    [self.children addObject:queryNode];
}

-(void) updateMamArchivePrefDefault:(NSString *) pref
{
    /**
     pref is aways, never or roster
     */
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"prefs";
    [queryNode.attributes setObject:@"urn:xmpp:mam:2" forKey:kXMLNS];
    [queryNode.attributes setObject:pref forKey:@"default"];
    [self.children addObject:queryNode];
}

-(void) setMAMQueryLatestMessagesForJid:(NSString*) jid before:(NSString*) uid
{
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"urn:xmpp:mam:2" withAttributes:@{
        @"queryid": [NSString stringWithFormat:@"MLhistory:%@", [[NSUUID UUID] UUIDString]]
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"x" andNamespace:@"jabber:x:data" withAttributes:@{
            @"type": @"submit"
        } andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"field" withAttributes:@{
                @"var": @"FORM_TYPE",
                @"type": @"hidden"
            } andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:@"urn:xmpp:mam:2"]
            ] andData:nil],
            [[MLXMLNode alloc] initWithElement:@"field" withAttributes:@{
                @"var": @"with",
            } andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:jid]
            ] andData:nil]
        ] andData:nil],
        [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"max" withAttributes:@{} andChildren:@[] andData:@"50"],
            [[MLXMLNode alloc] initWithElement:@"before" withAttributes:@{} andChildren:@[] andData:uid]
        ] andData:nil]
    ] andData:nil];
    [self.children addObject:queryNode];
}

-(void) setMAMQueryForLatestId
{
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"urn:xmpp:mam:2" withAttributes:@{
        @"queryid": [NSString stringWithFormat:@"MLignore:%@", [[NSUUID UUID] UUIDString]]
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"x" andNamespace:@"jabber:x:data" withAttributes:@{
            @"type": @"submit"
        } andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"field" withAttributes:@{
                @"var": @"FORM_TYPE",
                @"type": @"hidden"
            } andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:@"urn:xmpp:mam:2"]
            ] andData:nil],
            [[MLXMLNode alloc] initWithElement:@"field" withAttributes:@{
                @"var": @"end",
            } andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:[HelperTools generateDateTimeString:[NSDate date]]]
            ] andData:nil]
        ] andData:nil],
        [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"max" withAttributes:@{} andChildren:@[] andData:@"1"],
            [[MLXMLNode alloc] initWithElement:@"before"]
        ] andData:nil]
    ] andData:nil];
    [self.children addObject:queryNode];
}

-(void) setMAMQueryAfter:(NSString*) uid
{
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"urn:xmpp:mam:2" withAttributes:@{
        @"queryid": [NSString stringWithFormat:@"MLcatchup:%@", [[NSUUID UUID] UUIDString]]
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"x" andNamespace:@"jabber:x:data" withAttributes:@{
            @"type": @"submit"
        } andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"field" withAttributes:@{
                @"var": @"FORM_TYPE",
                @"type": @"hidden"
            } andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:@"urn:xmpp:mam:2"]
            ] andData:nil],
        ] andData:nil],
        [[MLXMLNode alloc] initWithElement:@"set" andNamespace:@"http://jabber.org/protocol/rsm" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"max" withAttributes:@{} andChildren:@[] andData:@"50"],
            [[MLXMLNode alloc] initWithElement:@"after" withAttributes:@{} andChildren:@[] andData:uid]
        ] andData:nil]
    ] andData:nil];
    [self.children addObject:queryNode];
}

-(void) setRemoveFromRoster:(NSString*) jid
{
    MLXMLNode* queryNode = [[MLXMLNode alloc] init];
    queryNode.element = @"query";
    [queryNode.attributes setObject:@"jabber:iq:roster" forKey:kXMLNS];
    [self.children addObject:queryNode];
    
    MLXMLNode* itemNode = [[MLXMLNode alloc] init];
    itemNode.element = @"item";
    [itemNode.attributes setObject:jid forKey:@"jid"];
    [itemNode.attributes setObject:@"remove" forKey:@"subscription"];
    [queryNode.children addObject:itemNode];
}

-(void) setRosterRequest:(NSString *) version
{
    MLXMLNode* queryNode = [[MLXMLNode alloc] init];
    queryNode.element = @"query";
    [queryNode.attributes setObject:@"jabber:iq:roster" forKey:kXMLNS];
    if(version)
        [queryNode.attributes setObject:version forKey:@"ver"];
    [self.children addObject:queryNode];
}

-(void) setVersion
{
    MLXMLNode* queryNode = [[MLXMLNode alloc] init];
    queryNode.element = @"query";
    [queryNode.attributes setObject:@"jabber:iq:version" forKey:kXMLNS];
    
    MLXMLNode* name = [[MLXMLNode alloc] init];
    name.element = @"name";
    name.data = @"Monal";
    
#if TARGET_OS_MACCATALYST
    MLXMLNode* os = [[MLXMLNode alloc] init];
    os.element = @"os";
    os.data = @"macOS";
#else
    MLXMLNode* os = [[MLXMLNode alloc] init];
    os.element = @"os";
    os.data = @"iOS";
#endif
    
    MLXMLNode* appVersion = [[MLXMLNode alloc] initWithElement:@"version"];
    appVersion.data = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    
    [queryNode.children addObject:name];
    [queryNode.children addObject:os];
    [queryNode.children addObject:appVersion];
    [self.children addObject:queryNode];
}

-(void) setBlocked:(BOOL) blocked forJid:(NSString* _Nonnull) blockedJid
{
    MLXMLNode* blockNode = [[MLXMLNode alloc] initWithElement:(blocked ? @"block" : @"unblock") andNamespace:@"urn:xmpp:blocking"];
    
    MLXMLNode* itemNode = [[MLXMLNode alloc] initWithElement:@"item"];
    [itemNode.attributes setObject:blockedJid forKey:kJid];
    [blockNode.children addObject:itemNode];
    
    [self.children addObject:blockNode];
}

-(void) httpUploadforFile:(NSString *) file ofSize:(NSNumber *) filesize andContentType:(NSString *) contentType
{
    MLXMLNode* requestNode = [[MLXMLNode alloc] initWithElement:@"request" andNamespace:@"urn:xmpp:http:upload:0"];
    requestNode.attributes[@"filename"] = file;
    requestNode.attributes[@"size"] = [NSString stringWithFormat:@"%@", filesize];
    requestNode.attributes[@"content-type"] = contentType;
    [self.children addObject:requestNode];
}


#pragma mark iq get

-(void) getVcardTo:(NSString*) to
{
    [self setiqTo:to];

    MLXMLNode* vcardNode =[[MLXMLNode alloc] init];
    vcardNode.element=@"vCard";
    [vcardNode setXMLNS:@"vcard-temp"];
    
    [self.children addObject:vcardNode];
}

-(void) getEntitySoftWareVersionTo:(NSString*) to
{
    [self setiqTo:to];
    
    MLXMLNode* queryNode = [[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"jabber:iq:version"];
    
    [self.children addObject:queryNode];
}

#pragma mark MUC
-(void) setInstantRoom
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"http://jabber.org/protocol/muc#owner" forKey:kXMLNS];
    
    MLXMLNode* xNode =[[MLXMLNode alloc] init];
    xNode.element=@"x";
    [xNode.attributes setObject:@"jabber:x:data" forKey:kXMLNS];
    [xNode.attributes setObject:@"submit" forKey:@"type"];
    
    [queryNode.children addObject:xNode];
    [self.children addObject:queryNode];
}

#pragma mark Jingle

-(void) setJingleInitiateTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info
{
    [self setiqTo:[NSString stringWithFormat:@"%@/%@",jid,resource]];
    
    MLXMLNode* jingleNode =[[MLXMLNode alloc] init];
    jingleNode.element=@"jingle";
    [jingleNode setXMLNS:@"urn:xmpp:jingle:1"];
    [jingleNode.attributes setObject:@"session-initiate" forKey:@"action"];
    [jingleNode.attributes setObject:[info objectForKey:@"initiator"] forKey:@"initiator"];
   [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
 
   MLXMLNode* contentNode =[[MLXMLNode alloc] init];
    contentNode.element=@"content";
    [contentNode.attributes setObject:@"initiator" forKey:@"creator"];
    [contentNode.attributes setObject:@"audio-session" forKey:@"name"];
    
    MLXMLNode* description =[[MLXMLNode alloc] init];
    description.element=@"description";
    [description.attributes setObject:@"urn:xmpp:jingle:apps:rtp:1" forKey:kXMLNS];
    [description.attributes setObject:@"audio" forKey:@"media"];

    
    MLXMLNode* payload =[[MLXMLNode alloc] init];
    payload.element=@"payload-type";
    [payload.attributes setObject:@"8" forKey:@"id"];
    [payload.attributes setObject:@"PCMA" forKey:@"name"];
    [payload.attributes setObject:@"8000" forKey:@"clockrate"];
    [payload.attributes setObject:@"1" forKey:@"channels"];
    
    [description.children addObject:payload];
    
    MLXMLNode* transport =[[MLXMLNode alloc] init];
    transport.element=@"transport";
    [transport.attributes setObject:@"urn:xmpp:jingle:transports:raw-udp:1" forKey:kXMLNS];

    
    MLXMLNode* candidate1 =[[MLXMLNode alloc] init];
    candidate1.element=@"candidate";
    [candidate1.attributes setObject:@"1" forKey:@"component"];
    [candidate1.attributes setObject:[info objectForKey:@"ownip"] forKey:@"ip"];
    [candidate1.attributes setObject:[info objectForKey:@"localport1"] forKey:@"port"];
    [candidate1.attributes setObject:@"monal001" forKey:@"id"];
    [candidate1.attributes setObject:@"0" forKey:@"generation"];
    
    MLXMLNode* candidate2 =[[MLXMLNode alloc] init];
    candidate2.element=@"candidate";
    [candidate2.attributes setObject:@"2" forKey:@"component"];
    [candidate2.attributes setObject:[info objectForKey:@"ownip"] forKey:@"ip"];
    [candidate2.attributes setObject:[info objectForKey:@"localport2"] forKey:@"port"];
    [candidate2.attributes setObject:@"monal002" forKey:@"id"];
    [candidate2.attributes setObject:@"0" forKey:@"generation"];
    
    [transport.children addObject:candidate1];
    [transport.children addObject:candidate2];
    
    [contentNode.children addObject:description];
    [contentNode.children addObject:transport];
    
    [jingleNode.children addObject:contentNode];
    [self.children addObject:jingleNode];
    
    
//        [query appendFormat:@" <iq to='%@/%@' id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' initiator='%@' responder='%@' sid='%@'>
//         <content creator='initiator'  name=\"audio-session\" senders=\"both\" responder='%@'>
//         <description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\">
//         <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\" channels='0'/></description>
//         
//         <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'>
//         <candidate component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\"   />
//         <candidate component=\"2\" ip=\"%@\" port=\"%@\"   id=\"monal002\" generation=\"0\"  /> </transport> </content>
//         
//         </jingle> </iq>", self.otherParty, _resource, _iqid, self.me, _to,  self.thesid, _to, _ownIP, self.localPort, _ownIP,self.localPort2];
}


-(void) setJingleAcceptTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info
{
    [self setiqTo:[NSString stringWithFormat:@"%@/%@",jid,resource]];
    
    MLXMLNode* jingleNode =[[MLXMLNode alloc] init];
    jingleNode.element=@"jingle";
    [jingleNode setXMLNS:@"urn:xmpp:jingle:1"];
    [jingleNode.attributes setObject:@"session-accept" forKey:@"action"];
    [jingleNode.attributes setObject:[info objectForKey:@"initiator"] forKey:@"initiator"];
    [jingleNode.attributes setObject:[info objectForKey:@"responder"] forKey:@"responder"];
    [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
    
    MLXMLNode* contentNode =[[MLXMLNode alloc] init];
    contentNode.element=@"content";
    [contentNode.attributes setObject:@"creator" forKey:@"initiator"];
    [contentNode.attributes setObject:@"audio-session" forKey:@"name"];
    [contentNode.attributes setObject:@"both" forKey:@"senders"];
    [contentNode.attributes setObject:[info objectForKey:@"responder"] forKey:@"responder"];
    
    
    MLXMLNode* description =[[MLXMLNode alloc] init];
    description.element=@"description";
    [description.attributes setObject:@"urn:xmpp:jingle:apps:rtp:1" forKey:kXMLNS];
    [description.attributes setObject:@"audio" forKey:@"media"];
    
    
    MLXMLNode* payload =[[MLXMLNode alloc] init];
    payload.element=@"payload-type";
    [payload.attributes setObject:@"8" forKey:@"id"];
    [payload.attributes setObject:@"PCMA" forKey:@"name"];
    [payload.attributes setObject:@"8000" forKey:@"clockrate"];
    [payload.attributes setObject:@"1" forKey:@"channels"];
    
    [description.children addObject:payload];
    
    MLXMLNode* transport =[[MLXMLNode alloc] init];
    transport.element=@"transport";
    [transport.attributes setObject:@"urn:xmpp:jingle:transports:raw-udp:1" forKey:kXMLNS];
    
    
    MLXMLNode* candidate1 =[[MLXMLNode alloc] init];
    candidate1.element=@"candidate";
    [candidate1.attributes setObject:@"1" forKey:@"component"];
    [candidate1.attributes setObject:[info objectForKey:@"ownip"] forKey:@"ip"];
    [candidate1.attributes setObject:[info objectForKey:@"localport1"] forKey:@"port"];
    [candidate1.attributes setObject:@"monal001" forKey:@"id"];
    [candidate1.attributes setObject:@"0" forKey:@"generation"];
    
    MLXMLNode* candidate2 =[[MLXMLNode alloc] init];
    candidate2.element=@"candidate";
    [candidate2.attributes setObject:@"2" forKey:@"component"];
    [candidate2.attributes setObject:[info objectForKey:@"ownip"] forKey:@"ip"];
    [candidate2.attributes setObject:[info objectForKey:@"localport2"] forKey:@"port"];
    [candidate2.attributes setObject:@"monal002" forKey:@"id"];
    [candidate2.attributes setObject:@"0" forKey:@"generation"];
    
    [transport.children addObject:candidate1];
    [transport.children addObject:candidate2];
    
    [contentNode.children addObject:description];
    [contentNode.children addObject:transport];
    
    [jingleNode.children addObject:contentNode];
    [self.children addObject:jingleNode];
    
}
-(void) setJingleDeclineTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info
{
    [self setiqTo:[NSString stringWithFormat:@"%@/%@",jid,resource]];

    MLXMLNode* jingleNode =[[MLXMLNode alloc] init];
    jingleNode.element=@"jingle";
    [jingleNode setXMLNS:@"urn:xmpp:jingle:1"];
    [jingleNode.attributes setObject:@"session-terminate" forKey:@"action"];
    [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
    
    MLXMLNode* reason =[[MLXMLNode alloc] init];
    reason.element=@"reason";
    
    MLXMLNode* decline =[[MLXMLNode alloc] init];
    decline.element=@"decline";
    
    [reason.children addObject:decline] ;
    [jingleNode.children addObject:reason];
    [self.children addObject:jingleNode];
    
}

-(void) setJingleTerminateTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info
{
    if([jid rangeOfString:@"/"].location==NSNotFound) {
        [self setiqTo:[NSString stringWithFormat:@"%@/%@",jid,resource]];
    }
    else {
        [self setiqTo:jid];
    }
    
    MLXMLNode* jingleNode =[[MLXMLNode alloc] init];
    jingleNode.element=@"jingle";
    [jingleNode setXMLNS:@"urn:xmpp:jingle:1"];
    [jingleNode.attributes setObject:@"session-terminate" forKey:@"action"];
  
    [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
    
    MLXMLNode* reason =[[MLXMLNode alloc] init];
    reason.element=@"reason";

    MLXMLNode* success =[[MLXMLNode alloc] init];
    success.element=@"success";

    [reason.children addObject:success] ;
    [jingleNode.children addObject:reason];
    [self.children addObject:jingleNode];

  
}

#pragma mark - signal

-(void) subscribeDevices:(NSString*) jid
{
    MLXMLNode* pubsubNode =[[MLXMLNode alloc] init];
    pubsubNode.element=@"pubsub";
    [pubsubNode.attributes setObject:@"http://jabber.org/protocol/pubsub" forKey:kXMLNS];
    
    MLXMLNode* subscribe =[[MLXMLNode alloc] init];
    subscribe.element=@"subscribe";
    [subscribe.attributes setObject:@"eu.siacs.conversations.axolotl.devicelist" forKey:@"node"];
    [subscribe.attributes setObject:jid forKey:@"jid"];
    [pubsubNode.children addObject:subscribe];
    
    [self.children addObject:pubsubNode];
}


-(void) publishDevices:(NSArray*) devices
{
    MLXMLNode* pubsubNode =[[MLXMLNode alloc] init];
    pubsubNode.element=@"pubsub";
    [pubsubNode.attributes setObject:@"http://jabber.org/protocol/pubsub" forKey:kXMLNS];
    
    MLXMLNode* publish =[[MLXMLNode alloc] init];
    publish.element=@"publish";
    [publish.attributes setObject:@"eu.siacs.conversations.axolotl.devicelist" forKey:@"node"];
    
    MLXMLNode* itemNode =[[MLXMLNode alloc] initWithElement:@"item"];
    [itemNode.attributes setObject:@"current" forKey:kId];
    
    MLXMLNode* listNode =[[MLXMLNode alloc] init];
    listNode.element=@"list";
    [listNode.attributes setObject:@"eu.siacs.conversations.axolotl" forKey:kXMLNS];
    
    [devices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *deviceid= (NSString *)obj;
        MLXMLNode* device =[[MLXMLNode alloc] init];
        device.element=@"device";
        [device.attributes setObject:deviceid forKey:kId];
        [listNode.children addObject:device];
    }];
  
    [itemNode.children addObject:listNode];
    
    [publish.children addObject:itemNode];
    [pubsubNode.children addObject:publish];
    
    [self.children addObject:pubsubNode];
}



-(void) publishKeys:(NSDictionary *) keys andPreKeys:(NSArray *) prekeys withDeviceId:(NSString*) deviceid
{
    MLXMLNode* pubsubNode =[[MLXMLNode alloc] init];
    pubsubNode.element=@"pubsub";
    [pubsubNode.attributes setObject:@"http://jabber.org/protocol/pubsub" forKey:kXMLNS];
    
    MLXMLNode* publish =[[MLXMLNode alloc] init];
    publish.element=@"publish";
    [publish.attributes setObject:[NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%@", deviceid] forKey:@"node"];
    
    MLXMLNode* itemNode =[[MLXMLNode alloc] init];
    itemNode.element=@"item";
    [itemNode.attributes setObject:@"current" forKey:kId];
    
    MLXMLNode* bundle =[[MLXMLNode alloc] init];
    bundle.element=@"bundle";
    [bundle.attributes setObject:@"eu.siacs.conversations.axolotl" forKey:kXMLNS];
    
    MLXMLNode* signedPreKeyPublic =[[MLXMLNode alloc] init];
    signedPreKeyPublic.element=@"signedPreKeyPublic";
    [signedPreKeyPublic.attributes setObject:[keys objectForKey:@"signedPreKeyId"] forKey:@"signedPreKeyId"];
    signedPreKeyPublic.data = [HelperTools encodeBase64WithData: [keys objectForKey:@"signedPreKeyPublic"]];
    [bundle.children addObject:signedPreKeyPublic];
    
    
    MLXMLNode* signedPreKeySignature =[[MLXMLNode alloc] init];
    signedPreKeySignature.element=@"signedPreKeySignature";
    signedPreKeySignature.data = [HelperTools encodeBase64WithData:[keys objectForKey:@"signedPreKeySignature"]];
    [bundle.children addObject:signedPreKeySignature];
    
    MLXMLNode* identityKey =[[MLXMLNode alloc] init];
    identityKey.element=@"identityKey";
    identityKey.data = [HelperTools encodeBase64WithData:[keys objectForKey:@"identityKey"]];
    [bundle.children addObject:identityKey];
    
    MLXMLNode* prekeyNode =[[MLXMLNode alloc] init];
    prekeyNode.element=@"prekeys";

    [prekeys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        SignalPreKey *prekey=(SignalPreKey *) obj;
        
        MLXMLNode* preKeyPublic =[[MLXMLNode alloc] init];
        preKeyPublic.element=@"preKeyPublic";
        [preKeyPublic.attributes setObject:[NSString stringWithFormat:@"%d", prekey.preKeyId] forKey:@"preKeyId"];
        preKeyPublic.data = [HelperTools encodeBase64WithData:prekey.keyPair.publicKey];
        [prekeyNode.children addObject:preKeyPublic];
        
    }];
    
    [bundle.children addObject:prekeyNode];
    [itemNode.children addObject:bundle];
    
    [publish.children addObject:itemNode];
    [pubsubNode.children addObject:publish];
    
    [self.children addObject:pubsubNode];
}


-(void) requestNode:(NSString*) node
{
    MLXMLNode* pubsubNode =[[MLXMLNode alloc] init];
    pubsubNode.element=@"pubsub";
    [pubsubNode.attributes setObject:@"http://jabber.org/protocol/pubsub" forKey:kXMLNS];

    
    MLXMLNode* subscribe =[[MLXMLNode alloc] init];
    subscribe.element=@"items";
    [subscribe.attributes setObject:node forKey:@"node"];
//[subscribe.attributes setObject:@"1" forKey:@"max_items"];
    
    [pubsubNode.children addObject:subscribe];
    [self.children addObject:pubsubNode];
    
}

-(void) requestDevices
{
    [self requestNode:@"eu.siacs.conversations.axolotl.devicelist"];
    
}

-(void) requestBundles:(NSString*) deviceid
{
    [self requestNode:[NSString stringWithFormat:@"eu.siacs.conversations.axolotl.bundles:%@", deviceid]];
}

#pragma mark - Account Management
-(void) getRegistrationFields
{
    MLXMLNode* query =[[MLXMLNode alloc] init];
    query.element=@"query";
    [query setXMLNS:kRegisterNameSpace];
    [self.children addObject:query];
}

/*
 This is really hardcoded for yax.im might work for others
 */
-(void) registerUser:(NSString *) user withPassword:(NSString *) newPass captcha:(NSString *) captcha andHiddenFields:(NSDictionary *)hiddenFields
{
    MLXMLNode* query =[[MLXMLNode alloc] init];
    query.element=@"query";
    [query setXMLNS:kRegisterNameSpace];
    
    MLXMLNode* x =[[MLXMLNode alloc] init];
    x.element=@"x";
    [x setXMLNS:kDataNameSpace];
    [x.attributes setValue:@"submit" forKey:@"type"];
    
    
    MLXMLNode* username =[[MLXMLNode alloc] init];
    username.element=@"field";
    [username.attributes setValue:@"username" forKey:@"var"];
    MLXMLNode* usernameValue =[[MLXMLNode alloc] init];
    usernameValue.element=@"value";
    usernameValue.data=user;
    [username.children addObject:usernameValue];
    
    MLXMLNode* password =[[MLXMLNode alloc] init];
    password.element=@"field";
    [password.attributes setValue:@"password" forKey:@"var"];
    MLXMLNode* passwordValue =[[MLXMLNode alloc] init];
    passwordValue.element=@"value";
    passwordValue.data=newPass;
     [password.children addObject:passwordValue];
    
    MLXMLNode* ocr =[[MLXMLNode alloc] init];
    ocr.element=@"field";
     [ocr.attributes setValue:@"ocr" forKey:@"var"];
    MLXMLNode* ocrValue =[[MLXMLNode alloc] init];
    ocrValue.element=@"value";
    ocrValue.data=captcha;
    [ocr.children addObject:ocrValue];
    
    [hiddenFields enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
       
        MLXMLNode* field =[[MLXMLNode alloc] init];
        field.element=@"field";
        [field.attributes setValue:key forKey:@"var"];
        MLXMLNode* fieldValue =[[MLXMLNode alloc] init];
        fieldValue.element=@"value";
        fieldValue.data=obj;
        [field.children addObject:fieldValue];
        
        [x.children addObject:field];
        
    }];
    
    [x.children addObject:username];
    [x.children addObject:password];
    [x.children addObject:ocr];
    
    [query.children addObject:x];
    
    [self.children addObject:query];
}

-(void) changePasswordForUser:(NSString *) user newPassword:(NSString *)newPass
{
    MLXMLNode* query =[[MLXMLNode alloc] init];
    query.element=@"query";
    [query setXMLNS:kRegisterNameSpace];
    
    MLXMLNode* username =[[MLXMLNode alloc] init];
    username.element=@"username";
    username.data=user;
    
    MLXMLNode* password =[[MLXMLNode alloc] init];
    password.element=@"password";
    password.data=newPass;
   
    [query.children addObject:username];
    [query.children addObject:password];
    
    [self.children addObject:query];
    
}


@end
