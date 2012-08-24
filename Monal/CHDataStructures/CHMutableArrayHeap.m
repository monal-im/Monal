/*
 CHDataStructures.framework -- CHMutableArrayHeap.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHMutableArrayHeap.h"

@implementation CHMutableArrayHeap

- (void) heapifyFromIndex:(NSUInteger)parentIndex {
	NSUInteger leftIndex, rightIndex;
	id parent, leftChild, rightChild;
	
	// Bubble the specified node down until the heap property is satisfied.
	NSUInteger count = [array count];
	while (parentIndex < count / 2) {
		leftIndex = parentIndex * 2 + 1;
		rightIndex = leftIndex + 1;
		
		parent = [array objectAtIndex:parentIndex];
		leftChild = [array objectAtIndex:leftIndex];
		rightChild = (rightIndex < count) ? [array objectAtIndex:rightIndex] : nil;
		// A binary heap is always a complete tree, so left will never be nil.
		if (rightChild == nil || [leftChild compare:rightChild] == sortOrder) {
			if ([parent compare:leftChild] != sortOrder) {
				[array exchangeObjectAtIndex:parentIndex withObjectAtIndex:leftIndex];
				parentIndex = leftIndex;
			}
			else
				break;
		}
		else {
			if ([parent compare:rightChild] != sortOrder) {
				[array exchangeObjectAtIndex:parentIndex withObjectAtIndex:rightIndex];
				parentIndex = rightIndex;
			}
			else
				break;
		}
	}
}

#pragma mark -

- (void) dealloc {
	[array release];
	[super dealloc];
}

- (id) init {
	return [self initWithOrdering:NSOrderedAscending array:nil];
}

- (id) initWithArray:(NSArray*)anArray {
	return [self initWithOrdering:NSOrderedAscending array:anArray];
}

// This is the designated initializer for NSMutableArray (must be overridden)
- (id) initWithCapacity:(NSUInteger)capacity {
	if ((self = [super init]) == nil) return nil;
	array = [[NSMutableArray alloc] initWithCapacity:capacity];
	return self;	
}

- (id) initWithOrdering:(NSComparisonResult)order {
	return [self initWithOrdering:order array:nil];
}

// This is the designated initializer for CHMutableArrayHeap
- (id) initWithOrdering:(NSComparisonResult)order array:(NSArray*)anArray {
	// Parent initializer allocates empty array; add objects after order is set.
	if ((self = [self initWithCapacity:[anArray count]]) == nil) return nil;
	if (order != NSOrderedAscending && order != NSOrderedDescending)
		CHInvalidArgumentException([self class], _cmd, @"Invalid sort order.");
	sortOrder = order;
	[self addObjectsFromArray:anArray]; // establishes heap ordering of elements
	return self;
}

#pragma mark <NSCoding>

// Overridden from NSMutableArray to encode/decode as the proper class.
- (Class) classForKeyedArchiver {
	return [self class];
}

- (id) initWithCoder:(NSCoder*)decoder {
	// Ordinarily we'd call -[super initWithCoder:], but we must set order first
	return [self initWithOrdering:([decoder decodeBoolForKey:@"sortAscending"]
	                               ? NSOrderedAscending : NSOrderedDescending)
	                        array:[decoder decodeObjectForKey:@"array"]];
}

- (void) encodeWithCoder:(NSCoder*)encoder {
	[super encodeWithCoder:encoder];
	[encoder encodeObject:array forKey:@"array"];
	[encoder encodeBool:(sortOrder == NSOrderedAscending) forKey:@"sortAscending"];
}

#pragma mark <NSCopying>

- (id) copyWithZone:(NSZone*)zone {
	return [[[self class] allocWithZone:zone] initWithOrdering:sortOrder array:array];
}

#pragma mark <NSFastEnumeration>

// This overridden method returns the heap contents in fully-sorted order.
// Just as -objectEnumerator above, the first call incurs a hidden sorting cost.
- (NSUInteger) countByEnumeratingWithState:(NSFastEnumerationState*)state
                                   objects:(id*)stackbuf
                                     count:(NSUInteger)len
{
	// Currently (in Leopard) NSEnumerators from NSArray only return 1 each time
	if (state->state == 0) {
		// Create a sorted array to use for enumeration, store it in the state.
		state->extra[4] = (unsigned long) [self allObjectsInSortedOrder];
	}
	NSArray *sorted = (NSArray*) state->extra[4];
	NSUInteger count = [sorted countByEnumeratingWithState:state
	                                               objects:stackbuf
	                                                 count:len];
	state->mutationsPtr = &mutations; // point state to mutations for heap array
	return count;
}

#pragma mark -

// NOTE: This method is not part of the CHHeap protocol.
/**
 Returns an array containing the objects in this heap in their current order. The contents are almost certainly not sorted (since only the heap property need be satisfied) but this is the quickest way to retrieve all the elements in a heap.
 
 @return An array containing the objects in this heap in their current order. If the heap is empty, the array is also empty.
 
 @see allObjectsInSortedOrder
 @see count
 @see objectEnumerator
 @see removeAllObjects
 */
- (NSArray*) allObjects {
	return [[array copy] autorelease];
}

- (NSArray*) allObjectsInSortedOrder {
	NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc]
	                                    initWithKey:nil
	                                      ascending:(sortOrder == NSOrderedAscending)];
	return [array sortedArrayUsingDescriptors:[NSArray arrayWithObject:[sortDescriptor autorelease]]];
}

/**
 Determine whether the receiver contains a given object, matched using \link NSObject-p#isEqual: -isEqual:\endlink.
 
 @param anObject The object to test for membership in the heap.
 @return @c YES if @a anObject appears in the heap at least once, @c NO if @a anObject is @c nil or not present.
 
 @see containsObjectIdenticalTo:
 @see removeObject:
 */
- (BOOL) containsObject:(id)anObject {
	return [array containsObject:anObject];
}

// NOTE: This method is not part of the CHHeap protocol.
- (BOOL) containsObjectIdenticalTo:(id)anObject {
	return ([array indexOfObjectIdenticalTo:anObject] != NSNotFound);
}

- (NSUInteger) count {
	return [array count];
}

- (id) firstObject {
	return ([array count] > 0) ? [array objectAtIndex:0] : nil;
}

- (NSUInteger) hash {
	id anObject = [self firstObject];
	return hashOfCountAndObjects([self count], anObject, anObject);
}

- (BOOL) isEqual:(id)otherObject {
	if ([otherObject conformsToProtocol:@protocol(CHHeap)])
		return [self isEqualToHeap:otherObject];
	else
		return NO;
}

- (BOOL) isEqualToHeap:(id<CHHeap>)otherHeap {
	return collectionsAreEqual(self, otherHeap);
}

- (id) objectAtIndex:(NSUInteger)index {
	return [array objectAtIndex:index];
}

- (NSEnumerator*) objectEnumerator {
	return [[self allObjectsInSortedOrder] objectEnumerator];
}

#pragma mark -

- (void) addObject:(id)anObject {
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	++mutations;
	[array addObject:anObject];
	// Bubble the new object (at the end of the array) up the heap as necessary.
	NSUInteger parentIndex;
	NSUInteger index = [array count] - 1;
	while (index > 0) {
		parentIndex = (index - 1) / 2;
		if ([[array objectAtIndex:parentIndex] compare:anObject] != sortOrder) {
			[array exchangeObjectAtIndex:parentIndex withObjectAtIndex:index];
			index = parentIndex;
		}
		else
			break;
	}
}

- (void) addObjectsFromArray:(NSArray*)anArray {
	if (anArray == nil)
		return;
	++mutations;
	[array addObjectsFromArray:anArray];
	// Re-heapify from the middle of the heap array backwards to the beginning.
	// (This must be done since we don't know the ordering of the new objects.)
	// We could choose to bubble each new element up, but this is likely faster.
	NSUInteger index = [array count]/2;
	while (0 < index--)
		[self heapifyFromIndex:index];
}

- (void)insertObject:(id)anObject atIndex:(NSUInteger)index {
	CHUnsupportedOperationException([self class], _cmd);
}

- (void) removeFirstObject {
	if ([array count] > 0) {
		++mutations;
		[array exchangeObjectAtIndex:0 withObjectAtIndex:([array count]-1)];
		[array removeLastObject];
		// Bubble the swapped node down until the heap property is again satisfied
		[self heapifyFromIndex:0];
	}
}

// NOTE: This method is not part of the CHHeap protocol.
- (void) removeObject:(id)anObject {
	NSUInteger count = [array count];
	if (count == 0 || anObject == nil)
		return;
	++mutations;
	NSUInteger index = 0;
	NSRange range;
	range.location = 0;
	range.length = count;
	while ((index = [array indexOfObject:anObject inRange:range]) != NSNotFound) {
		[array exchangeObjectAtIndex:index withObjectAtIndex:(--count)];
		[array removeLastObject];
		// Bubble the swapped node down until the heap property is again satisfied
		[self heapifyFromIndex:index/2];
		range.location = index;
		range.length = count - index;
	}
}

- (void) removeObjectAtIndex:(NSUInteger)index {
	CHUnsupportedOperationException([self class], _cmd);
}

// NOTE: This method is not part of the CHHeap protocol.
- (void) removeObjectIdenticalTo:(id)anObject {
	NSUInteger count = [array count];
	if (count == 0 || anObject == nil)
		return;
	++mutations;
	NSUInteger index = 0;
	NSRange range;
	range.location = 0;
	range.length = count;
	while ((index = [array indexOfObjectIdenticalTo:anObject inRange:range]) != NSNotFound) {
		[array exchangeObjectAtIndex:index withObjectAtIndex:(--count)];
		[array removeLastObject];
		// Bubble the swapped node down until the heap property is again satisfied
		[self heapifyFromIndex:index/2];
		range.location = index;
		range.length = count - index;
	}
}

- (void) removeAllObjects {
	[array removeAllObjects];
	++mutations;
}

@end
