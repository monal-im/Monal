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
#import "SignalError.h"

@implementation SignalPreKeyBundle

- (void) dealloc {
    if (_bundle) {
        SIGNAL_UNREF(_bundle);
    }
}

- (nullable instancetype) initWithRegistrationId:(uint32_t)registrationId
                               deviceId:(uint32_t)deviceId
                               preKeyId:(uint32_t)preKeyId
                           preKeyPublic:(NSData*)preKeyPublic
                         signedPreKeyId:(uint32_t)signedPreKeyId
                     signedPreKeyPublic:(NSData*)signedPreKeyPublic
                              signature:(NSData*)signature
                            identityKey:(NSData*)identityKey
                                  error:(NSError* __autoreleasing *)error {
    NSParameterAssert(preKeyPublic);
    NSParameterAssert(signedPreKeyPublic);
    NSParameterAssert(signature);
    NSParameterAssert(identityKey);
    if (!preKeyPublic || !signedPreKeyPublic || !signature || !identityKey) {
        if (error) {
            *error = ErrorFromSignalError(SignalErrorInvalidArgument);
        }
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
        
        ec_public_key *pre_key_public = [SignalKeyPair publicKeyFromData:preKeyPublic error:error];
        if (!pre_key_public) {
            return nil;
        }
        ec_public_key *signed_pre_key_public = [SignalKeyPair publicKeyFromData:signedPreKeyPublic error:error];
        if (!signed_pre_key_public) {
            return nil;
        }
        ec_public_key *identity_key = [SignalKeyPair publicKeyFromData:identityKey error:error];
        if (!identity_key) {
            return nil;
        }
        
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
        if (result < 0 || !_bundle) {
            if (error) {
                *error = ErrorFromSignalErrorCode(result);
            }
            return nil;
        }
        BOOL valid = [self checkValidity:error];
        if (!valid) {
            return nil;
        }
    }
    return self;
}

/** This will do a rough check if bundle is considered valid */
- (BOOL) checkValidity:(NSError * __autoreleasing *)error {
    // session_builder.c:191
    // int session_builder_process_pre_key_bundle(session_builder *builder, session_pre_key_bundle *bundle)
    
    BOOL (^handleResult)(int result) = ^BOOL(int result) {
        if (result < 0) {
            if (error) {
                *error = ErrorFromSignalErrorCode(result);
            }
            return NO;
        }
        return YES;
    };

    int result = 0;
    ec_public_key *signed_pre_key = 0;
    ec_public_key *pre_key = 0;

    session_pre_key_bundle *bundle = _bundle;
    signed_pre_key = session_pre_key_bundle_get_signed_pre_key(bundle);
    pre_key = session_pre_key_bundle_get_pre_key(bundle);
    
    if(signed_pre_key) {
        ec_public_key *identity_key = session_pre_key_bundle_get_identity_key(bundle);
        signal_buffer *signature = session_pre_key_bundle_get_signed_pre_key_signature(bundle);
        
        signal_buffer *serialized_signed_pre_key = 0;
        result = ec_public_key_serialize(&serialized_signed_pre_key, signed_pre_key);
        if(result < 0) {
            return handleResult(result);
        }
        
        result = curve_verify_signature(identity_key,
                                        signal_buffer_data(serialized_signed_pre_key),
                                        signal_buffer_len(serialized_signed_pre_key),
                                        signal_buffer_data(signature),
                                        signal_buffer_len(signature));
        
        signal_buffer_free(serialized_signed_pre_key);
        
        if(result == 0) {
            result = SG_ERR_INVALID_KEY;
        }
        if(result < 0) {
            return handleResult(result);
        }
    }
    
    if(!signed_pre_key) {
        result = SG_ERR_INVALID_KEY;
        return handleResult(result);
    }
    
    return handleResult(result);
}

@end
