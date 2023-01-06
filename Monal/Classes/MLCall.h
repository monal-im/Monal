//
//  MLCall.h
//  monalxmpp
//
//  Created by Thilo Molitor on 30.12.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

#ifndef MLCall_h
#define MLCall_h
NS_ASSUME_NONNULL_BEGIN

@class MLXMLNode;
@class WebRTCClient;
@class CXAnswerCallAction;
@class CXEndCallAction;
@class xmpp;
@class MLVoIPProcessor;

typedef NS_ENUM(NSUInteger, MLCallDirection) {
    MLCallDirectionIncoming,
    MLCallDirectionOutgoing,
};

typedef NS_ENUM(NSUInteger, MLCallState) {
    MLCallStateRinging,
    MLCallStateConnecting,
    MLCallStateConnected,
    MLCallStateFinished,
    MLCallStateIdle,
};

typedef NS_ENUM(NSUInteger, MLCallFinishReason) {
    MLCallFinishReasonUnknown,
    MLCallFinishReasonNormal,
    MLCallFinishReasonError,
    MLCallFinishReasonUnanswered,
    MLCallFinishReasonRejected,
    MLCallFinishReasonAnsweredElsewhere,
};

@interface MLCall : NSObject
@property (strong, readonly) NSString* description;

@property (nonatomic, strong, readonly) NSUUID* uuid;
@property (nonatomic, strong, readonly) MLContact* contact;
@property (nonatomic, readonly) MLCallDirection direction;
@property (nonatomic, readonly) MLCallState state;
@property (nonatomic, readonly) MLCallFinishReason finishReason;
@property (nonatomic, readonly) uint32_t time;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) BOOL speaker;

+(instancetype) makeDummyCall:(int) type;
-(void) end;

-(BOOL) isEqualToContact:(MLContact*) contact;
-(BOOL) isEqualToCall:(MLCall*) call;
-(BOOL) isEqual:(id _Nullable) object;
-(NSUInteger) hash;
@end

NS_ASSUME_NONNULL_END
#endif /* MLCall_h */
