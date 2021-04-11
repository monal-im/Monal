//
//  MLStream.h
//  Monal
//
//  Created by Thilo Molitor on 11.04.21.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLStream : NSStream <NSStreamDelegate>

@property(readonly) NSStreamStatus streamStatus;
@property(nullable, readonly, copy) NSError* streamError;

+(void) connectWithSNIDomain:(NSString*) SNIDomain connectHost:(NSString*) host connectPort:(NSNumber*) port inputStream:(NSInputStream* _Nullable * _Nonnull) inputStream  outputStream:(NSOutputStream* _Nullable * _Nonnull) outputStream;

@end

@interface MLInputStream : MLStream

@property(readonly) BOOL hasBytesAvailable;

@end

@interface MLOutputStream : MLStream

@property(readonly) BOOL hasSpaceAvailable;

@end

NS_ASSUME_NONNULL_END
