/*
 CHDataStructures.framework -- CHRedBlackTree.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHRedBlackTree.h"
#import "CHAbstractBinarySearchTree_Internal.h"

#pragma mark C Functions for Optimized Operations

static inline CHBinaryTreeNode* rotateNodeWithLeftChild(CHBinaryTreeNode *node) {
	CHBinaryTreeNode *leftChild = node->left;
	node->left = leftChild->right;
	leftChild->right = node;
	node->color = kRED;
	leftChild->color = kBLACK;
	return leftChild;
}

static inline CHBinaryTreeNode* rotateNodeWithRightChild(CHBinaryTreeNode *node) {
	CHBinaryTreeNode *rightChild = node->right;
	node->right = rightChild->left;
	rightChild->left = node;
	node->color = kRED;
	rightChild->color = kBLACK;
	return rightChild;
}

HIDDEN CHBinaryTreeNode* rotateObjectOnAncestor(id anObject, CHBinaryTreeNode *ancestor) {
	if ([ancestor->object compare:anObject] == NSOrderedDescending) {
		if ([ancestor->left->object compare:anObject] == NSOrderedDescending)
			ancestor->left = rotateNodeWithLeftChild(ancestor->left);
		else
			ancestor->left = rotateNodeWithRightChild(ancestor->left);
		return ancestor->left;
	}
	else {
		if ([ancestor->right->object compare:anObject] == NSOrderedDescending)
			ancestor->right = rotateNodeWithLeftChild(ancestor->right);
		else
			ancestor->right = rotateNodeWithRightChild(ancestor->right);
		return ancestor->right;
	}
}

static inline CHBinaryTreeNode* singleRotation(CHBinaryTreeNode *node, BOOL goingRight) {
	CHBinaryTreeNode *save = node->link[!goingRight];
	node->link[!goingRight] = save->link[goingRight];
	save->link[goingRight] = node;
	node->color = kRED;
	save->color = kBLACK;
	return save;
}

static inline CHBinaryTreeNode* doubleRotation(CHBinaryTreeNode *node, BOOL goingRight) {
	node->link[!goingRight] = singleRotation(node->link[!goingRight], !goingRight);
	return singleRotation(node, goingRight);	
}

#pragma mark -

@implementation CHRedBlackTree

// NOTE: The header and sentinel nodes are initialized to black (0) by default.

/*
 Basically, as you walk down the tree to insert, if the present node has two red children, color it red and change the two children to black. If its parent is red, the tree must be rotated. (Just change the root's color back to black if you changed it). Returns without incrementing the count if the object already exists in the tree.
 */
- (void) addObject:(id)anObject {
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	++mutations;

	CHBinaryTreeNode *current, *parent, *grandparent, *greatgrandparent;
	grandparent = parent = current = header;
	
	sentinel->object = anObject;
	NSComparisonResult comparison;
	while (comparison = [current->object compare:anObject]) {
		greatgrandparent = grandparent, grandparent = parent, parent = current;
		current = current->link[comparison == NSOrderedAscending];
		
		// Check for the bad case of red parent and red sibling of parent
		if (current->left->color == kRED && current->right->color == kRED) {
			// Simple red violation: resolve with color flip
			current->color = kRED;
			current->left->color = kBLACK;
			current->right->color = kBLACK;
			
			// Hard red violation: rotations necessary
			if (parent->color == kRED) {
//				BOOL lastWentRight = (grandparent->right == parent);
//				greatgrandparent->link[greatgrandparent->right == grandparent]
//					= (parent->link[lastWentRight])
//						? singleRotation(grandparent, !lastWentRight)
//						: doubleRotation(grandparent, !lastWentRight);
				grandparent->color = kRED;
				if ([grandparent->object compare:anObject] != [parent->object compare:anObject])
					parent = rotateObjectOnAncestor(anObject, grandparent);
				current = rotateObjectOnAncestor(anObject, greatgrandparent);
				current->color = kBLACK;
			}
		}
	}
	
	[anObject retain];
	if (current != sentinel) {
		// If an existing node matched, simply replace the existing value.
		[current->object release];
		current->object = anObject;
	} else {
		++count;
		current = CHCreateBinaryTreeNodeWithObject(anObject);
		current->left = sentinel;
		current->right = sentinel;
		
		parent->link[([parent->object compare:anObject] == NSOrderedAscending)] = current;
		
		// one last reorientation check...
		
		// Color flip
		current->color = kRED;
		current->left->color = kBLACK;
		current->right->color = kBLACK;
		// Fix red violation
		if (parent->color == kRED) 	{
			grandparent->color = kRED;
			if ([grandparent->object compare:anObject] != [parent->object compare:anObject])
				rotateObjectOnAncestor(anObject, grandparent);
			current = rotateObjectOnAncestor(anObject, greatgrandparent);
			current->color = kBLACK;
		}
		header->right->color = kBLACK;  // Always reset root to black
	}
}

/**
 @param anObject The object to be removed from the tree.
 
 @bug Performance decays exponentially (not linearly) when removing objects.
 @todo Speed up red-black removal. The EternallyConfuzzled.com tutorial opts to push a red node down the tree using rotations and flips to avoid a nasty case of deleting a black node. This is almost certainly what causes the performance problems.

 @see http://www.stanford.edu/~blp/avl/libavl.html/Deleting-from-an-RB-Tree.html
 @see http://eternallyconfuzzled.com/tuts/datastructures/jsw_tut_rbtree.aspx
 */
- (void) removeObject:(id)anObject {
	if (count == 0 || anObject == nil)
		return;
	++mutations;
	
	CHBinaryTreeNode *current, *parent, *grandparent;
	parent = current = header;
	
	CHBinaryTreeNode *found = NULL, *sibling;
	sentinel->object = anObject;
	NSComparisonResult comparison;
	BOOL isGoingRight = YES, prevWentRight = YES;
	while (current->link[isGoingRight] != sentinel) {
		grandparent = parent;
		parent = current;
		current = current->link[isGoingRight];
		comparison = [current->object compare:anObject];
		prevWentRight = isGoingRight;
		isGoingRight = (comparison != NSOrderedDescending);
		if (comparison == NSOrderedSame)
			found = current; // Save a pointer; removal happens outside the loop
		
		// There are only potential violations when removing a black node.
		// If so, push the child red node down using rotations and color flips.
		if (current->color != kRED && current->link[isGoingRight]->color != kRED) {
			if (current->link[!isGoingRight]->color == kRED) {
				parent->link[prevWentRight] = singleRotation(current, isGoingRight);
				parent = parent->link[prevWentRight];
			}
			else {
				sibling = parent->link[prevWentRight];
				if (sibling != sentinel) {
					if (sibling->left->color == kBLACK && sibling->right->color == kBLACK) {
						// If sibling's children are both black, do a color flip
						parent->color = kBLACK;
						sibling->color = kRED;
						current->color = kRED;
					}
					else {
						CHBinaryTreeNode *tempNode = grandparent->link[(grandparent->right == parent)];
						if (sibling->link[prevWentRight]->color == kRED)
							tempNode = doubleRotation(parent, prevWentRight);
						else if (sibling->link[!prevWentRight]->color == kRED)
							tempNode = singleRotation(parent, prevWentRight);
						/* Ensure correct coloring */
						current->color = tempNode->color = kRED;
						tempNode->left->color = kBLACK;
						tempNode->right->color = kBLACK;
					}
				} // if (sibling != sentinel)
			}
		}
	}
	
	// Transfer replacement value up to outgoing node, remove the "donor" node.
    if (found != NULL) {
		[found->object release];
		found->object = current->object;
		parent->link[(parent->right == current)]
			= current->link[(current->left == sentinel)];
		if (kCHGarbageCollectionNotEnabled)
			free(current);
		--count;
    }
	header->right->color = kBLACK; // Make the root black for simplified logic
}

- (NSString*) debugDescriptionForNode:(CHBinaryTreeNode*)node {
	return [NSString stringWithFormat:@"[%s]\t\"%@\"",
			(node->color == kRED) ? " RED " : "BLACK", node->object];
}

- (NSString*) dotGraphStringForNode:(CHBinaryTreeNode*)node {
	return [NSString stringWithFormat:@"  \"%@\" [color=%@];\n",
			node->object, (node->color == kRED) ? @"red" : @"black"];
}

@end
