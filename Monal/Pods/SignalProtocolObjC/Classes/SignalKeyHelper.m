//
//  SignalKeyHelper.m
//  Pods
//
//  Created by Chris Ballinger on 6/29/16.
//
//

#import "SignalKeyHelper.h"
#import "SignalContext_Internal.h"
#import "SignalError.h"
#import "SignalIdentityKeyPair_Internal.h"
#import "SignalPreKey_Internal.h"
#import "SignalSignedPreKey_Internal.h"
@import SignalProtocolC;

@implementation SignalKeyHelper

- (instancetype) initWithContext:(SignalContext*)context {
    NSParameterAssert(context);
    if (!context) { return nil; }
    if (self = [super init]) {
        _context = context;
    }
    return self;
}

- (nullable SignalIdentityKeyPair*) generateIdentityKeyPair {
    ratchet_identity_key_pair *keyPair = NULL;
    int result = signal_protocol_key_helper_generate_identity_key_pair(&keyPair, _context.context);
    if (result < 0 || !keyPair) {
        return nil;
    }
    SignalIdentityKeyPair *identityKey = [[SignalIdentityKeyPair alloc] initWithIdentityKeyPair:keyPair];
    SIGNAL_UNREF(keyPair);
    return identityKey;
}

- (uint32_t) generateRegistrationId {
    uint32_t registration_id = 0;
    int result = signal_protocol_key_helper_generate_registration_id(&registration_id, 1, _context.context);
    if (result < 0) {
        return 0;
    }
    return registration_id;
}

- (NSArray<SignalPreKey*>*)generatePreKeysWithStartingPreKeyId:(NSUInteger)startingPreKeyId
                                                         count:(NSUInteger)count {
    signal_protocol_key_helper_pre_key_list_node *head = NULL;
    int result = signal_protocol_key_helper_generate_pre_keys(&head, (unsigned int)startingPreKeyId, (unsigned int)count, _context.context);
    if (!head || result < 0) {
        return @[];
    }
    NSMutableArray<SignalPreKey*> *keys = [NSMutableArray array];
    while (head) {
        session_pre_key *pre_key = signal_protocol_key_helper_key_list_element(head);
        SignalPreKey *preKey = [[SignalPreKey alloc] initWithPreKey:pre_key];
        [keys addObject:preKey];
        head = signal_protocol_key_helper_key_list_next(head);
    }
    return keys;
}

- (nullable SignalPreKey*)generateLastResortPreKey {
    session_pre_key *pre_key = NULL;
    int result = signal_protocol_key_helper_generate_last_resort_pre_key(&pre_key, _context.context);
    if (result < 0) {
        return nil;
    }
    SignalPreKey *key = [[SignalPreKey alloc] initWithPreKey:pre_key];
    return key;
}

- (SignalSignedPreKey*)generateSignedPreKeyWithIdentity:(SignalIdentityKeyPair*)identityKeyPair
                                         signedPreKeyId:(uint32_t)signedPreKeyId
                                              timestamp:(NSDate*)timestamp

{
    NSParameterAssert(identityKeyPair);
    NSParameterAssert(identityKeyPair.identity_key_pair);
    if (!identityKeyPair || !identityKeyPair.identity_key_pair) { return nil; }
    session_signed_pre_key *signed_pre_key = NULL;
    uint64_t unixTimestamp = [timestamp timeIntervalSince1970] * 1000;
    int result = signal_protocol_key_helper_generate_signed_pre_key(&signed_pre_key, identityKeyPair.identity_key_pair, signedPreKeyId, unixTimestamp, _context.context);
    if (result < 0 || !signed_pre_key) {
        return nil;
    }
    SignalSignedPreKey *signedPreKey = [[SignalSignedPreKey alloc] initWithSignedPreKey:signed_pre_key];
    return signedPreKey;
}


- (SignalSignedPreKey*)generateSignedPreKeyWithIdentity:(SignalIdentityKeyPair*)identityKeyPair
                                         signedPreKeyId:(uint32_t)signedPreKeyId
                                                   {
    return [self generateSignedPreKeyWithIdentity:identityKeyPair signedPreKeyId:signedPreKeyId timestamp:[NSDate date]];
}

@end
