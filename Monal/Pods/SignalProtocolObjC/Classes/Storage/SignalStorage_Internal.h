//
//  SignalStorage_Internal.h
//  Pods
//
//  Created by Chris Ballinger on 6/27/16.
//
//

#import "SignalStorage.h"
@import SignalProtocolC;

@interface SignalStorage ()
@property (nonatomic, strong, readonly) id<SignalSessionStore> sessionStore;
@property (nonatomic, strong, readonly) id<SignalPreKeyStore> preKeyStore;
@property (nonatomic, strong, readonly) id<SignalSignedPreKeyStore> signedPreKeyStore;
@property (nonatomic, strong, readonly) id<SignalIdentityKeyStore> identityKeyStore;
@property (nonatomic, strong, readonly) id<SignalSenderKeyStore> senderKeyStore;
@property (nonatomic, readonly) signal_protocol_store_context *storeContext;
- (void) setupWithContext:(signal_context*)context;
@end
