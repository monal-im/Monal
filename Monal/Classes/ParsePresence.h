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
@property (nonatomic, strong, readonly) NSString* from; // full name as sent
@property (nonatomic, strong, readonly) NSString* user; //user part of from
@property (nonatomic, strong, readonly) NSString* resource; // resource part of from
@property (nonatomic, strong, readonly) NSString* idval;

@end
