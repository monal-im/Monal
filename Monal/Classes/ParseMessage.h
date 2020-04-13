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
@property (nonatomic, strong, readonly) NSString* stanzaId;

/**
 In the event of MUC this is ths user who really sent the message and from is the group name.
 */
@property (nonatomic, copy, readonly) NSString* actualFrom;
@property (nonatomic, copy, readonly) NSString* messageText;
@property (nonatomic, copy, readonly) NSString* messagHTML;
@property (nonatomic, copy, readonly) NSString* subject;
@property (nonatomic, assign, readonly) BOOL hasBody;
@property (nonatomic, copy, readonly) NSDate *delayTimeStamp;
@property (nonatomic, copy, readonly) NSString* avatarData;
@property (nonatomic, copy, readonly) NSString* oobURL;

/** Messages that are requesting a resposne */
@property (nonatomic, assign, readonly) BOOL requestReceipt;
/** Messages that are the resposne */
@property (nonatomic, copy, readonly) NSString* receivedID;

@property (nonatomic, assign, readonly) BOOL mucInvite;
@property (nonatomic, assign, readonly) BOOL mamResult;

/** OMEMO */
@property (nonatomic, strong, readonly) NSMutableArray *devices;

@property (nonatomic, copy, readonly) NSString* sid; // sender device id
@property (nonatomic, copy, readonly) NSString* encryptedPayload;
@property (nonatomic, copy, readonly) NSString* iv;
@property (nonatomic, strong, readonly) NSMutableArray *signalKeys; 

@end
