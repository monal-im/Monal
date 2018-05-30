//
//  SignalContext.h
//  SignalProtocol-ObjC
//
//  Created by Chris Ballinger on 6/26/16.
//
//

@import Foundation;
#import "SignalStorage.h"

NS_ASSUME_NONNULL_BEGIN
@interface SignalContext : NSObject

@property (nonatomic, strong, readonly) SignalStorage *storage;

- (nullable instancetype) initWithStorage:(SignalStorage*)storage;

@end
NS_ASSUME_NONNULL_END