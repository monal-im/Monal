//
//  MLBasePaser.h
//  monalxmpp
//
//  Created by Anurodh Pokharel on 4/11/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "MLConstants.h"
#import "MLXMPPConstants.h"

//parsers
#import "ParseStream.h"
#import "ParseIq.h"
#import "ParsePresence.h"
#import "ParseMessage.h"
#import "ParseChallenge.h"
#import "ParseFailure.h"
#import "ParseEnabled.h"
#import "ParseR.h"
#import "ParseA.h"
#import "ParseResumed.h"
#import "ParseFailed.h"


NS_ASSUME_NONNULL_BEGIN

typedef void (^stanzaCompletion)(XMPPParser * _Nullable parsedStanza);

@interface MLBasePaser : NSObject <NSXMLParserDelegate>

-(id) initWithCompeltion:(stanzaCompletion) completion;
-(void) reset; 
@property (nonatomic, strong, readonly) XMPPParser *currentStanzaParser;

@end

NS_ASSUME_NONNULL_END
