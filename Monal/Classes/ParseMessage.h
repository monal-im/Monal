//
//  ParseMessage.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/13/13.
//
//

#import "XMPPParser.h"
#import "XMPPMessage.h"



@interface ParseMessage : XMPPParser
{
    
}

@property (nonatomic, strong, readonly) NSString* type;
/**
 full name as sent from server
 */
@property (nonatomic, strong, readonly) NSString* from;

/**
In the event of MUC this is ths user who really sent the message and from is the group name.
 */
@property (nonatomic, strong, readonly) NSString* actualFrom;

/**
 username part of from
 */
@property (nonatomic, strong, readonly) NSString* user;
/**
 resource part of from
 */
@property (nonatomic, strong, readonly) NSString* resource;
@property (nonatomic, strong, readonly) NSString* idval;

@property (nonatomic, strong,readonly) NSString* messageText; 

@end
