//
//  ParseEnabled.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/2/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "XMPPParser.h"

@interface ParseEnabled : XMPPParser

@property (nonatomic, assign, readonly) BOOL resume;
@property (nonatomic, strong, readonly) NSString *streamID;


@end
