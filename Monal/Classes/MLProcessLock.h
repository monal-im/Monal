//
//  MLProcessLock.h
//  monalxmpp
//
//  Created by Thilo Molitor on 26.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <monalxmpp/MLConstants.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLProcessLock : NSObject

+(void) initializeForProcess:(NSString*) processName;
+(BOOL) checkRemoteRunning:(NSString*) processName;
+(void) waitForRemoteTermination:(NSString*) processName;
+(void) waitForRemoteTermination:(NSString*) processName withLoopHandler:(monal_void_block_t _Nullable) handler;
+(void) lock;
+(void) unlock;

@end

NS_ASSUME_NONNULL_END
