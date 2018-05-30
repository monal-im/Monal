//
//  SignalStorage.m
//  SignalProtocol-ObjC
//
//  Created by Chris Ballinger on 6/27/16.
//
//

#import "SignalStorage.h"
#import "SignalAddress_Internal.h"
#import "SignalStorage_Internal.h"
@import SignalProtocolC;

#pragma mark signal_protocol_session_store callbacks

static int load_session_func(signal_buffer **record, const signal_protocol_address *address, void *user_data) {
    id <SignalSessionStore> sessionStore = (__bridge id<SignalSessionStore>)(user_data);
    SignalAddress *addr = [[SignalAddress alloc] initWithAddress:address];
    NSData *data = nil;
    if (addr) {
        data = [sessionStore sessionRecordForAddress:addr];
    } else {
        return -1;
    }
    if (!data) {
        return 0;
    }
    signal_buffer *buffer = signal_buffer_create(data.bytes, data.length);
    *record = buffer;
    return 1;
}

static int get_sub_device_sessions_func(signal_int_list **sessions, const char *name, size_t name_len, void *user_data) {
    id <SignalSessionStore> sessionStore = (__bridge id<SignalSessionStore>)(user_data);
    NSString *nameString = [NSString stringWithUTF8String:name];
    NSArray<NSNumber*> *deviceIds = [sessionStore allDeviceIdsForAddressName:nameString];
    signal_int_list *list = signal_int_list_alloc();
    if (!list) {
        return -1;
    }
    [deviceIds enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        signal_int_list_push_back(list, obj.intValue);
    }];
    *sessions = list;
    return (int)deviceIds.count;
}

static int store_session_func(const signal_protocol_address *address, uint8_t *record, size_t record_len, void *user_data) {
    id <SignalSessionStore> sessionStore = (__bridge id<SignalSessionStore>)(user_data);
    SignalAddress *addr = [[SignalAddress alloc] initWithAddress:address];
    if (!addr) {
        return -1;
    }
    NSData *recordData = [NSData dataWithBytes:record length:record_len];
    BOOL result = [sessionStore storeSessionRecord:recordData forAddress:addr];
    if (result) {
        return 0;
    } else {
        return -1;
    }
}

static int contains_session_func(const signal_protocol_address *address, void *user_data) {
    id <SignalSessionStore> sessionStore = (__bridge id<SignalSessionStore>)(user_data);
    SignalAddress *addr = [[SignalAddress alloc] initWithAddress:address];
    if (!addr) {
        return -1;
    }
    BOOL exists = [sessionStore sessionRecordExistsForAddress:addr];
    return exists;
}

static int delete_session_func(const signal_protocol_address *address, void *user_data) {
    id <SignalSessionStore> sessionStore = (__bridge id<SignalSessionStore>)(user_data);
    SignalAddress *addr = [[SignalAddress alloc] initWithAddress:address];
    if (!addr) {
        return -1;
    }
    BOOL wasDeleted = [sessionStore deleteSessionRecordForAddress:addr];
    return wasDeleted;
}

static int delete_all_sessions_func(const char *name, size_t name_len, void *user_data) {
    id <SignalSessionStore> sessionStore = (__bridge id<SignalSessionStore>)(user_data);
    int result = [sessionStore deleteAllSessionsForAddressName:[NSString stringWithUTF8String:name]];
    return result;
}

static void destroy_func(void *user_data) {}

#pragma mark signal_protocol_pre_key_store

static int load_pre_key(signal_buffer **record, uint32_t pre_key_id, void *user_data) {
    id <SignalPreKeyStore> preKeyStore = (__bridge id<SignalPreKeyStore>)(user_data);
    NSData *preKey = [preKeyStore loadPreKeyWithId:pre_key_id];
    if (!preKey) {
        return SG_ERR_INVALID_KEY_ID;
    }
    signal_buffer *buffer = signal_buffer_create(preKey.bytes, preKey.length);
    *record = buffer;
    return SG_SUCCESS;
}

static int store_pre_key(uint32_t pre_key_id, uint8_t *record, size_t record_len, void *user_data) {
    id <SignalPreKeyStore> preKeyStore = (__bridge id<SignalPreKeyStore>)(user_data);
    NSData *preKey = [NSData dataWithBytes:record length:record_len];
    BOOL success = [preKeyStore storePreKey:preKey preKeyId:pre_key_id];
    if (success) {
        return 0;
    } else {
        return -1;
    }
}

static int contains_pre_key(uint32_t pre_key_id, void *user_data) {
    id <SignalPreKeyStore> preKeyStore = (__bridge id<SignalPreKeyStore>)(user_data);
    BOOL containsPreKey = [preKeyStore containsPreKeyWithId:pre_key_id];
    return containsPreKey;
}

static int remove_pre_key(uint32_t pre_key_id, void *user_data) {
    id <SignalPreKeyStore> preKeyStore = (__bridge id<SignalPreKeyStore>)(user_data);
    BOOL success = [preKeyStore deletePreKeyWithId:pre_key_id];
    if (success) {
        return 0;
    } else {
        return -1;
    }
}

#pragma mark signal_protocol_signed_pre_key_store

static int load_signed_pre_key(signal_buffer **record, uint32_t signed_pre_key_id, void *user_data) {
    id <SignalSignedPreKeyStore> signedPreKeyStore = (__bridge id<SignalSignedPreKeyStore>)(user_data);
    NSData *key = [signedPreKeyStore loadSignedPreKeyWithId:signed_pre_key_id];
    if (!key) {
        return SG_ERR_INVALID_KEY_ID;
    }
    signal_buffer *buffer = signal_buffer_create(key.bytes, key.length);
    *record = buffer;
    return SG_SUCCESS;
}

static int store_signed_pre_key(uint32_t signed_pre_key_id, uint8_t *record, size_t record_len, void *user_data) {
    id <SignalSignedPreKeyStore> signedPreKeyStore = (__bridge id<SignalSignedPreKeyStore>)(user_data);
    NSData *key = [NSData dataWithBytes:record length:record_len];
    BOOL result = [signedPreKeyStore storeSignedPreKey:key signedPreKeyId:signed_pre_key_id];
    if (result) {
        return 0;
    } else {
        return -1;
    }
}

static int contains_signed_pre_key(uint32_t signed_pre_key_id, void *user_data) {
    id <SignalSignedPreKeyStore> signedPreKeyStore = (__bridge id<SignalSignedPreKeyStore>)(user_data);
    BOOL result = [signedPreKeyStore containsSignedPreKeyWithId:signed_pre_key_id];
    return result;
}

static int remove_signed_pre_key(uint32_t signed_pre_key_id, void *user_data) {
    id <SignalSignedPreKeyStore> signedPreKeyStore = (__bridge id<SignalSignedPreKeyStore>)(user_data);
    BOOL result = [signedPreKeyStore removeSignedPreKeyWithId:signed_pre_key_id];
    if (result) {
        return 0;
    } else {
        return -1;
    }
}

#pragma mark signal_protocol_identity_key_store

static int get_identity_key_pair(signal_buffer **public_data, signal_buffer **private_data, void *user_data) {
    id <SignalIdentityKeyStore> identityKeyStore = (__bridge id<SignalIdentityKeyStore>)(user_data);
    SignalKeyPair *keyPair = [identityKeyStore getIdentityKeyPair];
    if (!keyPair) {
        return -1;
    }
    if (keyPair.publicKey) {
        signal_buffer *public = signal_buffer_create(keyPair.publicKey.bytes, keyPair.publicKey.length);
        *public_data = public;
    }
    if (keyPair.privateKey) {
        signal_buffer *private = signal_buffer_create(keyPair.privateKey.bytes, keyPair.privateKey.length);
        *private_data = private;
    }
    return 0;
}

static int get_local_registration_id(void *user_data, uint32_t *registration_id) {
    id <SignalIdentityKeyStore> identityKeyStore = (__bridge id<SignalIdentityKeyStore>)(user_data);
    uint32_t regId = [identityKeyStore getLocalRegistrationId];
    if (regId > 0) {
        *registration_id = regId;
        return 0;
    } else {
        return -1;
    }
}

static int save_identity(const signal_protocol_address *_address, uint8_t *key_data, size_t key_len, void *user_data) {
    id <SignalIdentityKeyStore> identityKeyStore = (__bridge id<SignalIdentityKeyStore>)(user_data);
    SignalAddress *address = [[SignalAddress alloc] initWithAddress:_address];
    NSData *key = nil;
    if (key_data) {
        key = [NSData dataWithBytes:key_data length:key_len];
    }
    BOOL success = [identityKeyStore saveIdentity:address identityKey:key];
    if (success) {
        return 0;
    } else {
        return -1;
    }
}

static int is_trusted_identity(const signal_protocol_address *_address, uint8_t *key_data, size_t key_len, void *user_data) {
    id <SignalIdentityKeyStore> identityKeyStore = (__bridge id<SignalIdentityKeyStore>)(user_data);
    SignalAddress *address = [[SignalAddress alloc] initWithAddress:_address];
    NSData *key = [NSData dataWithBytes:key_data length:key_len];
    BOOL isTrusted = [identityKeyStore isTrustedIdentity:address identityKey:key];
    return isTrusted;
}

#pragma mark signal_protocol_sender_key_store

static int store_sender_key(const signal_protocol_sender_key_name *sender_key_name, uint8_t *record, size_t record_len, void *user_data) {
    id <SignalSenderKeyStore> senderKeyStore = (__bridge id<SignalSenderKeyStore>)(user_data);
    SignalAddress *address = [[SignalAddress alloc] initWithAddress:&sender_key_name->sender];
    NSString *groupId = [NSString stringWithUTF8String:sender_key_name->group_id];
    NSData *key = [NSData dataWithBytes:record length:record_len];
    BOOL result = [senderKeyStore storeSenderKey:key address:address groupId:groupId];
    if (result) {
        return 0;
    } else {
        return -1;
    }
}

static int load_sender_key(signal_buffer **record, const signal_protocol_sender_key_name *sender_key_name, void *user_data) {
    id <SignalSenderKeyStore> senderKeyStore = (__bridge id<SignalSenderKeyStore>)(user_data);
    SignalAddress *address = [[SignalAddress alloc] initWithAddress:&sender_key_name->sender];
    NSString *groupId = [NSString stringWithUTF8String:sender_key_name->group_id];
    NSData *key = [senderKeyStore loadSenderKeyForAddress:address groupId:groupId];
    if (key) {
        signal_buffer *buffer = signal_buffer_create(key.bytes, key.length);
        *record = buffer;
        return 1;
    } else {
        return 0;
    }
}

#pragma mark

@implementation SignalStorage

- (void) dealloc {
    if (_storeContext) {
        signal_protocol_store_context_destroy(_storeContext);
    }
    _storeContext = NULL;
}

- (instancetype) initWithSignalStore:(id<SignalStore>)signalStore {
    if (self = [self initWithSessionStore:signalStore preKeyStore:signalStore signedPreKeyStore:signalStore identityKeyStore:signalStore senderKeyStore:signalStore]){
    }
    return self;
}

- (instancetype) initWithSessionStore:(id<SignalSessionStore>)sessionStore
                          preKeyStore:(id<SignalPreKeyStore>)preKeyStore
                    signedPreKeyStore:(id<SignalSignedPreKeyStore>)signedPreKeyStore
                     identityKeyStore:(id<SignalIdentityKeyStore>)identityKeyStore
                       senderKeyStore:(id<SignalSenderKeyStore>)senderKeyStore {
    NSParameterAssert(sessionStore);
    NSParameterAssert(preKeyStore);
    NSParameterAssert(signedPreKeyStore);
    NSParameterAssert(identityKeyStore);
    NSParameterAssert(senderKeyStore);
    if (self = [super init]) {
        _sessionStore = sessionStore;
        _preKeyStore = preKeyStore;
        _signedPreKeyStore = signedPreKeyStore;
        _identityKeyStore = identityKeyStore;
        _senderKeyStore = senderKeyStore;
    }
    return self;
}

- (void) setupWithContext:(signal_context*)context {
    NSParameterAssert(context != NULL);
    if (!context) {
        return;
    }
    signal_protocol_store_context_create(&_storeContext, context);
    
    // Session Store
    signal_protocol_session_store sessionStoreCallbacks;
    sessionStoreCallbacks.load_session_func = load_session_func;
    sessionStoreCallbacks.get_sub_device_sessions_func = get_sub_device_sessions_func;
    sessionStoreCallbacks.store_session_func = store_session_func;
    sessionStoreCallbacks.contains_session_func = contains_session_func;
    sessionStoreCallbacks.delete_session_func = delete_session_func;
    sessionStoreCallbacks.delete_all_sessions_func = delete_all_sessions_func;
    sessionStoreCallbacks.destroy_func = destroy_func;
    sessionStoreCallbacks.user_data = (__bridge void *)(_sessionStore);
    signal_protocol_store_context_set_session_store(_storeContext, &sessionStoreCallbacks);
    
    // PreKey store
    signal_protocol_pre_key_store preKeyStoreCallbacks;
    preKeyStoreCallbacks.load_pre_key = load_pre_key;
    preKeyStoreCallbacks.store_pre_key = store_pre_key;
    preKeyStoreCallbacks.contains_pre_key = contains_pre_key;
    preKeyStoreCallbacks.remove_pre_key = remove_pre_key;
    preKeyStoreCallbacks.destroy_func = destroy_func;
    preKeyStoreCallbacks.user_data = (__bridge void *)(_preKeyStore);
    signal_protocol_store_context_set_pre_key_store(_storeContext, &preKeyStoreCallbacks);
    
    // Signed PreKey Store
    signal_protocol_signed_pre_key_store signedPreKeyStoreCallbacks;
    signedPreKeyStoreCallbacks.load_signed_pre_key = load_signed_pre_key;
    signedPreKeyStoreCallbacks.store_signed_pre_key = store_signed_pre_key;
    signedPreKeyStoreCallbacks.contains_signed_pre_key = contains_signed_pre_key;
    signedPreKeyStoreCallbacks.remove_signed_pre_key = remove_signed_pre_key;
    signedPreKeyStoreCallbacks.destroy_func = destroy_func;
    signedPreKeyStoreCallbacks.user_data = (__bridge void *)(_signedPreKeyStore);
    signal_protocol_store_context_set_signed_pre_key_store(_storeContext, &signedPreKeyStoreCallbacks);
    
    // Identity Key Store
    signal_protocol_identity_key_store identityKeyStoreCallbacks;
    identityKeyStoreCallbacks.get_identity_key_pair = get_identity_key_pair;
    identityKeyStoreCallbacks.get_local_registration_id = get_local_registration_id;
    identityKeyStoreCallbacks.save_identity = save_identity;
    identityKeyStoreCallbacks.is_trusted_identity = is_trusted_identity;
    identityKeyStoreCallbacks.destroy_func = destroy_func;
    identityKeyStoreCallbacks.user_data = (__bridge void *)(_identityKeyStore);
    signal_protocol_store_context_set_identity_key_store(_storeContext, &identityKeyStoreCallbacks);
    
    // Sender Key Store
    signal_protocol_sender_key_store senderKeyStoreCallbacks;
    senderKeyStoreCallbacks.store_sender_key = store_sender_key;
    senderKeyStoreCallbacks.load_sender_key = load_sender_key;
    senderKeyStoreCallbacks.destroy_func = destroy_func;
    identityKeyStoreCallbacks.user_data = (__bridge void *)(_senderKeyStore);
    signal_protocol_store_context_set_sender_key_store(_storeContext, &senderKeyStoreCallbacks);
}

@end
