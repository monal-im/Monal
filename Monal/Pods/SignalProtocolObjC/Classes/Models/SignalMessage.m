//
//  SignalMessage.m
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalMessage.h"
#import "SignalMessage_Internal.h"
#import "SignalError.h"
#import "SignalContext_Internal.h"

@implementation SignalMessage

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
        int result = signal_message_deserialize(&_signal_message, data.bytes, data.length, context.context);
        if (result < 0 || !_signal_message) {
            if (error) {
                *error = ErrorFromSignalError(SignalErrorFromCode(result));
            }
            return nil;
        }
    }
    return self;
}

@end
