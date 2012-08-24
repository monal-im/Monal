/*
 CHDataStructures.framework -- CHMultiDictionary.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHMultiDictionary.h"

/**
 Utility function for creating a new NSMutableSet containing object; if object is a set or array, the set containts all objects in the collection.
 */
static inline NSMutableSet* createMutableSetFromObject(id object) {
	if (object == nil)
		return nil;
	if ([object isKindOfClass:[NSSet class]])
		return [NSMutableSet setWithSet:object];
	if ([object isKindOfClass:[NSArray class]])
		return [NSMutableSet setWithArray:object];
	else
		return [NSMutableSet setWithObject:object];
}

#pragma mark -

@implementation CHMultiDictionary

- (id) initWithObjects:(NSArray*)objectsArray forKeys:(NSArray*)keyArray {
	if ([keyArray count] != [objectsArray count])
		CHInvalidArgumentException([self class], _cmd, @"Unequal array counts.");
	if (self = [super initWithCapacity:[objectsArray count]]) {
		NSEnumerator *objects = [objectsArray objectEnumerator];
		for (id key in keyArray) {
			[self setObject:[objects nextObject] forKey:key];
		}
	}
	return self;
}

#pragma mark Querying Contents

- (NSUInteger) countForAllKeys {
	return objectCount;
}

- (NSUInteger) countForKey:(id)aKey {
	return [[self objectForKey:aKey] count];
}

- (NSSet*) objectsForKey:(id)aKey {
	return [[[(id)dictionary objectForKey:aKey] copy] autorelease];
}

#pragma mark Modifying Contents

- (void) addObject:(id)anObject forKey:(id)aKey {
	NSMutableSet *objects = [self objectForKey:aKey];
	if (objects == nil)
		[super setObject:(objects = [NSMutableSet set]) forKey:aKey];
	else
		objectCount -= [objects count];
	[objects addObject:anObject];
	objectCount += [objects count];
}

- (void) addObjects:(NSSet*)objectSet forKey:(id)aKey {
	NSMutableSet *objects = [self objectForKey:aKey];
	if (objects == nil)
		[super setObject:(objects = [NSMutableSet set]) forKey:aKey];
	else
		objectCount -= [objects count];
	[objects unionSet:objectSet];
	objectCount += [objects count];
}

- (void) removeAllObjects {
	[super removeAllObjects];
	objectCount = 0;
}

- (void) removeObject:(id)anObject forKey:(id)aKey {
	NSMutableSet *objects = [self objectForKey:aKey];
	if ([objects containsObject:anObject]) {
		[objects removeObject:anObject];
		--objectCount;
		if ([objects count] == 0)
			[self removeObjectForKey:aKey];
	}
}

- (void) removeObjectsForKey:(id)aKey {
	objectCount -= [[self objectForKey:aKey] count];
	[self removeObjectForKey:aKey];
}

- (void) setObject:(id)anObject forKey:(id)aKey {
	NSSet *objectSet = createMutableSetFromObject(anObject);
	if (aKey != nil)
		objectCount += ([objectSet count] - [[self objectForKey:aKey] count]);
	[super setObject:objectSet forKey:aKey];
}

- (void) setObjects:(NSSet*)objectSet forKey:(id)aKey {
	[self setObject:objectSet forKey:aKey];
}

@end
