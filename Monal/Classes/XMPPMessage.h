//
//  XMPPMessage.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//


#import <monalxmpp/XMPPStanza.h>

FOUNDATION_EXPORT NSString* const kMessageChatType;
FOUNDATION_EXPORT NSString* const kMessageGroupChatType;
FOUNDATION_EXPORT NSString* const kMessageErrorType;
FOUNDATION_EXPORT NSString* const kMessageNormalType;
FOUNDATION_EXPORT NSString* const kMessageHeadlineType;

@interface XMPPMessage : XMPPStanza

-(XMPPMessage*) init;
-(XMPPMessage*) initWithType:(NSString*) type to:(NSString*) to;
-(XMPPMessage*) initToContact:(MLContact*) toContact;
-(XMPPMessage*) initWithType:(NSString*) type;
-(XMPPMessage*) initWithXMPPMessage:(XMPPMessage*) msg;

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
-(void) setDisplayed:(NSString*) messageId;
-(void) setMDSDisplayed:(NSString*) stanzaId withStanzaIdBy:(NSString*) by;

/**
 Hint saying the message should be stored
 @see https://xmpp.org/extensions/xep-0334.html
 */
-(void) setStoreHint;
-(void) setNoStoreHint;

@end
