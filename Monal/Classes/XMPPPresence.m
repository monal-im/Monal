//
//  XMPPPresence.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/5/13.
//
//

#import "XMPPPresence.h"

@implementation XMPPPresence

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

-(void) setAway
{
    XMLNode* show =[[XMLNode alloc] init];
    show.element=@"show";
    show.data=@"away";
    [self.children addObject:show];
}

-(void) setClientPriority
{
    XMLNode* priorityNode =[[XMLNode alloc] init];
    priorityNode.element=@"priority";
    priorityNode.data=[NSString stringWithFormat:@"%d",_priority];
    [self.children addObject:priorityNode];
}

@end
