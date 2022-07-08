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

@interface MLVoIPProcessor : NSObject
@property (nonatomic, readonly) NSUInteger pendingCallsCount;
-(void) voipRegistration;

-(NSUUID*) initiateAudioCallToContact:(MLContact*) contact;
@end

NS_ASSUME_NONNULL_END

#endif /* MLVoIPProcessor_h */
