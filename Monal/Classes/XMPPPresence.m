//
//  XMPPPresence.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/5/13.
//
//

#import "XMPPPresence.h"
#import "HelperTools.h"

@implementation XMPPPresence

-(id) init
{
    self = [super init];
    self.element = @"presence";
    [self setXMLNS:@"jabber:client"];
    self.attributes[@"id"] = [[NSUUID UUID] UUIDString];
    return self;
}

-(id) initWithHash:(NSString*) version
{
    self = [self init];
    [self addChild:[[MLXMLNode alloc] initWithElement:@"c" andNamespace:@"http://jabber.org/protocol/caps" withAttributes:@{
        @"node": @"http://monal.im/",
        @"hash": @"sha-1",
        @"ver": version
    } andChildren:@[] andData:nil]];
    return self;
}

#pragma mark own state
-(void) setShow:(NSString*) showVal
{
    MLXMLNode* show = [[MLXMLNode alloc] init];
    show.element = @"show";
    show.data=showVal;
    [self addChild:show];
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
    MLXMLNode* statusNode = [[MLXMLNode alloc] init];
    statusNode.element = @"status";
    statusNode.data = status;
    [self addChild:statusNode];
}

-(void) setLastInteraction:(NSDate*) date
{
    MLXMLNode* idle = [[MLXMLNode alloc] initWithElement:@"idle" andNamespace:@"urn:xmpp:idle:1"];
    [idle.attributes setValue:[HelperTools generateDateTimeString:date] forKey:@"since"];
    [self addChild:idle];
}

#pragma mark MUC 

-(void) joinRoom:(NSString*) room withPassword:(NSString*) password onServer:(NSString*) server withName:(NSString*)name
{
    [self.attributes setObject:[NSString stringWithFormat:@"%@@%@/%@", room,server,name] forKey:@"to"];
    
    MLXMLNode* xNode =[[MLXMLNode alloc] init];
    xNode.element=@"x";
    [xNode.attributes setObject:@"http://jabber.org/protocol/muc" forKey:kXMLNS];
    
    MLXMLNode* historyNode =[[MLXMLNode alloc] init];
    historyNode.element=@"history";
    [historyNode.attributes setObject:@"0" forKey:@"maxstanzas"];
    [xNode addChild:historyNode];
    
    if(password)
    {
    MLXMLNode* passwordNode =[[MLXMLNode alloc] init];
    passwordNode.element=@"password";
    passwordNode.data=password;
    [xNode addChild:passwordNode];
    }

    [self addChild:xNode];
    
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
