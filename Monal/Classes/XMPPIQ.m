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

-(void) setBindWithResource:(NSString*) resource
{

    XMLNode* bindNode =[[XMLNode alloc] init];
    bindNode.element=@"bind";
    [bindNode.attributes setObject:@"urn:ietf:params:xml:ns:xmpp-bind" forKey:@"xmlns"];
    
    XMLNode* resourceNode =[[XMLNode alloc] init];
    resourceNode.element=@"resource";
    resourceNode.data=resource;
    
    [self.children addObject:bindNode];
    [self.children addObject:resourceNode];
    
}

-(void) setiqTo:(NSString*) to
{
    [self.attributes setObject:to forKey:@"to"];
}

-(void) setPing
{
    
    XMLNode* pingNode =[[XMLNode alloc] init];
    pingNode.element=@"ping";
    [pingNode.attributes setObject:@"urn:ietf:params:xml:ns:xmpp-bind" forKey:@"xmlns"];
    [self.children addObject:pingNode];

}

@end
