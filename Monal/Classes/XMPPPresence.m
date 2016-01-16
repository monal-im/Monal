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
    
    MLXMLNode* c =[[MLXMLNode alloc] init];
    c.element=@"c";
    [c.attributes setObject:@"http://monal.im/caps" forKey:@"node"];
  //  [c.attributes setObject:self.versionHash forKey:@"ver"];
   [c.attributes setObject:@"sha-1" forKey:@"hash"];
    [c.attributes setObject:[NSString stringWithFormat:@"%@ %@", kextpmuc, kextvoice] forKey:@"ext"]; //deprecated .. for legacy
    [c.attributes setObject:@"http://jabber.org/protocol/caps" forKey:@"xmlns"];
    [self.children addObject:c];
    
    /*
     having xmlns:caps seems to make it accept legacy caps? doesnt seem to check hash value
     */
     
    
    return self;
}

#pragma mark own state
-(void) setShow:(NSString*) showVal
{
    MLXMLNode* show =[[MLXMLNode alloc] init];
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
    MLXMLNode* statusNode =[[MLXMLNode alloc] init];
    statusNode.element=@"status";
    statusNode.data=status;
    [self.children addObject:statusNode];
}

-(void) setPriority:(NSInteger)priority
{
    _priority=priority; 
    MLXMLNode* priorityNode =[[MLXMLNode alloc] init];
    priorityNode.element=@"priority";
    priorityNode.data=[NSString stringWithFormat:@"%d",_priority];
    [self.children addObject:priorityNode];
}

-(void) setInvisible
{
  [self.attributes setObject:@"unavailable" forKey:@"type"];
}

#pragma mark MUC 

-(void) joinRoom:(NSString*) room withPassword:(NSString*) password onServer:(NSString*) server withName:(NSString*)name
{
    [self.attributes setObject:[NSString stringWithFormat:@"%@@%@/%@", room,server,name] forKey:@"to"];
    
    MLXMLNode* xNode =[[MLXMLNode alloc] init];
    xNode.element=@"x";
    [xNode.attributes setObject:@"http://jabber.org/protocol/muc" forKey:@"xmlns"];
    
    MLXMLNode* historyNode =[[MLXMLNode alloc] init];
    historyNode.element=@"history";
    [historyNode.attributes setObject:@"5" forKey:@"maxstanzas"];
    [xNode.children addObject:historyNode];
    
    if(password)
    {
    MLXMLNode* passwordNode =[[MLXMLNode alloc] init];
    passwordNode.element=@"password";
    passwordNode.data=password;
    [xNode.children addObject:passwordNode];
    }

    [self.children addObject:xNode];
    
}


-(void) leaveRoom:(NSString*) room onServer:(NSString*) server withName:(NSString*)name
{
    //depeding on how this is called room might have the full server name
    if(server && ![room hasSuffix:server]) {
        [self.attributes setObject:[NSString stringWithFormat:@"%@@%@/%@", room,server,name] forKey:@"to"];
    }
    else {
        [self.attributes setObject:[NSString stringWithFormat:@"%@/%@", room,name] forKey:@"to"];
    }
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
