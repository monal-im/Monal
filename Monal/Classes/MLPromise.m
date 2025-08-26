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

@interface MLPromise()

-(void) resolve:(id _Nullable) argument;

@property(nonatomic, strong) AnyPromise* anyPromise;
@property(nonatomic, strong) id resolvedArgument;
@property(nonatomic, assign) BOOL isResolved;

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
    self.isResolved = false;

    [self serialize];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deserialize) name:kMonalUnfrozen object:nil];

    DDLogVerbose(@"Initialized promise %@", self);

    return self;
}

-(nullable instancetype) initWithCoder:(NSCoder*) coder
{
    self.uuid = [coder decodeObjectForKey:@"uuid"];
    self.resolvedArgument = [coder decodeObjectForKey:@"resolvedArgument"];
    self.isResolved = [coder decodeBoolForKey:@"isResolved"];
    DDLogVerbose(@"Initialised from coder a promise %@", self);
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    DDLogVerbose(@"Deallocated promise %@", self);
}

-(void) serialize
{
    [[DataLayer sharedInstance] addPromise:self];
    DDLogVerbose(@"Serialized promise %@", self);
}

-(void) deserialize
{
    MLPromise* dbPromise = [[DataLayer sharedInstance] getPromise:self];
    self.resolvedArgument = dbPromise.resolvedArgument;
    self.isResolved = dbPromise.isResolved;
    DDLogVerbose(@"Deserialized promise %@", self);

    [self attemptConsume];
}

// A stale promise is a promise that is still in the DB, but doesn't have an entry in the resolvers map.
// It is "stale" because it is not possible to consume it - we've lost the linkage from MLPromise to AnyPromise that _resolvers provides.
// When we start the app, the resolvers map is empty; therefore, all promises still in the DB are stale.
+(void) removeStalePromises
{
    MLAssert([_resolvers count] == 0, @"Resolvers map should be empty, but it was not. This function should only be called on app start-up");
    [[DataLayer sharedInstance] removeAllPromises];
}

-(void) resolve:(id _Nullable) argument
{
    DDLogDebug(@"Resolving promise %@ and argument %@", self, argument);
    NSAssert(!self.isResolved, @"Trying to resolve an already resolved promise");

    self.resolvedArgument = argument;
    self.isResolved = true;
    [self serialize];
    [self attemptConsume];
}

-(void) fulfill:(id _Nullable) argument
{
    [self resolve:argument];
}

-(void) reject:(NSError*) error
{
    [self resolve:error];
}

-(AnyPromise*) toAnyPromise
{
    DDLogDebug(@"Converting promise %@ to AnyPromise", self);

    if(self.anyPromise != nil)
    {
        DDLogVerbose(@"Returning already existing AnyPromise");
        return self.anyPromise;
    }

    self.anyPromise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        DDLogVerbose(@"Adding resolver %@ with uuid %@ to resolvers map", resolve, self.uuid);
        [_resolvers setObject:resolve forKey:self.uuid];
        DDLogVerbose(@"Resolvers map is now: %@", _resolvers);
    }];

    return self.anyPromise;
}

-(void) attemptConsume
{
    DDLogDebug(@"Intend to consume promise %@ and argument %@", self, self.resolvedArgument);

    if([HelperTools isAppExtension])
    {
        DDLogDebug(@"Not consuming promise %@ as we are in the app extension", self);
        return;
    }

    if(!self.isResolved)
    {
        DDLogDebug(@"Not consuming promise %@ as it has not been resolved yet", self);
        return;
    }

    PMKResolver resolve = _resolvers[self.uuid];

    if(resolve == nil)
    {
        DDLogDebug(@"Tried to consume promise %@ when there is no resolver available", self);
        return;
    }

    DDLogDebug(@"Resolving promise %@ and argument %@", self, self.resolvedArgument);
    resolve(self.resolvedArgument);

    DDLogVerbose(@"Removing resolver with uuid %@ from resolvers map", self.uuid);
    [_resolvers removeObjectForKey:self.uuid];
    DDLogVerbose(@"Resolvers map is now: %@", _resolvers);

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
    [coder encodeBool:self.isResolved forKey:@"isResolved"];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"MLPromise(uuid=%@, isResolved=%@)", self.uuid, bool2str(self.isResolved)];
}

@end

NS_ASSUME_NONNULL_END
