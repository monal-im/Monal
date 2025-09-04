//
//  MLBasePaser.h
//  monalxmpp
//
//  Created by Anurodh Pokharel on 4/11/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLXMLNode.h>

//stanzas
#import <monalxmpp/XMPPIQ.h>
#import <monalxmpp/XMPPPresence.h>
#import <monalxmpp/XMPPMessage.h>
#import <monalxmpp/XMPPDataForm.h>


NS_ASSUME_NONNULL_BEGIN

typedef void (^stanza_completion_t)(MLXMLNode* _Nullable parsedStanza);

@interface MLBasePaser : NSObject

-(id) initWithCompletion:(stanza_completion_t) completion;
-(void) reset;

-(void) parserDidStartDocument:(NSString*) xmlVersion;
-(void) parserDidStartElement:(NSString*) elementName namespaceURI:(NSString*) namespaceURI attributes:(NSDictionary*) attributeDict;
-(void) parserFoundCharacters:(NSString*) string;
-(void) parserDidEndInnermostElement;
-(void) parserErrorOccurred:(NSString*) parseError;

@end

NS_ASSUME_NONNULL_END
