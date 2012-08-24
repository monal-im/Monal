/*
 CHDataStructures.framework -- CHCircularBuffer.m
 
 Copyright (c) 2009-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHCircularBuffer.h"

#define DEFAULT_BUFFER_SIZE 16u

#define transformIndex(index) ((headIndex + index) % arrayCapacity)
#define incrementIndex(index) (index = (index + 1) % arrayCapacity)
#define decrementIndex(index) (index = index ? index - 1 : arrayCapacity - 1)

// Shift a group of elements within the underlying array; used to close up gaps.
// Guarantees that 'number' is in the correct range for the array capacity.
#define blockMove(dst, src, scan) \
do { \
	NSUInteger itemsLeftToCopy = (scan - src + arrayCapacity) % arrayCapacity; \
	while (itemsLeftToCopy) { \
		NSUInteger size = MIN(itemsLeftToCopy, arrayCapacity - MAX(dst, src)); \
		objc_memmove_collectable(&array[dst], &array[src], kCHPointerSize * size); \
		src = (src + size) % arrayCapacity; \
		dst = (dst + size) % arrayCapacity; \
		itemsLeftToCopy -= size; \
	} \
} while(0)

/**
 An NSEnumerator for traversing a CHAbstractCircularBufferCollection subclass.
 
 Enumerators encapsulate their own state, and more than one may be active at once.
 However, like an enumerator for a mutable data structure, any instances of this
 enumerator become invalid if the underlying collection is modified.
 */
@interface CHCircularBufferEnumerator : NSEnumerator
{
	id *array;                   // Underlying circular buffer to be enumerated.
	NSUInteger arrayCapacity;    // Allocated capacity of @a array.
	NSUInteger arrayCount;       // Number of elements in @a array.
	NSUInteger enumerationCount; // How many objects have been enumerated.
	NSUInteger enumerationIndex; // Index of the next element to enumerate.
	BOOL reverseEnumeration;     // Whether to enumerate back-to-front.
	unsigned long mutationCount; // Stores the collection's initial mutation.
	unsigned long *mutationPtr;  // Pointer for checking changes in mutation.
}

/**
 Create an enumerator which traverses a circular buffer in the specified order.
 
 @param anArray The C pointer array of the circular buffer being enumerated.
 @param capacity The total capacity of the circular buffer being enumerated.
 @param count The number of items currently in the circular buffer.
 @param startIndex The index at which to begin enumerating (forward or reverse).
 @param direction The direction in which to enumerate. (@c NSOrderedDescending is back-to-front).
 @param mutations A pointer to the collection's mutation count for invalidation.
 @return An initialized CHCircularBufferEnumerator which will enumerate objects in @a anArray in the order specified by @a direction.
 */
- (id) initWithArray:(id*)anArray
            capacity:(NSUInteger)capacity
               count:(NSUInteger)count
          startIndex:(NSUInteger)startIndex
           direction:(NSComparisonResult)direction
     mutationPointer:(unsigned long*)mutations;

/**
 Returns an array of objects the receiver has yet to enumerate.
 
 @return An array of objects the receiver has yet to enumerate.
 
 Invoking this method exhausts the remainder of the objects, such that subsequent
 invocations of #nextObject return @c nil.
 */
- (NSArray*) allObjects;

/**
 Returns the next object from the collection being enumerated.
 
 @return The next object from the collection being enumerated, or
 @c nil when all objects have been enumerated.
 */
- (id) nextObject;

@end

@implementation CHCircularBufferEnumerator

- (id) initWithArray:(id*)anArray
            capacity:(NSUInteger)capacity
               count:(NSUInteger)count
          startIndex:(NSUInteger)startIndex
           direction:(NSComparisonResult)direction
     mutationPointer:(unsigned long*)mutations
{
	if ((self = [super init]) == nil) return nil;
	array = anArray;
	arrayCapacity = capacity;
	arrayCount = count;
	enumerationCount = 0;
	enumerationIndex = startIndex;
	reverseEnumeration = (direction == NSOrderedDescending);
	if (reverseEnumeration)
		decrementIndex(enumerationIndex);
	mutationCount = *mutations;
	mutationPtr = mutations;
	return self;
}

- (NSArray*) allObjects {
	NSMutableArray *allObjects = [[NSMutableArray alloc] init];
	if (reverseEnumeration) {
		while (enumerationCount++ < arrayCount) {
			[allObjects addObject:array[enumerationIndex]];
			decrementIndex(enumerationIndex);
		}
	}
	else {
		while (enumerationCount++ < arrayCount) {
			[allObjects addObject:array[enumerationIndex]];
			incrementIndex(enumerationIndex);
		}
	}
	if (mutationCount != *mutationPtr)
		CHMutatedCollectionException([self class], _cmd);
	return [allObjects autorelease];
}

- (id) nextObject {
	id object = nil;
	if (enumerationCount++ < arrayCount) {
		object = array[enumerationIndex];
		if (reverseEnumeration) {
			decrementIndex(enumerationIndex);
		}
		else {
			incrementIndex(enumerationIndex);
		}
	}
	if (mutationCount != *mutationPtr)
		CHMutatedCollectionException([self class], _cmd);
	return object;
}

@end

#pragma mark -

/**
 @todo Reimplement @c removeObjectsAtIndexes: for efficiency with multiple objects.

 @todo Look at refactoring @c insertObject:atIndex: and @c removeObjectAtIndex:
 to always shift the smaller chunk of elements and deal with wrapping around.
 The current worst-case is that removing at index N-1 of N when the buffer wraps
 (or inserting at index 1 of N when it doesn't) causes N-1 objects to be shifted
 in memory, where it would obviously make more sense to shift only one object.
 Being able to shift the shorter side would almost always move less total data.
 - Shifting without wrapping requires only 1 memmove(), <= the current size.
 - Shifting around the end requires 0-2 memmove()s and an assignment.
	- 0 if inserting/removing just inside head or tail, causing them to (un)wrap.
	- 1 if inserting in first/last array slot with 1+ items wrapped on other end.
	- 2 if inserting/removing further inside with 1+ items on other end.
 */
@implementation CHCircularBuffer

- (void) dealloc {
	[self removeAllObjects];
	free(array);
	[super dealloc];
}

// Note: Defined here since -init is not implemented in NS(Mutable)Array.
- (id) init {
	return [self initWithCapacity:DEFAULT_BUFFER_SIZE];
}

- (id) initWithArray:(NSArray*)anArray {
	NSUInteger capacity = DEFAULT_BUFFER_SIZE;
	while (capacity <= [anArray count])
		capacity *= 2;
	if ([self initWithCapacity:capacity] == nil) return nil;
	for (id anObject in anArray) {
		array[tailIndex++] = [anObject retain];
	}
	count = [anArray count];
	return self;
}

// This is the designated initializer for CHCircularBuffer.
- (id) initWithCapacity:(NSUInteger)capacity {
	if ((self = [super init]) == nil) return nil;
	arrayCapacity = capacity ? capacity : DEFAULT_BUFFER_SIZE;
	array = NSAllocateCollectable(kCHPointerSize*arrayCapacity, NSScannedOption);
	return self;	
}

#pragma mark <NSCoding>

// Overridden from NSMutableArray to encode/decode as the proper class.
- (Class) classForKeyedArchiver {
	return [self class];
}

- (id) initWithCoder:(NSCoder*)decoder {
	return [self initWithArray:[decoder decodeObjectForKey:@"array"]];
}

- (void) encodeWithCoder:(NSCoder*)encoder {
	[encoder encodeObject:[self allObjects] forKey:@"array"];
}

#pragma mark <NSCopying>

- (id) copyWithZone:(NSZone*)zone {
	return [[[self class] allocWithZone:zone] initWithArray:[self allObjects]];
}

#pragma mark <NSFastEnumeration>

/*
 Since this class uses a C array for storage, we can return a pointer to any spot in the array and a count greater than "len". This approach avoids copy overhead, and is also more efficient since this method will be called only 2 or 3 times, depending on whether the buffer wraps around the end of the array. (The last call always returns 0 and requires no extra processing.)
 */
- (NSUInteger) countByEnumeratingWithState:(NSFastEnumerationState*)state
                                   objects:(id*)stackbuf
                                     count:(NSUInteger)len
{
	if (state->state == 0) {
		state->mutationsPtr = &mutations;
		state->itemsPtr = array + headIndex; // pointer arithmetic for offset
		// If the buffer wraps, only provide elements to the end of the array.
		NSUInteger enumeratedCount = MIN(arrayCapacity - headIndex, count);
		state->state = (unsigned long) enumeratedCount;
		return enumeratedCount;
	}
	else if (state->state < count) {
		// This means the buffer wrapped around; now return the wrapped segment.
		state->itemsPtr = array;
		NSUInteger enumeratedCount = (NSUInteger) state->state;
		state->state = (unsigned long) count;
		return (count - enumeratedCount);
	}
	else {
		return 0;
	}
}

#pragma mark Querying Contents

- (NSArray*) allObjects {
	NSMutableArray *allObjects = [[NSMutableArray alloc] init];
	if (count > 0) {
		for (id anObject in self) {
			[allObjects addObject:anObject];
		}
	}
	return [allObjects autorelease];
}

- (BOOL) containsObject:(id)anObject {
	NSUInteger iterationIndex = headIndex;
	while (iterationIndex != tailIndex) {
		if ([array[iterationIndex] isEqual:anObject])
			return YES;
		incrementIndex(iterationIndex);
	}
	return NO;
}

- (BOOL) containsObjectIdenticalTo:(id)anObject {
	NSUInteger iterationIndex = headIndex;
	while (iterationIndex != tailIndex) {
		if (array[iterationIndex] == anObject)
			return YES;
		incrementIndex(iterationIndex);
	}
	return NO;
}

// NSArray primitive method
- (NSUInteger) count {
	return count;
}

- (id) firstObject {
	return (count > 0) ? array[headIndex] : nil;
}

- (NSUInteger) hash {
	return hashOfCountAndObjects(count, [self firstObject], [self lastObject]);
}

- (id) lastObject {
	return (count > 0) ? array[((tailIndex) ? tailIndex : arrayCapacity) - 1] : nil;
}

- (NSUInteger) indexOfObject:(id)anObject {
	return [self indexOfObject:anObject inRange:NSMakeRange(0, count)];
}

- (NSUInteger) indexOfObject:(id)anObject inRange:(NSRange)range {
	NSUInteger onePastLastRelativeIndex = range.location + range.length;
	if (onePastLastRelativeIndex > count)
		CHIndexOutOfRangeException([self class], _cmd, onePastLastRelativeIndex, count);
	NSUInteger iterationIndex = transformIndex(range.location);
	NSUInteger relativeIndex = range.location;
	while (relativeIndex < onePastLastRelativeIndex) {
		if ([array[iterationIndex] isEqual:anObject])
			return relativeIndex;
		incrementIndex(iterationIndex);
		relativeIndex++;
	}
	return NSNotFound;
}

- (NSUInteger) indexOfObjectIdenticalTo:(id)anObject {
	return [self indexOfObjectIdenticalTo:anObject inRange:NSMakeRange(0, count)];
}

- (NSUInteger)indexOfObjectIdenticalTo:(id)anObject inRange:(NSRange)range {
	NSUInteger onePastLastRelativeIndex = range.location + range.length;
	if (onePastLastRelativeIndex > count)
		CHIndexOutOfRangeException([self class], _cmd, onePastLastRelativeIndex, count);
	NSUInteger iterationIndex = transformIndex(range.location);
	NSUInteger relativeIndex = range.location;
	while (relativeIndex < onePastLastRelativeIndex) {
		if (array[iterationIndex] == anObject)
			return relativeIndex;
		incrementIndex(iterationIndex);
		relativeIndex++;
	}
	return NSNotFound;
}

// NSArray primitive method
- (id) objectAtIndex:(NSUInteger)index {
	if (index >= count)
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	return array[transformIndex(index)];
}

- (NSArray*) objectsAtIndexes:(NSIndexSet*)indexes {
	if (indexes == nil)
		CHNilArgumentException([self class], _cmd);
	if ([indexes count] == 0)
		return [NSArray array];
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:[indexes count]];
	NSUInteger index = [indexes firstIndex];
	while (index != NSNotFound) {
		[objects addObject:[self objectAtIndex:index]];
		index = [indexes indexGreaterThanIndex:index];
	}
	return objects;
}

- (NSEnumerator*) objectEnumerator {
	return [[[CHCircularBufferEnumerator alloc]
	         initWithArray:array
	              capacity:arrayCapacity
	                 count:count
	            startIndex:headIndex
	             direction:NSOrderedAscending
	       mutationPointer:&mutations] autorelease];
}

- (NSEnumerator*) reverseObjectEnumerator {
	return [[[CHCircularBufferEnumerator alloc]
	         initWithArray:array
	              capacity:arrayCapacity
	                 count:count
	            startIndex:tailIndex
	             direction:NSOrderedDescending
	       mutationPointer:&mutations] autorelease];
}

#pragma mark Modifying Contents

// NSMutableArray primitive method
- (void) addObject:(id)anObject {
	[self insertObject:anObject atIndex:count];
}

// NSMutableArray primitive method
- (void) insertObject:(id)anObject atIndex:(NSUInteger)index {
	if (index > count)
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	[anObject retain];
	if (count == 0 || index == count) {
		// To append, just move the tail forward one slot (wrapping if needed)
		array[tailIndex] = anObject;
		incrementIndex(tailIndex);
	} else if (index == 0) {
		// To prepend, just move the head backward one slot (wrapping if needed)
		decrementIndex(headIndex);
		array[headIndex] = anObject;
	} else {
		NSUInteger actualIndex = transformIndex(index);
		if (actualIndex > tailIndex) {
			// Buffer wraps and 'index' is between head and end, so shift left.
			objc_memmove_collectable(&array[headIndex-1], &array[headIndex],
			                         kCHPointerSize * index);
			// These can't wrap around (we'll hit tail first) so just decrement.
			--headIndex;
			--actualIndex;
		}
		else {
			// Otherwise, shift everything from given index onward to the right.
			objc_memmove_collectable(&array[actualIndex+1], &array[actualIndex],
			                         kCHPointerSize * (tailIndex - actualIndex));
			incrementIndex(tailIndex);
		}
		array[actualIndex] = anObject;
	}
	++count;
	++mutations;	
	// If this insertion filled the array to capacity, double its size and copy.
	if (headIndex == tailIndex) {
		array = NSReallocateCollectable(array, kCHPointerSize*arrayCapacity*2, NSScannedOption);
		// Copy wrapped-around portion to end of queue and move tail index
		objc_memmove_collectable(array + arrayCapacity, array,
		                         kCHPointerSize * tailIndex);
		bzero(array, kCHPointerSize * tailIndex); // Zero the source of the copy
		tailIndex += arrayCapacity;
		arrayCapacity *= 2;
	}
}

- (void) exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2 {
	if (idx1 >= count || idx2 >= count)
		CHIndexOutOfRangeException([self class], _cmd, MAX(idx1,idx2), count);
	if (idx1 != idx2) {
		// Find the "real" equivalents of the provided indexes
		NSUInteger realIdx1 = transformIndex(idx1);
		NSUInteger realIdx2 = transformIndex(idx2);
		// Swap the objects at the provided indexes
		id tempObject   = array[realIdx1];
		array[realIdx1] = array[realIdx2];
		array[realIdx2] = tempObject;
		++mutations;
	}
}

- (void) removeFirstObject {
	if (count == 0)
		return;
	[array[headIndex] release];
	array[headIndex] = nil; // Let GC do its thing
	incrementIndex(headIndex);
	--count;
	++mutations;
}

// NSMutableArray primitive method
- (void) removeLastObject {
	if (count == 0)
		return;
	decrementIndex(tailIndex);
	[array[tailIndex] release];
	array[tailIndex] = nil; // Let GC do its thing
	--count;
	++mutations;
}

// Private method that accepts a function pointer for testing object equality.
- (void) removeObject:(id)anObject withEqualityTest:(BOOL(*)(id,id))objectsMatch {
	if (count == 0 || anObject == nil)
		return;
	// Strip off leading matches if any exist in the buffer.
	while (headIndex != tailIndex && objectsMatch(array[headIndex], anObject)) {
		[array[headIndex] release];
		array[headIndex] = nil; // Let GC do its thing
		incrementIndex(headIndex);
	}
	// Scan ahead to find the next matching object to remove, if one exists.
	NSUInteger scanIndex = headIndex;
	while (scanIndex != tailIndex && !objectsMatch(array[scanIndex], anObject))
		incrementIndex(scanIndex);
	// Scan other objects; release and skip matches, block copy objects to keep.
	NSUInteger copySrcIndex = scanIndex; // index to copy FROM when closing gaps
	NSUInteger copyDstIndex = scanIndex; // index to copy TO when closing gaps
	while (scanIndex != tailIndex) {
		if (objectsMatch(array[scanIndex], anObject)) {
			[array[scanIndex] release];
			// If the object is preceded by 1+ not to remove, close the gap now.
			// NOTE: blockMove advances src/dst indexes by the count of objects.
			if (copySrcIndex != scanIndex)
				blockMove(copyDstIndex, copySrcIndex, scanIndex);
			incrementIndex(copySrcIndex); // Advance to where scanIndex will be.
		}
		incrementIndex(scanIndex);
	}
	blockMove(copyDstIndex, copySrcIndex, tailIndex); // fixes any trailing gaps
	if (tailIndex != copyDstIndex) {
		// Zero any now-unoccupied array elements if tail pointer moved left.
		// Under GC, this prevents holding onto removed objects unnecessarily.
		// Under retain-release, it promotes fail-fast behavior to reveal bugs.
		if (tailIndex > copyDstIndex) {
			bzero(array + copyDstIndex, kCHPointerSize * (tailIndex - copyDstIndex));
		} else {
			bzero(array + copyDstIndex, kCHPointerSize * (arrayCapacity - copyDstIndex));
			bzero(array,                kCHPointerSize * tailIndex);
		}
		tailIndex = copyDstIndex;
	}
	count = (tailIndex + arrayCapacity - headIndex) % arrayCapacity;
	++mutations;
}

- (void) removeObject:(id)anObject {
	[self removeObject:anObject withEqualityTest:&objectsAreEqual];
}

// NSMutableArray primitive method
- (void) removeObjectAtIndex:(NSUInteger)index {
	if (index >= count)
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	NSUInteger actualIndex = transformIndex(index);
	[array[actualIndex] release];
	// Handle the simple cases of removing the first or last object first.
	if (index == 0) {
		array[actualIndex] = nil; // Prevents possible memory leak under GC
		incrementIndex(headIndex);
	} else if (index == count - 1) {
		array[actualIndex] = nil; // Prevents possible memory leak under GC
		decrementIndex(tailIndex);
	} else {
		// This logic is derived from http://www.javafaq.nu/java-article808.html
		// For simplicity, this code doesnt shift elements around the array end.
		// Consequently headIndex and tailIndex will not wrap past the end here.
		if (actualIndex > tailIndex) {
			// If the buffer wraps and index is in "the right side", shift right.
			objc_memmove_collectable(&array[headIndex+1], &array[headIndex],
			                         kCHPointerSize * index);
			array[headIndex++] = nil; // Prevents possible memory leak under GC
		} else {
			// Otherwise, shift everything from index to tail one to the left.
			objc_memmove_collectable(&array[actualIndex], &array[actualIndex+1],
			                         kCHPointerSize * (tailIndex-actualIndex-1));
			array[--tailIndex] = nil; // Prevents possible memory leak under GC
		}
	}
	--count;
	++mutations;
}

- (void) removeObjectIdenticalTo:(id)anObject {
	[self removeObject:anObject withEqualityTest:&objectsAreIdentical];
}

- (void) removeObjectsAtIndexes:(NSIndexSet*)indexes {
	if (indexes == nil)
		CHNilArgumentException([self class], _cmd);
	if ([indexes count] > 0) {
		NSUInteger index = [indexes lastIndex];
		while (index != NSNotFound) {
			[self removeObjectAtIndex:index];
			index = [indexes indexLessThanIndex:index];
		}
	}
}

- (void) removeAllObjects {
	if (count > 0) {
		if (kCHGarbageCollectionNotEnabled) {
			while (headIndex != tailIndex) {
				[array[headIndex] release];
				incrementIndex(headIndex);
			}
		}
		else {
			// Only zero out pointers that will remain when the buffer shrinks.
			bzero(array, kCHPointerSize * MIN(arrayCapacity, DEFAULT_BUFFER_SIZE));
		}
		if (arrayCapacity > DEFAULT_BUFFER_SIZE) {
			arrayCapacity = DEFAULT_BUFFER_SIZE;
			// Shrink the size of allocated memory; calls realloc() under non-GC
			array = NSReallocateCollectable(array, kCHPointerSize*arrayCapacity, NSScannedOption);
		}
	}
	headIndex = tailIndex = 0;
	count = 0;
	++mutations;
}

// NSMutableArray primitive method
- (void) replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
	if (index >= count)
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	[anObject retain];
	[array[transformIndex(index)] release];
	array[transformIndex(index)] = anObject;
}

@end
