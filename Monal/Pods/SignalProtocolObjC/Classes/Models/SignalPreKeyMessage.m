//
//  SignalPreKeySignalMessage.m
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalPreKeyMessage.h"
#import "SignalPreKeyMessage_Internal.h"
#import "SignalContext_Internal.h"
#import "SignalError.h"

@implementation SignalPreKeyMessage

- (void) dealloc {
    if (_pre_key_signal_message) {
        SIGNAL_UNREF(_pre_key_signal_message);
    }
}

- (instancetype) initWithData:(NSData*)data
                      context:(SignalContext*)context
                        error:(NSError**)error {
    NSParameterAssert(data);
    NSParameterAssert(context);
    if (!data || !context) {
        if (error) {
            *error = ErrorFromSignalError(SignalErrorInvalidArgument);
        }
        return nil;
    }
    if (self = [super init]) {
        int result = pre_key_signal_message_deserialize(&_pre_key_signal_message, data.bytes, data.length, context.context);
        if (result < 0 || !_pre_key_signal_message) {
            if (error) {
                *error = ErrorFromSignalError(SignalErrorFromCode(result));
            }
            return nil;
        }
    }
    return self;
}

@end
