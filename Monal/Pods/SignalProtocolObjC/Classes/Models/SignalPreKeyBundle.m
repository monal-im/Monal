//
//  SignalPreKeyBundle.m
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalPreKeyBundle.h"
#import "SignalPreKeyBundle_Internal.h"
#import "SignalKeyPair_Internal.h"

@implementation SignalPreKeyBundle

- (void) dealloc {
    if (_bundle) {
        SIGNAL_UNREF(_bundle);
    }
}

- (instancetype) initWithRegistrationId:(uint32_t)registrationId
                               deviceId:(uint32_t)deviceId
                               preKeyId:(uint32_t)preKeyId
                           preKeyPublic:(NSData*)preKeyPublic
                         signedPreKeyId:(uint32_t)signedPreKeyId
                     signedPreKeyPublic:(NSData*)signedPreKeyPublic
                              signature:(NSData*)signature
                            identityKey:(NSData*)identityKey {
    NSParameterAssert(preKeyPublic);
    NSParameterAssert(signedPreKeyPublic);
    NSParameterAssert(signature);
    NSParameterAssert(identityKey);
    if (!preKeyPublic || !signedPreKeyPublic || !signature || !identityKey) {
        return nil;
    }
    if (self = [super init]) {
        _registrationId = registrationId;
        _deviceId = deviceId;
        _preKeyId = preKeyId;
        _preKeyPublic = preKeyPublic;
        _signedPreKeyId = signedPreKeyId;
        _signedPreKeyPublic = signedPreKeyPublic;
        _signature = signature;
        _identityKey = identityKey;
        
        ec_public_key *pre_key_public = [SignalKeyPair publicKeyFromData:preKeyPublic];
        ec_public_key *signed_pre_key_public = [SignalKeyPair publicKeyFromData:signedPreKeyPublic];
        ec_public_key *identity_key = [SignalKeyPair publicKeyFromData:identityKey];
        
        int result = session_pre_key_bundle_create(&_bundle,
                                                   registrationId,
                                                   deviceId,
                                                   preKeyId,
                                                   pre_key_public,
                                                   signedPreKeyId,
                                                   signed_pre_key_public,
                                                   signature.bytes,
                                                   signature.length,
                                                   identity_key);
        SIGNAL_UNREF(pre_key_public);
        SIGNAL_UNREF(signed_pre_key_public);
        SIGNAL_UNREF(identity_key);
        NSAssert(result >= 0, @"error creating prekey bundle");
        if (result < 0 || !_bundle) { return nil; }
    }
    return self;
}

@end
