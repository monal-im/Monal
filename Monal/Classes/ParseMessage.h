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
@property (nonatomic, strong, readonly) NSString* subject;
@property (nonatomic, assign, readonly) BOOL hasBody; 
@property (nonatomic, strong, readonly) NSDate *delayTimeStamp;
@property (nonatomic, strong, readonly) NSString* avatarData;

/** Messages that are requesting a resposne */
@property (nonatomic, assign, readonly) BOOL requestReceipt;
/** Messages that are the resposne */
@property (nonatomic, strong, readonly) NSString* receivedID;

@property (nonatomic, assign, readonly) BOOL mucInvite;
@property (nonatomic, assign, readonly) BOOL mamResult;

/** OMEMO */

@property (nonatomic, strong, readonly) NSString* sid; // sender device id
@property (nonatomic, strong, readonly) NSString* encryptedPayload;
@property (nonatomic, strong, readonly) NSString* keyRid; //recipient device id
@property (nonatomic, strong, readonly) NSString* keyValue;
@property (nonatomic, strong, readonly) NSString* iv;
@property (nonatomic, strong, readonly) NSString* preKeyRid; 
@property (nonatomic, strong, readonly) NSString* preKeyValue;

@end
