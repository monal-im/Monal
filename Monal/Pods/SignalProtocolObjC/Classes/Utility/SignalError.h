//
//  SignalError.h
//  Pods
//
//  Created by Chris Ballinger on 6/28/16.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SignalError) {
    SignalErrorUnknown = 0,
    SignalErrorNoMemory,
    SignalErrorInvalidArgument,
    SignalErrorDuplicateMessage,
    SignalErrorInvalidKey,
    SignalErrorInvalidKeyId,
    SignalErrorInvalidMAC,
    SignalErrorInvalidMessage,
    SignalErrorInvalidVersion,
    SignalErrorLegacyMessage,
    SignalErrorNoSession,
    SignalErrorStaleKeyExchange,
    SignalErrorUntrustedIdentity,
    SignalErrorInvalidProtoBuf,
    SignalErrorFingerprintVersionMismatch,
    SignalErrorFingerprintIdentityMismatch
};

/** Translate from libsignal-protocol-c internal errors to SignalError enum */
FOUNDATION_EXPORT SignalError SignalErrorFromCode(int errorCode);
FOUNDATION_EXPORT NSString *SignalErrorDescription(SignalError signalError);
/** Internal signal error codes */
FOUNDATION_EXPORT NSError *ErrorFromSignalErrorCode(int errorCode);
FOUNDATION_EXPORT NSError *ErrorFromSignalError(SignalError signalError);
/** "org.whispersystems.SignalProtocol" */
FOUNDATION_EXPORT NSString * const SignalErrorDomain;

NS_ASSUME_NONNULL_END
