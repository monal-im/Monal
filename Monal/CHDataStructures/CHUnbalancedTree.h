/*
 CHDataStructures.framework -- CHUnbalancedTree.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHAbstractBinarySearchTree.h"

/**
 @file CHUnbalancedTree.h
 A generic, unbalanced implementation of CHSearchTree.
 */

/**
 A simple unbalanced binary tree that <b>does not</b> guarantee O(log n) access. The algorithms for insertion and removal have been adapted from code in the <a href="http://eternallyconfuzzled.com/tuts/datastructures/jsw_tut_bst1.aspx"> Binary Search Trees tutorial</a>, which is in the public domain, courtesy of <a href="http://eternallyconfuzzled.com/">Julienne Walker</a>. Method names have been changed to match the APIs of existing Cocoa collections provided by Apple.
 
 Even though the tree is not balanced when items are added or removed, access is <b>at worst</b> linear if the tree essentially degenerates into a linked list. This class is fast, and without stack risk because it works without recursion.
 */
@interface CHUnbalancedTree : CHAbstractBinarySearchTree

@end
