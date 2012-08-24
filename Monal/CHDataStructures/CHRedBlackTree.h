/*
 CHDataStructures.framework -- CHRedBlackTree.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHAbstractBinarySearchTree.h"

#define kBLACK 0
#define kRED 1

/**
 @file CHRedBlackTree.h
 A <a href="http://en.wikipedia.org/wiki/Red-black_trees">Red-Black tree</a> implementation of CHSearchTree.
 */

/**
 A <a href="http://en.wikipedia.org/wiki/Red-black_trees">Red-Black tree</a>, a balanced binary search tree with guaranteed O(log n) access. The algorithms for insertion and removal in this implementation have been adapted from code in the <a href="http://eternallyconfuzzled.com/tuts/datastructures/jsw_tut_rbtree.aspx"> Red-Black trees tutorial</a>, which is in the public domain, courtesy of <a href="http://eternallyconfuzzled.com/">Julienne Walker</a>. Method names have been changed to match the APIs of existing Cocoa collections provided by Apple.
 
 A Red-Black tree has a few fundamental rules:
 <ol>
 <li>Every node is red or black.</li>
 <li>All leaves (null children) are black, even when the parent is black.</li>
 <li>If a node is red, both of its children must be black.</li>
 <li>Every path from a node to its leaves has the same number of black nodes.</li>
 <li>The root of the tree is black. (Optional, but simplifies things.)</li>
 </ol>
 
 These constraints, and in particular the black path height and non-consecutive red nodes, guarantee that longest path from the root to a leaf is no more than twice as long as the shortest path from the root to a leaf. (This is true since the shortest possible path has only black nodes, and the longest possible path alternates between red and black nodes.) The result is a fairly balanced tree.
 
 <div align="center"><b>Figure 1 - A sample Red-Black tree</b></div>
 @image html red-black-tree.png
 
 The sentinel node (which appears whenever a child link would be null) is always colored black. The algorithms for balancing Red-Black trees can be made to work without explicitly representing the nil leaf children, but they work better and with much less heartache if those links are present. The same sentinel value is used for every leaf link, so it only adds the cost of storing one more node. In addition, tracing a path down the tree doesn't have to check for null children at each step, so insertion, search, and deletion are all a little bit faster.
 
 Red-Black trees were originally described in the following papers:
 
 <div style="margin: 0 25px 10px; font-weight: bold;">
 R. Bayer. "Binary B-Trees for Virtual Memory." <em>ACM-SIGFIDET Workshop on
 Data Description, 1971</em>, San Diego, California, Session 5B, p. 219-235.
 </div>
 
 <div style="margin: 0 25px 10px; font-weight: bold;">
 R. Bayer and E. M. McCreight. "Organization and Maintenance of Large Ordered
 Indexes." <em>Acta Informatica</em> 1, 173-189, 1972.
 </div>
 
 <div style="margin: 0 25px; font-weight: bold;">
 L. J. Guibas and R. Sedgewick. "A dichromatic framework for balanced trees."
 <em>19th Annual Symposium on Foundations of Computer Science</em>, pp.8-21,
 1978. (<a href="http://dx.doi.org/10.1109/SFCS.1978.3">DOI link to IEEE</a>)
 </div>
 */
@interface CHRedBlackTree : CHAbstractBinarySearchTree

@end
