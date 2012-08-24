/*
 CHDataStructures.framework -- CHOrderedDictionary.h
 
 Copyright (c) 2009-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHMutableDictionary.h"

/**
 @file CHOrderedDictionary.h
 
 A dictionary which enumerates keys in the order in which they are inserted.
 */

/**
 A dictionary which enumerates keys in the order in which they are inserted. The following additional operations are provided to take advantage of the ordering:
   - \link #firstKey\endlink
   - \link #lastKey\endlink
   - \link #keyAtIndex:\endlink
   - \link #reverseKeyEnumerator\endlink
 
 Key-value entries are inserted just as in a normal dictionary, including replacement of values for existing keys, as detailed in \link #setObject:forKey: -setObject:forKey:\endlink. However, an additional structure is used in parallel to track insertion order, and keys are enumerated in that order. If a key to be added does not currently exist in the dictionary, it is added to the end of the list, otherwise the insertion order of the key does not change.

 Implementations of insertion-ordered dictionaries (aka "maps") in other languages include the following:
 
 - <a href="http://java.sun.com/javase/6/docs/api/java/util/LinkedHashMap.html">LinkedHashMap</a> / <a href="http://commons.apache.org/collections/apidocs/org/apache/commons/collections/map/LinkedMap.html">LinkedMap</a> (Java)
 - <a href="http://sano.luaforge.net/documentation/LinkedMap.html">LinkedMap</a> (Lua)
 - <a href="http://www.python.org/dev/peps/pep-0372/">OrderedDict</a> (Python)
 - <a href="http://msdn.microsoft.com/en-us/library/system.collections.specialized.ordereddictionary.aspx">OrderedDictionary</a> (.NET)
 - <a href="http://codeendeavor.com/gsdocs/net/guttershark/util/collections/OrderedDictionary.html">OrderedDictionary</a> (Flash)
 
 @note Any method inherited from NSDictionary or NSMutableDictionary is supported, but only overridden methods are listed here.
 
 @see CHOrderedSet
 */
@interface CHOrderedDictionary : CHMutableDictionary {
	id keyOrdering;
}

#pragma mark Querying Contents
/** @name Querying Contents */
// @{

/**
 Returns the first key in the receiver, according to insertion order.
 
 @return The first key in the receiver, or @c nil if the receiver is empty.
 
 @see keyAtIndex:
 @see lastKey
 */
- (id) firstKey;

/**
 Returns the last key in the receiver, according to insertion order.
 
 @return The last key in the receiver, or @c nil if the receiver is empty.
 
 @see firstKey
 @see keyAtIndex:
 */
- (id) lastKey;

/**
 Returns the index of a given key based on insertion order.
 
 @param aKey The key to search for in the receiver.
 @return The index of @a akey based on insertion order. If the key does not exist in the receiver, @c NSNotFound is returned.
 
 @see firstKey
 @see keyAtIndex:
 @see lastKey
 */
- (NSUInteger) indexOfKey:(id)aKey;

/**
 Returns the key at the specified index, based on insertion order.
 
 @param index The insertion-order index of the key to retrieve.
 @return The key at the specified index, based on insertion order.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see \link NSDictionary#containsKey: -containsKey:\endlink
 @see firstKey
 @see indexOfKey:
 @see lastKey
 */
- (id) keyAtIndex:(NSUInteger)index;

/**
 Returns an array containing the keys in the receiver at the indexes specified by a given index set.
 
 @param indexes A set of positions corresponding to keys to retrieve from the receiver.
 @return A new array containing the keys in the receiver specified by @a indexes.
 
 @throw NSRangeException if any location in @a indexes exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a indexes is @c nil.
 
 @see \link NSDictionary#allKeys -allKeys\endlink
 @see orderedDictionaryWithKeysAtIndexes:
 */
- (NSArray*) keysAtIndexes:(NSIndexSet*)indexes;

/**
 Returns the value for the key at the specified index, based on insertion order.
 
 @param index The insertion-order index of the key for the value to retrieve.
 @return The value for the key at the specified index, based on insertion order.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see indexOfKey:
 @see keyAtIndex:
 @see \link NSDictionary#objectForKey: -objectForKey:\endlink
 @see removeObjectForKeyAtIndex:
 */
- (id) objectForKeyAtIndex:(NSUInteger)index;

/**
 Returns the set of objects from the receiver corresponding to the keys at the indexes specified by a given index set.
 
 @param indexes A set of positions corresponding to objects to retrieve from the receiver.
 @return A new array containing the objects in the receiver for the keys specified by @a indexes.

 @throw NSRangeException if any location in @a indexes exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a indexes is @c nil.
 
 @see keysAtIndexes:
 @see \link NSDictionary#objectsForKeys:notFoundMarker: -objectsForKeys:notFoundMarker:\endlink
 @see removeObjectsForKeysAtIndexes:
 */
- (NSArray*) objectsForKeysAtIndexes:(NSIndexSet*)indexes;

/**
 Returns an ordered dictionary containing the entries in the receiver with keys at the indexes specified by a given index set.
 
 @param indexes A set of indexes for keys to retrieve from the receiver.
 @return An array containing the entries in the receiver at the indexes specified by @a indexes.
 
 @throw NSRangeException if any location in @a indexes exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a indexes is @c nil.
 
 @attention To retrieve entries in a given NSRange, pass <code>[NSIndexSet indexSetWithIndexesInRange:range]</code> as the parameter.
 */
- (CHOrderedDictionary*) orderedDictionaryWithKeysAtIndexes:(NSIndexSet*)indexes;

/**
 Returns an enumerator that lets you access each key in the receiver in reverse order.
 
 @return An enumerator that lets you access each key in the receiver in reverse order. The enumerator returned is never @c nil; if the dictionary is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
 @attention The enumerator retains the collection. Once all objects in the enumerator have been consumed, the collection is released.
 @warning Modifying a collection while it is being enumerated is unsafe, and may cause a mutation exception to be raised.
 
 @note If you need to modify the entries concurrently, use \link NSDictionary#allKeys -allKeys\endlink to create a "snapshot" of the dictionary's keys and work from this snapshot to modify the entries.
 
 @see \link NSDictionary#allKeys -allKeys\endlink
 @see \link NSDictionary#allKeysForObject: -allKeysForObject:\endlink
 @see NSFastEnumeration protocol
 */
- (NSEnumerator*) reverseKeyEnumerator;

// @}
#pragma mark Modifying Contents
/** @name Modifying Contents */
// @{

/**
 Exchange the keys in the receiver at given indexes.
 
 @param idx1 The index of the key to replace with the key at @a idx2.
 @param idx2 The index of the key to replace with the key at @a idx1.
 
 @throw NSRangeException if @a idx1 or @a idx2 exceeds the bounds of the receiver.
 
 @see indexOfKey:
 @see keyAtIndex:
 */
- (void) exchangeKeyAtIndex:(NSUInteger)idx1 withKeyAtIndex:(NSUInteger)idx2;

/**
 Adds a given key-value pair to the receiver, with the key at a given index in the ordering.
 
 @param anObject The value for @a aKey. The object receives a @c -retain message before being added to the receiver. Must not be @c nil.
 @param aKey The key for @a anObject. The key is copied using @c -copyWithZone: so keys must conform to the NSCopying protocol. Must not be @c nil.
 @param index The index in the receiver's key ordering at which to insert @a anObject.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a aKey or @a anObject is @c nil.  If you need to represent a @c nil value in the dictionary, use NSNull.
 
 @see indexOfKey:
 @see keyAtIndex:
 @see setObject:forKey:
 */
- (void) insertObject:(id)anObject forKey:(id)aKey atIndex:(NSUInteger)index;

/**
 Removes the key at a given index from the receiver. Elements on the non-wrapped end of the buffer are shifted one spot to fill the gap.
 
 @param index The index of the key to remove.
 
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see indexOfKey:
 @see keyAtIndex:
 @see objectForKeyAtIndex:
 @see \link NSMutableDictionary#removeObjectForKey: -removeObjectForKey:\endlink
 */
- (void) removeObjectForKeyAtIndex:(NSUInteger)index;

/**
 Removes the keys at the specified indexes from the receiver. This method is similar to #removeObjectForKeyAtIndex: but allows you to efficiently remove multiple keys with a single operation.
 
 @param indexes The indexes of the keys to remove from the receiver.
 
 @throw NSRangeException if any location in @a indexes exceeds the bounds of the receiver.
 @throw NSInvalidArgumentException if @a indexes is @c nil.
 
 @see objectsForKeysAtIndexes:
 @see removeObjectForKeyAtIndex:
 */
- (void) removeObjectsForKeysAtIndexes:(NSIndexSet*)indexes;

/**
 Adds a given key-value pair to the receiver, with the key added at the end of the ordering.
 
 @param anObject The value for @a aKey. The object receives a @c -retain message before being added to the receiver. Must not be @c nil.
 @param aKey The key for @a anObject. The key is copied using @c -copyWithZone: so keys must conform to the NSCopying protocol. Must not be @c nil.
 
 @see insertObject:forKey:atIndex:
 @see setObject:forKeyAtIndex:
 */
- (void) setObject:(id)anObject forKey:(id)aKey;

/**
 Sets the value for the key at the specified index in the receiver.
 
 @param anObject The new value to be set for the key at @a index. The object receives a @c -retain message before being added to the receiver. Must not be @c nil.
 @param index The index of the key for which to set the value.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil. If you need to represent a @c nil value in the dictionary, use NSNull.
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 
 @see insertObject:forKey:atIndex:
 @see setObject:forKey:
 */
- (void) setObject:(id)anObject forKeyAtIndex:(NSUInteger)index;

// @}
@end
