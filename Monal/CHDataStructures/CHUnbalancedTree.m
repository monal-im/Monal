/*
 CHDataStructures.framework -- CHUnbalancedTree.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHUnbalancedTree.h"
#import "CHAbstractBinarySearchTree_Internal.h"

@implementation CHUnbalancedTree

- (void) addObject:(id)anObject {
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	++mutations;
	
	CHBinaryTreeNode *parent = header, *current = header->right;
	sentinel->object = anObject; // Assure that we find a spot to insert
	NSComparisonResult comparison;
	while (comparison = [current->object compare:anObject]) {
		parent = current;
		current = current->link[comparison == NSOrderedAscending]; // R on YES
	}
	
	[anObject retain]; // Must retain whether replacing value or adding new node
	if (current != sentinel) {
		// Replace the existing object with the new object.
		[current->object release];
		current->object = anObject;		
	} else {
		// Create a new node to hold the value being inserted
		current = CHCreateBinaryTreeNodeWithObject(anObject);
		current->left   = sentinel;
		current->right  = sentinel;
		++count;
		// Link from parent as the proper child, based on last comparison
		comparison = [parent->object compare:anObject]; // restore prior compare
		parent->link[comparison == NSOrderedAscending] = current;
	}
}


// Removal is guaranteed to not make the tree deeper/taller, since it uses the
// "min of the right subtree" algorithm if the node to be removed has 2 children.
- (void) removeObject:(id)anObject {
	if (count == 0 || anObject == nil)
		return;
	++mutations;
	
	CHBinaryTreeNode *parent = nil, *current = header;
	
	sentinel->object = anObject; // Assure that we find a spot to insert
	NSComparisonResult comparison;
	while (comparison = [current->object compare:anObject]) {
		parent = current;
		current = current->link[comparison == NSOrderedAscending]; // R on YES
	}
	NSAssert(parent != nil, @"Illegal state, parent should never be nil!");
	// Exit if the specified node was not found in the tree.
	if (current == sentinel)
		return;

	[current->object release]; // Object must be released in any case
	--count;
	if (current->left == sentinel || current->right == sentinel) {
		// One or both of the child pointers are null, so removal is simpler
		parent->link[parent->right == current]
			= current->link[current->left == sentinel];
		if (kCHGarbageCollectionNotEnabled)
			free(current);
	} else {
		// The most complex case: removing a node with 2 non-null children
		// (Replace object with the leftmost object in the right subtree.)
		parent = current;
		CHBinaryTreeNode *replacement = current->right;
		while (replacement->left != sentinel) {
			parent = replacement;
			replacement = replacement->left;
		}
		current->object = replacement->object;
		parent->link[parent->right == replacement] = replacement->right;
		if (kCHGarbageCollectionNotEnabled)
			free(replacement);
	}
}

@end
