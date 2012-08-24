/*
 CHDataStructures.framework -- CHAVLTree.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHAVLTree.h"
#import "CHAbstractBinarySearchTree_Internal.h"

// Two-way single rotation
static inline CHBinaryTreeNode* singleRotation(CHBinaryTreeNode *node, u_int32_t dir) {
    CHBinaryTreeNode *save = node->link[!dir];
    node->link[!dir] = save->link[dir];
    save->link[dir] = node;
	return save;
}

// Two-way double rotation
static inline CHBinaryTreeNode* doubleRotation(CHBinaryTreeNode *node, u_int32_t dir) {
    CHBinaryTreeNode *save = node->link[!dir]->link[dir];
    node->link[!dir]->link[dir] = save->link[!dir];
    save->link[!dir] = node->link[!dir];
    node->link[!dir] = save;
	
    save = node->link[!dir];
    node->link[!dir] = save->link[dir];
    save->link[dir] = node;
    return save;
}

static inline void adjustBalance(CHBinaryTreeNode *root, u_int32_t dir, int32_t bal) {
    CHBinaryTreeNode *n = root->link[dir];
    CHBinaryTreeNode *nn = n->link[!dir];
    if (nn->balance == 0)
        root->balance = n->balance = 0;
    else if (nn->balance == bal) {
        root->balance = -bal;
        n->balance = 0;
    } else { // nn->balance == -bal
        root->balance = 0;
        n->balance = bal;
    }
    nn->balance = 0;
}

@implementation CHAVLTree

// NOTE: The header and sentinel nodes are initialized to balance 0 by default.

- (void) addObject:(id)anObject {
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	++mutations;
	
	CHBinaryTreeNode *parent = nil, *save = nil, *current = header;
	CHBinaryTreeStack_DECLARE();
	CHBinaryTreeStack_INIT();
	
	sentinel->object = anObject; // Assure that we find a spot to insert
	NSComparisonResult comparison;
	while (comparison = [current->object compare:anObject]) {
		CHBinaryTreeStack_PUSH(current);
		if (current == header)
			save = current->right;
		else if (current->balance != 0)
			save = current;
		current = current->link[comparison == NSOrderedAscending]; // R on YES
	}
	NSAssert(save != nil, @"Illegal state, save should never be nil!");
	
	[anObject retain]; // Must retain whether replacing value or adding new node
	if (current != sentinel) {
		// Replace the existing object with the new object.
		[current->object release];
		current->object = anObject;
		// No need to rebalance up the path since we didn't modify the structure
		goto done;
	} else {
		current = CHCreateBinaryTreeNodeWithObject(anObject);
		current->left   = sentinel;
		current->right  = sentinel;
		++count;
		// Link from parent as the proper child, based on last comparison
		parent = CHBinaryTreeStack_POP();
		NSAssert(parent != nil, @"Illegal state, parent should never be nil!");
		comparison = [parent->object compare:anObject];
		parent->link[comparison == NSOrderedAscending] = current; // R if YES
	}
	
	// Trace back up the path, rebalancing as we go
	BOOL isRightChild;
	BOOL keepBalancing = YES;
	// Stop at the header so the tree root remains its right child.
	while (keepBalancing && parent != header) {
		isRightChild = (parent->right == current);
		// Update the balance factor
		if (isRightChild)
			parent->balance++;
		else
			parent->balance--;
		
		if (parent == save) {
			// Rebalance if the balance factor is out of whack, then terminate
			if (abs(parent->balance) > 1) {
				CHBinaryTreeNode *node = parent->link[isRightChild];
				int32_t bal = (isRightChild) ? +1 : -1;
				if (node->balance == bal) {
					parent->balance = node->balance = 0;
					parent = singleRotation(parent, !isRightChild);
				} else { // node->balance == -bal
					adjustBalance(parent, isRightChild, bal);
					parent = doubleRotation(parent, !isRightChild);
				}
			}
			keepBalancing = NO;
		}
		// Move to the next node up the path to the root
		current = parent;
		parent = CHBinaryTreeStack_POP();
		NSAssert(parent != nil, @"Illegal state, parent should never be nil!");
		// Link from parent as the proper child, based on last comparison
		comparison = [parent->object compare:current->object];
		parent->link[comparison == NSOrderedAscending] = current; // R if YES
	}
done:
	CHBinaryTreeStack_FREE(stack);
}

- (void) removeObject:(id)anObject {
	if (count == 0 || anObject == nil)
		return;
	++mutations;

	CHBinaryTreeNode *parent, *current = header;
	CHBinaryTreeStack_DECLARE();
	CHBinaryTreeStack_INIT();

	sentinel->object = anObject; // Assure that we stop at a leaf if not found.
	NSComparisonResult comparison;
	// Search down the node for the tree and save the path
	while (comparison = [current->object compare:anObject]) {
		CHBinaryTreeStack_PUSH(current);
		current = current->link[comparison == NSOrderedAscending]; // R on YES
	}
	// Exit if the specified node was not found in the tree.
	if (current == sentinel) {
		goto done;
	}
	
	[current->object release]; // Object must be released in any case
	--count;
	CHBinaryTreeNode *replacement;
	BOOL isRightChild;
	if (current->left == sentinel || current->right == sentinel) {
		// Single/zero child case -- replace node with non-nil child (if exists)
		replacement = current->link[current->left == sentinel];
		parent = CHBinaryTreeStack_POP();
		NSAssert(parent != nil, @"Illegal state, parent should never be nil!");
		isRightChild = (parent->right == current);
		parent->link[isRightChild] = replacement;
		if (kCHGarbageCollectionNotEnabled)
			free(current);
	} else {
		// Two child case -- replace with minimum object in right subtree
		CHBinaryTreeStack_PUSH(current); // Need to start here when rebalancing
		replacement = current->right;
		while (replacement->left != sentinel) {
			CHBinaryTreeStack_PUSH(replacement);
			replacement = replacement->left;
		}
		// Grab object from replacement node, steal its right child, deallocate
		current->object = replacement->object;
		parent = CHBinaryTreeStack_POP();
		isRightChild = (parent->right == replacement);
		parent->link[isRightChild] = replacement->right;
		if (kCHGarbageCollectionNotEnabled)
			free(replacement);
	}
	
	// Trace back up the search path, rebalancing as we go until we're done
	BOOL done = NO;
	while (!done && stackSize > 0) {
		// Update the balance factor
		if (isRightChild)
			parent->balance--;
		else
			parent->balance++;
		// If the subtree heights differ by more than 1, rebalance them
		if (parent->balance > 1 || parent->balance < -1) {
			CHBinaryTreeNode *node = parent->link[!isRightChild];
			int32_t bal = (isRightChild) ? +1 : -1;
			if (node->balance == -bal) {
				parent->balance = node->balance = 0;
				parent = singleRotation(parent, isRightChild);
			}
			else if (node->balance == bal) {
				adjustBalance(parent, !isRightChild, -bal);
				parent = doubleRotation(parent, isRightChild);
			}
			else { // node->balance == 0
				parent->balance = -bal;
				node->balance = bal;
				parent = singleRotation(parent, isRightChild);
				done = YES;
			}
			comparison = [CHBinaryTreeStack_TOP->object compare:parent->object];
			CHBinaryTreeStack_TOP->link[comparison == NSOrderedAscending] = parent;
		}
		else if (parent->balance != 0)
			break;

		current = parent;
		parent = CHBinaryTreeStack_POP();
		isRightChild = (parent->right == current);
	}
done:
	CHBinaryTreeStack_FREE(stack);
}

- (NSString*) debugDescriptionForNode:(CHBinaryTreeNode*)node {
	return [NSString stringWithFormat:@"[%2d]\t\"%@\"",
			node->balance, node->object];
}

- (NSString*) dotGraphStringForNode:(CHBinaryTreeNode*)node {
	return [NSString stringWithFormat:@"  \"%@\" [label=\"%@\\n%d\"];\n",
			node->object, node->object, node->balance];
}

@end
