//
//  ParseResumed.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/3/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "XMPPParser.h"

@interface ParseResumed : XMPPParser
/**
 last handled value
 */
@property (nonatomic, strong, readonly) NSNumber *h;


@end
