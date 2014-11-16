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

/**
 In the event of MUC this is ths user who really sent the message and from is the group name.
 */
@property (nonatomic, strong, readonly) NSString* actualFrom;
@property (nonatomic, strong, readonly) NSString* messageText;
@property (nonatomic, strong, readonly) NSString* messagHTML;
@property (nonatomic, assign, readonly) BOOL hasBody; 

@property (nonatomic, assign, readonly) NSString* avatarData;


@property (nonatomic, assign, readonly) BOOL mucInvite;

@end
