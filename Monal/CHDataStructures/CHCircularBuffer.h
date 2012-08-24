/*
 CHDataStructures.framework -- CHCircularBuffer.h
 
 Copyright (c) 2009-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "Util.h"

/**
 @file CHCircularBuffer.h
 
 A circular buffer array.
 */

/**
 A <a href="http://en.wikipedia.org/wiki/Circular_buffer">circular buffer</a> is a structure that emulates a continuous ring of N data slots. This class uses a C array and tracks the indexes of the front and back elements in the buffer, such that the first element is treated as logical index 0 regardless of where it is actually stored. The buffer dynamically expands to accommodate added objects. This type of storage is ideal for scenarios where objects are added and removed only at one or both ends (such as a stack or queue) but still supports all normal NSMutableArray functionality.
 
 @note Any method inherited from NSArray or NSMutableArray is supported by this class and its children. Please see the documentation for those classes for details.
*/
@interface CHCircularBuffer : NSMutableArray {
	__strong id *array; // Primitive C array for storing collection contents.
	NSUInteger arrayCapacity; // How many pointers @a array can accommodate.
	NSUInteger count; // The number of objects currently in the buffer.
	NSUInteger headIndex; // The array index of the first object.
	NSUInteger tailIndex; // The array index after the last object.
	unsigned long mutations; // Tracks mutations for NSFastEnumeration.
}

// The following methods are undocumented since they are only reimplementations.
// Users should consult the API documentation for NSArray and NSMutableArray.

- (id) initWithArray:(NSArray*)anArray;

- (NSArray*) allObjects;
- (BOOL) containsObject:(id)anObject;
- (BOOL) containsObjectIdenticalTo:(id)anObject;
- (void) exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2;
- (id) firstObject;
- (NSUInteger) indexOfObject:(id)anObject;
- (NSUInteger) indexOfObjectIdenticalTo:(id)anObject;
- (id) lastObject;
- (NSEnumerator*) objectEnumerator;
- (NSArray*) objectsAtIndexes:(NSIndexSet*)indexes;
- (void) removeAllObjects;
- (void) removeFirstObject;
- (void) removeLastObject;
- (void) removeObject:(id)anObject;
- (void) removeObjectIdenticalTo:(id)anObject;
- (void) removeObjectsAtIndexes:(NSIndexSet*)indexes;
- (void) replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject;
- (NSEnumerator*) reverseObjectEnumerator;

#pragma mark Adopted Protocols

- (void) encodeWithCoder:(NSCoder*)encoder;
- (id) initWithCoder:(NSCoder*)decoder;
- (id) copyWithZone:(NSZone*)zone;
- (NSUInteger) countByEnumeratingWithState:(NSFastEnumerationState*)state
                                   objects:(id*)stackbuf
                                     count:(NSUInteger)len;

@end
