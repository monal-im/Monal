//
//  XMPPMessage.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//


#import "XMPPStanza.h"

FOUNDATION_EXPORT NSString* const kMessageChatType;
FOUNDATION_EXPORT NSString* const kMessageGroupChatType;
FOUNDATION_EXPORT NSString* const kMessageErrorType;
FOUNDATION_EXPORT NSString* const kMessageNormalType;
FOUNDATION_EXPORT NSString* const kMessageHeadlineType;

@interface XMPPMessage : XMPPStanza

-(id) initWithXMPPMessage:(XMPPMessage*) msg;

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

/**
 send image uploads out of band 
 */
-(void) setOobUrl:(NSString*) link;

-(void) setLMCFor:(NSString*) id;

/**
 sets the receipt child element
 */
-(void) setReceipt:(NSString*) messageId;
-(void) setChatmarkerReceipt:(NSString*) messageId;
-(void) setDisplayed:(NSString*) messageId;

/**
 Hint saying the message should be stored
 @see https://xmpp.org/extensions/xep-0334.html
 */
-(void) setStoreHint;
-(void) setNoStoreHint;

@end
