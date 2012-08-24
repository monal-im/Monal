/*
 CHDataStructures.framework -- CHSearchTree.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHSortedSet.h"

/**
 @file CHSearchTree.h
 
 A protocol which specifes an interface for N-ary search trees.
 */

/**
 A set of constant values denoting the order in which to traverse a tree structure. For details, see: http://en.wikipedia.org/wiki/Tree_traversal#Traversal_methods
 */
typedef enum {
	CHTraverseAscending,   ///< Visit left subtree, node, then right subtree.
	CHTraverseDescending,  ///< Visit right subtree, node, then left subtree.
	CHTraversePreOrder,    ///< Visit node, left subtree, then right subtree.
	CHTraversePostOrder,   ///< Visit left subtree, right subtree, then node.
	CHTraverseLevelOrder   ///< Visit nodes from left-right, top-bottom.
} CHTraversalOrder;

#define isValidTraversalOrder(o) (o>=CHTraverseAscending && o<=CHTraverseLevelOrder)

/**
 A protocol which specifes an interface for search trees, such as standard <a href="http://en.wikipedia.org/wiki/Binary_search_tree">binary trees</a>, <a href="http://en.wikipedia.org/wiki/B-tree">B-trees</a>, N-ary trees, or any similar tree-like structure. This protocol extends the CHSortedSet protocol with two additional methods (\link #allObjectsWithTraversalOrder:\endlink and \link #objectEnumeratorWithTraversalOrder:\endlink) specific to search tree implementations of a sorted set.
 
 Trees have a hierarchical structure and make heavy use of pointers to child nodes to organize information. There are several methods for visiting each node in a tree data structure, known as <a href="http://en.wikipedia.org/wiki/Tree_traversal">tree traversal</a> techniques. (Traversal applies to N-ary trees, not just binary trees.) Whereas linked lists and arrays have one or two logical means of stepping through the elements, because trees are branching structures, there are many different ways to choose how to visit all of the nodes. There are 5 most commonly-used tree traversal methods (4 are depth-first, 1 is breadth-first) which are shown below. Table 1 shows the results enumerating the nodes in Figure 1 using each traversal and includes the constant associated with each. These constants can be passed to \link #allObjectsWithTraversalOrder:\endlink or \link #objectEnumeratorWithTraversalOrder:\endlink to enumerate objects from a search tree in a specified order. (Both \link #allObjects\endlink and \link #objectEnumerator\endlink use @c CHTraverseAscending; \link #reverseObjectEnumerator\endlink uses @c CHTraverseDescending.)
 
 <table align="center" width="100%" border="0" cellpadding="0">
 <tr>
 <td style="vertical-align: bottom">
 @image html tree-traversal.png "Figure 1 — A sample binary search tree."
 </td>
 <td style="vertical-align: bottom" align="center">
 
 <table style="border-collapse: collapse;" border="1" cellpadding="3">
 <tr style="background: #ddd;">
     <th>Traversal</th>     <th>Visit Order</th> <th>Node Ordering</th>                  <th>CHTraversalOrder</th>
 </tr>
 <tr><td>In-order</td>      <td>L, node, R</td>  <td><code>A B C D E F G H I</code></td> <td>CHTraverseAscending</td></tr>
 <tr><td>Reverse-order</td> <td>R, node, L</td>  <td><code>I H G F E D C B A</code></td> <td>CHTraverseDescending</td></tr>
 <tr><td>Pre-order</td>     <td>node, L, R</td>  <td><code>F B A D C E G I H</code></td> <td>CHTraversePreOrder</td></tr>
 <tr><td>Post-order</td>    <td>L, R, node</td>  <td><code>A C E D B H I G F</code></td> <td>CHTraversePostOrder</td></tr>
 <tr><td>Level-order</td>   <td>L→R, T→B</td>    <td><code>F B G A D I C E H</code></td> <td>CHTraverseLevelOrder</td></tr>
 </table>
 <p><strong>Table 1 - Various traversals as performed on the tree in Figure 1.</strong></p>
 
 </td></tr>
 </table>
 
 */
@protocol CHSearchTree <CHSortedSet>

/**
 Initialize a search tree with no objects.
 
 @return An initialized search tree that contains no objects.
 
 @see initWithArray:
 */
- (id) init;

/**
 Initialize a search tree with the contents of an array. Objects are added to the tree in the order they occur in the array.
 
 @param anArray An array containing objects with which to populate a new search tree.
 @return An initialized search tree that contains the objects in @a anArray in sorted order.
 */
- (id) initWithArray:(NSArray*)anArray;

#pragma mark Querying Contents
/** @name Tree Traversals */
// @{

/**
 Returns an NSArray which contains the objects in this tree in a given ordering. The object traversed last will appear last in the array.
 
 @param order The traversal order to use for enumerating the given tree.
 @return An array containing the objects in this tree. If the tree is empty, the array is also empty.

 @see \link allObjects - allObjects\endlink
 @see objectEnumeratorWithTraversalOrder:
 @see \link reverseObjectEnumerator - reverseObjectEnumerator\endlink
 */
- (NSArray*) allObjectsWithTraversalOrder:(CHTraversalOrder)order;

/**
 Compares the receiving search tree to another search tree. Two search trees have equal contents if they each hold the same number of objects and objects at a given position in each search tree satisfy the \link NSObject-p#isEqual: -isEqual:\endlink test.
 
 @param otherTree A search tree.
 @return @c YES if the contents of @a otherTree are equal to the contents of the receiver, otherwise @c NO.
 */
- (BOOL) isEqualToSearchTree:(id<CHSearchTree>)otherTree;

/**
 Returns an enumerator that accesses each object using a given traversal order.
 
 @param order The order in which an enumerator should traverse nodes in the tree. @return An enumerator that accesses each object in the tree in a given order. The enumerator returned is never @c nil; if the tree is empty, the enumerator will always return @c nil for \link NSEnumerator#nextObject -nextObject\endlink and an empty array for \link NSEnumerator#allObjects -allObjects\endlink.
 
 @attention The enumerator retains the collection. Once all objects in the enumerator have been consumed, the collection is released.
 @warning Modifying a collection while it is being enumerated is unsafe, and may cause a mutation exception to be raised.
 
 @see allObjectsWithTraversalOrder:
 @see \link objectEnumerator - objectEnumerator\endlink
 @see \link reverseObjectEnumerator - reverseObjectEnumerator\endlink
 */
- (NSEnumerator*) objectEnumeratorWithTraversalOrder:(CHTraversalOrder)order;

// @}
@end
