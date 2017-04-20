//
//  ParseFailed.h
//  Monal
//
//  Created by Thilo Molitor on 4/19/17.
//  Copyright (c) 2017 Monal.im. All rights reserved.
//

#import "XMPPParser.h"

@interface ParseFailed : XMPPParser
/**
 last handled value
 */
@property (nonatomic, strong, readonly) NSNumber *h;


@end
