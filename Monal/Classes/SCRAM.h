//
//  SCRAM.h
//  Monal
//
//  Created by Thilo Molitor on 05.08.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

#ifndef SCRAM_h
#define SCRAM_h

NS_ASSUME_NONNULL_BEGIN

@interface SCRAM : NSObject
+(NSArray*) supportedMechanismsIncludingChannelBinding:(BOOL) include;
-(instancetype) initWithUsername:(NSString*) username password:(NSString*) password andMethod:(NSString*) method;
-(void) setSSDPMechanisms:(NSArray<NSString*>*) mechanisms andChannelBindingTypes:(NSArray<NSString*>* _Nullable) cbTypes;

-(NSString*) clientFirstMessageWithChannelBinding:(NSString* _Nullable) channelBindingType;
-(BOOL) parseServerFirstMessage:(NSString*) str;
-(NSString*) clientFinalMessageWithChannelBindingData:(NSData* _Nullable) channelBindingData;
-(BOOL) parseServerFinalMessage:(NSString*) str;
-(NSData*) hashPasswordWithSalt:(NSData*) salt andIterationCount:(uint32_t) iterationCount;

@property (nonatomic, readonly) NSString* method;
@property (nonatomic, readonly) BOOL finishedSuccessfully;
@property (nonatomic, readonly) BOOL ssdpSupported;
@end

NS_ASSUME_NONNULL_END

#endif /* SCRAM_h */
