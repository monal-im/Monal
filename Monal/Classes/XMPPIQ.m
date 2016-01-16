//
//  XMPPIQ.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMPPIQ.h"

@implementation XMPPIQ

-(id) initWithId:(NSString*) sessionid andType:(NSString*) iqType
{
    self=[super init];
    self.element=@"iq";
    if (sessionid && iqType) {
        [self.attributes setObject:sessionid forKey:@"id"];
        [self.attributes setObject:iqType forKey:@"type"];
    }
    return self;
}

#pragma mark iq set

-(void) setAuthWithUserName:(NSString *)username resource:(NSString *) resource andPassword:(NSString *) password
{
    [self.attributes setObject:@"auth1" forKey:@"id"];
    [self.attributes setObject:kiqSetType forKey:@"type"];
    
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"jabber:iq:auth"];
    
    MLXMLNode* userNode =[[MLXMLNode alloc] init];
    userNode.element=@"username";
    userNode.data =username;
    
    MLXMLNode* resourceNode =[[MLXMLNode alloc] init];
    resourceNode.element=@"resource";
    resourceNode.data =resource;
    
    MLXMLNode* passNode =[[MLXMLNode alloc] init];
    passNode.element=@"password";
    passNode.data =password;
    
    [queryNode.children addObject:userNode];
     [queryNode.children addObject:resourceNode];
     [queryNode.children addObject:passNode];
    [self.children addObject:queryNode];
}

-(void) setBindWithResource:(NSString*) resource
{

    MLXMLNode* bindNode =[[MLXMLNode alloc] init];
    bindNode.element=@"bind";
    [bindNode.attributes setObject:@"urn:ietf:params:xml:ns:xmpp-bind" forKey:@"xmlns"];
    
    MLXMLNode* resourceNode =[[MLXMLNode alloc] init];
    resourceNode.element=@"resource";
    resourceNode.data=resource;
    [bindNode.children addObject:resourceNode];
    
    [self.children addObject:bindNode];
    
    
}

-(void) setDiscoInfoNode
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"http://jabber.org/protocol/disco#info"];
    [self.children addObject:queryNode];
}

-(void) setDiscoItemNode
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"http://jabber.org/protocol/disco#items"];
    [self.children addObject:queryNode];
}

-(void) setDiscoInfoWithFeaturesAndNode:(NSString*) node
{
    
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"http://jabber.org/protocol/disco#info"];
    if(node){
        [queryNode. attributes setObject:node forKey:@"node"];
    }
    
   NSArray* features=@[@"http://jabber.org/protocol/caps",@"http://jabber.org/protocol/disco#info", @"http://jabber.org/protocol/disco#items",@"http://jabber.org/protocol/muc#user"
                       ];
//    ,@"jabber:iq:version", ,@"urn:xmpp:jingle:1",@"urn:xmpp:jingle:transports:raw-udp:0",
//                       @"urn:xmpp:jingle:transports:raw-udp:1",@"urn:xmpp:jingle:apps:rtp:1",@"urn:xmpp:jingle:apps:rtp:audio"];
    
    for(NSString* feature in features)
    {
    
    MLXMLNode* featureNode =[[MLXMLNode alloc] init];
    featureNode.element=@"feature";
        [featureNode.attributes setObject:feature forKey:@"var"];
    [queryNode.children addObject:featureNode];
    
   }
    
    MLXMLNode* identityNode =[[MLXMLNode alloc] init];
    identityNode.element=@"identity";
    [identityNode.attributes setObject:@"client" forKey:@"category"];
     [identityNode.attributes setObject:@"phone" forKey:@"type"];
     [identityNode.attributes setObject:[NSString stringWithFormat:@"Monal %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]] forKey:@"name"];
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
    MLXMLNode* pingNode =[[MLXMLNode alloc] init];
    pingNode.element=@"ping";
    [pingNode.attributes setObject:@"urn:xmpp:ping" forKey:@"xmlns"];
    [self.children addObject:pingNode];

}

-(void) setRemoveFromRoster:(NSString*) jid
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"jabber:iq:roster" forKey:@"xmlns"];
    [self.children addObject:queryNode];
    
    MLXMLNode* itemNode =[[MLXMLNode alloc] init];
    itemNode.element=@"query";
    [itemNode.attributes setObject:jid forKey:@"jid"];
    [itemNode.attributes setObject:@"remove" forKey:@"subscription"];
    [self.children addObject:itemNode];
}

-(void) setRosterRequest
{       
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"jabber:iq:roster" forKey:@"xmlns"];
    [self.children addObject:queryNode];
	
}

-(void) setVersion
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"jabber:iq:version" forKey:@"xmlns"];
    
    MLXMLNode* name =[[MLXMLNode alloc] init];
    name.element=@"name";
    name.data=@"Monal";
    

    MLXMLNode* os =[[MLXMLNode alloc] init];
    os.element=@"os";
    os.data=@"iOS";
    
    MLXMLNode* appVersion =[[MLXMLNode alloc] init];
    appVersion.element=@"version";
    appVersion.data=[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    
    [queryNode.children addObject:name];
    [queryNode.children addObject:os];
    [queryNode.children addObject:appVersion];
    [self.children addObject:queryNode];
}



-(void) setLast
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"jabber:iq:last" forKey:@"xmlns"];
     [queryNode.attributes setObject:@"0" forKey:@"seconds"]; // hasnt been away for 0 seconds
    [self.children addObject:queryNode];
}




#pragma mark iq get
-(void) getAuthwithUserName:(NSString *)username
{
    [self.attributes setObject:@"auth1" forKey:@"id"];
    [self.attributes setObject:kiqGetType forKey:@"type"];
    
    
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"jabber:iq:auth"];
    
    MLXMLNode* userNode =[[MLXMLNode alloc] init];
    userNode.element=@"username";
    userNode.data =username;
    
    [queryNode.children addObject:userNode];
    [self.children addObject:queryNode];
}

-(void) getVcardTo:(NSString*) to
{
    [self setiqTo:to];
    [self.attributes setObject:@"v1" forKey:@"id"];
    
    MLXMLNode* vcardNode =[[MLXMLNode alloc] init];
    vcardNode.element=@"vCard";
    [vcardNode setXMLNS:@"vcard-temp"];
    
    [self.children addObject:vcardNode];
}

#pragma mark MUC
-(void) setInstantRoom
{
    MLXMLNode* queryNode =[[MLXMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"http://jabber.org/protocol/muc#owner" forKey:@"xmlns"];
    
    MLXMLNode* xNode =[[MLXMLNode alloc] init];
    xNode.element=@"x";
    [xNode.attributes setObject:@"jabber:x:data" forKey:@"xmlns"];
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
    [jingleNode.attributes setObject:[info objectForKey:@"responder"] forKey:@"responder"];
    [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
 
   MLXMLNode* contentNode =[[MLXMLNode alloc] init];
    contentNode.element=@"content";
    [contentNode.attributes setObject:@"initiator" forKey:@"creator"];
    [contentNode.attributes setObject:@"audio-session" forKey:@"name"];
    [contentNode.attributes setObject:@"both" forKey:@"senders"];
    [contentNode.attributes setObject:[info objectForKey:@"responder"] forKey:@"responder"];
    
    
    MLXMLNode* description =[[MLXMLNode alloc] init];
    description.element=@"description";
    [description.attributes setObject:@"urn:xmpp:jingle:apps:rtp:1" forKey:@"xmlns"];
    [description.attributes setObject:@"audio" forKey:@"media"];

    
    MLXMLNode* payload =[[MLXMLNode alloc] init];
    payload.element=@"payload-type";
    [payload.attributes setObject:@"8" forKey:@"id"];
    [payload.attributes setObject:@"PCMA" forKey:@"name"];
    [payload.attributes setObject:@"8000" forKey:@"clockrate"];
    [payload.attributes setObject:@"0" forKey:@"channels"];
    
    [description.children addObject:payload];
    
    MLXMLNode* transport =[[MLXMLNode alloc] init];
    transport.element=@"transport";
    [transport.attributes setObject:@"urn:xmpp:jingle:transports:raw-udp:1" forKey:@"xmlns"];

    
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
    [description.attributes setObject:@"urn:xmpp:jingle:apps:rtp:1" forKey:@"xmlns"];
    [description.attributes setObject:@"audio" forKey:@"media"];
    
    
    MLXMLNode* payload =[[MLXMLNode alloc] init];
    payload.element=@"payload-type";
    [payload.attributes setObject:@"8" forKey:@"id"];
    [payload.attributes setObject:@"PCMA" forKey:@"name"];
    [payload.attributes setObject:@"8000" forKey:@"clockrate"];
    [payload.attributes setObject:@"0" forKey:@"channels"];
    
    [description.children addObject:payload];
    
    MLXMLNode* transport =[[MLXMLNode alloc] init];
    transport.element=@"transport";
    [transport.attributes setObject:@"urn:xmpp:jingle:transports:raw-udp:1" forKey:@"xmlns"];
    
    
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
    [jingleNode.attributes setObject:[info objectForKey:@"initiator"] forKey:@"initiator"];
    [jingleNode.attributes setObject:[info objectForKey:@"responder"] forKey:@"responder"];
    [jingleNode.attributes setObject:[info objectForKey:@"sid"] forKey:@"sid"];
    
    MLXMLNode* reason =[[MLXMLNode alloc] init];
    reason.element=@"reason";

    MLXMLNode* success =[[MLXMLNode alloc] init];
    success.element=@"success";

    [reason.children addObject:success] ;
    [jingleNode.children addObject:reason];
    [self.children addObject:jingleNode];

  
}


@end
