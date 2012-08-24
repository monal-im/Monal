/*
 CHDataStructures.framework -- CHStack.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "Util.h"

/**
 @file CHStack.h
 
 A <a href="http://en.wikipedia.org/wiki/Stack_(data_structure)">stack</a> protocol with methods for <a href="http://en.wikipedia.org/wiki/LIFO">LIFO</a> ("Last In, First Out") operations. 
 */

/**
 A <a href="http://en.wikipedia.org/wiki/Stack_(data_structure)">stack</a> protocol with methods for <a href="http://en.wikipedia.org/wiki/LIFO">LIFO</a> ("Last In, First Out") operations. 
 
 A stack is commonly compared to a stack of plates. Objects may be added in any order (\link #pushObject: -pushObject:\endlink) and the most recently added object may be removed (\link #popObject -popObject\endlink) or returned without removing it (\link #topObject -topObject\endlink).
 
 @see CHDeque
 @see CHQueue
 */
@protocol CHStack <NSObject, NSCoding, NSCopying, NSFastEnumeration>

/**
 Initialize a stack with no objects.
 
 @return An initialized stack that contains no objects.
 
 @see initWithArray:
 */
- (id) init;

/**
 Initialize a stack with the contents of an array. Objects are pushed on the stack in the order they occur in the array.
 
 @param anArray An array containing objects with which to populate a new stack.
 @return An initialized stack that contains the objects in @a anArray.
 */
- (id) initWithArray:(NSArray*)anArray;

#pragma mark Querying Contents
/** @name Querying Contents */
// @{

/**
 Returns an array of the objects in this stack, ordered from top to bottom.
 
 @return An array of the objects in this stack. If the stack is empty, the array is also empty.
 
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
 Returns the number of objects currently on the stack.
 
 @return The number of objects currently on the stack.
 
 @see allObjects
 */
- (NSUInteger) count;

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
 Compares the receiving stack to another stack. Two stacks have equal contents if they each hold the same number of objects and objects at a given position in each stack satisfy the \link NSObject-p#isEqual: -isEqual:\endlink test.
 
 @param otherStack A stack.
 @return @c YES if the contents of @a otherStack are equal to the contents of the receiver, otherwise @c NO.
 */
- (BOOL) isEqualToStack:(id<CHStack>)otherStack;

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
 Returns an enumerator that accesses each object in the stack from top to bottom.
 
 @return An enumerator that accesses each object in the stack from top to bottom. The enumerator returned is never @c nil; if the stack is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
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

/**
 Returns the object on the top of the stack without removing it.
 
 @return The topmost object from the stack.
 
 @see popObject
 @see pushObject:
 */
- (id) topObject;

// @}
#pragma mark Modifying Contents
/** @name Modifying Contents */
// @{

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
 Remove the topmost object on the stack; no effect if the stack is already empty.
 
 @see pushObject:
 @see removeObject:
 @see topObject
 */
- (void) popObject;

/**
 Add an object to the top of the stack.
 
 @param anObject The object to add to the top of the stack.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 @see popObject
 @see topObject
 */
- (void) pushObject:(id)anObject;

/**
 Empty the receiver of all of its members.
 
 @see allObjects
 @see popObject
 @see removeObject:
 @see removeObjectIdenticalTo:
 */
- (void) removeAllObjects;

/**
 Remove @b all occurrences of @a anObject, matched using @c isEqual:.
 
 @param anObject The object to be removed from the stack.
 
 If the stack is empty, @a anObject is @c nil, or no object matching @a anObject is found, there is no effect, aside from the possible overhead of searching the contents.
 
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
 
 @param anObject The object to be removed from the stack.
 
 If the stack is empty, @a anObject is @c nil, or no object matching @a anObject is found, there is no effect, aside from the possible overhead of searching the contents.
 
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
