//
//  SignalError.h
//  Pods
//
//  Created by Chris Ballinger on 6/28/16.
//
//

#import <Foundation/Foundation.h>


typedef NS_ENUM(NSInteger, SignalError) {
    SignalErrorNoMemory,
    SignalErrorInvalidArgument,
    SignalErrorUnknown,
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
SignalError SignalErrorFromCode(int errorCode);
NSString *SignalErrorDescription(SignalError signalError);
NSError *ErrorFromSignalError(SignalError signalError);