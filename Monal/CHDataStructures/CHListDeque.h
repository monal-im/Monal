/*
 CHDataStructures.framework -- CHListDeque.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHDeque.h"
#import "CHAbstractListCollection.h"

/**
 @file CHListDeque.h
 A simple CHDeque implemented using a CHDoublyLinkedList.
 */

/**
 A simple CHDeque implemented using a CHDoublyLinkedList. A doubly-linked list is a natural choice since a deque supports insertion and removal at both ends (removing from the tail is O(n) in a singly-linked list, but O(1) in a doubly-linked list) and enumerating objects from back to front (hopelessly inefficient in a singly-linked list). The trade-offs for these benefits are marginally higher storage cost and marginally slower operations due to handling reverse links.
 */
@interface CHListDeque : CHAbstractListCollection <CHDeque>

@end
