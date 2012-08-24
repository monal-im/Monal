/*
 CHDataStructures.framework -- CHBidirectionalDictionary.m
 
 Copyright (c) 2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHBidirectionalDictionary.h"

@implementation CHBidirectionalDictionary

// This macro is used as an alias for the 'dictionary' ivar in the parent class.
#define keysToObjects dictionary

- (void) dealloc {
	if (inverse != nil)
		inverse->inverse = nil; // Unlink from inverse dictionary if one exists.
	CFRelease(objectsToKeys); // The dictionary can never be null at this point.
	[super dealloc];
}

- (id) initWithCapacity:(NSUInteger)numItems {
	if ((self = [super initWithCapacity:numItems]) == nil) return nil;
	createCollectableCFMutableDictionary(&objectsToKeys, numItems);
	return self;
}

#pragma mark Querying Contents

/** @todo Determine the proper ownership/lifetime of the inverse dictionary. */
- (CHBidirectionalDictionary*) inverseDictionary {
	if (inverse == nil) {
		// Create a new instance of this class to represent the inverse mapping
		inverse = [[CHBidirectionalDictionary alloc] init];
		// Release the CFMutableDictionary -init creates so we don't leak memory
		if (kCHGarbageCollectionNotEnabled)
			CFRelease(inverse->dictionary);
		// Set its dictionary references to the reverse of what they are here
		// (NOTE: CFMakeCollectable() works under GC, and is a no-op otherwise.)
		CFMakeCollectable(CFRetain(inverse->keysToObjects = objectsToKeys));
		CFMakeCollectable(CFRetain(inverse->objectsToKeys = keysToObjects));
		// Set this instance as the mutual inverse of the newly-created instance 
		inverse->inverse = self;
	}
	return inverse;
}

- (id) keyForObject:(id)anObject {
	return (id)CFDictionaryGetValue(objectsToKeys, anObject);
}

- (NSEnumerator*) objectEnumerator {
	return [(id)objectsToKeys keyEnumerator];
}

#pragma mark Modifying Contents

- (void) addEntriesFromDictionary:(NSDictionary*)otherDictionary {
	[super addEntriesFromDictionary:otherDictionary];
}

- (void) removeAllObjects {
	[super removeAllObjects];
	CFDictionaryRemoveAllValues(objectsToKeys);
}

- (void) removeKeyForObject:(id)anObject {
	[super removeObjectForKey:[self keyForObject:anObject]];
	CFDictionaryRemoveValue(objectsToKeys, anObject);
}

- (void) removeObjectForKey:(id)aKey {
	CFDictionaryRemoveValue(objectsToKeys, [self objectForKey:aKey]);
	[super removeObjectForKey:aKey];
}

- (void) setObject:(id)anObject forKey:(id)aKey {
	if (anObject == nil || aKey == nil)
		CHNilArgumentException([self class], _cmd);
	// Remove existing mappings for aKey and anObject if they currently exist.
	CFDictionaryRemoveValue(keysToObjects, CFDictionaryGetValue(objectsToKeys, anObject));
	CFDictionaryRemoveValue(objectsToKeys, CFDictionaryGetValue(keysToObjects, aKey));
	aKey = [[aKey copy] autorelease];
	anObject = [[anObject copy] autorelease];
	CFDictionarySetValue(keysToObjects, aKey, anObject); // May replace key-value pair
	CFDictionarySetValue(objectsToKeys, anObject, aKey); // May replace value-key pair
}

@end
