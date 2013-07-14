//
//  ParsePresence.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/6/13.
//
//

#import "XMPPParser.h"
#import "XMPPPresence.h" // for the constants

@interface ParsePresence : XMPPParser

/**
 the text inside of show tags e.g. away
 */
@property (nonatomic, strong, readonly) NSString* show;
/**
 text inside of status tags. e.g. this is a status message
 */
@property (nonatomic, strong, readonly) NSString* status;

@end
