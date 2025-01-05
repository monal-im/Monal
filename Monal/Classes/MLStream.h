//
//  MLStream.h
//  Monal
//
//  Created by Thilo Molitor on 11.04.21.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLStream : NSStream <NSStreamDelegate>

@property(readonly) NSStreamStatus streamStatus;
@property(nullable, readonly, copy) NSError* streamError;


+(void) connectWithSNIDomain:(NSString*) SNIDomain connectHost:(NSString*) host connectPort:(NSNumber*) port tls:(BOOL) tls inputStream:(NSInputStream* _Nullable * _Nonnull) inputStream  outputStream:(NSOutputStream* _Nullable * _Nonnull) outputStream logtag:(id _Nullable) logtag;
-(void) startTLS;
@property(readonly) BOOL hasTLS;
@property(readonly) BOOL isTLS13;

@property(nullable, readonly) NSArray* supportedChannelBindingTypes;
-(NSData* _Nullable) channelBindingDataForType:(NSString* _Nullable) type;
@end

@interface MLInputStream : MLStream

@property(readonly) BOOL hasBytesAvailable;

@end

@interface MLOutputStream : MLStream

@property(readonly) BOOL hasSpaceAvailable;

@end

NS_ASSUME_NONNULL_END
