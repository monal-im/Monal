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
}

-(NSString *) xmppId
{
    return [self.attributes objectForKey:@"id"];
}

-(void) setBody:(NSString*) messageBody
{
    MLXMLNode* body =[[MLXMLNode alloc] init];
    body.element=@"body";
    body.data=messageBody;
    [self addChild:body];
}

-(void) setOobUrl:(NSString*) link
{
    MLXMLNode* oob =[[MLXMLNode alloc] init];
    oob.element=@"x";
    [oob.attributes setValue:@"jabber:x:oob" forKey:kXMLNS];
    MLXMLNode* url =[[MLXMLNode alloc] init];
    url.element=@"url";
    url.data=link;
    [oob addChild:url];
    [self addChild:oob];
    
    [self setBody:link]; // fallback
}

/**
 @see https://xmpp.org/extensions/xep-0184.html
 */
-(void) setReceipt:(NSString*) messageId
{
    MLXMLNode* received =[[MLXMLNode alloc] init];
    received.element=@"received";
    [received.attributes setValue:@"urn:xmpp:receipts" forKey:kXMLNS];
    [received.attributes setValue:messageId forKey:@"id"];
    [self addChild:received];
}

-(void) setStoreHint
{
    MLXMLNode* store =[[MLXMLNode alloc] init];
    store.element=@"store";
    [store.attributes setValue:@"urn:xmpp:hints" forKey:kXMLNS];
    [self addChild:store];
}

-(void) setNoStoreHint
{
    MLXMLNode* store = [[MLXMLNode alloc] initWithElement:@"no-store" andNamespace:@"urn:xmpp:hints"];
    [self addChild:store];
    MLXMLNode* storage = [[MLXMLNode alloc] initWithElement:@"no-storage" andNamespace:@"urn:xmpp:hints"];
    [self addChild:storage];
}

@end
