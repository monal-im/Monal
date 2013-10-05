//
//  XMPPPresence.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/5/13.
//
//

#import "XMPPPresence.h"

@implementation XMPPPresence

-(id) init
{
    self=[super init];
    self.element=@"presence";
    return self;
}

-(id) initWithHash:(NSString*) version
{
    self=[super init];
    self.element=@"presence";
    self.versionHash=version;
    
    XMLNode* c =[[XMLNode alloc] init];
    c.element=@"c";
    [c.attributes setObject:@"http://monal.im/caps" forKey:@"node"];
    [c.attributes setObject:self.versionHash forKey:@"ver"];
    [c.attributes setObject:[NSString stringWithFormat:@"%@ %@", kextpmuc, kextvoice] forKey:@"ext"];
    [c setXMLNS:@"http://jabber.org/protocol/caps"];
    [self.children addObject:c];
    
    return self;
}

#pragma mark own state
-(void) setShow:(NSString*) showVal
{
    XMLNode* show =[[XMLNode alloc] init];
    show.element=@"show";
    show.data=showVal;
    [self.children addObject:show];
}

-(void) setAway
{
    [self setShow:@"away"];
}

-(void) setAvailable
{
    [self setShow:@"chat"];
}

-(void) setStatus:(NSString*) status
{
    XMLNode* statusNode =[[XMLNode alloc] init];
    statusNode.element=@"status";
    statusNode.data=status;
    [self.children addObject:statusNode];
}

-(void) setPriority:(NSInteger)priority
{
    _priority=priority; 
    XMLNode* priorityNode =[[XMLNode alloc] init];
    priorityNode.element=@"priority";
    priorityNode.data=[NSString stringWithFormat:@"%d",_priority];
    [self.children addObject:priorityNode];
}

-(void) setInvisible
{
  [self.attributes setObject:@"unavailable" forKey:@"type"];
}



#pragma mark subscription
-(void) unsubscribeContact:(NSString*) jid
{
    [self.attributes setObject:jid forKey:@"to"];
    [self.attributes setObject:@"unsubscribe" forKey:@"type"];
}

-(void) subscribeContact:(NSString*) jid
{
    [self.attributes setObject:jid forKey:@"to"];
    [self.attributes setObject:@"subscribe" forKey:@"type"];
}

-(void) subscribedContact:(NSString*) jid
{
    [self.attributes setObject:jid forKey:@"to"];
    [self.attributes setObject:@"subscribed" forKey:@"type"];
}

-(void) unsubscribedContact:(NSString*) jid
{
    [self.attributes setObject:jid forKey:@"to"];
    [self.attributes setObject:@"unsubscribed" forKey:@"type"];
}

@end
