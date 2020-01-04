//
//  XMPPMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import "XMPPMessage.h"
#import "MLXMPPConstants.h"

@implementation XMPPMessage

 NSString* const kMessageChatType=@"chat";
 NSString* const kMessageGroupChatType=@"groupchat";
 NSString* const kMessageErrorType=@"error";
 NSString* const kMessageNormalType =@"normal";

-(id) init
{
    self= [super init];
    self.element=@"message";
    return self;
}

-(void) setXmppId:(NSString*) idval
{
    [self.attributes setObject:idval forKey:@"id"];
}

-(NSString *) xmppId
{
    return  [self.attributes objectForKey:@"id"];
}

-(void) setBody:(NSString*) messageBody
{
    MLXMLNode* body =[[MLXMLNode alloc] init];
    body.element=@"body";
    body.data=messageBody;
    [self.children addObject:body];
}

-(void) setOobUrl:(NSString*) link
{
    MLXMLNode* oob =[[MLXMLNode alloc] init];
    oob.element=@"x";
    [oob.attributes setValue:@"jabber:x:oob" forKey:kXMLNS];
    MLXMLNode* url =[[MLXMLNode alloc] init];
    url.element=@"url";
    url.data=link;
    [oob.children addObject:url];
    [self.children addObject:oob];
    
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
    [self.children addObject:received];
}


@end
