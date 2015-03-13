//
//  ParseEnabled.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/2/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "XMPPParser.h"

@interface ParseEnabled : XMPPParser

/**
 supports resume on server
 */
@property (nonatomic, assign, readonly) BOOL resume;
@property (nonatomic, strong, readonly) NSString *streamID;

/**
 server's max resumption time -- not implemented
 */
@property (nonatomic, strong, readonly) NSNumber *max;

/**
 where to reconnect to -- not implemented
 */
@property (nonatomic, strong, readonly) NSString *location;


@end
