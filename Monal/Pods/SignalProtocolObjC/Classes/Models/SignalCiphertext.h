//
//  SignalCiphertext.h
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SignalCiphertextType) {
    SignalCiphertextTypeUnknown,
    SignalCiphertextTypeMessage,
    SignalCiphertextTypePreKeyMessage
};

NS_ASSUME_NONNULL_BEGIN
@interface SignalCiphertext : NSObject

@property (nonatomic, readonly) SignalCiphertextType type;
@property (nonatomic, strong, readonly) NSData *data;

- (instancetype) initWithData:(NSData*)data
                         type:(SignalCiphertextType)type;

@end
NS_ASSUME_NONNULL_END