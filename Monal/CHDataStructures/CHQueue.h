/*
 CHDataStructures.framework -- CHQueue.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "Util.h"

/**
 @file CHQueue.h
 
 A <a href="http://en.wikipedia.org/wiki/Queue_(data_structure)">queue</a> protocol with methods for <a href="http://en.wikipedia.org/wiki/FIFO">FIFO</a> ("First In, First Out") operations.
 */

/**
 A <a href="http://en.wikipedia.org/wiki/Queue_(data_structure)">queue</a> protocol with methods for <a href="http://en.wikipedia.org/wiki/FIFO">FIFO</a> ("First In, First Out") operations.
 
 A queue is commonly compared to waiting in line. When objects are added, they go to the back of the line, and objects are always removed from the front of the line. These actions are accomplished using \link #addObject: -addObject:\endlink and \link #removeFirstObject -removeFirstObject\endlink, respectively. The frontmost object may be examined (not removed) using \link #firstObject -firstObject\endlink.
 
 @see CHDeque
 @see CHStack
 */
@protocol CHQueue <NSObject, NSCoding, NSCopying, NSFastEnumeration>

/**
 Initialize a queue with no objects.
 
 @return An initialized queue that contains no objects.
 
 @see initWithArray:
 */
- (id) init;

/**
 Initialize a queue with the contents of an array. Objects are enqueued in the order they occur in the array.
 
 @param anArray An array containing objects with which to populate a new queue.
 @return An initialized queue that contains the objects in @a anArray.
 */
- (id) initWithArray:(NSArray*)anArray;

#pragma mark Querying Contents
/** @name Querying Contents */
// @{

/**
 Returns an array with the objects in this queue, ordered from front to back.
 
 @return An array with the objects in this queue. If the queue is empty, the array is also empty.
 
 @see count
 @see objectEnumerator
 @see removeAllObjects
 */
- (NSArray*) allObjects;

/**
 Determine whether the receiver contains a given object, matched using \link NSObject-p#isEqual: -isEqual:\endlink.
 
 @param anObject The object to test for membership in the receiver.
 @return @c YES if the receiver contains @a anObject (as determined by \link NSObject-p#isEqual: -isEqual:\endlink), @c NO if @a anObject is @c nil or not present.
 
 @see containsObjectIdenticalTo:
 @see removeObject:
 */
- (BOOL) containsObject:(id)anObject;

/**
 Determine whether the receiver contains a given object, matched using the == operator.
 
 @param anObject The object to test for membership in the receiver.
 @return @c YES if the receiver contains @a anObject (as determined by the == operator), @c NO if @a anObject is @c nil or not present.
 
 @see containsObject:
 @see removeObjectIdenticalTo:
 */
- (BOOL) containsObjectIdenticalTo:(id)anObject;

/**
 Returns the number of objects currently in the queue.
 
 @return The number of objects currently in the queue.
 
 @see allObjects
 */
- (NSUInteger) count;

/**
 Returns the object at the front of the queue without removing it.
 
 @return The first object in the queue, or @c nil if the queue is empty.
 
 @see lastObject
 @see removeFirstObject
 */
- (id) firstObject;

/**
 Returns the lowest index of a given object, matched using @c isEqual:.
 
 @param anObject The object to search for in the receiver.
 @return The index of the first object which is equal to @a anObject. If none of the objects in the receiver match @a anObject, returns @c NSNotFound.
 
 @see indexOfObjectIdenticalTo:
 @see objectAtIndex:
 @see removeObjectAtIndex:
 */
- (NSUInteger) indexOfObject:(id)anObject;

/**
 Returns the lowest index of a given object, matched using the == operator.
 
 @param anObject The object to be matched and located in the receiver.
 @return The index of the first object which is equal to @a anObject. If none of the objects in the receiver match @a anObject, returns @c NSNotFound.
 
 @see indexOfObject:
 @see objectAtIndex:
 @see removeObjectAtIndex:
 */
- (NSUInteger) indexOfObjectIdenticalTo:(id)anObject;

/**
 Compares the receiving queue to another queue. Two queues have equal contents if they each hold the same number of objects and objects at a given position in each queue satisfy the \link NSObject-p#isEqual: -isEqual:\endlink test.
 
 @param otherQueue A queue.
 @return @c YES if the contents of @a otherQueue are equal to the contents of the receiver, otherwise @c NO.
 */
- (BOOL) isEqualToQueue:(id<CHQueue>)otherQueue;

/**
 Returns the object at the back of the queue without removing it.
 
 @return The last object in the queue, or @c nil if the queue is empty.
 
 @see addObject:
 @see firstObject
 */
- (id) lastObject;

/**
 Returns the object located at @a index in the receiver.
 
 @param index An index from which to retrieve an object.
 @return The object located at @a index.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see indexOfObject:
 @see indexOfObjectIdenticalTo:
 @see removeObjectAtIndex:
 */
- (id) objectAtIndex:(NSUInteger)index;

/**
 Returns an enumerator that accesses each object in the queue from front to back.
 
 @return An enumerator that accesses each object in the queue from front to back. The enumerator returned is never @c nil; if the queue is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
 @attention The enumerator retains the collection. Once all objects in the enumerator have been consumed, the collection is released.
 @warning Modifying a collection while it is being enumerated is unsafe, and may cause a mutation exception to be raised.

 @see allObjects
 */
- (NSEnumerator*) objectEnumerator;

/**
 Returns an array containing the objects in the receiver at the indexes specified by a given index set.
 
 @param indexes A set of positions corresponding to objects to retrieve from the receiver.
 @return A new array containing the objects in the receiver specified by @a indexes.
 
 @throw NSRangeException if any location in @a indexes exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a indexes is @c nil.
 
 @attention To retrieve objects in a given NSRange, pass <code>[NSIndexSet indexSetWithIndexesInRange:range]</code> as the parameter to this method.
 
 @see allObjects
 @see objectAtIndex:
 @see removeObjectsAtIndexes:
 */
- (NSArray*) objectsAtIndexes:(NSIndexSet*)indexes;

// @}
#pragma mark Modifying Contents
/** @name Modifying Contents */
// @{

/**
 Add an object to the back of the queue.
 
 @param anObject The object to add to the back of the queue.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 @see lastObject
 @see removeFirstObject
 */
- (void) addObject:(id)anObject;

/**
 Exchange the objects in the receiver at given indexes.
 
 @param idx1 The index of the object to replace with the object at @a idx2.
 @param idx2 The index of the object to replace with the object at @a idx1.
 
 @throw NSRangeException if @a idx1 or @a idx2 exceeds the bounds of the receiver.
 
 @see indexOfObject:
 @see objectAtIndex:
 */
- (void) exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2;

/**
 Empty the receiver of all of its members.
 
 @see allObjects
 @see removeFirstObject
 @see removeObject:
 @see removeObjectIdenticalTo:
 */
- (void) removeAllObjects;

/**
 Remove the front object in the queue; no effect if the queue is already empty.
 
 @see firstObject
 @see removeObject:
 */
- (void) removeFirstObject;

/**
 Remove @b all occurrences of @a anObject, matched using @c isEqual:.
 
 @param anObject The object to be removed from the queue.
 
 If the queue is empty, @a anObject is @c nil, or no object matching @a anObject is found, there is no effect, aside from the possible overhead of searching the contents.
 
 @see containsObject:
 @see removeObjectIdenticalTo:
 */
- (void) removeObject:(id)anObject;

/**
 Remove the object at a given index from the receiver.
 
 @param index The index of the object to remove.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see indexOfObject:
 @see indexOfObjectIdenticalTo:
 @see objectAtIndex:
 */
- (void) removeObjectAtIndex:(NSUInteger)index;

/**
 Remove @b all occurrences of @a anObject, matched using the == operator.
 
 @param anObject The object to be removed from the queue.
 
 If the queue is empty, @a anObject is @c nil, or no object matching @a anObject is found, there is no effect, aside from the possible overhead of searching the contents.
 
 @see containsObjectIdenticalTo:
 @see removeObject:
 */
- (void) removeObjectIdenticalTo:(id)anObject;

/**
 Remove the objects at the specified indexes from the receiver. Indexes of elements beyond the first specified index will decrease.
 @param indexes A set of positions corresponding to objects to remove from the receiver.
 
 @throw NSRangeException if any location in @a indexes exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a indexes is @c nil.
 
 @attention To remove objects in a given @c NSRange, pass <code>[NSIndexSet indexSetWithIndexesInRange:range]</code> as the parameter to this method.
 
 @see objectsAtIndexes:
 @see removeAllObjects
 @see removeObjectAtIndex:
 */
- (void) removeObjectsAtIndexes:(NSIndexSet*)indexes;

/**
 Replaces the object at a given index with a given object.
 
 @param index The index of the object to be replaced.
 @param anObject The object with which to replace the object at @a index in the receiver.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 */
- (void) replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject;

// @}
@end
