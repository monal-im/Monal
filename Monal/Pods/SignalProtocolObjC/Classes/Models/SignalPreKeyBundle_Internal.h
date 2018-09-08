//
//  SignalPreKeyBundle_Internal.h
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import "SignalPreKeyBundle.h"
#include "signal_protocol.h"

@interface SignalPreKeyBundle ()

@property (nonatomic, readonly) session_pre_key_bundle *bundle;

@end
