/*
 CHDataStructures.framework -- CHDeque.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "Util.h"

/**
 @file CHDeque.h
 
 A <a href="http://en.wikipedia.org/wiki/Deque">deque</a> protocol with methods for insertion and removal on both ends.
 */

/**
 A <a href="http://en.wikipedia.org/wiki/Deque">deque</a> protocol with methods for insertion and removal on both ends. This differs from standard stacks (where objects are inserted and removed from the same end, a.k.a. LIFO) and queues (where objects are inserted at one end and removed at the other, a.k.a. FIFO). However, a deque can act as either a stack or a queue (or other possible sub-types) by selectively restricting a subset of its input and output operations.
 
 @see CHQueue
 @see CHStack
 */
@protocol CHDeque <NSObject, NSCoding, NSCopying, NSFastEnumeration>

/**
 Initialize a deque with no objects.
 
 @return An initialized deque that contains no objects.
 
 @see initWithArray:
 */
- (id) init;

/**
 Initialize a deque with the contents of an array. Objects are appended in the order they occur in the array.
 
 @param anArray An array containing objects with which to populate a new deque.
 @return An initialized deque that contains the objects in @a anArray.
 */
- (id) initWithArray:(NSArray*)anArray;

#pragma mark Querying Contents
/** @name Querying Contents */
// @{

/**
 Returns an array with the objects in this deque, ordered from front to back.
 
 @return An array with the objects in this deque. If the deque is empty, the array is also empty.
 
 @see count
 @see objectEnumerator
 @see removeAllObjects
 @see reverseObjectEnumerator
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
 Returns the number of objects currently in the deque.
 
 @return The number of objects currently in the deque.
 
 @see allObjects
 */
- (NSUInteger) count;

/**
 Returns the first object in the deque without removing it.
 
 @return The first object in the deque, or @c nil if it is empty.
 
 @see lastObject
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
 Compares the receiving deque to another deque. Two deques have equal contents if they each hold the same number of objects and objects at a given position in each deque satisfy the \link NSObject-p#isEqual: -isEqual:\endlink test.
 
 @param otherDeque A deque.
 @return @c YES if the contents of @a otherDeque are equal to the contents of the receiver, otherwise @c NO.
 */
- (BOOL) isEqualToDeque:(id<CHDeque>)otherDeque;

/**
 Returns the last object in the deque without removing it.
 
 @return The last object in the deque, or @c nil if it is empty.
 
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
 Returns an enumerator that accesses each object in the deque from front to back.
 
 @return An enumerator that accesses each object in the deque from front to back. The enumerator returned is never @c nil; if the deque is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
 @attention The enumerator retains the collection. Once all objects in the enumerator have been consumed, the collection is released.
 @warning Modifying a collection while it is being enumerated is unsafe, and may cause a mutation exception to be raised.
 
 @see allObjects
 @see reverseObjectEnumerator
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

/**
 Returns an enumerator that accesses each object in the deque from back to front.
 
 @return An enumerator that accesses each object in the deque from back to front. The enumerator returned is never @c nil; if the deque is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
 @attention The enumerator retains the collection. Once all objects in the enumerator have been consumed, the collection is released.
 @warning Modifying a collection while it is being enumerated is unsafe, and may cause a mutation exception to be raised.
 
 @see allObjects
 @see objectEnumerator
 */
- (NSEnumerator*) reverseObjectEnumerator;

// @}
#pragma mark Modifying Contents
/** @name Modifying Contents */
// @{

/**
 Add an object to the back of the deque.
 
 @param anObject The object to add to the back of the deque.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 @see lastObject
 @see removeLastObject
 */
- (void) appendObject:(id)anObject;

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
 Add an object to the front of the deque.
 
 @param anObject The object to add to the front of the deque.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 @see firstObject
 @see removeFirstObject
 */
- (void) prependObject:(id)anObject;

/**
 Empty the receiver of all of its members.
 
 @see allObjects
 @see removeFirstObject
 @see removeLastObject
 @see removeObject:
 @see removeObjectIdenticalTo:
 */
- (void) removeAllObjects;

/**
 Remove the first object in the deque; no effect if it is empty.
 
 @see firstObject
 @see removeLastObject
 @see removeObject:
 */
- (void) removeFirstObject;

/**
 Remove the last object in the deque; no effect if it is empty.
 
 @see lastObject
 @see removeFirstObject
 @see removeObject:
 */
- (void) removeLastObject;

/**
 Remove @b all occurrences of @a anObject, matched using @c isEqual:.
 
 @param anObject The object to be removed from the deque.

 If the deque is empty, @a anObject is @c nil, or no object matching @a anObject is found, there is no effect, aside from the possible overhead of searching the contents.
 
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
 
 @param anObject The object to be removed from the deque.
 
 If the deque is empty, @a anObject is @c nil, or no object matching @a anObject is found, there is no effect, aside from the possible overhead of searching the contents.
 
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
