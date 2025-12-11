//
//  HT.h
//  Monal
//
//  Created by Thilo Molitor on 11.12.25.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

#ifndef HT_h
#define HT_h

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MLHtStatus) {
    MLHtStatusResponderMessageError,
    MLHtStatusResponderSignatureError,
    MLHtStatusResponderMessageOK,
};

@interface HT : NSObject
+(NSArray*) supportedMechanismsIncludingChannelBinding:(BOOL) include;

-(instancetype) initWithUsername:(NSString*) username token:(NSString*) token method:(NSString*) method andChannelBindingData:(NSData* _Nullable) channelBindingData;
-(NSData*) initiatorMessage;
-(MLHtStatus) parseResponderMessage:(NSData*) message;

@property (nonatomic, readonly) NSString* method;
@property (nonatomic, readonly) BOOL finishedSuccessfully;

@end

NS_ASSUME_NONNULL_END

#endif /* HT_h */
