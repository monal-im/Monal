//
//  SignalPreKey.m
//  Pods
//
//  Created by Chris Ballinger on 6/29/16.
//
//

#import "SignalPreKey.h"
#import "SignalPreKey_Internal.h"
#import "SignalKeyPair_Internal.h"
#import "SignalError.h"

@implementation SignalPreKey

- (void) dealloc {
    if (_preKey) {
        SIGNAL_UNREF(_preKey);
    }
    _preKey = NULL;
}

- (instancetype) initWithPreKey:(session_pre_key*)preKey {
    NSParameterAssert(preKey);
    if (!preKey) { return nil; }
    if (self = [super init]) {
        _preKey = preKey;
    }
    return self;
}

- (uint32_t) preKeyId {
    return session_pre_key_get_id(_preKey);
}

- (SignalKeyPair*)keyPair {
    ec_key_pair *ec_key_pair = session_pre_key_get_key_pair(_preKey);
    SignalKeyPair *keyPair = [[SignalKeyPair alloc] initWithECKeyPair:ec_key_pair];
    return keyPair;
}

/** Serialized data, or nil if there was an error */
- (nullable NSData*)serializedData {
    signal_buffer *buffer = NULL;
    int result = session_pre_key_serialize(&buffer, _preKey);
    NSData *data = nil;
    if (buffer && result >= 0) {
        data = [NSData dataWithBytes:signal_buffer_data(buffer) length:signal_buffer_len(buffer)];
    }
    return data;
}

/** Deserialized object, or nil if there is an error */
- (nullable instancetype) initWithSerializedData:(NSData*)serializedData error:(NSError **)error {
    NSParameterAssert(serializedData);
    if (!serializedData) {
        if (error) {
            *error = ErrorFromSignalError(SignalErrorInvalidArgument);
        }
        return nil;
    }
    if (self = [super init]) {
        int result = session_pre_key_deserialize(&_preKey, serializedData.bytes, serializedData.length, NULL);
        if (result < 0) {
            if (error) {
                *error = ErrorFromSignalError(SignalErrorFromCode(result));
            }
            return nil;
        }
    }
    return self;
}

#pragma mark NSSecureCoding

+ (BOOL) supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    NSData *data = [aDecoder decodeObjectOfClass:[NSData class] forKey:@"data"];
    return [self initWithSerializedData:data error:nil];
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.serializedData forKey:@"data"];
}


@end
