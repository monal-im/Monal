//
//  SignalPreKeyMessage_Internal.h
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalPreKeyMessage.h"
#include "signal_protocol.h"

@interface SignalPreKeyMessage ()
@property (nonatomic, readonly) pre_key_signal_message *pre_key_signal_message;
@end
