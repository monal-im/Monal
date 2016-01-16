//
//  XMPPMessage.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import "XMPPMessage.h"

@implementation XMPPMessage

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


@end
