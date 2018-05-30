//
//  SignalContext_Internal.h
//  Pods
//
//  Created by Chris Ballinger on 6/28/16.
//
//

#import "SignalContext.h"
#import "SignalCommonCryptoProvider.h"
@import SignalProtocolC;

@interface SignalContext ()
@property (nonatomic, readonly) signal_context *context;
@property (nonatomic, strong, readonly) SignalCommonCryptoProvider *cryptoProvider;
@property (nonatomic, strong, readonly) NSRecursiveLock *lock;
@end