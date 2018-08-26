//
//  SignalKeyPair.m
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalKeyPair.h"
#import "SignalKeyPair_Internal.h"
#import "SignalError.h"

@implementation SignalKeyPair
@synthesize publicKey = _publicKey;
@synthesize privateKey = _privateKey;
@synthesize ec_key_pair = _ec_key_pair;
@synthesize ec_public_key = _ec_public_key;
@synthesize ec_private_key = _ec_private_key;

- (void) dealloc {
    if (_ec_key_pair) {
        SIGNAL_UNREF(_ec_key_pair);
    }
    if (_ec_private_key) {
        SIGNAL_UNREF(_ec_private_key);
    }
    if (_ec_public_key) {
        SIGNAL_UNREF(_ec_public_key);
    }
}

- (ec_key_pair*)ec_key_pair {
    if (!_ec_key_pair) {
        NSParameterAssert(_ec_private_key);
        NSParameterAssert(_ec_public_key);
        int result = ec_key_pair_create(&_ec_key_pair, _ec_public_key, _ec_private_key);
        NSAssert(result >= 0, @"couldnt create keypair");
    }
    NSParameterAssert(_ec_key_pair);
    return _ec_key_pair;
}

- (NSData*) privateKey {
    if (!_privateKey) {
        ec_private_key *private = [self ec_private_key];
        NSParameterAssert(private);
        if (!private) { return nil; }
        signal_buffer *buffer = NULL;
        int result = ec_private_key_serialize(&buffer, private);
        if (result == 0 && buffer) {
            _privateKey = [NSData dataWithBytes:signal_buffer_data(buffer) length:signal_buffer_len(buffer)];
        }
        signal_buffer_bzero_free(buffer);
        NSAssert(_privateKey != nil, @"private key shouldn't be nil!");
    }
    return _privateKey;
}

- (NSData*) publicKey {
    if (!_publicKey) {
        ec_public_key *public = [self ec_public_key];
        NSParameterAssert(public);
        if (!public) { return nil; }
        signal_buffer *buffer = NULL;
        int result = ec_public_key_serialize(&buffer, public);
        if (result == 0 && buffer) {
            _publicKey = [NSData dataWithBytes:signal_buffer_data(buffer) length:signal_buffer_len(buffer)];
        }
        signal_buffer_free(buffer);
        NSAssert(_publicKey != nil, @"public key shouldn't be nil!");
    }
    return _publicKey;
}

- (instancetype) initWithECPublicKey:(ec_public_key*)ec_public_key
                        ecPrivateKey:(ec_private_key*)ec_private_key {
    NSParameterAssert(ec_public_key);
    NSParameterAssert(ec_private_key);
    if (!ec_public_key || !ec_private_key) { return nil; }
    if (self = [super init]) {
        SIGNAL_REF(ec_public_key);
        _ec_public_key = ec_public_key;
        SIGNAL_REF(ec_private_key);
        _ec_private_key = ec_private_key;
    }
    return self;
}

+ (nullable ec_public_key*)publicKeyFromData:(NSData*)data error:(NSError**)error {
    NSParameterAssert(data);
    if (!data) { return nil; }
    ec_public_key *public = NULL;
    int result = curve_decode_point(&public, data.bytes, data.length, NULL);
    if (result < 0 || !public) {
        if (error) {
            *error = ErrorFromSignalErrorCode(result);
        }
        return nil;
    }
    return public;
}

- (nullable instancetype) initWithPublicKey:(NSData*)publicKey
                        privateKey:(NSData*)privateKey
                             error:(NSError**)error {
    NSParameterAssert(publicKey);
    NSParameterAssert(privateKey);
    if (!publicKey || !privateKey) {
        if (error) {
            *error = ErrorFromSignalError(SignalErrorInvalidArgument);
        }
        return nil;
    }
    ec_public_key *public = [[self class] publicKeyFromData:publicKey error:error];
    if (!public) {
        return nil;
    }
    _ec_public_key = public;
    int result = curve_decode_private_point(&_ec_private_key, privateKey.bytes, privateKey.length, NULL);
    NSAssert(result >= 0, @"couldnt decode private key");
    if (result < 0 || !_ec_private_key) {
        if (error) {
            *error = ErrorFromSignalErrorCode(result);
        }
        return nil;
    }
    
    if (self = [super init]) {
        _publicKey = publicKey;
        _privateKey = privateKey;
    }
    return self;
}

- (nullable instancetype) initWithECKeyPair:(ec_key_pair*)ec_key_pair {
    NSParameterAssert(ec_key_pair);
    if (!ec_key_pair) { return nil; }
    ec_private_key *private = ec_key_pair_get_private(ec_key_pair);
    ec_public_key *public = ec_key_pair_get_public(ec_key_pair);
    if (self = [self initWithECPublicKey:public ecPrivateKey:private]) {
        SIGNAL_REF(ec_key_pair);
        _ec_key_pair = ec_key_pair;
    }
    return self;
}

#pragma mark NSSecureCoding

+ (BOOL) supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    NSData *publicKey = [aDecoder decodeObjectOfClass:[NSData class] forKey:@"public"];
    NSData *privateKey = [aDecoder decodeObjectOfClass:[NSData class] forKey:@"private"];
    return [self initWithPublicKey:publicKey privateKey:privateKey error:nil];
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.publicKey forKey:@"public"];
    [aCoder encodeObject:self.privateKey forKey:@"private"];
}

@end
