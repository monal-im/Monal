//
//  XMPPMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import "XMPPMessage.h"


@implementation XMPPMessage

NSString* const kMessageChatType=@"chat";
NSString* const kMessageGroupChatType=@"groupchat";
NSString* const kMessageErrorType=@"error";
NSString* const kMessageNormalType =@"normal";
NSString* const kMessageHeadlineType=@"headline";

-(id) init
{
    self = [super init];
    self.element = @"message";
    [self setXMLNS:@"jabber:client"];
    [self setXmppId:[[NSUUID UUID] UUIDString]];        //default value, can be overwritten later on
    return self;
}

-(id) initWithXMPPMessage:(XMPPMessage*) msg
{
    self = [self initWithElement:msg.element withAttributes:msg.attributes andChildren:msg.children andData:msg.data];
    return self;
}

-(void) setXmppId:(NSString*) idval
{
    [self.attributes setObject:idval forKey:@"id"];
    //add origin id to indicate we are using uuids for our stanza ids
    if([self check:@"{urn:xmpp:sid:0}origin-id"])       //modify existing origin id
        ((MLXMLNode*)[self findFirst:@"{urn:xmpp:sid:0}origin-id"]).attributes[@"id"] = idval;
    else
        [self addChild:[[MLXMLNode alloc] initWithElement:@"origin-id" andNamespace:@"urn:xmpp:sid:0" withAttributes:@{@"id":idval} andChildren:@[] andData:@"extra added"]];
}

-(NSString*) xmppId
{
    return [self.attributes objectForKey:@"id"];
}

-(void) setBody:(NSString*) messageBody
{
    [self addChild:[[MLXMLNode alloc] initWithElement:@"body" withAttributes:@{} andChildren:@[] andData:messageBody]];
}

-(void) setOobUrl:(NSString*) link
{
    [self addChild:[[MLXMLNode alloc] initWithElement:@"x" andNamespace:@"jabber:x:oob" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"url" withAttributes:@{} andChildren:@[] andData:link]
    ] andData:nil]];
    [self setBody:link];    //http filetransfers must have a message body equal to the oob link to be recognized as filetransfer
}

-(void) setLMCFor:(NSString*) id withNewBody:(NSString*) newBody
{
    [self addChild:[[MLXMLNode alloc] initWithElement:@"replace" andNamespace:@"urn:xmpp:message-correct:0" withAttributes:@{@"id": id} andChildren:@[] andData:nil]];
    [self setBody:newBody];
}

/**
 @see https://xmpp.org/extensions/xep-0184.html
 */
-(void) setReceipt:(NSString*) messageId
{
    [self addChild:[[MLXMLNode alloc] initWithElement:@"received" andNamespace:@"urn:xmpp:receipts" withAttributes:@{@"id":messageId} andChildren:@[] andData:nil]];
}

-(void) setChatmarkerReceipt:(NSString*) messageId
{
    [self addChild:[[MLXMLNode alloc] initWithElement:@"received" andNamespace:@"urn:xmpp:chat-markers:0" withAttributes:@{@"id":messageId} andChildren:@[] andData:nil]];
}

-(void) setDisplayed:(NSString*) messageId
{
    [self addChild:[[MLXMLNode alloc] initWithElement:@"displayed" andNamespace:@"urn:xmpp:chat-markers:0" withAttributes:@{@"id":messageId} andChildren:@[] andData:nil]];
}

-(void) setStoreHint
{
    [self addChild:[[MLXMLNode alloc] initWithElement:@"store" andNamespace:@"urn:xmpp:hints"]];
}

-(void) setNoStoreHint
{
    [self addChild:[[MLXMLNode alloc] initWithElement:@"no-store" andNamespace:@"urn:xmpp:hints"]];
    [self addChild:[[MLXMLNode alloc] initWithElement:@"no-storage" andNamespace:@"urn:xmpp:hints"]];
}

@end
