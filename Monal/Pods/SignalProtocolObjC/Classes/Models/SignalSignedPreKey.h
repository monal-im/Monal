//
//  SignalSignedPreKey.h
//  Pods
//
//  Created by Chris Ballinger on 6/29/16.
//
//

#import <Foundation/Foundation.h>
#import "SignalSerializable.h"
#import "SignalKeyPair.h"

NS_ASSUME_NONNULL_BEGIN
@interface SignalSignedPreKey : NSObject <SignalSerializable, NSSecureCoding>

@property (nonatomic, readonly) uint32_t preKeyId;
@property (nonatomic, readonly) NSDate *timestamp;
@property (nonatomic, readonly) NSData *signature;
@property (nonatomic, readonly, nullable) SignalKeyPair *keyPair;

@end
NS_ASSUME_NONNULL_END
