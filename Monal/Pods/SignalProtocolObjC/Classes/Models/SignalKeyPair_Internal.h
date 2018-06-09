//
//  SignalKeyPair_Internal.h
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalKeyPair.h"
#import "signal_protocol.h"

NS_ASSUME_NONNULL_BEGIN
@interface SignalKeyPair ()

@property (nonatomic, readonly) ec_key_pair *ec_key_pair;

@property (nonatomic, readonly) ec_public_key* ec_public_key;
@property (nonatomic, readonly) ec_private_key* ec_private_key;

- (nullable instancetype) initWithECKeyPair:(ec_key_pair*)ec_key_pair;
- (nullable instancetype) initWithECPublicKey:(ec_public_key*)ec_public_key
                        ecPrivateKey:(ec_private_key*)ec_private_key;

/** make sure to call SIGNAL_UNREF when you're done */
+ (nullable ec_public_key*)publicKeyFromData:(NSData*)data error:(NSError**)error;

@end
NS_ASSUME_NONNULL_END
