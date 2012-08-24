/*
 CHDataStructures.framework -- CHDoublyLinkedList.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHLinkedList.h"

/**
 @file CHDoublyLinkedList.h
 A standard doubly-linked list implementation with pointers to head and tail.
 */

/** A struct for nodes in a CHDoublyLinkedList. */
typedef struct CHDoublyLinkedListNode {
	id object; ///< The object associated with this node in the list.
	__strong struct CHDoublyLinkedListNode *next; ///< Next node in the list.
	__strong struct CHDoublyLinkedListNode *prev; ///< Previous node in the list.
} CHDoublyLinkedListNode;

#pragma mark -

/**
 A standard doubly-linked list implementation with pointers to head and tail. The extra 'previous' link allows for reverse enumeration and cheaper removal for objects near the tail of the list. The tradeoff is a little extra storage in each list node and a little extra work when inserting and removing. Nodes are represented with C structs, providing much faster performance than Objective-C objects.
 
 The use of head and tail nodes allows for simplification of the algorithms for insertion and deletion, since the special cases of checking whether a node is the first or last in the list (and handling the next and previous pointers) are done away with. The figures below demonstrate what a doubly-linked list looks like when it contains 0 objects, 1 object, and 2 or more objects.
 
 @image html doubly-linked-0.png Figure 1 - Doubly-linked list with 0 objects.

 @image html doubly-linked-1.png Figure 2 - Doubly-linked list with 1 object.

 @image html doubly-linked-N.png Figure 3 - Doubly-linked list with 2+ objects.
 
 Just as with sentinel nodes used in binary search trees, the object pointer in the head and tail nodes can be nil or set to the value being searched for. This means there is no need to check whether the next node is null before moving on; just stop at the node whose object matches, then check after the match is found whether the node containing it was the head/tail or a valid internal node.
 
 The operations \link #insertObject:atIndex:\endlink and \link #removeObjectAtIndex:\endlink take advantage of the bi-directional links, and search from the closest possible point. To reduce code duplication, all methods that append or prepend objects call \link #insertObject:atIndex:\endlink, and the methods to remove the first or last objects use \link #removeObjectAtIndex:\endlink underneath.
 
 Doubly-linked lists are well-suited as an underlying collection for other data structures, such as a deque (double-ended queue) like the one declared in CHListDeque. The same functionality can be achieved using a circular buffer and an array, and many libraries choose to do so when objects are only added to or removed from the ends, but the dynamic structure of a linked list is much more flexible when inserting and deleting in the middle of a list.
 */
@interface CHDoublyLinkedList : NSObject <CHLinkedList>
{
	__strong CHDoublyLinkedListNode *head; // Dummy node at the front of the list.
	__strong CHDoublyLinkedListNode *tail; // Dummy node at the back of the list.
	__strong CHDoublyLinkedListNode *cachedNode; // Pointer to last accessed node.
	NSUInteger cachedIndex; // Index of last accessed node.
	NSUInteger count; // The number of objects currently in the list.
	unsigned long mutations; // Tracks mutations for NSFastEnumeration.
}

/**
 Returns an enumerator that accesses each object in the receiver from back to front.
 
 @return An enumerator that accesses each object in the receiver from back to front. The enumerator returned is never @c nil; if the receiver is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
 @attention The enumerator retains the collection. Once all objects in the enumerator have been consumed, the collection is released.
 @warning Modifying a collection while it is being enumerated is unsafe, and may cause a mutation exception to be raised.
 */
- (NSEnumerator*) reverseObjectEnumerator;

@end
