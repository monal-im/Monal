//
//  MLVoIPProcessor.h
//  Monal
//
//  Created by admin on 03.07.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

#ifndef MLVoIPProcessor_h
#define MLVoIPProcessor_h

NS_ASSUME_NONNULL_BEGIN

@class MLCall;
@class CXCallController;
@class CXProvider;

@interface MLVoIPProcessor : NSObject
-(MLCall*) initiateAudioCallToContact:(MLContact*) contact;

@property (nonatomic, readonly) NSUInteger pendingCallsCount;
-(NSDictionary<NSString*, MLCall*>*) getActiveCalls;
-(MLCall* _Nullable) getActiveCallWithContact:(MLContact*) contact;

-(void) voipRegistration;
@end

NS_ASSUME_NONNULL_END

#endif /* MLVoIPProcessor_h */
