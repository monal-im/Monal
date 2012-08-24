/*
 CHDataStructures.framework -- CHLinkedList.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "Util.h"

/**
 @file CHLinkedList.h
 
 A <a href="http://en.wikipedia.org/wiki/Linked_list">linked list</a> protocol with methods that work for singly- or doubly-linked lists.
 */

/**
 A <a href="http://en.wikipedia.org/wiki/Linked_list">linked list</a> protocol with methods that work for singly- or doubly-linked lists.
 
 This type of data structure is useful for storing sparse data that will be traversed often. (Linked lists are very memory efficient when dealing with sparse data, unlike hashing and some array schemes.) Insertion and removal at either end of a list is extremely fast, but if fast random access (whether insertion, search, or removal) is desired, a linked list will generally incur a substantial performance penalty.
 
 Linked lists maintain references to both the start and end of the list, but there is no externally-visibly notion of state, such as a "current node". Implementations may choose to add indexing or hashing schemes to improve index-based or object-relative random access; several optional methods are included to allow such flexibility if desired. However, bear in mind that any such additions will increase memory cost and diminish the comparative advantages over classes such as NSMutableArray.
 
 Index-based operations are included in this protocol, but users should be aware that unless a subclass chooses to use a special indexing scheme, all index-based methods in a linked list are O(n). If indexed operations are used frequently, it is likely that a better alternative is to use an NSMutableArray.
 */ 
@protocol CHLinkedList <NSObject, NSCoding, NSCopying, NSFastEnumeration>

/**
 Initialize a linked list with no objects.
 
 @return An initialized linked list that contains no objects.
 
 @see initWithArray:
 */
- (id) init;

/**
 Initialize a linked list with the contents of an array. Objects are appended in the order they occur in the array.
 
 @param anArray An array containing objects with which to populate a new linked list.
 @return An initialized linked list that contains the objects in @a anArray.
 */
- (id) initWithArray:(NSArray*)anArray;

#pragma mark Querying Contents
/** @name Querying Contents */
// @{

/**
 Returns an array containing the objects in the receiver, ordered front to back.
 
 @return An array containing the objects in the receiver. If the receiver is empty, the array is also empty.
 
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
 Returns the number of objects currently in the receiver.
 
 @return The number of objects currently in the receiver.
 
 @see allObjects
 */
- (NSUInteger) count;

/**
 Returns the first object in the receiver.
 
 @return The first object in the receiver, or @c nil if the receiver is empty.
 
 @see lastObject
 @see removeFirstObject
 */
- (id) firstObject;

/**
 Returns the last object in the receiver.
 
 @return The last object in the receiver, or @c nil if the receiver is empty.
 
 @see firstObject
 @see removeLastObject
 */
- (id) lastObject;

/**
 Returns the lowest index of a given object, matched using @c isEqual:.
 
 @param anObject The object to be matched and located in the receiver.
 @return The index of the first object which is equal to @a anObject. If none of the objects in the receiver match @a anObject, returns @c NSNotFound.
 */
- (NSUInteger) indexOfObject:(id)anObject;

/**
 Returns the lowest index of a given object, matched using the == operator.
 
 @param anObject The object to be matched and located in the receiver.
 @return The index of the first object which is equal to @a anObject. If none of the objects in the receiver match @a anObject, returns @c NSNotFound.
 */
- (NSUInteger) indexOfObjectIdenticalTo:(id)anObject;

/**
 Compares the receiving linked list to another linked list. Two linked lists have equal contents if they each hold the same number of objects and objects at a given position in each linked list satisfy the \link NSObject-p#isEqual: -isEqual:\endlink test.
 
 @param otherLinkedList A linked list.
 @return @c YES if the contents of @a otherLinkedList are equal to the contents of the receiver, otherwise @c NO.
 */
- (BOOL) isEqualToLinkedList:(id<CHLinkedList>)otherLinkedList;

/**
 Returns the object located at @a index.
 
 @param index An index from which to retrieve an object.
 @return The object located at @a index.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see indexOfObject:
 @see indexOfObjectIdenticalTo:
 */
- (id) objectAtIndex:(NSUInteger)index;

/**
 Returns an enumerator that accesses each object in the receiver from front to back.
 
 @return An enumerator that accesses each object in the receiver from front to back. The enumerator returned is never @c nil; if the receiver is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
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
 Add an object to the receiver, inserted at the back.
 
 @param anObject The object to add to the receiver.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 @see lastObject
 @see prependObject:
 */
- (void) addObject:(id)anObject;

/**
 Adds the objects in a given array to the receiver, then re-establish the heap property. After all the objects have been inserted, objects are "heapified" as necessary, proceeding backwards from index @c count/2 down to @c 0.
 
 @param anArray An array of objects to add to the receiver.
 
 @see addObject:
 */
- (void) addObjectsFromArray:(NSArray*)anArray;

/**
 Exchange the objects in the receiver at given indexes.
 
 @param idx1 The index of the object to replace with the object at @a idx2.
 @param idx2 The index of the object to replace with the object at @a idx1.
 
 @throw NSRangeException if @a idx1 or @a idx2 exceeds the bounds of the receiver.
 
 @attention Index-oriented operations are generally slow in linked lists, which are not optimized for random access. Arrays are much faster for such functionality.
 
 @see indexOfObject:
 @see objectAtIndex:
 */
- (void) exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2;

/**
 Insert a given object at a given index. If @a index is already occupied, then objects at @a index and beyond are (conceptually) shifted one spot toward the end.
 
 @param anObject The object to add to the receiver.
 @param index The index at which to insert @a anObject.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see insertObjects:atIndexes:
 */
- (void) insertObject:(id)anObject atIndex:(NSUInteger)index;

/**
 Insert the objects in in a given array at the specified indexes in the receiver. Each object in @a objects is inserted into the receiver in turn at the corresponding location specified in @a indexes after earlier insertions have been made. The resulting behavior is the same as that exhibited by the same method in NSMutableArray.
 
 @param objects An array of objects to insert into the receiver at locations from @a indexes.
 @param indexes The indexes at which the objects in @a objects should be inserted.
 
 @throw NSInvalidArgumentException if @a objects or @a indexes is @c nil, or if <code>[objects count] != [indexes count]</code>.
 @throw NSRangeException if any index in @a indexes exceeds the bounds of the receiver.

 @see insertObject:atIndex:
 */
- (void) insertObjects:(NSArray *)objects atIndexes:(NSIndexSet *)indexes;

/**
 Add an object to the receiver, inserted at the front.
 
 @param anObject The object to add to the receiver.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 @see addObject:
 @see firstObject
 */
- (void) prependObject:(id)anObject;

/**
 Removes the first item in the receiver.
 
 @see firstObject
 @see removeLastObject
 */
- (void) removeFirstObject;

/**
 Remove the last item in the receiver.
 
 @see lastObject
 @see removeFirstObject
 */
- (void) removeLastObject;

/**
 Remove @b all occurrences of @a anObject, matched using @c isEqual:.
 
 @param anObject The object to remove from the receiver.
 
 If the receiver is empty, @a anObject is @c nil, or no object matching @a anObject is found, there is no effect, aside from the possible overhead of searching the contents.
 
 @note Use #indexOfObject: and #removeObjectAtIndex: to search for and remove only a specific match.
 
 @see containsObject:
 @see removeObjectIdenticalTo:
 */
- (void) removeObject:(id)anObject;

/**
 Remove the object at @a index. To fill the gap, elements beyond @a index have 1 subtracted from their index.
 
 @param index The index from which to remove the object.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 */
- (void) removeObjectAtIndex:(NSUInteger)index;

/**
 Remove @b all occurrences of @a anObject, matched using the == operator.
 
 @param anObject The object to remove from the receiver.
 
 If the receiver is empty, @a anObject is @c nil, or no object matching @a anObject is found, there is no effect, aside from the possible overhead of searching the contents.
 
 @note Use #indexOfObjectIdenticalTo: and #removeObjectAtIndex: to search for and remove only a specific match.
 
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
 Empty the receiver of all of its members.
 
 @see removeFirstObject
 @see removeLastObject
 @see removeObject:
 @see removeObjectIdenticalTo:
 */
- (void) removeAllObjects;

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
