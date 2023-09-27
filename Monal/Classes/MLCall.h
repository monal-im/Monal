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

@class WebRTCClient;
@protocol RTCVideoRenderer;
@class CXAnswerCallAction;
@class CXEndCallAction;
@class xmpp;
@class MLVoIPProcessor;
@class MLContact;


typedef NS_ENUM(NSUInteger, MLCallType) {
    MLCallTypeAudio,
    MLCallTypeVideo,
};

typedef NS_ENUM(NSUInteger, MLCallDirection) {
    MLCallDirectionIncoming,
    MLCallDirectionOutgoing,
};

typedef NS_ENUM(NSUInteger, MLCallState) {
    MLCallStateUnknown,
    MLCallStateDiscovering,
    MLCallStateRinging,
    MLCallStateConnecting,
    MLCallStateReconnecting,
    MLCallStateConnected,
    MLCallStateFinished,
};

typedef NS_ENUM(NSUInteger, MLCallFinishReason) {
    MLCallFinishReasonUnknown,              //dummy default value
    MLCallFinishReasonNormal,               //used for a call answered and finished locally (call direction etc. don't matter here)
    MLCallFinishReasonConnectivityError,    //used for a call accepted but not connected (call direction etc. don't matter here)
    MLCallFinishReasonSecurityError,        //used for a call that could not be encrypted using OMEMO
    MLCallFinishReasonUnanswered,           //used for a call retracted remotely (always remote party)
    MLCallFinishReasonAnsweredElsewhere,    //used for a call answered and finished remotely (own account OR remote party)
    MLCallFinishReasonRetracted,            //used for a call retracted locally (always own acount)
    MLCallFinishReasonRejected,             //used for a call rejected remotely (own account OR remote party)
    MLCallFinishReasonDeclined,             //used for a call rejected locally (always own account)
    MLCallFinishReasonError,                //used for a call error
};

@interface MLCall : NSObject
@property (strong, readonly) NSString* description;

@property (nonatomic, strong, readonly) NSUUID* uuid;
@property (nonatomic, strong, readonly) NSString* jmiid;
@property (nonatomic, strong, readonly) MLContact* contact;
@property (nonatomic, readonly) MLCallType callType;
@property (nonatomic, readonly) MLCallDirection direction;
@property (nonatomic, readonly) MLCallState state;
@property (nonatomic, readonly) MLCallFinishReason finishReason;
@property (nonatomic, readonly) uint32_t durationTime;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) BOOL speaker;

+(instancetype) makeDummyCall:(int) type;
-(void) end;
//these will not use the correct RTCVideoRenderer protocol like in the implementation because the forward declaration of
//RTCVideoRenderer will not be visible to swift until we have swift 5.9 (feature flag ImportObjcForwardDeclarations) or swift 6.0 support
//see https://github.com/apple/swift-evolution/blob/main/proposals/0384-importing-forward-declared-objc-interfaces-and-protocols.md
-(void) startCaptureLocalVideoWithRenderer:(id) renderer;
-(void) renderRemoteVideoWithRenderer:(id) renderer;

-(BOOL) isEqualToContact:(MLContact*) contact;
-(BOOL) isEqualToCall:(MLCall*) call;
-(BOOL) isEqual:(id _Nullable) object;
-(NSUInteger) hash;
@end

NS_ASSUME_NONNULL_END
#endif /* MLCall_h */
