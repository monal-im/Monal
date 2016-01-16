//
//  XMPPMessage.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//


#import "MLXMLNode.h"

#define kMessageChatType @"chat"
#define kMessageGroupChatType @"groupchat"
#define kMessageErrorType @"error"
#define kMessageNormalType @"normal"

@interface XMPPMessage : MLXMLNode
{
    
}
/**
 Sets the id attribute of the element
 */
-(void) setXmppId:(NSString*) idval;

/**
 returns value of id attribute if set
 */
-(NSString *) xmppId;

/**
 Sets the body child element
 */
-(void) setBody:(NSString*) messageBody;

@end
