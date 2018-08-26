//
//  SignalPreKeyMessage.h
//  Pods
//
//  Created by Chris Ballinger on 6/30/16.
//
//

#import <Foundation/Foundation.h>
#import "SignalContext.h"

NS_ASSUME_NONNULL_BEGIN
@interface SignalPreKeyMessage : NSObject

- (nullable instancetype) initWithData:(NSData*)data
                               context:(SignalContext*)context
                                 error:(NSError**)error;

@end
NS_ASSUME_NONNULL_END