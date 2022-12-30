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

@interface MLCall : NSObject <NSSecureCoding>

@property (nonatomic, strong) NSUUID* uuid;
@property (nonatomic, strong) NSString* callID;
@property (nonatomic, strong) WebRTCClient* webRTCClient;

@property (nonatomic, strong) MLXMLNode* jmiPropose;
@end

NS_ASSUME_NONNULL_END
#endif /* MLCall_h */
