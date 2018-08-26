//
//  SignalKeyHelper.h
//  Pods
//
//  Created by Chris Ballinger on 6/29/16.
//
//

#import <Foundation/Foundation.h>
#import "SignalContext.h"
#import "SignalIdentityKeyPair.h"
#import "SignalPreKey.h"
#import "SignalSignedPreKey.h"

NS_ASSUME_NONNULL_BEGIN
@interface SignalKeyHelper : NSObject

@property (nonatomic, strong, readonly) SignalContext *context;

- (nullable instancetype) initWithContext:(SignalContext*)context;

/**
 * Generate an identity key pair.  Clients should only do this once,
 * at install time.
 */
- (nullable SignalIdentityKeyPair*) generateIdentityKeyPair;

/**
 * Generate a registration ID.  Clients should only do this once,
 * at install time. If result is 0, there was an error.
 */
- (uint32_t) generateRegistrationId;

/**
 * Generate a list of PreKeys.  Clients should do this at install time, and
 * subsequently any time the list of PreKeys stored on the server runs low.
 *
 * Pre key IDs are shorts, so they will eventually be repeated.  Clients should
 * store pre keys in a circular buffer, so that they are repeated as infrequently
 * as possible.
 */
- (NSArray<SignalPreKey*>*)generatePreKeysWithStartingPreKeyId:(NSUInteger)startingPreKeyId
                                                         count:(NSUInteger)count;

/**
 * Generate a signed pre key
 */
- (nullable SignalSignedPreKey*)generateSignedPreKeyWithIdentity:(SignalIdentityKeyPair*)identityKeyPair
                                                  signedPreKeyId:(uint32_t)signedPreKeyId;



@end
NS_ASSUME_NONNULL_END
