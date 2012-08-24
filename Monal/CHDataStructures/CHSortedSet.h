/*
 CHDataStructures.framework -- CHSortedSet.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "Util.h"

/**
 @file CHSortedSet.h
 
 A protocol which specifes an interface for sorted sets.
 */

/**
 These constants are passed to \link CHSortedSet#subsetFromObject:toObject:options: -[CHSortedSet subsetFromObject:toObject:options:]\endlink and affect how the subset is constructed. You can pass 0 to use the default behavior.
 */
typedef enum {
	/** Indicates that a subset should exclude the low endpoint if it is not nil. */
	CHSubsetExcludeLowEndpoint  = 1 << 0,
	/** Indicates that a subset should exclude the high endpoint if it is not nil. */
	CHSubsetExcludeHighEndpoint = 1 << 1
} CHSubsetConstructionOptions;

/**
 A protocol which specifes an interface for sorted sets.
 
 A <strong>sorted set</strong> is a <a href="http://en.wikipedia.org/wiki/Set_(computer_science)">set</a> that further provides a <em>total ordering</em> on its elements. This protocol defines sorted set methods for insertion, removal, search, and object enumeration. Though any conforming class must implement all these methods, they may document that certain of them are unsupported, and/or raise exceptions when they are called.
 
 In a sorted set, objects are inserted according to their sorted order, so they must respond to the @c -compare: selector, which accepts another object and returns @c NSOrderedAscending, @c NSOrderedSame, or @c NSOrderedDescending (constants in <a href="http://tinyurl.com/NSComparisonResult">NSComparisonResult</a>) as the receiver is less than, equal to, or greater than the argument, respectively. (Several Cocoa classes already implement the @c -compare: method, including NSString, NSDate, NSNumber, NSDecimalNumber, and NSCell.)
 
 Java includes a <a href="http://java.sun.com/javase/6/docs/api/java/util/SortedSet.html">SortedSet</a> interface as part of the <a href="http://java.sun.com/javase/6/docs/technotes/guides/collections/">Java Collections Framework</a>. Many other programming languages also have sorted sets, most commonly implemented as <a href="http://en.wikipedia.org/wiki/Binary_search_tree">binary search trees</a>.
 
 @see CHSearchTree
 @see CHSortedDictionary

 @todo Add more operations similar to those supported by NSSet and NSMutableSet, such as:
	- <code>- (NSArray*) allObjectsFilteredUsingPredicate:</code>
	- <code>- (void) filterUsingPredicate:</code>
	- <code>- (BOOL) isEqualToSortedSet:</code>
	- <code>- (BOOL) isSubsetOfSortedSet:</code>
	- <code>- (BOOL) intersectsSet:</code>
	- <code>- (void) intersectSet:</code>
	- <code>- (void) minusSet:</code>
	- <code>- (void) unionSet:</code>
 
 @todo Consider adding other possible sorted set implementations, such as <a href="http://en.wikipedia.org/wiki/Skip_list">skip lists</a>, <a href="http://www.concentric.net/~Ttwang/tech/sorthash.htm">sorted linear hash sets</a>, and <a href="http://code.activestate.com/recipes/230113/">sorted lists</a>.

 */
@protocol CHSortedSet <NSObject, NSCoding, NSCopying, NSFastEnumeration>

/**
 Initialize a sorted set with no objects.
 
 @return An initialized sorted set that contains no objects.
 
 @see initWithArray:
 */
- (id) init;

/**
 Initialize a sorted set with the contents of an array. Objects are added to the set in the order they occur in the array.
 
 @param anArray An array containing objects with which to populate a new sorted set.
 @return An initialized sorted set that contains the objects in @a anArray in sorted order.
 */
- (id) initWithArray:(NSArray*)anArray;

#pragma mark Querying Contents
/** @name Querying Contents */
// @{

/**
 Returns an NSArray containing the objects in the receiver in ascending order.
 
 @return An array containing the objects in the receiver. If the receiver is empty, the array is also empty.
 
 @see anyObject
 @see count
 @see objectEnumerator
 @see removeAllObjects
 @see set
 */
- (NSArray*) allObjects;

/**
 Returns one of the objects in the receiver, or @c nil if the receiver contains no objects. The object returned is chosen at the receiver's convenience; the selection is not guaranteed to be random.
 
 @return An arbitrarily-selected object from the receiver, or @c nil if the receiver is empty.
 
 @see allObjects
 @see firstObject
 @see lastObject
 */
- (id) anyObject;

/**
 Returns the number of objects currently in the receiver.
 
 @return The number of objects currently in the receiver.
 
 @see allObjects
 */
- (NSUInteger) count;

/**
 Determine whether a given object is present in the receiver.
 
 @param anObject The object to test for membership in the receiver.
 @return @c YES if the receiver contains @a anObject (as determined by \link NSObject-p#isEqual: -isEqual:\endlink), @c NO if @a anObject is @c nil or not present.
 
 @attention To test whether the matching object is identical to @a anObject, compare @a anObject with the value returned from #member: using the == operator.
 
 @see member:
 @see set
 */
- (BOOL) containsObject:(id)anObject;

/**
 Returns the minimum object in the receiver, according to natural sorted order.
 
 @return The minimum object in the receiver, or @c nil if the receiver is empty.
 
 @see anyObject
 @see lastObject
 @see removeFirstObject
 */
- (id) firstObject;

/**
 Compares the receiving sorted set to another sorted set. Two sorted sets have equal contents if they each hold the same number of objects and objects at a given position in each sorted set satisfy the \link NSObject-p#isEqual: -isEqual:\endlink test.
 
 @param otherSortedSet A sorted set.
 @return @c YES if the contents of @a otherSortedSet are equal to the contents of the receiver, otherwise @c NO.
 */
- (BOOL) isEqualToSortedSet:(id<CHSortedSet>)otherSortedSet;

/**
 Returns the maximum object in the receiver, according to natural sorted order.
 
 @return The maximum object in the receiver, or @c nil if the receiver is empty.
 
 @see addObject:
 @see anyObject
 @see firstObject
 @see removeLastObject
 */
- (id) lastObject;

/**
 Determine whether the receiver contains a given object, and returns the object if present.
 
 @param anObject The object to test for membership in the receiver.
 @return If the receiver contains an object equal to @a anObject (as determined by \link NSObject-p#isEqual: -isEqual:\endlink) then that object (typically this will be @a anObject) is returned, otherwise @c nil.
 
 @attention If you override \link NSObject-p#isEqual: -isEqual:\endlink for a custom class, you must also override \link NSObject-p#hash -hash\endlink for #member: to work correctly on objects of your class.

 @see containsObject:
 @see set
 */
- (id) member:(id)anObject;

/**
 Returns an enumerator that accesses each object in the receiver in ascending order.
 
 @return An enumerator that accesses each object in the receiver in ascending order. The enumerator returned is never @c nil; if the receiver is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
 @attention The enumerator retains the collection. Once all objects in the enumerator have been consumed, the collection is released.
 @warning Modifying a collection while it is being enumerated is unsafe, and may cause a mutation exception to be raised.
 
 @see allObjects
 @see reverseObjectEnumerator
 */
- (NSEnumerator*) objectEnumerator;

/**
 Returns an enumerator that accesses each object in the receiver in descending order.
 
 @return An enumerator that accesses each object in the receiver in descending order. The enumerator returned is never @c nil; if the receiver is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
 @attention The enumerator retains the collection. Once all objects in the enumerator have been consumed, the collection is released.
 @warning Modifying a collection while it is being enumerated is unsafe, and may cause a mutation exception to be raised.
 
 @see objectEnumerator
 */
- (NSEnumerator*) reverseObjectEnumerator;

/**
 Returns an (autoreleased) NSSet object containing the objects in the receiver. This is an alternative to @c -allObjects, which returns the objects in sorted order. Returning an unordered set may be more efficient for the receiver, and thus preferable when the caller doesn't care about ordering, such as for fast tests of membership.
 
 @return An (autoreleased) NSSet object containing the objects in the receiver. The receiver may choose to return a mutable subclass if desired, since the objects may be stored internally using a different data structure. (For example, CHSearchTree implementations store elements in custom nodes, not an NSSet or subclass thereof.)
 
 @see allObjects
 @see objectEnumerator
 */
- (NSSet*) set;

/**
 Returns a new sorted set containing the objects delineated by two given objects. The subset is a shallow copy (new memory is allocated for the structure, but the copy points to the same objects) so any changes to the objects in the subset affect the receiver as well. The subset is an instance of the same class as the receiver.
 
 @param start Low endpoint of the subset to be returned; need not be present in the set.
 @param end High endpoint of the subset to be returned; need not be present in the set.
 @param options A combination of @c CHSubsetConstructionOptions values that specifies how to construct the subset. Pass 0 for the default behavior, or one or more options combined with a bitwise OR to specify different behavior.
 @return A new sorted set containing the objects delineated by @a start and @a end. The contents of the returned subset depend on the input parameters as follows:
 - If both @a start and @a end are @c nil, all objects in the receiver are included. (Equivalent to calling @c -copy.)
 - If only @a start is @c nil, objects that match or follow @a start are included.
 - If only @a end is @c nil, objects that match or preceed @a start are included.
 - If @a start comes before @a end in an ordered set, objects between @a start and @a end (or which match either object) are included.
 - Otherwise, all objects @b except those that fall between @a start and @a end are included.
 */
- (id<CHSortedSet>) subsetFromObject:(id)start
							toObject:(id)end
							 options:(CHSubsetConstructionOptions)options;

// @}
#pragma mark Modifying Contents
/** @name Modifying Contents */
// @{

/**
 Adds a given object to the receiver, if the object is not already a member.
 
 Ordering is based on an object's response to the @c -compare: message. Since no duplicates are allowed, if the receiver already contains an object for which a @c -compare: message returns @c NSOrderedSame, that object is released and replaced by @a anObject.
 
 @param anObject The object to add to the receiver.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 @see addObjectsFromArray:
 */
- (void) addObject:(id)anObject;

/**
 Adds to the receiver each object in a given array, if the object is not already a member.
 
 Ordering is based on an object's response to the @c -compare: message. Since no duplicates are allowed, if the receiver already contains an object for which a @c -compare: message returns @c NSOrderedSame, that object is released and replaced by the matching object from @a anArray.
 
 @param anArray An array of objects to add to the receiver.
 
 @see addObject:
 @see lastObject
 */
- (void) addObjectsFromArray:(NSArray*)anArray;

/**
 Remove all objects from the receiver; if the receiver is already empty, there is no effect.
 
 @see allObjects
 @see removeFirstObject
 @see removeLastObject
 @see removeObject:
 */
- (void) removeAllObjects;

/**
 Remove the minimum object from the receiver, according to natural sorted order.
 
 @see firstObject
 @see removeLastObject
 @see removeObject:
 */
- (void) removeFirstObject;

/**
 Remove the maximum object from the receiver, according to natural sorted order.
 
 @see lastObject
 @see removeFirstObject
 @see removeObject:
 */
- (void) removeLastObject;

/**
 Remove the object for which @c -compare: returns @c NSOrderedSame from the receiver. If no matching object exists, there is no effect.
 
 @param anObject The object to be removed from the receiver.
 
 If the receiver is empty, @a anObject is @c nil, or no object matching @a anObject is found, there is no effect, aside from the possible overhead of searching the contents.
 
 @see containsObject:
 @see removeAllObjects
 */
- (void) removeObject:(id)anObject;

// @}
@end
