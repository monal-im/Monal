//
//  XMPPPresence.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/5/13.
//
//

#import <monalxmpp/XMPPPresence.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLContact.h>

@class MLContact;

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
        @"node": @"https://monal-im.org/",
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

-(void) createRoom:(NSString*) room withNick:(NSString*) nick
{
    self.to = [NSString stringWithFormat:@"%@/%@", room, nick];
    [self addChildNode:[[MLXMLNode alloc] initWithElement:@"x" andNamespace:@"http://jabber.org/protocol/muc" withAttributes:@{} andChildren:@[] andData:nil]];
}

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

-(void) unsubscribeContact:(MLContact*) contact
{
    [self.attributes setObject:contact.contactJid forKey:@"to"];
    [self.attributes setObject:@"unsubscribe" forKey:@"type"];
}

-(void) subscribeContact:(MLContact*) contact
{
    [self subscribeContact:contact withPreauthToken:nil];
}

-(void) subscribedContact:(MLContact*) contact
{
    [self.attributes setObject:contact.contactJid forKey:@"to"];
    [self.attributes setObject:@"subscribed" forKey:@"type"];
}

-(void) unsubscribedContact:(MLContact*) contact
{
    [self.attributes setObject:contact.contactJid forKey:@"to"];
    [self.attributes setObject:@"unsubscribed" forKey:@"type"];
}

-(void) subscribeContact:(MLContact*) contact withPreauthToken:(NSString* _Nullable) token
{
    [self.attributes setObject:contact.contactJid forKey:@"to"];
    [self.attributes setObject:@"subscribe" forKey:@"type"];
    if(token != nil)
        [self addChildNode:[[MLXMLNode alloc] initWithElement:@"preauth" andNamespace:@"urn:xmpp:pars:0" withAttributes:@{
            @"token": token
        } andChildren:@[] andData:nil]];
    
}

@end
