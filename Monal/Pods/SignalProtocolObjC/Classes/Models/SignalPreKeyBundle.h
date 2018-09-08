//
//  SignalPreKeyBundle.h
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SignalPreKeyBundle : NSObject

@property (nonatomic, readonly) uint32_t registrationId;
@property (nonatomic, readonly) uint32_t deviceId;
@property (nonatomic, readonly) uint32_t preKeyId;
@property (nonatomic, strong, readonly) NSData *preKeyPublic;
@property (nonatomic, readonly) uint32_t signedPreKeyId;
@property (nonatomic ,strong, readonly) NSData *signedPreKeyPublic;
@property (nonatomic ,strong, readonly) NSData *signature;
@property (nonatomic ,strong, readonly) NSData *identityKey;

- (instancetype) initWithRegistrationId:(uint32_t)registrationId
                               deviceId:(uint32_t)deviceId
                               preKeyId:(uint32_t)preKeyId
                           preKeyPublic:(NSData*)preKeyPublic
                         signedPreKeyId:(uint32_t)signedPreKeyId
                     signedPreKeyPublic:(NSData*)signedPreKeyPublic
                              signature:(NSData*)signature
                            identityKey:(NSData*)identityKey;

@end
NS_ASSUME_NONNULL_END
