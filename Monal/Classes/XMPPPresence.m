//
//  XMPPPresence.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/5/13.
//
//

#import "XMPPPresence.h"
#import "HelperTools.h"

@interface MLXMLNode()
@property (atomic, strong, readwrite) NSString* element;
@end

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
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"c" andNamespace:@"http://jabber.org/protocol/caps" withAttributes:@{
        @"node": @"http://monal-im.org/",
        @"hash": @"sha-1",
        @"ver": version
    } andChildren:@[] andData:nil]];
    return self;
}

#pragma mark own state
-(void) setShow:(NSString*) showVal
{
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"show" withAttributes:@{} andChildren:@[] andData:showVal]];
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
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"status" withAttributes:@{} andChildren:@[] andData:status]];
}

-(void) setLastInteraction:(NSDate*) date
{
    MLXMLNode* idle = [[MLXMLNode alloc] initWithElement:@"idle" andNamespace:@"urn:xmpp:idle:1"];
    [idle.attributes setValue:[HelperTools generateDateTimeString:date] forKey:@"since"];
    [self addChildNode:idle];
}

#pragma mark MUC 

-(void) joinRoom:(NSString*) room withNick:(NSString*) nick
{
    [self.attributes setObject:[NSString stringWithFormat:@"%@/%@", room, nick] forKey:@"to"];
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"x" andNamespace:@"http://jabber.org/protocol/muc" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"history" withAttributes:@{@"maxstanzas": @"0"} andChildren:@[] andData:nil]
    ] andData:nil]];
}


-(void) leaveRoom:(NSString*) room withNick:(NSString*) nick
{
    self.attributes[@"to"] = [NSString stringWithFormat:@"%@/%@", room, nick];
    self.attributes[@"type"] = @"unavailable";
}

#pragma mark subscription

-(void) unsubscribeContact:(NSString*) jid
{
    [self.attributes setObject:jid forKey:@"to"];
    [self.attributes setObject:@"unsubscribe" forKey:@"type"];
}

-(void) subscribeContact:(NSString*) jid
{
    [self subscribeContact:jid withPreauthToken:nil];
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

-(void) subscribeContact:(NSString*) jid withPreauthToken:(NSString* _Nullable) token
{
    [self.attributes setObject:jid forKey:@"to"];
    [self.attributes setObject:@"subscribe" forKey:@"type"];
    if(token != nil)
        [self addChildNode:[[MLXMLNode alloc] initWithElement:@"preauth" andNamespace:@"urn:xmpp:pars:0" withAttributes:@{
            @"token": token
        } andChildren:@[] andData:nil]];
    
}

@end
