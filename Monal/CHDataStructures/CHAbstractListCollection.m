/*
 CHDataStructures.framework -- CHAbstractListCollection.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHAbstractListCollection.h"

@implementation CHAbstractListCollection

- (void) dealloc {
	[list release];
	[super dealloc];
}

// Child classes must implement -init to initialize the "list" instance variable

- (id) initWithArray:(NSArray*)anArray {
	if ([self init] == nil) return nil;
	for (id anObject in anArray) {
		[list addObject:anObject];
	}
	return self;
}

#pragma mark <NSCoding>

- (id) initWithCoder:(NSCoder*)decoder {
	if ((self = [super init]) == nil) return nil;
	list = [[decoder decodeObjectForKey:@"list"] retain];
	return self;
}

- (void) encodeWithCoder:(NSCoder*)encoder {
	[encoder encodeObject:list forKey:@"list"];
}

#pragma mark <NSCopying>

- (id) copyWithZone:(NSZone*)zone {
	id copy = [[[self class] allocWithZone:zone] init];
	for (id anObject in self) {
		[copy addObject:anObject];
	}
	return copy;
}

#pragma mark <NSFastEnumeration>

- (NSUInteger) countByEnumeratingWithState:(NSFastEnumerationState*)state
                                   objects:(id*)stackbuf
                                     count:(NSUInteger)len
{
	return [list countByEnumeratingWithState:state objects:stackbuf count:len];
}

#pragma mark -

- (NSUInteger) count {
	return [list count];
}

- (BOOL) containsObject:(id)anObject {
	return [list containsObject:anObject];
}

- (BOOL) containsObjectIdenticalTo:(id)anObject {
	return [list containsObjectIdenticalTo:anObject];
}

- (void) exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2 {
	[list exchangeObjectAtIndex:idx1 withObjectAtIndex:idx2];
}

- (NSUInteger) hash {
	return hashOfCountAndObjects([list count], [list firstObject], [list lastObject]);
}

- (NSUInteger) indexOfObject:(id)anObject {
	return [list indexOfObject:anObject];
}

- (NSUInteger) indexOfObjectIdenticalTo:(id)anObject {
	return [list indexOfObjectIdenticalTo:anObject];
}

- (id) objectAtIndex:(NSUInteger)index {
	return [list objectAtIndex:index];
}

- (NSArray*) objectsAtIndexes:(NSIndexSet*)indexes {
	return [list objectsAtIndexes:indexes];
}

- (void) removeObject:(id)anObject {
	[list removeObject:anObject];
}

- (void) removeObjectIdenticalTo:(id)anObject {
	[list removeObjectIdenticalTo:anObject];
}

- (void) removeObjectAtIndex:(NSUInteger)index {
	[list removeObjectAtIndex:index];
}

- (void) removeObjectsAtIndexes:(NSIndexSet*)indexes {
	[list removeObjectsAtIndexes:indexes];
}

- (void) removeAllObjects {
	[list removeAllObjects];
}

- (void) replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
	[list replaceObjectAtIndex:index withObject:anObject];
}

- (NSArray*) allObjects {
	return [list allObjects];
}

- (NSEnumerator*) objectEnumerator {
	return [list objectEnumerator];
}

- (NSString*) description {
	return [list description];
}

@end
