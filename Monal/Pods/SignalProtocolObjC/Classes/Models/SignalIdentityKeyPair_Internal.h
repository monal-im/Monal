//
//  SignalIdentityKeyPair_Internal.h
//  Pods
//
//  Created by Chris Ballinger on 6/29/16.
//
//

#import "SignalIdentityKeyPair.h"
@import SignalProtocolC;

NS_ASSUME_NONNULL_BEGIN
@interface SignalIdentityKeyPair ()

@property (nonatomic, readonly) ratchet_identity_key_pair *identity_key_pair;

- (instancetype) initWithIdentityKeyPair:(ratchet_identity_key_pair*)identity_key_pair;

@end
NS_ASSUME_NONNULL_END