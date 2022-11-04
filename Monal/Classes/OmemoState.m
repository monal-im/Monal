//
//  OmemoState.m
//  monalxmpp
//
//  Created by admin on 05.11.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OmemoState.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OmemoState

-(instancetype) init
{
    self = [super self];
    self.queuedKeyTransportElements = [NSMutableDictionary new];
    self.openBundleFetches = [NSMutableDictionary new];
    self.openDevicelistFetches = [NSMutableSet new];
    self.openDevicelistSubscriptions = [NSMutableSet new];
    self.queuedSessionRepairs = [NSMutableDictionary new];
    self.catchupDone = NO;
    self.hasSeenDeviceList = NO;
    return self;
}

-(void) updateWith:(OmemoState*) state
{
    self.queuedKeyTransportElements = state.queuedKeyTransportElements;
    self.openBundleFetches = state.openBundleFetches;
    self.openDevicelistFetches = state.openDevicelistFetches;
    self.openDevicelistSubscriptions = state.openDevicelistSubscriptions;
    self.queuedSessionRepairs = state.queuedSessionRepairs;
    self.catchupDone = state.catchupDone;
    self.hasSeenDeviceList = state.hasSeenDeviceList;
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.openBundleFetches forKey:@"openBundleFetches"];
    [coder encodeObject:self.openDevicelistFetches forKey:@"openDevicelistFetches"];
    [coder encodeObject:self.openDevicelistSubscriptions forKey:@"openDevicelistSubscriptions"];
    [coder encodeObject:self.queuedKeyTransportElements forKey:@"queuedKeyTransportElements"];
    [coder encodeObject:self.queuedSessionRepairs forKey:@"queuedSessionRepairs"];
    [coder encodeBool:self.hasSeenDeviceList forKey:@"hasSeenDeviceList"];
    [coder encodeBool:self.catchupDone forKey:@"catchupDone"];
}

-(instancetype _Nullable) initWithCoder:(NSCoder*) coder
{
    self = [self init];
    self.openBundleFetches = [coder decodeObjectForKey:@"openBundleFetches"];
    self.openDevicelistFetches = [coder decodeObjectForKey:@"openDevicelistFetches"];
    self.openDevicelistSubscriptions = [coder decodeObjectForKey:@"openDevicelistSubscriptions"];
    self.queuedKeyTransportElements = [coder decodeObjectForKey:@"queuedKeyTransportElements"];
    self.queuedSessionRepairs = [coder decodeObjectForKey:@"queuedSessionRepairs"];
    self.hasSeenDeviceList = [coder decodeBoolForKey:@"hasSeenDeviceList"];
    self.catchupDone = [coder decodeBoolForKey:@"catchupDone"];
    return self;
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"OmemoState(\n\topenBundleFetches=%@\n\topenDevicelistFetches=%@\n\topenDevicelistSubscriptions=%@\n\tqueuedKeyTransportElements=%@\n\tqueuedSessionRepairs=%@\n\thasSeenDeviceList=%@\n\tcatchupDone=%@\n)", self.openBundleFetches, self.openDevicelistFetches, self.openDevicelistSubscriptions, self.queuedKeyTransportElements, self.queuedSessionRepairs, self.hasSeenDeviceList ? @"YES" : @"NO", self.catchupDone ? @"YES" : @"NO"];
}

@end

NS_ASSUME_NONNULL_END
