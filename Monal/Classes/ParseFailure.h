//
//  ParseFailure.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/22/13.
//
//

#import "XMPPParser.h"

@interface ParseFailure : XMPPParser
@property (nonatomic, assign, readonly) BOOL saslError;
@property (nonatomic, assign, readonly) BOOL notAuthorized;

@end
