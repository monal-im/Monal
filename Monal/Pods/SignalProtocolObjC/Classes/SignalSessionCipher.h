//
//  SignalSessionCipher.h
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import <Foundation/Foundation.h>
#import "SignalAddress.h"
#import "SignalContext.h"
#import "SignalCiphertext.h"

NS_ASSUME_NONNULL_BEGIN
@interface SignalSessionCipher : NSObject

@property (nonatomic, strong, readonly) SignalAddress *address;
@property (nonatomic, strong, readonly) SignalContext *context;

- (instancetype) initWithAddress:(SignalAddress*)address
                         context:(SignalContext*)context;

- (nullable SignalCiphertext*)encryptData:(NSData*)data error:(NSError**)error;
- (nullable NSData*)decryptCiphertext:(SignalCiphertext*)ciphertext error:(NSError**)error;

@end
NS_ASSUME_NONNULL_END