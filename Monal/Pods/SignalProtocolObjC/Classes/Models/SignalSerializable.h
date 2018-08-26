//
//  SignalSerializable.h
//  Pods
//
//  Created by Chris Ballinger on 6/29/16.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol SignalSerializable <NSObject>
@required

/** Serialized data, or nil if there was an error */
- (nullable NSData*)serializedData;
/** Deserialized object, or nil if there is an error */
- (nullable instancetype) initWithSerializedData:(NSData*)serializedData error:(NSError **)error;

@end
NS_ASSUME_NONNULL_END