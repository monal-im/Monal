//
//  SignalStorage.h
//  SignalProtocol-ObjC
//
//  Created by Chris Ballinger on 6/27/16.
//
//

#import <Foundation/Foundation.h>
#import "SignalSessionStore.h"
#import "SignalIdentityKeyStore.h"
#import "SignalPreKeyStore.h"
#import "SignalSenderKeyStore.h"
#import "SignalSignedPreKeyStore.h"

@protocol SignalStore <SignalSessionStore, SignalPreKeyStore, SignalSignedPreKeyStore, SignalIdentityKeyStore, SignalSenderKeyStore>
@end

NS_ASSUME_NONNULL_BEGIN
@interface SignalStorage : NSObject

- (instancetype) initWithSignalStore:(id<SignalStore>)signalStore;

- (instancetype) initWithSessionStore:(id<SignalSessionStore>)sessionStore
                          preKeyStore:(id<SignalPreKeyStore>)preKeyStore
                    signedPreKeyStore:(id<SignalSignedPreKeyStore>)signedPreKeyStore
                     identityKeyStore:(id<SignalIdentityKeyStore>)identityKeyStore
                       senderKeyStore:(id<SignalSenderKeyStore>)senderKeyStore;

@end
NS_ASSUME_NONNULL_END