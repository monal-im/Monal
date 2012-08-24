/*
 CHDataStructures.framework -- CHListQueue.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHQueue.h"
#import "CHAbstractListCollection.h"

/**
 @file CHListQueue.h
 A simple CHQueue implemented using a CHSinglyLinkedList.
 */

/**
 A simple CHQueue implemented using a CHSinglyLinkedList. A singly-linked list is a natural choice since a queue can only insert at one end (the back) and remove at the other end (the front). Since CHSinglyLinkedList tracks the tail node, both of these operations are O(1). Other queue operations generally only proceed from front to back, so the lack of reverse pointers is not problematic, and each object requires less storage space.
 */
@interface CHListQueue : CHAbstractListCollection <CHQueue>

@end
