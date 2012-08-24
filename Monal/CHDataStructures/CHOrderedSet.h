/*
 CHDataStructures.framework -- CHOrderedSet.h
 
 Copyright (c) 2009-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHMutableSet.h"

/**
 @file CHOrderedSet.h
 A set which also maintains order of insertion, including manual reordering.
 */

/**
 A set which also maintains order of insertion, including manual reordering.
 
 An <strong>ordered set</strong> is a composite data structure which combines a <a href="http://en.wikipedia.org/wiki/Set_(computer_science)">set</a> and a <a href="http://en.wikipedia.org/wiki/List_(computing)">list</a>. It blends the uniqueness aspect of sets with the ability to recall the order in which items were added to the set. While this is possible with only a ordered set, the speedy test for membership is a set means  that many basic operations (such as add, remove, and contains) that take linear time for a list can be accomplished in constant time (i.e. O(1) instead of O(n) complexity. Compared to these gains, the time overhead required for maintaining the list is negligible, although it does increase memory requirements.
 
 One of the most common implementations of an insertion-ordered set is Java's <a href="http://java.sun.com/javase/6/docs/api/java/util/LinkedHashSet.html">LinkedHashSet</a>. This implementation wraps an NSMutableSet and a circular buffer to maintain insertion order. The API is designed to be as consistent as possible with that of NSSet and NSMutableSet.
 
 @see CHOrderedDictionary
 
 @todo Allow setting a maximum size, and either reject additions or evict the "oldest" item when the limit is reached? (Perhaps this would be better done by the user...)
 */
@interface CHOrderedSet : CHMutableSet {
	id ordering; // A structure for maintaining ordering of the objects.
}

#pragma mark Querying Contents
/** @name Querying Contents */
// @{

/**
 Returns an array of the objects in the set, in the order in which they were inserted.
 
 @return An array of the objects in the set, in the order in which they were inserted.
 
 @see anyObject
 @see objectEnumerator
 */
- (NSArray*) allObjects;

/**
 Returns the "oldest" member of the receiver.
 
 @return The "oldest" member of the receiver.
 
 @see addObject:
 @see anyObject
 @see lastObject
 @see removeFirstObject
 */
- (id) firstObject;

/**
 Returns the index of a given object based on insertion order.
 
 @param anObject The object to search for in the receiver.
 @return The index of @a anObject based on insertion order. If the object does not existsin the receiver, @c NSNotFound is returned.
 
 @see firstObject
 @see lastObject
 @see objectAtIndex:
 @see removeObjectAtIndex:
 */
- (NSUInteger) indexOfObject:(id)anObject;

/**
 Compares the receiving ordered set to another ordered set. Two ordered sets have equal contents if they each hold the same number of objects and objects at a given position in each ordered set satisfy the \link NSObject-p#isEqual: -isEqual:\endlink test.
 
 @param otherOrderedSet A ordered set.
 @return @c YES if the contents of @a otherOrderedSet are equal to the contents of the receiver, otherwise @c NO.
 */
- (BOOL) isEqualToOrderedSet:(CHOrderedSet*)otherOrderedSet;

/**
 Returns the "youngest" member of the receiver.
 
 @return The object in the array with the highest index value. If the array is empty, returns nil.

 @see addObject:
 @see anyObject
 @see firstObject
 @see removeLastObject
 */
- (id) lastObject;

/**
 Returns the value at the specified index.
 
 @param index The insertion-order index of the value to retrieve.
 @return The value at the specified index, based on insertion order.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see indexOfObject:
 @see objectsAtIndexes:
 @see removeObjectAtIndex:
 */
- (id) objectAtIndex:(NSUInteger)index;

/**
 Returns an enumerator object that lets you access each object in the receiver by insertion order.
 
 @return An enumerator object that lets you access each object in the receiver by insertion order.
 
 @warning Modifying a collection while it is being enumerated is unsafe, and may cause a mutation exception to be raised.
 
 If you need to modify the entries concurrently, you can enumerate over a "snapshot" of the set's values obtained from #allObjects.
 
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
 Returns an ordered dictionary containing the objects in the receiver at the indexes specified by a given index set.
 
 @param indexes A set of indexes for keys to retrieve from the receiver.
 @return An array containing the objects in the receiver at the indexes specified by @a indexes.
 
 @throw NSRangeException if any location in @a indexes exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a indexes is @c nil.
 
 @attention To retrieve entries in a given NSRange, pass <code>[NSIndexSet indexSetWithIndexesInRange:range]</code> as the parameter.
 */
- (CHOrderedSet*) orderedSetWithObjectsAtIndexes:(NSIndexSet*)indexes;

// @}
#pragma mark Modifying Contents
/** @name Modifying Contents */
// @{

/**
 Adds a given object to the receiver at a given index. If the receiver already contains an equivalent object, it is replaced with @a anObject.
 
 @param anObject The object to add to the receiver.
 @param index The index at which @a anObject should be inserted.
 
 @see addObject:
 @see indexOfObject:
 @see objectAtIndex:
 */
- (void) insertObject:(id)anObject atIndex:(NSUInteger)index;

/**
 Exchange the objects in the receiver at given indexes.
 
 @param idx1 The index of the object to replace with the object at @a idx2.
 @param idx2 The index of the object to replace with the object at @a idx1.
 
 @throw NSRangeException if @a idx1 or @a idx2 exceeds the bounds of the receiver.
 
 @see indexOfObject:
 @see insertObject:atIndex:
 @see objectAtIndex:
 */
- (void) exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2;

/**
 Remove the "oldest" member of the receiver.
 
 @see firstObject
 @see removeAllObjects
 @see removeObject:
 @see removeObjectAtIndex:
 */
- (void) removeFirstObject;

/**
 Remove the "youngest" member of the receiver. 

 @see lastObject
 @see removeAllObjects
 @see removeObject:
 @see removeObjectAtIndex:
 */
- (void) removeLastObject;

/**
 Remove the object at a given index from the receiver.
 
 @param index The index of the object to remove.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see minusSet:
 @see objectAtIndex:
 @see removeAllObjects
 @see removeFirstObject
 @see removeLastObject
 @see removeObject:
 @see removeObjectsAtIndexes:
 */
- (void) removeObjectAtIndex:(NSUInteger)index;

/**
 Remove the objects at the specified indexes from the receiver.
 @param indexes A set of positions corresponding to objects to remove from the receiver.
 
 @throw NSRangeException if any location in @a indexes exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a indexes is @c nil.
 
 @attention To remove objects in a given @c NSRange, pass <code>[NSIndexSet indexSetWithIndexesInRange:range]</code> as the parameter to this method.
 
 @see objectsAtIndexes:
 @see removeAllObjects
 @see removeObjectAtIndex:
 */
- (void) removeObjectsAtIndexes:(NSIndexSet*)indexes;

// @}
@end
