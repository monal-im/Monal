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
    [self.attributes setObject:sessionid forKey:@"id"];
    [self.attributes setObject:iqType forKey:@"type"];
    return self; 
}

#pragma mark iq set
-(void) setBindWithResource:(NSString*) resource
{

    XMLNode* bindNode =[[XMLNode alloc] init];
    bindNode.element=@"bind";
    [bindNode.attributes setObject:@"urn:ietf:params:xml:ns:xmpp-bind" forKey:@"xmlns"];
    
    XMLNode* resourceNode =[[XMLNode alloc] init];
    resourceNode.element=@"resource";
    resourceNode.data=resource;
    [bindNode.children addObject:resourceNode];
    
    [self.children addObject:bindNode];
    
    
}

-(void) setDiscoInfoNode
{
    XMLNode* queryNode =[[XMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"http://jabber.org/protocol/disco#info"];
    [self.children addObject:queryNode];
}

-(void) setDiscoItemNode
{
    XMLNode* queryNode =[[XMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"http://jabber.org/protocol/disco#items"];
    [self.children addObject:queryNode];
}

-(void) setDiscoInfoWithFeatures
{
    
    XMLNode* queryNode =[[XMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode setXMLNS:@"http://jabber.org/protocol/disco#info"];
    
   NSArray* features=@[@"http://jabber.org/protocol/disco#info", @"http://jabber.org/protocol/disco#items",@"jabber:iq:version", @"http://jabber.org/protocol/muc#user",@"urn:xmpp:jingle:1",@"urn:xmpp:jingle:transports:raw-udp:0",
                       @"urn:xmpp:jingle:transports:raw-udp:1",@"urn:xmpp:jingle:apps:rtp:1",@"urn:xmpp:jingle:apps:rtp:audio"];
    
    for(NSString* feature in features)
    {
    
    XMLNode* featureNode =[[XMLNode alloc] init];
    featureNode.element=@"feature";
        [featureNode.attributes setObject:feature forKey:@"var"];
    [queryNode.children addObject:featureNode];
    
   }
    
    XMLNode* identityNode =[[XMLNode alloc] init];
    identityNode.element=@"identity";
    [identityNode.attributes setObject:@"client" forKey:@"category"];
     [identityNode.attributes setObject:@"phone" forKey:@"type"];
     [identityNode.attributes setObject:@"monal" forKey:@"name"];
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
    
    XMLNode* pingNode =[[XMLNode alloc] init];
    pingNode.element=@"ping";
    [pingNode.attributes setObject:@" urn:xmpp:ping" forKey:@"xmlns"];
    [self.children addObject:pingNode];

}

-(void) setRemoveFromRoster:(NSString*) jid
{
    XMLNode* queryNode =[[XMLNode alloc] init];
    queryNode.element=@"query";
    [queryNode.attributes setObject:@"jabber:iq:roster" forKey:@"xmlns"];
    [self.children addObject:queryNode];
    
    XMLNode* itemNode =[[XMLNode alloc] init];
    itemNode.element=@"query";
    [itemNode.attributes setObject:jid forKey:@"jid"];
    [itemNode.attributes setObject:@"remove" forKey:@"subscription"];
    [self.children addObject:itemNode];
}

#pragma mark iq get
-(void) getVcardTo:(NSString*) to
{
    [self setiqTo:to];
    [self.attributes setObject:@"v1" forKey:@"id"];
    
    XMLNode* vcardNode =[[XMLNode alloc] init];
    vcardNode.element=@"vCard";
    [vcardNode setXMLNS:@"vcard-temp"];
    
    [self.children addObject:vcardNode];
}
@end
