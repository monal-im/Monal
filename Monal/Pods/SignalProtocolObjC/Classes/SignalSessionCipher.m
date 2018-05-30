//
//  SignalSessionCipher.m
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalSessionCipher.h"
#import "SignalContext_Internal.h"
#import "SignalStorage_Internal.h"
#import "SignalAddress_Internal.h"
#import "SignalMessage_Internal.h"
#import "SignalPreKeyMessage_Internal.h"
#import "SignalError.h"

@import SignalProtocolC;

@interface SignalSessionCipher ()
@property (nonatomic, readonly) session_cipher *cipher;
@end

@implementation SignalSessionCipher



- (instancetype) initWithAddress:(SignalAddress*)address
                         context:(SignalContext*)context {
    NSParameterAssert(address);
    NSParameterAssert(context);
    if (!address || !context) { return nil; }
    if (self = [super init]) {
        _context = context;
        _address = address;
        int result = session_cipher_create(&_cipher, context.storage.storeContext, address.address, context.context);
        NSAssert(result >= 0 && _cipher, @"couldn't create cipher");
        if (result < 0 || !_cipher) {
            return nil;
        }
    }
    return self;
}

- (nullable SignalCiphertext*)encryptData:(NSData*)data error:(NSError**)error {
    NSParameterAssert(data);
    if (!data) {
        if (error) {
            *error = ErrorFromSignalError(SignalErrorInvalidArgument);
        }
        return nil;
    }
    ciphertext_message *message = NULL;
    int result = session_cipher_encrypt(_cipher, data.bytes, data.length, &message);
    if (result < 0 || !message) {
        *error = ErrorFromSignalError(SignalErrorFromCode(result));
        return nil;
    }
    signal_buffer *serialized = ciphertext_message_get_serialized(message);
    NSData *outData = [NSData dataWithBytes:signal_buffer_data(serialized) length:signal_buffer_len(serialized)];
    int type = ciphertext_message_get_type(message);
    SignalCiphertextType outType = SignalCiphertextTypeUnknown;
    if (type == CIPHERTEXT_SIGNAL_TYPE) {
        outType = SignalCiphertextTypeMessage;
    } else if (type == CIPHERTEXT_PREKEY_TYPE) {
        outType = SignalCiphertextTypePreKeyMessage;
    }
    SignalCiphertext *encrypted = [[SignalCiphertext alloc] initWithData:outData type:outType];
    SIGNAL_UNREF(message);
    return encrypted;
}

- (nullable NSData*)decryptCiphertext:(SignalCiphertext*)ciphertext error:(NSError**)error {
    NSParameterAssert(ciphertext && ciphertext.data);
    if (!ciphertext || !ciphertext.data) {
        if (error) {
            *error = ErrorFromSignalError(SignalErrorInvalidArgument);
        }
        return nil;
    }
    SignalMessage *message = nil;
    SignalPreKeyMessage *preKeyMessage = nil;
    if (ciphertext.type == SignalCiphertextTypePreKeyMessage) {
        preKeyMessage = [[SignalPreKeyMessage alloc] initWithData:ciphertext.data context:_context error:error];
        if (!preKeyMessage) { return nil; }
    } else if (ciphertext.type == SignalCiphertextTypeMessage) {
        message = [[SignalMessage alloc] initWithData:ciphertext.data context:_context error:error];
        if (!message) { return nil; }
    } else {
        // Fall back to brute force type detection...
        preKeyMessage = [[SignalPreKeyMessage alloc] initWithData:ciphertext.data context:_context error:error];
        message = [[SignalMessage alloc] initWithData:ciphertext.data context:_context error:error];
        if (!preKeyMessage && !message) {
            if (error) {
                if (!*error) {
                    *error = ErrorFromSignalError(SignalErrorInvalidArgument);
                }
            }
            return nil;
        }
    }
    
    signal_buffer *buffer = NULL;
    int result = SG_ERR_UNKNOWN;
    if (message) {
        result = session_cipher_decrypt_signal_message(_cipher, message.signal_message, NULL, &buffer);
    } else if (preKeyMessage) {
        result = session_cipher_decrypt_pre_key_signal_message(_cipher, preKeyMessage.pre_key_signal_message, NULL, &buffer);
    }
    if (result < 0 || !buffer) {
        if (error) {
            *error = ErrorFromSignalError(SignalErrorFromCode(result));
        }
        return nil;
    }
    NSData *outData = [NSData dataWithBytes:signal_buffer_data(buffer) length:signal_buffer_len(buffer)];
    signal_buffer_free(buffer);
    return outData;
}

@end
