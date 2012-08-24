/*
 CHDataStructures.framework -- CHBidirectionalDictionary.h
 
 Copyright (c) 2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHMutableDictionary.h"

/**
 A dictionary that allows bidirectional lookup by keys and values with equal ease. This is possible because a <a href="http://en.wikipedia.org/wiki/Bidirectional_map">bidirectional dictionary</a> enforces the restriction that there is a 1-to-1 relation between keys and values, meaning that multiple keys cannot map to the same value. This is accomplished using a second internal dictionary which stores value-to-key mappings so values can be checked for uniqueness upon insertion. (Since values become the keys in this secondary dictionary, values must also be unique.) See \link #setObject:forKey: -setObject:forKey:\endlink below for details.
 
 The main purpose of this constraint is to make it trivial to do bidirectional lookups of one-to-one relationships. A trivial example might be to store husband-wife pairs and look up by either, rather than choosing only one.
 
 There are two simple ways (equivalent in performance) to look up a key by it's value:
 - Call \link #keyForObject: -keyForObject:\endlink on a bidirectional dictionary.
 - Acquire the inverse dictionary via \link #inverseDictionary -inverseDictionary\endlink, then call \link #setObject:forKey: -objectForKey:\endlink on that.
 
 @attention Since values are used as keys in the inverse dictionary, both keys and values must conform to the NSCopying protocol. (NSDictionary requires that keys conform to NSCopying, but not values.) If they don't, a crash will result when this collection attempts to copy them.
 
 @warning If a dictionary is passed to \link NSDictionary#initWithDictionary: -initWithDictionary:\endlink which maps the same value to multiple keys, the value will be mapped to whichever key mapped to that value is enumerated last. Depending on the specifics of the dictionary, this ordering may be arbitrary.
 
 Implementations of bidirectional dictionaries (aka "maps") in other languages include the following:
 
 - <a href="http://google-collections.googlecode.com/svn/trunk/javadoc/index.html?com/google/common/collect/BiMap.html">BiMap</a> / <a href="http://commons.apache.org/collections/api-release/org/apache/commons/collections/BidiMap.html">BidiMap</a> (Java)
 - <a href="http://cablemodem.fibertel.com.ar/mcape/boost/libs/bimap/">Boost.Bimap</a> / <a href="http://www.codeproject.com/KB/stl/bimap.aspx">bimap</a> (C++)
 - <a href="http://www.go4expert.com/forums/showthread.php?t=1466">BiDirHashtable</a> (C#)
 */
@interface CHBidirectionalDictionary : CHMutableDictionary {
	__strong CFMutableDictionaryRef objectsToKeys; // Used for reverse mapping.
	CHBidirectionalDictionary* inverse; // Pointer to inverse dictionary.
}

#pragma mark Querying Contents
/** @name Querying Contents */
// @{

/**
 Returns the key associated with a given value.
 
 @param anObject The value for which to return the corresponding key.
 @return The key associated with @a value, or @c nil if no such key exists.
 
 @see \link NSDictionary#allKeys -allKeys\endlink
 @see \link NSDictionary#objectForKey: -objectForKey:\endlink
 @see removeKeyForObject:
 */
- (id) keyForObject:(id)anObject;

/**
 Returns the inverse view of the receiver, which maps each value to its associated key. The receiver and its inverse are backed by the same data; any changes to one will appear in the other. A reference to the inverse (if one exists) is stored internally, and vice versa, so the two instances are linked. If one is released, it will cut its ties to and from the other.
 
 @return The inverse view of the receiver,
 
 @attention There is no guaranteed correspondence between the order in which keys are enumerated for a dictionary and its inverse.
 */
- (CHBidirectionalDictionary*) inverseDictionary;

// @}
#pragma mark Modifying Contents
/** @name Modifying Contents */
// @{

/**
 Adds the entries from another dictionary to the receiver. Keys and values are copied as described in #setObject:forKey: below. If a key or value already exists in the receiver, the existing key-value mapping is replaced.
 
 @param otherDictionary The dictionary from which to add entries. All its keys @b and values must conform to the NSCopying protocol.
 
 @attention If @a otherDictionary maps the same value to multiple keys, the value can only appear once in the receiver, and will be mapped to the key that is enumerated @b last, which may be arbitrary. However, if @a otherDictionary is also a CHBidirectionalDictionary, the results will always be deterministic.
 
 @see \link NSDictionary#initWithDictionary: -initWithDictionary:\endlink
 @see setObject:forKey:
 */
- (void) addEntriesFromDictionary:(NSDictionary*)otherDictionary;

/**
 Removes the key for a given value (and its inverse key-value mapping) from the receiver. Does nothing if the specified value doesn't exist.
 
 @param anObject The value to remove.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 @see keyForObject:
 @see removeObjectForKey:
 */
- (void) removeKeyForObject:(id)anObject;

/**
 Removes the value for a given key (and its inverse value-key mapping) from the receiver. Does nothing if the specified key doesn't exist.

 @param aKey The key to remove.
 
 @throw NSInvalidArgumentException if @a aKey is @c nil.
 
 @see \link NSDictionary#objectForKey: -objectForKey:\endlink
 @see removeKeyForObject:
 */
- (void) removeObjectForKey:(id)aKey;

/**
 Adds a given key-value pair to the receiver, replacing any existing pair with the given key or value.
 
 @param anObject The value for @a aKey. The object is copied, so it @b must conform to the NSCopying protocol or a crash will result.
 @param aKey The key for @a anObject. The key is copied, so it @b must conform to the NSCopying protocol or a crash will result.
 
 @throw NSInvalidArgumentException if @a aKey or @a anObject is @c nil. If you need to represent a nil value in the dictionary, use NSNull.
 
 @attention If @a aKey already exists in the receiver, the value previously associated with it is replaced by @a anObject, just as expected. However, if @a anObject already exists in the reciever with a different key, that mapping is removed to ensure that @a anObject only occurs once in the inverse dictionary. To check whether this will occur, call #keyForObject: first.
 
 @b Example:
 @code
 id dict = [[CHBidirectionalDictionary alloc] init];
 [dict setObject:@"B" forKey:@"A"]; // now contains A -> B
 [dict setObject:@"C" forKey:@"A"]; // now contains A -> C
 [dict setObject:@"C" forKey:@"B"]; // now contains B -> C
 // Values must be unique just like keys, so A -> C is removed
 [dict setObject:@"D" forKey:@"A"]; // now contains B -> C, A -> D
 @endcode
 
 @see keyForObject:
 @see \link NSDictionary#objectForKey: -objectForKey:\endlink
 */
- (void) setObject:(id)anObject forKey:(id)aKey;

// @}
@end
