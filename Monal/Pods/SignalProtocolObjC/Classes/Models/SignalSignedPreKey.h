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

@interface SignalSignedPreKey : NSObject <SignalSerializable, NSSecureCoding>

- (uint32_t) preKeyId;
- (NSDate*) timestamp;
- (NSData*) signature;
- (SignalKeyPair*)keyPair;

@end
