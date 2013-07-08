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
{
    
}

@property (nonatomic, strong, readonly) NSString* type;
/**
 full name as sent from server
 */
@property (nonatomic, strong, readonly) NSString* from;
/**
 username part of from 
 */
@property (nonatomic, strong, readonly) NSString* user;
/**
 resource part of from
 */
@property (nonatomic, strong, readonly) NSString* resource;
@property (nonatomic, strong, readonly) NSString* idval;

/**
 the text inside of show tags e.g. away
 */
@property (nonatomic, strong, readonly) NSString* show;
/**
 text inside of status tags. e.g. this is a status message
 */
@property (nonatomic, strong, readonly) NSString* status;

@end
