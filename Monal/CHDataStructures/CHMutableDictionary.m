/*
 CHDataStructures.framework -- CHMutableDictionary.m
 
 Copyright (c) 2009-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHMutableDictionary.h"

#pragma mark CFDictionary callbacks

const void* CHDictionaryRetain(CFAllocatorRef allocator, const void *value) {
	return [(id)value retain];
}

void CHDictionaryRelease(CFAllocatorRef allocator, const void *value) {
	[(id)value release];
}

CFStringRef CHDictionaryDescription(const void *value) {
	return CFRetain([(id)value description]);
}

Boolean CHDictionaryEqual(const void *value1, const void *value2) {
	return [(id)value1 isEqual:(id)value2];
}

CFHashCode CHDictionaryHash(const void *value) {
	return (CFHashCode)[(id)value hash];
}

static const CFDictionaryKeyCallBacks kCHDictionaryKeyCallBacks = {
	0, // default version
	CHDictionaryRetain,
	CHDictionaryRelease,
	CHDictionaryDescription,
	CHDictionaryEqual,
	CHDictionaryHash
};

static const CFDictionaryValueCallBacks kCHDictionaryValueCallBacks = {
	0, // default version
	CHDictionaryRetain,
	CHDictionaryRelease,
	CHDictionaryDescription,
	CHDictionaryEqual
};

void createCollectableCFMutableDictionary(__strong CFMutableDictionaryRef* dictionary, NSUInteger initialCapacity) {
	// Create a CFMutableDictionaryRef with callback functions as defined above.
	*dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault,
	                                       initialCapacity,
	                                       &kCHDictionaryKeyCallBacks,
	                                       &kCHDictionaryValueCallBacks);
	// Hand the reference off to GC if it's enabled, perform a no-op otherwise.
	CFMakeCollectable(*dictionary);
}

#pragma mark -

@implementation CHMutableDictionary

- (void) dealloc {
	CFRelease(dictionary); // The dictionary will never be null at this point.
	[super dealloc];
}

// Note: Defined here since -init is not implemented in NS(Mutable)Dictionary.
- (id) init {
	return [self initWithCapacity:0]; // The 0 means we provide no capacity hint
}

// Note: This is the designated initializer for NSMutableDictionary and this class.
// Subclasses may override this as necessary, but must call back here first.
- (id) initWithCapacity:(NSUInteger)numItems {
	if ((self = [super init]) == nil) return nil;
	createCollectableCFMutableDictionary(&dictionary, numItems);
	return self;
}

#pragma mark <NSCoding>

// Overridden from NSMutableDictionary to encode/decode as the proper class.
- (Class) classForKeyedArchiver {
	return [self class];
}

- (id) initWithCoder:(NSCoder*)decoder {
	return [self initWithDictionary:[decoder decodeObjectForKey:@"dictionary"]];
}

- (void) encodeWithCoder:(NSCoder*)encoder {
	[encoder encodeObject:(NSDictionary*)dictionary forKey:@"dictionary"];
}

#pragma mark <NSCopying>

- (id) copyWithZone:(NSZone*) zone {
	// We could use -initWithDictionary: here, but it would just use more memory.
	// (It marshals key-value pairs into two id* arrays, then inits from those.)
	CHMutableDictionary *copy = [[[self class] allocWithZone:zone] init];
	[copy addEntriesFromDictionary:self];
	return copy;
}

#pragma mark <NSFastEnumeration>

- (NSUInteger) countByEnumeratingWithState:(NSFastEnumerationState*)state
                                   objects:(id*)stackbuf
                                     count:(NSUInteger)len
{
	return [super countByEnumeratingWithState:state objects:stackbuf count:len];
}

#pragma mark Querying Contents

- (NSUInteger) count {
	return CFDictionaryGetCount(dictionary);
}

- (NSString*) debugDescription {
	CFStringRef description = CFCopyDescription(dictionary);
	CFRelease([(id)description retain]);
	return [(id)description autorelease];
}

- (NSEnumerator*) keyEnumerator {
	return [(id)dictionary keyEnumerator];
}

- (NSEnumerator*) objectEnumerator {
	return [(id)dictionary objectEnumerator];
}

- (id) objectForKey:(id)aKey {
	return (id)CFDictionaryGetValue(dictionary, aKey);
}

#pragma mark Modifying Contents

- (void) removeAllObjects {
	CFDictionaryRemoveAllValues(dictionary);
}

- (void) removeObjectForKey:(id)aKey {
	CFDictionaryRemoveValue(dictionary, aKey);
}

- (void) setObject:(id)anObject forKey:(id)aKey {
	if (anObject == nil || aKey == nil)
		CHNilArgumentException([self class], _cmd);
	CFDictionarySetValue(dictionary, [[aKey copy] autorelease], anObject);
}

@end
