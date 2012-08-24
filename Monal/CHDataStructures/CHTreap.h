/*
 CHDataStructures.framework -- CHTreap.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHAbstractBinarySearchTree.h"

/**
 @file CHTreap.h
 A <a href="http://en.wikipedia.org/wiki/Treap">Treap</a> implementation of CHSearchTree.
 */

/**
 A <a href="http://en.wikipedia.org/wiki/Treap">Treap</a>, a balanced binary tree with O(log n) access in general, and improbable worst cases. The name "treap" is a portmanteau of "tree" and "heap", which is fitting since treaps exhibit properties of both binary search trees and heaps.
 
 Each node in a treap contains an object and a priority value, which may be arbitrarily-selected. Nodes in a treap are arranged such that the objects are ordered as in a binary search tree, and the priorities are ordered to obey the heap property (every node must have a higher priority than both its children). A sample treap is presented below, with priorities shown below the nodes.
 
 @image html treap-sample.png "Figure 1 - A sample treap with node priorities."
 
 Notice that, unlike a binary heap, a treap need not be a <i>complete tree</i>, which is a tree where every level is complete, with the possible exception of the lowest level, in which case any gaps must occur only on the level's right side. Also, the priority can be any numerical value (integer or floating point, positive or negative, signed or unsigned) as long as the range is large enough to accommodate the number of objects that may be added to the treap. Uniqueness of priority values is not strictly required, but it can help.
 
 Nodes are reordered to satisfy the heap property using rotations involving only two nodes, which change the position of children in the tree, but leave the subtrees unchanged. The rotation operations are mirror images of each other, and are shown below:
 
 @image html treap-rotations.png "Figure 2 - The effect of rotation operations."
 
 Since subtrees may be rotated to satisfy the heap property without violating the BST property, these two properties never conflict. In fact, for a given set of objects and unique priorities, there is only one treap structure that can satisfy both properties. In practice, when the priority for each node is truly random, the tree is relatively well balanced, with expected height of Θ(log n). Treap performance is extremely fast on average, with a small risk of slow performance in random worst cases, which tend to be quite rare in practice.
 
 Insertion is a cross between standard BST insertion and heap insertion: a new leaf node is created in the appropriate sorted location, and a random value is assigned. The path back to the root is then retraced, rotating the node upward as necessary until the new node's priority is greater than both its children's. Deletion is generally implemented by rotating the node to be removed down the tree until it becomes a leaf and can be clipped. At each rotation, the child whose priority is higher is rotated to become the root, and the node to delete descends the opposite subtree. (It is also possible to swap with the successor node as is common in BST deletion, but in order to preserve the tree's balance, the priorities should also be swapped, and the successor be bubbled up until the heap property is again satisfied, an approach quite similar to insertion.)
 
 This treap implementation adds two methods to those in the CHSearchTree protocol:
 - \link #addObject:withPriority: -addObject:withPriority:\endlink
 - \link #priorityForObject: -priorityForObject:\endlink
 
 Treaps were originally described in the following paper:
 
 <div style="margin: 0 25px; font-weight: bold;">
 R. Seidel and C. R. Aragon. "Randomized Search Trees." <em>Algorithmica</em>, 16(4/5):464-497, 1996.
 </div>
 
 (See <a href="http://sims.berkeley.edu/~aragon/pubs/rst89.pdf">PDF original</a>
 or <a href="http://www-tcs.cs.uni-sb.de/Papers/rst.ps">PostScript revision</a>)
 
 @todo Examine performance issues (treaps are often the slowest balanced tree).
 */
@interface CHTreap : CHAbstractBinarySearchTree

/** Priority when an object is not found in a treap (max value for u_int32_t). */
#define CHTreapNotFound UINT32_MAX

/**
 Add an object to the tree with a randomly-generated priority value. This encourages (but doesn't necessarily guarantee) well-balanced treaps. Random numbers are generated using @c arc4random and cast as an NSUInteger.
 
 @param anObject The object to add to the treap.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 @see #addObject:withPriority:
 */
- (void) addObject:(id)anObject;

/**
 Add an object to the treap using a given priority value. Ordering is based on an object's response to the @c -compare: message. Since no duplicates are allowed, if the tree already contains an object for which @c compare: returns @c NSOrderedSame, that object is released and replaced by @a anObject.
 
 @param anObject The object to add to the treap.
 @param priority The priority to assign to @a nObject. Higher values percolate to the top.
 @note Although @a priority is typed as NSUInteger (consistent with Foundation APIs), \link CHBinaryTreeNode CHBinaryTreeNode->priority\endlink is typed as @c u_int32_t, so the value stored is actually <code>priority % CHTreapNotFound</code>.
 
 @throw NSInvalidArgumentException if @a anObject is @c nil.
 
 If @a anObject already exists in the treap, @a priority replaces the existing priority, and the existing node is percolated up or down to maintain the heap property. Thus, this method can be used to manipulate the depth of an object. Using a specific priority value for an object allows the user to impose a heap ordering by giving higher priorities to objects that should bubble towards the top, and lower priorities to objects that should bubble towards the bottom. In theory, this makes it significantly faster to retrieve commonly searched-for items, at the possible cost of a less-balanced treap overall, depending on the mapping of priorities and the sorted order of the objects. Use with caution.
 */
- (void) addObject:(id)anObject withPriority:(NSUInteger)priority;

/**
 Returns the priority for @a anObject if it's in the treap, @c CHTreapNotFound otherwise.
 
 @param anObject The object for which to find the treap priority, if it exists.
 @return The priority for @a anObject if it is in the treap, @c CHTreapNotFound if it is @c nil or not present.
 */
- (NSUInteger) priorityForObject:(id)anObject;

@end
