//
//  MLBasePaser.h
//  monalxmpp
//
//  Created by Anurodh Pokharel on 4/11/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLXMLNode.h"

//stanzas
#import "XMPPIQ.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"
#import "XMPPDataForm.h"


NS_ASSUME_NONNULL_BEGIN

typedef void (^stanza_completion_t)(MLXMLNode* _Nullable parsedStanza);

@interface MLBasePaser : NSObject <NSXMLParserDelegate>

-(id) initWithCompletion:(stanza_completion_t) completion;
-(void) reset;

@end

NS_ASSUME_NONNULL_END
