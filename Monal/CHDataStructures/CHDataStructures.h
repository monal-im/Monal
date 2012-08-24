/*
 CHDataStructures.framework -- CHDataStructures.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import <Foundation/Foundation.h>

// Protocols
#import "CHDeque.h"
#import "CHHeap.h"
#import "CHLinkedList.h"
#import "CHQueue.h"
#import "CHSearchTree.h"
#import "CHSortedSet.h"
#import "CHStack.h"

// Concrete Implementations
#import "CHAnderssonTree.h"
#import "CHBidirectionalDictionary.h"
#import "CHBinaryHeap.h"
#import "CHAVLTree.h"
#import "CHCircularBuffer.h"
#import "CHCircularBufferDeque.h"
#import "CHCircularBufferQueue.h"
#import "CHCircularBufferStack.h"
#import "CHDoublyLinkedList.h"
#import "CHListDeque.h"
#import "CHListQueue.h"
#import "CHListStack.h"
#import "CHMultiDictionary.h"
#import "CHMutableArrayHeap.h"
#import "CHOrderedDictionary.h"
#import "CHOrderedSet.h"
#import "CHRedBlackTree.h"
#import "CHSinglyLinkedList.h"
#import "CHSortedDictionary.h"
#import "CHTreap.h"
#import "CHUnbalancedTree.h"

// Utilities
#import "Util.h"

/**
 @file CHDataStructures.h
 
 An umbrella header which imports all the public header files for the framework. Headers for individual classes have minimal dependencies, and they import any other header files they may require. For example, this header does not import any of the CHAbstract... header files (since only subclasses use them), but all such headers are still included with the framework. (The protocols for abstract data types are imported so clients can use protocol-typed variables if needed.)
 */

/**
 @mainpage Overview

 <strong>CHDataStructures.framework</strong> <http://cocoaheads.byu.edu/code/CHDataStructures> is an open-source library of standard data structures which can be used in any Objective-C program, for educational purposes or as a foundation for other data structures to build on. Data structures in this framework adopt Objective-C protocols that define the functionality of and API for interacting with any implementation thereof, regardless of its internals.
 
 Apple's extensive and flexible <a href="http://developer.apple.com/cocoa/">Cocoa frameworks</a> include several collections classes that are highly optimized and amenable to many situations. However, sometimes an honest-to-goodness stack, queue, linked list, tree, etc. can greatly improve the clarity and comprehensibility of code. This framework provides Objective-C implementations of common data structures which are currently beyond the purview of Cocoa.
 
 The abstract data type protocols include:
 - CHDeque
 - CHHeap
 - CHLinkedList
 - CHQueue
 - CHSearchTree
 - CHSortedSet
 - CHStack
 
 The concrete child classes of NSMutableArray include:
 - CHCircularBuffer
	 - CHCircularBufferDeque
	 - CHCircularBufferQueue
	 - CHCircularBufferStack
 - CHMutableArrayHeap
 
 The concrete child classes of NSMutableDictionary include:
 - CHMutableDictionary
	 - CHBidirectionalDictionary
	 - CHMultiDictionary
	 - CHOrderedDictionary
	 - CHSortedDictionary
 
 The concrete child classes of NSMutableSet include:
 - CHMutableSet
	 - CHOrderedSet
 
 The code is written for Cocoa applications and does use some features of <a href="http://developer.apple.com/documentation/Cocoa/Conceptual/ObjectiveC/">Objective-C 2.0</a>, which is present in Mac OS X 10.5+ and all versions of iOS. Most of the code could be ported to other Objective-C environments (such as <a href="http://www.gnustep.org">GNUStep</a>) without too much trouble. However, such efforts would probably be better accomplished by forking this project rather than integrating with it, for several main reasons:
 
 <ol>
 <li>Supporting multiple environments increases code complexity, and consequently the effort required to test, maintain, and improve it.</li>
 <li>Libraries that have bigger and slower binaries to accommodate all possible platforms don't help the mainstream developer.</li>
 <li>Apple is the de facto custodian and strongest proponent of Objective-C, a trend which isn't likely to change soon.</li>
 </ol>
 
 While certain implementations utilize straight C for their internals, this framework exposes fairly high-level APIs, and uses composition rather than inheritance wherever it makes sense. The framework was originally created as an exercise in writing Objective-C code and consisted mainly of ported Java code. In later revisions, performance has gained greater emphasis, but the primary motivation is to provide friendly, intuitive Objective-C interfaces for data structures, not to maximize speed at any cost, which sometimes happens with C++ and the STL. The algorithms should all be sound (i.e., you won't get O(n) performance where it should be O(log n) or O(1), etc.) and perform quite well in general. If your choice of data structure type and implementation are dependent on performance or memory usage, it would be wise to run the benchmarks from Xcode and choose based on the time and memory complexity for specific implementations.
 
 This framework is released under a variant of the <a href="http://www.isc.org/software/license">ISC license</a>, an extremely simple and permissive free software license (functionally equivalent to the <a href="http://opensource.org/licenses/mit-license">MIT license</a> and two-clause <a href="http://opensource.org/licenses/bsd-license">BSD license</a>) approved by the <a href="http://opensource.org/licenses/isc-license">Open Source Initiative (OSI)</a> and recognized as GPL-compatible by the <a href="http://www.gnu.org/licenses/license-list.html#ISC">GNU Project</a>. The license is included in every source file, and is reproduced in its entirety here:
 
 <div style="margin: 0 30px; text-align: justify;"><em>Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.<br><br>The software is provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.</em></div>
 
 Earlier versions of this framework were released under a <a href="http://www.gnu.org/copyleft/">copyleft license</a>, which are generally unfriendly towards commercial software development.
 
 If you would like to contribute to the library or let me know that you use it, please <a href="mailto:quinntaylor@mac.com?subject=CHDataStructures.framework">email me</a>. I am very receptive to help, criticism, flames, whatever.
 
   &mdash; <a href="http://homepage.mac.com/quinntaylor/">Quinn Taylor</a>
 
 <hr>
 
 @todo Add support for NSSortDescriptor for comparator-style sorting. (Currently, all implementations use -compare: for sorting.)
 
 @todo Consider implementing "versionable" <a href="http://en.wikipedia.org/wiki/Persistent_data_structure">persistent data structures</a>, wherein concurrent enumeration and modification are supported via tagged versions of the structure. (An example of this for red-black trees is an exercise for the reader in "Introduction to Algorithms, 2nd Edition" (ISBN: <a href="http://isbn.nu/9780262032933">9780262032933</a>) in problem 13.1, pages 294-295.) The best candidates are probably queues, heaps, and search trees (sorted sets).
 
 @todo Look at adding @c -filterUsingPredicate: to all data structures. This would allow applying an NSPredicate and removing only objects that don't match. Also add copying variants (@c -filteredQueueUsingPredicate:, @c -filteredSortedSetUsingPredicate:, etc.) to avoid the overhead of a full copy before filtering.
 
 @todo Examine feasibility and utility of implementing key-value observing/coding/binding.
 */
