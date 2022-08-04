//
//  SCRAM.h
//  Monal
//
//  Created by Thilo Molitor on 05.08.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

#ifndef SCRAM_h
#define SCRAM_h

@interface SCRAM : NSObject
+(NSArray*) supportedMechanisms;

-(instancetype) initWithUsername:(NSString*) username password:(NSString*) password andMethod:(NSString*) method;

-(NSString*) clientFirstMessage;
-(BOOL) parseServerFirstMessage:(NSString*) str;
-(NSString*) clientFinalMessage;
-(BOOL) parseServerFinalMessage:(NSString*) str;

@property (nonatomic, readonly) NSString* method;
@end

#endif /* SCRAM_h */
