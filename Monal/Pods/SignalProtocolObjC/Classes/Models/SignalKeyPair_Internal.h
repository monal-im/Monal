//
//  SignalKeyPair_Internal.h
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalKeyPair.h"
@import SignalProtocolC;

NS_ASSUME_NONNULL_BEGIN
@interface SignalKeyPair ()

@property (nonatomic, readonly) ec_key_pair *ec_key_pair;

@property (nonatomic, readonly) ec_public_key* ec_public_key;
@property (nonatomic, readonly) ec_private_key* ec_private_key;

- (instancetype) initWithECKeyPair:(ec_key_pair*)ec_key_pair;
- (instancetype) initWithECPublicKey:(ec_public_key*)ec_public_key
                        ecPrivateKey:(ec_private_key*)ec_private_key;

/** make sure to call SIGNAL_UNREF when you're done */
+ (ec_public_key*)publicKeyFromData:(NSData*)data;

@end
NS_ASSUME_NONNULL_END