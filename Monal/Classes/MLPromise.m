//
//  MLPromise.m
//  monalxmpp
//
//  Created by Matthew Fennell on 29/09/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLPromise.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PromiseResolutionState) {
    PromiseResolutionStateUnresolved,
    PromiseResolutionStateFulfilled,
    PromiseResolutionStateRejected,
};

@interface MLPromiseRejection()

@property(nonatomic, strong) NSString* errorDescription;
@property(nonatomic, strong) XMPPStanza* node;
@property(nonatomic, strong) NSNumber* accountID;

-(instancetype) initWithErrorDescription:(NSString*) description andNode:(XMPPStanza*) node forAccountWithID:(NSNumber*) accountID;

@end

@implementation MLPromiseRejection

-(instancetype) initWithErrorDescription:(NSString*) errorDescription andNode:(XMPPStanza*) node forAccountWithID:(NSNumber*) accountID
{
    self = [self init];
    self.errorDescription = errorDescription;
    self.node = node;
    self.accountID = accountID;
    return self;
}

-(nullable instancetype) initWithCoder:(NSCoder*) coder
{
    self.errorDescription = [coder decodeObjectForKey:@"errorDescription"];
    self.node = [coder decodeObjectForKey:@"node"];
    self.accountID = [coder decodeObjectForKey:@"accountID"];
    return self;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.errorDescription forKey:@"errorDescription"];
    [coder encodeObject:self.node forKey:@"node"];
    [coder encodeObject:self.accountID forKey:@"accountID"];
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

@end

@interface MLPromise()

@property(nonatomic, strong) AnyPromise* anyPromise;
@property(nonatomic, strong) id resolvedArgument;
@property(nonatomic, strong) MLPromiseRejection* rejection;
@property(nonatomic) PromiseResolutionState state;
@property(nonatomic) BOOL isStale;

@end

@implementation MLPromise

static NSMutableDictionary* _resolvers;

+(void) initialize
{
    _resolvers = [NSMutableDictionary new];
}

-(instancetype) init
{
    self.uuid = [NSUUID UUID];
    self.state = PromiseResolutionStateUnresolved;
    self.isStale = NO;

    [self serialize];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deserialize) name:kMonalUnfrozen object:nil];

    DDLogVerbose(@"Initialized promise %@ with uuid %@", self, self.uuid);

    return self;
}

-(nullable instancetype) initWithCoder:(NSCoder*) coder
{
    self.uuid = [coder decodeObjectForKey:@"uuid"];
    self.resolvedArgument = [coder decodeObjectForKey:@"resolvedArgument"];
    self.rejection = [coder decodeObjectForKey:@"rejection"];
    self.state = [coder decodeIntegerForKey:@"state"];
    self.isStale = [coder decodeBoolForKey:@"isStale"];
    DDLogVerbose(@"Initialised from coder a promise %@ with uuid %@", self, self.uuid);
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    DDLogVerbose(@"Deallocated promise %@ with uuid %@", self, self.uuid);
}

-(void) serialize
{
    [[DataLayer sharedInstance] addPromise:self];
    DDLogVerbose(@"Serialized promise %@ with uuid %@", self, self.uuid);
}

-(void) deserialize
{
    MLPromise* dbPromise = [[DataLayer sharedInstance] getPromise:self];
    self.resolvedArgument = dbPromise.resolvedArgument;
    self.state = dbPromise.state;
    DDLogVerbose(@"Deserialized promise %@ with uuid %@", self, self.uuid);

    [self attemptConsume];
}

// A stale promise is a promise that is still in the DB, but doesn't have an entry in the resolvers map.
// It is "stale" because it is not possible to consume it - we've lost the linkage from MLPromise to AnyPromise that _resolvers provides.
// When we start the app, the resolvers map is empty; therefore, all promises still in the DB are stale.
+(void) consumeStalePromises
{
    MLAssert([_resolvers count] == 0, @"Resolvers map should be empty, but it was not. This function should only be called on app start-up");
    NSMutableSet<MLPromise*>* stalePromises = [[[DataLayer sharedInstance] getAllPromises] mutableCopy];
    [stalePromises setValue:@YES forKey:@"isStale"];
    [stalePromises makeObjectsPerformSelector:@selector(attemptConsume)];
}

-(void) resolveWithArgument:(id _Nullable) argument andState:(PromiseResolutionState) state
{
    DDLogDebug(@"Resolving promise %@ with uuid %@ and argument %@", self, self.uuid, argument);
    NSAssert(self.state == PromiseResolutionStateUnresolved, @"Trying to resolve an already resolved promise");
    NSAssert(self.resolvedArgument == nil, @"Promise is unresolved, therefore resolvedArgument should be nil");

    self.resolvedArgument = argument;
    self.state = state;
    [self serialize];
    [self attemptConsume];
}

-(void) fulfill:(id _Nullable) argument
{
    [self resolveWithArgument:argument andState:PromiseResolutionStateFulfilled];
}

-(void) rejectWithError:(NSError*) error andNode:(XMPPStanza* _Nullable) node forAccountWithID:(NSNumber*) accountID
{
    self.rejection = [[MLPromiseRejection alloc] initWithErrorDescription:error.description andNode:node forAccountWithID:accountID];
    [self resolveWithArgument:error andState:PromiseResolutionStateRejected];
}

-(AnyPromise*) toAnyPromise
{
    DDLogDebug(@"Converting promise %@ with uuid %@ to AnyPromise", self, self.uuid);

    if(self.anyPromise != nil)
    {
        DDLogVerbose(@"Returning already existing AnyPromise");
        return self.anyPromise;
    }

    self.anyPromise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        [_resolvers setObject:resolve forKey:self.uuid];
        DDLogVerbose(@"Adding resolver %@ with uuid %@ to resolvers map", resolve, self.uuid);
        DDLogVerbose(@"Resolvers map is now: %@", _resolvers);
    }];

    return self.anyPromise;
}

-(void) attemptConsume
{
    DDLogDebug(@"Intend to consume promise %@ with uuid %@ and argument %@", self, self.uuid, self.resolvedArgument);

    if([HelperTools isAppExtension])
    {
        DDLogDebug(@"Not consuming promise %@ with uuid %@ as we are in the app extension", self, self.uuid);
        return;
    }

    if(self.state == PromiseResolutionStateUnresolved)
    {
        DDLogDebug(@"Not consuming promise %@ with uuid %@ as it has not been resolved yet", self, self.uuid);
        return;
    }

    PMKResolver resolve = _resolvers[self.uuid];

    if(resolve == nil && !self.isStale)
    {
        DDLogDebug(@"Tried to consume promise %@ with uuid %@ when there is no resolver available", self, self.uuid);
        return;
    }

    if(!self.isStale)
    {
        DDLogDebug(@"Resolving promise %@ with uuid %@ and argument %@", self, self.uuid, self.resolvedArgument);
        resolve(self.resolvedArgument);

        [_resolvers removeObjectForKey:self.uuid];
        DDLogVerbose(@"Removed resolver with uuid %@ from resolvers map", self.uuid);
        DDLogVerbose(@"Resolvers map is now: %@", _resolvers);
    }

    [[DataLayer sharedInstance] removePromise:self];
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.uuid forKey:@"uuid"];
    [coder encodeObject:self.resolvedArgument forKey:@"resolvedArgument"];
    [coder encodeObject:self.rejection forKey:@"rejection"];
    [coder encodeInteger:self.state forKey:@"state"];
    [coder encodeBool:self.isStale forKey:@"isStale"];
}

@end

NS_ASSUME_NONNULL_END
