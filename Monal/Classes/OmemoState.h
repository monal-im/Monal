//
//  OmemoState.h
//  monalxmpp
//
//  Created by Thilo Molitor on 05.11.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

#ifndef OmemoState_h
#define OmemoState_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OmemoState : NSObject <NSSecureCoding>
-(void) updateWith:(OmemoState*) state;
// *** data ***
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSMutableSet<NSNumber*>*>* openBundleFetches;
@property (nonatomic, strong) NSMutableSet<NSString*>* openDevicelistFetches;
@property (nonatomic, strong) NSMutableSet<NSString*>* openDevicelistSubscriptions;
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSMutableSet<NSNumber*>*>* queuedKeyTransportElements;
// jid -> @[deviceID1, deviceID2]
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSMutableSet<NSNumber*>*>* queuedSessionRepairs;

// *** flags ***
@property (atomic, assign) BOOL hasSeenDeviceList;
@property (atomic, assign) BOOL catchupDone;
@end

NS_ASSUME_NONNULL_END

#endif /* OmemoState_h */
