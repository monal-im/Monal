//
//  ParseA.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/2/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "XMPPParser.h"

@interface ParseA : XMPPParser

/**
last handled value
 */
@property (nonatomic, strong, readonly) NSNumber *h;

@end
