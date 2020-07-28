//
//  MLProcessLock.h
//  monalxmpp
//
//  Created by Thilo Molitor on 26.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface MLProcessLock : NSObject

+(BOOL) checkRemoteRunning:(NSString*) processName;
+(BOOL) waitForRemoteStartup:(NSString*) processName;
+(BOOL) waitForRemoteTermination:(NSString*) processName;
-(id) initWithProcessName:(NSString*) processName;

@end

NS_ASSUME_NONNULL_END
