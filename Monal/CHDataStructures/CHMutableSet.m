/*
 CHDataStructures.framework -- CHMutableSet.m
 
 Copyright (c) 2009-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHMutableSet.h"

const void* CHMutableSetRetain(CFAllocatorRef allocator, const void *value) {
	return [(id)value retain];
}

void CHMutableSetRelease(CFAllocatorRef allocator, const void *value) {
	[(id)value release];
}

CFStringRef CHMutableSetCopyDescription(const void *value) {
	return CFRetain([(id)value description]);
}

Boolean CHMutableSetEqual(const void *value1, const void *value2) {
	return [(id)value1 isEqual:(id)value2];
}

CFHashCode CHMutableSetHash(const void *value) {
	return (CFHashCode)[(id)value hash];
}

static const CFSetCallBacks kCHMutableSetCallbacks = {
	0, // default version
	CHMutableSetRetain,
	CHMutableSetRelease,
	CHMutableSetCopyDescription,
	CHMutableSetEqual,
	CHMutableSetHash
};

#pragma mark -

@implementation CHMutableSet

- (void) dealloc {
	CFRelease(set); // The set will never be null at this point.
	[super dealloc];
}

// Note: Defined here since -init is not implemented in NS(Mutable)Set.
- (id) init {
	return [self initWithCapacity:0]; // The 0 means we provide no capacity hint
}

// Note: This is the designated initializer for NSMutableSet and this class.
// Subclasses may override this as necessary, but must call back here first.
- (id) initWithCapacity:(NSUInteger)numItems {
	if ((self = [super init]) == nil) return nil;
	set = CFSetCreateMutable(kCFAllocatorDefault,
	                         numItems,
	                         &kCHMutableSetCallbacks);
	CFMakeCollectable(set); // Works under GC, and is a no-op otherwise.
	return self;
}

- (id) initWithCoder:(NSCoder*)decoder {
	return [self initWithArray:[decoder decodeObjectForKey:@"objects"]];
}

- (void) encodeWithCoder:(NSCoder*)encoder {
	[encoder encodeObject:[self allObjects] forKey:@"objects"];
}

// Overridden from NSMutableSet to encode/decode as the proper class.
- (Class) classForKeyedArchiver {
	return [self class];
}

#pragma mark Querying Contents

- (id) anyObject {
	return [(id)set anyObject];
}

- (BOOL) containsObject:(id)anObject {
	return CFSetContainsValue(set, anObject);
}

- (NSUInteger) count {
	return CFSetGetCount(set);
}

- (NSString*) debugDescription {
	CFStringRef description = CFCopyDescription(set);
	CFRelease([(id)description retain]);
	return [(id)description autorelease];
}

- (NSString*) description {
	return [[self allObjects] description];
}

- (id) member:(id)anObject {
	return [(id)set member:anObject];
}

- (NSEnumerator*) objectEnumerator {
	return [(id)set objectEnumerator];
}

#pragma mark Modifying Contents

- (void) addObject:(id)anObject {
	CFSetSetValue(set, anObject);
}

- (void) removeAllObjects {
	CFSetRemoveAllValues(set);
}

- (void) removeObject:(id)anObject {
	CFSetRemoveValue(set, anObject);
}

#pragma mark <NSCopying>

- (id) copyWithZone:(NSZone*)zone {
	CHMutableSet *copy = [[[self class] allocWithZone:zone] init];
	[copy addObjectsFromArray:[self allObjects]];
	return copy;
}

@end
