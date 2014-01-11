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

/**
the hash inside the photo tag
 */
@property (nonatomic, strong, readonly) NSString* photoHash;

/**
 Status codes that come back e.g. when you join a group chat.
 */
@property (nonatomic,strong) NSMutableArray* statusCodes;

@property (nonatomic,assign) BOOL MUC;


@end
