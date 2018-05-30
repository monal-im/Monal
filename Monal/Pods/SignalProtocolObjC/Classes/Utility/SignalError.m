//
//  SignalError.m
//  Pods
//
//  Created by Chris Ballinger on 6/28/16.
//
//

#import "SignalError.h"
@import SignalProtocolC;

SignalError SignalErrorFromCode(int errorCode) {
    switch (errorCode) {
        case SG_ERR_NOMEM:
            return SignalErrorNoMemory;
        case SG_ERR_INVAL:
            return SignalErrorInvalidArgument;
        case SG_ERR_UNKNOWN:
            return SignalErrorUnknown;
        case SG_ERR_DUPLICATE_MESSAGE:
            return SignalErrorDuplicateMessage;
        case SG_ERR_INVALID_KEY:
            return SignalErrorInvalidKey;
        case SG_ERR_INVALID_KEY_ID:
            return SignalErrorInvalidKeyId;
        case SG_ERR_INVALID_MAC:
            return SignalErrorInvalidMAC;
        case SG_ERR_INVALID_MESSAGE:
            return SignalErrorInvalidMessage;
        case SG_ERR_INVALID_VERSION:
            return SignalErrorInvalidVersion;
        case SG_ERR_LEGACY_MESSAGE:
            return SignalErrorLegacyMessage;
        case SG_ERR_NO_SESSION:
            return SignalErrorNoSession;
        case SG_ERR_STALE_KEY_EXCHANGE:
            return SignalErrorStaleKeyExchange;
        case SG_ERR_UNTRUSTED_IDENTITY:
            return SignalErrorUntrustedIdentity;
        case SG_ERR_INVALID_PROTO_BUF:
            return SignalErrorInvalidProtoBuf;
        case SG_ERR_FP_VERSION_MISMATCH:
            return SignalErrorFingerprintVersionMismatch;
        case SG_ERR_FP_IDENT_MISMATCH:
            return SignalErrorFingerprintIdentityMismatch;
        default:
            return SignalErrorUnknown;
    }
}

NSString *SignalErrorDescription(SignalError signalError) {
    switch (signalError) {
        case SignalErrorNoMemory:
            return @"No Memory";
        case SignalErrorInvalidArgument:
            return @"Invalid Argument";
        case SignalErrorUnknown:
            return @"Unknown Error";
        case SignalErrorDuplicateMessage:
            return @"Duplicate Message";
        case SignalErrorInvalidKey:
            return @"Invalid Key";
        case SignalErrorInvalidKeyId:
            return @"Invalid Key Id";
        case SignalErrorInvalidMAC:
            return @"Invalid MAC";
        case SignalErrorInvalidMessage:
            return @"Invalid Message";
        case SignalErrorInvalidVersion:
            return @"Invalid Version";
        case SignalErrorLegacyMessage:
            return @"Legacy Message";
        case SignalErrorNoSession:
            return @"No Session";
        case SignalErrorStaleKeyExchange:
            return @"Stale Key Exchange";
        case SignalErrorUntrustedIdentity:
            return @"Untrusted Identity";
        case SignalErrorInvalidProtoBuf:
            return @"Invalid ProtoBuf";
        case SignalErrorFingerprintVersionMismatch:
            return @"Fingerprint Version Mismatch";
        case SignalErrorFingerprintIdentityMismatch:
            return @"Fingerprint Identity Mismatch";
        default:
            return @"Unknown Error";
    }
}

NSError *ErrorFromSignalError(SignalError signalError) {
    NSString *errorString = SignalErrorDescription(signalError);
    NSError *error = [NSError errorWithDomain:@"org.whispersystems.SignalProtocol" code:signalError userInfo:@{NSLocalizedDescriptionKey: errorString}];
    return error;
}