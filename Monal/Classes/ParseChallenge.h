//
//  ParseChallenge.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import "XMPPParser.h"

@interface ParseChallenge : XMPPParser

@property (nonatomic, assign) BOOL saslChallenge;
@property (nonatomic, strong,readonly) NSString* challengeText;
@end 
