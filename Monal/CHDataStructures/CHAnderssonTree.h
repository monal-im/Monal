/*
 CHDataStructures.framework -- CHAnderssonTree.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHAbstractBinarySearchTree.h"

/**
 @file CHAnderssonTree.h
 An <a href="http://en.wikipedia.org/wiki/AA_tree">AA-tree</a> implementation of CHSearchTree.
 */

/**
 An <a href="http://en.wikipedia.org/wiki/AA_tree">AA-tree</a>, a balanced binary search tree with guaranteed O(log n) access. The algorithms for insertion and removal have been adapted from code in the <a href="http://eternallyconfuzzled.com/tuts/datastructures/jsw_tut_andersson.aspx">Andersson Tree tutorial</a>, which is in the public domain, courtesy of <a href="http://eternallyconfuzzled.com/">Julienne Walker</a>. Method names have been changed to match the APIs of existing Cocoa collections provided by Apple.
 
 The AA-tree (named after its creator, Arne Andersson) is extremely similar to a Red-Black tree. Both are abstractions of B-trees designed to make insertion and removal easier to understand and implement. In a Red-Black tree, a red node represents a horizontal link to a subtree rooted at the same level. In the AA-tree, horizontal links are represented by storing a node's level, not color. (A node whose level is the same as its parent is equivalent to a "red" node.)
 
 Similar to a Red-Black tree, there are several rules which must be true for an AA-tree to remain valid:
 
 <ol>
 <li>The level of a leaf node is one.</li>
 <li>The level of a left child is less than that of its parent.</li>
 <li>The level of a right child is less than or equal to that of its parent.</li>
 <li>The level of a right grandchild is less than that of its grandparent.</li>
 <li>Every node of level greater than one must have two children.</li>
 </ol>

 The AA-tree was invented to simplify the algorithms for balancing an abstract B-tree, and does so with  a simple restriction: horizontal links ("red nodes") are only allowed as the right child of a node. If we represent both node level and the implicit red colors, an AA-tree looks like the following example:
 
 <center>
 <b>Figure 1 - A sample AA-tree with node levels and implicit coloring.</b><br>
 @image html aa-tree-sample.png
 </center>
 
 Because horizontal links are only allowed on the right, rather than balancing all 7 possible subtrees of 2 and 3 nodes (shown in Figure 2) when removing, an AA-tree need only be concerned with 2: the first and last forms in the figure.
 
 <center>
 <b>Figure 2 - All possible 2- and 3-node subtrees</b>
 @image html aa-tree-shapes.png
 </center>
 
 Consequently, only two primitive balancing operations are necessary. The @c skew operation eliminates red nodes as left children, while the @c split operation eliminates consecutive right-child red nodes. (Both of these operations are depicted in the figures below.)
 
 <center>
 <b>Figure 3 - The skew operation.</b><br>
 @image html aa-tree-skew.png
 </center>
 
 <center>
 <b>Figure 4 - The split operation.</b><br>
 @image html aa-tree-split.png
 </center>
 
 Performance of an AA-tree is roughly equivalent to that of a Red-Black tree. While an AA-tree makes more rotations than a Red-Black tree, the algorithms are simpler to understand and tend to be somewhat faster, and all of this balances out to result in similar performance. A Red-Black tree is more consistent in its performance than an AA-tree, but an AA-tree tends to be flatter, which results in slightly faster search.

 AA-trees were originally described in the following paper:
 
 <div style="margin: 0 25px; font-weight: bold;">
 A. Andersson. "Balanced search trees made simple." <em>Workshop on Algorithms
 and Data Structures</em>, pp.60-71. Springer Verlag, 1993.
 </div>
 
 (See <a href="http://user.it.uu.se/~arnea/ps/simp.pdf">PDF original</a> or <a href="http://user.it.uu.se/~arnea/ps/simp.ps">PostScript original</a>)
 */
@interface CHAnderssonTree : CHAbstractBinarySearchTree

@end
