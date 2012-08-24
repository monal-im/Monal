/*
 CHDataStructures.framework -- CHAbstractBinarySearchTree.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHAbstractBinarySearchTree.h"
#import "CHAbstractBinarySearchTree_Internal.h"

// Definitions of extern variables from CHAbstractBinarySearchTree_Internal.h
size_t kCHBinaryTreeNodeSize = sizeof(CHBinaryTreeNode);

/**
 A dummy object that resides in the header node for a tree. Using a header node can simplify insertion logic by eliminating the need to check whether the root is null. The actual root of the tree is generally stored as the right child of the header node. In order to always proceed to the actual root node when traversing down the tree, instances of this class always return @c NSOrderedAscending when called as the receiver of the @c -compare: method.
 
 Since all header objects behave the same way, all search tree instances can share the same dummy header object. The singleton instance can be obtained via the \link #object +object\endlink method. The singleton is created once and persists for the duration of the program. Any calls to @c -retain, @c -release, or @c -autorelease will raise an exception. (Note: If garbage collection is enabled, any such calls are likely to be ignored or "optimized out" by the compiler before the object can respond anyway.)
 */
@interface CHSearchTreeHeaderObject : NSObject

/**
 Returns the singleton instance of this class. The singleton variable is defined in this file and is initialized only once.
 
 @return The singleton instance of this class.
 */
+ (id) object;

/**
 Always indicate that another given object should appear to the right side.
 
 @param otherObject The object to be compared to the receiver.
 @return @c NSOrderedAscending, indicating that traversal should go to the right child of the containing tree node.
 
 @warning The header object @b must be the receiver of the message (e.g. <code>[headerObject compare:anObject]</code>) in order to work correctly. Calling <code>[anObject compare:headerObject]</code> instead will almost certainly result in a crash.
 */
- (NSComparisonResult) compare:(id)otherObject;

@end

// Static variable for storing singleton instance of search tree header object.
static CHSearchTreeHeaderObject *headerObject = nil;

@implementation CHSearchTreeHeaderObject

+ (id) object {
	// Protecting the @synchronized block prevents unnecessary lock contention.
	if (headerObject == nil) {
		@synchronized([CHSearchTreeHeaderObject class]) {
			// Make sure the object wasn't created since we blocked on the lock.
			if (headerObject == nil) {
				headerObject = [[CHSearchTreeHeaderObject alloc] init];
			}
		}		
	}
	return headerObject;
}

- (NSComparisonResult) compare:(id)otherObject {
	return NSOrderedAscending;
}

- (id) retain {
	CHUnsupportedOperationException([self class], _cmd); return nil;
}

- (oneway void) release {
	CHUnsupportedOperationException([self class], _cmd);
}

- (id) autorelease {
	CHUnsupportedOperationException([self class], _cmd); return nil;
}

@end

#pragma mark -

/**
 An NSEnumerator for traversing any CHAbstractBinarySearchTree subclass in a specified order.
 
 This enumerator implements only iterative (non-recursive) tree traversal algorithms for two main reasons:
 <ol>
 <li>Recursive algorithms cannot easily be stopped and resumed in the middle of a traversal.</li>
 <li>Iterative algorithms are usually faster since they reduce overhead from function calls.</li>
 </ol>
 
 Traversal state is stored in either a stack or queue using dynamically-allocated C structs and @c \#define pseudo-functions to increase performance and reduce the required memory footprint.
 
 Enumerators encapsulate their own state, and more than one enumerator may be active at once. However, if a collection is modified, any existing enumerators for that collection become invalid and will raise a mutation exception if any further objects are requested from it.
 */
@interface CHBinarySearchTreeEnumerator : NSEnumerator
{
	__strong id<CHSearchTree> searchTree; // The tree being enumerated.
	__strong CHBinaryTreeNode *current; // The next node to be enumerated.
	__strong CHBinaryTreeNode *sentinelNode; // Sentinel node in the tree.
	CHTraversalOrder traversalOrder; // Order in which to traverse the tree.
	unsigned long mutationCount; // Stores the collection's initial mutation.
	unsigned long *mutationPtr; // Pointer for checking changes in mutation.
	
@private
	// Pointers and counters that are used for various tree traveral orderings.
	CHBinaryTreeStack_DECLARE();
	CHBinaryTreeQueue_DECLARE();
	// These macros are defined in CHAbstractBinarySearchTree_Internal.h
}

/**
 Create an enumerator which traverses a given (sub)tree in the specified order.
 
 @param tree The tree collection that is being enumerated. This collection is to be retained while the enumerator has not exhausted all its objects.
 @param root The root node of the @a tree whose elements are to be enumerated.
 @param sentinel The sentinel value used at the leaves of the specified @a tree.
 @param order The traversal order to use for enumerating the given @a tree.
 @param mutations A pointer to the collection's mutation count for invalidation.
 @return An initialized CHBinarySearchTreeEnumerator which will enumerate objects in @a tree in the order specified by @a order.
 */
- (id) initWithTree:(id<CHSearchTree>)tree
               root:(CHBinaryTreeNode*)root
           sentinel:(CHBinaryTreeNode*)sentinel
     traversalOrder:(CHTraversalOrder)order
    mutationPointer:(unsigned long*)mutations;

/**
 Returns an array of objects the receiver has yet to enumerate.
 
 @return An array of objects the receiver has yet to enumerate.
 
 Invoking this method exhausts the remainder of the objects, such that subsequent invocations of #nextObject return @c nil.
 */
- (NSArray*) allObjects;

/**
 Returns the next object from the collection being enumerated.
 
 @return The next object from the collection being enumerated, or @c nil when all objects have been enumerated.
 */
- (id) nextObject;

@end

@implementation CHBinarySearchTreeEnumerator

- (id) initWithTree:(id<CHSearchTree>)tree
               root:(CHBinaryTreeNode*)root
           sentinel:(CHBinaryTreeNode*)sentinel
     traversalOrder:(CHTraversalOrder)order
    mutationPointer:(unsigned long*)mutations
{
	if ((self = [super init]) == nil || !isValidTraversalOrder(order)) return nil;
	traversalOrder = order;
	searchTree = (root != sentinel) ? [tree retain] : nil;
	if (traversalOrder == CHTraverseLevelOrder) {
		CHBinaryTreeQueue_INIT();
		CHBinaryTreeQueue_ENQUEUE(root);
	} else {
		CHBinaryTreeStack_INIT();
		if (traversalOrder == CHTraversePreOrder) {
			CHBinaryTreeStack_PUSH(root);
		} else {
			current = root;
		}
	}
	sentinel->object = nil;
	sentinelNode = sentinel;
	mutationCount = *mutations;
	mutationPtr = mutations;
	return self;
}

- (void) dealloc {
	[searchTree release];
	free(stack);
	free(queue);
	[super dealloc];
}

- (NSArray*) allObjects {
	if (mutationCount != *mutationPtr)
		CHMutatedCollectionException([self class], _cmd);
	NSMutableArray *array = [[NSMutableArray alloc] init];
	id anObject;
	while ((anObject = [self nextObject]))
		[array addObject:anObject];
	[searchTree release];
	searchTree = nil;
	return [array autorelease];
}

- (id) nextObject {
	if (mutationCount != *mutationPtr)
		CHMutatedCollectionException([self class], _cmd);
	
	switch (traversalOrder) {
		case CHTraverseAscending: {
			if (stackSize == 0 && current == sentinelNode) {
				goto collectionExhausted;
			}
			while (current != sentinelNode) {
				CHBinaryTreeStack_PUSH(current);
				current = current->left;
				// TODO: How to not push/pop leaf nodes unnecessarily?
			}
			current = CHBinaryTreeStack_POP(); // Save top node for return value
			NSAssert(current != nil, @"Illegal state, current should never be nil!");
			id tempObject = current->object;
			current = current->right;
			return tempObject;
		}
			
		case CHTraverseDescending: {
			if (stackSize == 0 && current == sentinelNode) {
				goto collectionExhausted;
			}
			while (current != sentinelNode) {
				CHBinaryTreeStack_PUSH(current);
				current = current->right;
				// TODO: How to not push/pop leaf nodes unnecessarily?
			}
			current = CHBinaryTreeStack_POP(); // Save top node for return value
			NSAssert(current != nil, @"Illegal state, current should never be nil!");
			id tempObject = current->object;
			current = current->left;
			return tempObject;
		}
			
		case CHTraversePreOrder: {
			current = CHBinaryTreeStack_POP();
			if (current == NULL) {
				goto collectionExhausted;
			}
			if (current->right != sentinelNode)
				CHBinaryTreeStack_PUSH(current->right);
			if (current->left != sentinelNode)
				CHBinaryTreeStack_PUSH(current->left);
			return current->object;
		}
			
		case CHTraversePostOrder: {
			// This algorithm from: http://www.johny.ca/blog/archives/05/03/04/
			if (stackSize == 0 && current == sentinelNode) {
				goto collectionExhausted;
			}
			while (1) {
				while (current != sentinelNode) {
					CHBinaryTreeStack_PUSH(current);
					current = current->left;
				}
				NSAssert(stackSize > 0, @"Stack should never be empty!");
				// A null entry indicates that we've traversed the left subtree
				if (CHBinaryTreeStack_TOP != NULL) {
					current = CHBinaryTreeStack_TOP->right;
					CHBinaryTreeStack_PUSH(NULL);
					// TODO: How to not push a null pad for leaf nodes?
				}
				else {
					CHBinaryTreeStack_POP(); // ignore the null pad
					return CHBinaryTreeStack_POP()->object;
				}				
			}
		}
			
		case CHTraverseLevelOrder: {
			current = CHBinaryTreeQueue_FRONT;
			CHBinaryTreeQueue_DEQUEUE();
			if (current == NULL) {
				goto collectionExhausted;
			}
			if (current->left != sentinelNode)
				CHBinaryTreeQueue_ENQUEUE(current->left);
			if (current->right != sentinelNode)
				CHBinaryTreeQueue_ENQUEUE(current->right);
			return current->object;
		}
			
		collectionExhausted:
			if (searchTree != nil) {
				[searchTree release];
				searchTree = nil;
				CHBinaryTreeStack_FREE(stack);
				CHBinaryTreeQueue_FREE(queue);
			}
	}
	return nil;
}

@end

#pragma mark -

CHBinaryTreeNode* CHCreateBinaryTreeNodeWithObject(id anObject) {
	CHBinaryTreeNode *node;
	// NSScannedOption tells the garbage collector to scan object and children.
	node = NSAllocateCollectable(kCHBinaryTreeNodeSize, NSScannedOption);
	node->object = anObject;
	node->balance = 0; // Affects balancing info for any subclass (anon. union)
	return node;
}

@implementation CHAbstractBinarySearchTree

- (void) dealloc {
	[self removeAllObjects];
	free(header);
	free(sentinel);
	[super dealloc];
}

// This is the designated initializer for CHAbstractBinarySearchTree.
// Only to be called from concrete child classes to initialize shared variables.
- (id) init {
	if ((self = [super init]) == nil) return nil;
	count = 0;
	mutations = 0;
	sentinel = CHCreateBinaryTreeNodeWithObject(nil);
	sentinel->right = sentinel;
	sentinel->left = sentinel;
	header = CHCreateBinaryTreeNodeWithObject([CHSearchTreeHeaderObject object]);
	header->right = sentinel;
	header->left = sentinel;
	return self;
}

// Calling [self init] allows child classes to initialize their specific state.
// (The -init method in any subclass must always call to -[super init] first.)
- (id) initWithArray:(NSArray*)anArray {
	if ([self init] == nil) return nil;
	[self addObjectsFromArray:anArray];
	return self;
}

#pragma mark <NSCoding>

- (id) initWithCoder:(NSCoder*)decoder {
	// Decode the array of objects and use it to initialize the tree's contents.
	return [self initWithArray:[decoder decodeObjectForKey:@"objects"]];
}

- (void) encodeWithCoder:(NSCoder*)encoder {
	[encoder encodeObject:[self allObjectsWithTraversalOrder:CHTraverseLevelOrder]
	               forKey:@"objects"];
}

#pragma mark <NSCopying> methods

- (id) copyWithZone:(NSZone*)zone {
	id<CHSearchTree> newTree = [[[self class] allocWithZone:zone] init];
	// No point in using fast enumeration here until rdar://6296108 is addressed.
	NSEnumerator *e = [self objectEnumeratorWithTraversalOrder:CHTraverseLevelOrder];
	id anObject;
	while (anObject = [e nextObject]) {
		[newTree addObject:anObject];
	}
	return newTree;
}

#pragma mark <NSFastEnumeration>

- (NSUInteger) countByEnumeratingWithState:(NSFastEnumerationState*)state
                                   objects:(id*)stackbuf
                                     count:(NSUInteger)len
{
	CHBinaryTreeNode *current;
	CHBinaryTreeStack_DECLARE();
	
	// For the first call, start at leftmost node, otherwise the last saved node
	if (state->state == 0) {
		state->itemsPtr = stackbuf;
		state->mutationsPtr = &mutations;
		current = header->right;
		CHBinaryTreeStack_INIT();
	}
	else if (state->state == 1) {
		return 0;		
	}
	else {
		current = (CHBinaryTreeNode*) state->state;
		stack = (CHBinaryTreeNode**) state->extra[0];
		stackCapacity = (NSUInteger) state->extra[1];
		stackSize = (NSUInteger) state->extra[2];
	}
	NSAssert(current != nil, @"Illegal state, current should never be nil!");
	
	// Accumulate objects from the tree until we reach all nodes or the maximum
	NSUInteger batchCount = 0;
	while ( (current != sentinel || stackSize > 0) && batchCount < len) {
		while (current != sentinel) {
			CHBinaryTreeStack_PUSH(current);
			current = current->left;
		}
		current = CHBinaryTreeStack_POP(); // Save top node for return value
		NSAssert(current != nil, @"Illegal state, current should never be nil!");
		stackbuf[batchCount] = current->object;
		current = current->right;
		batchCount++;
	}
	
	if (current == sentinel && stackSize == 0) {
		CHBinaryTreeStack_FREE(stack);
		state->state = 1; // used as a termination flag
	}
	else {
		state->state    = (unsigned long) current;
		state->extra[0] = (unsigned long) stack;
		state->extra[1] = (unsigned long) stackCapacity;
		state->extra[2] = (unsigned long) stackSize;
	}
	return batchCount;
}

#pragma mark Concrete Implementations

- (void) addObjectsFromArray:(NSArray*)anArray {
	for (id anObject in anArray) {
		[self addObject:anObject];
	}
}

- (NSArray*) allObjects {
	return [self allObjectsWithTraversalOrder:CHTraverseAscending];
}

- (NSArray*) allObjectsWithTraversalOrder:(CHTraversalOrder)order {
	return [[self objectEnumeratorWithTraversalOrder:order] allObjects];
}

- (id) anyObject {
	return (count > 0) ? header->right->object : nil;
	// In an empty tree, sentinel's object may be nil, but let's not chance it.
	// (Our -removeAllObjects nils the pointer, child's -removeObject: may not.)
}

- (BOOL) containsObject:(id)anObject {
	return ([self member:anObject] != nil);
}

- (NSUInteger) count {
	return count;
}

- (NSString*) description {
	return [[self allObjectsWithTraversalOrder:CHTraverseAscending] description];
}

- (id) firstObject {
	sentinel->object = nil;
	CHBinaryTreeNode *current = header->right;
	while (current->left != sentinel)
		current = current->left;
	return current->object;
}

- (NSUInteger) hash {
	return hashOfCountAndObjects(count, [self firstObject], [self lastObject]);
}

- (BOOL) isEqual:(id)otherObject {
	if ([otherObject conformsToProtocol:@protocol(CHSortedSet)])
		return [self isEqualToSortedSet:otherObject];
	else
		return NO;
}

- (BOOL) isEqualToSearchTree:(id<CHSearchTree>)otherTree {
	return collectionsAreEqual(self, otherTree);
}

- (BOOL) isEqualToSortedSet:(id<CHSortedSet>)otherSortedSet {
	return collectionsAreEqual(self, otherSortedSet);
}

- (id) lastObject {
	sentinel->object = nil;
	CHBinaryTreeNode *current = header->right;
	while (current->right != sentinel)
		current = current->right;
	return current->object;
}

- (id) member:(id)anObject {
	if (anObject == nil)
		return nil;
	sentinel->object = anObject; // Make sure the target value is always "found"
	CHBinaryTreeNode *current = header->right;
	NSComparisonResult comparison;
	while (comparison = [current->object compare:anObject]) // while not equal
		current = current->link[comparison == NSOrderedAscending]; // R on YES
	return (current != sentinel) ? current->object : nil;
}

- (NSEnumerator*) objectEnumerator {
	return [self objectEnumeratorWithTraversalOrder:CHTraverseAscending];
}

- (NSEnumerator*) objectEnumeratorWithTraversalOrder:(CHTraversalOrder)order {
	return [[[CHBinarySearchTreeEnumerator alloc]
			 initWithTree:self
	                 root:header->right
	             sentinel:sentinel
	       traversalOrder:order
	      mutationPointer:&mutations] autorelease];
}

// Doesn't call -[NSGarbageCollector collectIfNeeded] -- lets the sender choose.
- (void) removeAllObjects {
	if (count == 0)
		return;
	++mutations;
	count = 0;
	
	if (kCHGarbageCollectionNotEnabled) {
		// Only deal with memory management if garbage collection is NOT enabled.
		// Remove each node from the tree and release the object it points to.
		// Use pre-order (depth-first) traversal for simplicity and performance.
		CHBinaryTreeStack_DECLARE();
		CHBinaryTreeStack_INIT();
		CHBinaryTreeStack_PUSH(header->right);

		CHBinaryTreeNode *current;
		while (current = CHBinaryTreeStack_POP()) {
			if (current->right != sentinel)
				CHBinaryTreeStack_PUSH(current->right);
			if (current->left != sentinel)
				CHBinaryTreeStack_PUSH(current->left);
			[current->object release];
			free(current);
		}
		free(stack); // declared in CHBinaryTreeStack_DECLARE() macro
	}
	header->right = sentinel; // With GC, this is sufficient to unroot the tree.
	sentinel->object = nil; // Make sure we don't accidentally retain an object.
}

// Incurs an extra search cost, but we don't know how the child class removes...
- (void) removeFirstObject {
	[self removeObject:[self firstObject]];
}

// Incurs an extra search cost, but we don't know how the child class removes...
- (void) removeLastObject {
	[self removeObject:[self lastObject]];
}

- (NSEnumerator*) reverseObjectEnumerator {
	return [self objectEnumeratorWithTraversalOrder:CHTraverseDescending];
}

- (NSSet*) set {
	NSMutableSet *set = [NSMutableSet new];
	NSEnumerator *e = [self objectEnumeratorWithTraversalOrder:CHTraversePreOrder];
	id anObject;
	while (anObject = [e nextObject]) {
		[set addObject:anObject];
	}
	return [set autorelease];
}

/*
 \copydoc CHSortedSet::subsetFromObject:toObject:
 
 \see     CHSortedSet#subsetFromObject:toObject:
 
 \link    CHSortedSet#subsetFromObject:toObject: \endlink
 
 \attention This implementation tests objects for membership in the subset according to their sorted order. This worst-case input causes more work for self-balancing trees, and subsets of unbalanced trees will always degenerate to linked lists.
 */
- (id<CHSortedSet>) subsetFromObject:(id)start
                            toObject:(id)end
                             options:(CHSubsetConstructionOptions)options
{
	// If both parameters are nil, return a copy containing all the objects.
	if (start == nil && end == nil)
		return [[self copy] autorelease];
	
	id<CHSortedSet> subset = [[[[self class] alloc] init] autorelease];
	if (count == 0)
		return subset;
	
	NSEnumerator *e;
	id anObject;
	
	if (start == nil) {
		// Start from the first object and add until we pass the end parameter.
		e = [self objectEnumeratorWithTraversalOrder:CHTraverseAscending];
		while ((anObject = [e nextObject]) &&
			   [anObject compare:end] != NSOrderedDescending) {
			[subset addObject:anObject];
		}
	}
	else if (end == nil) {
		// Start from the last object and add until we pass the start parameter.
		e = [self objectEnumeratorWithTraversalOrder:CHTraverseDescending];
		while ((anObject = [e nextObject]) &&
			   [anObject compare:start] != NSOrderedAscending) {
			[subset addObject:anObject];
		}
	}
	else {
		if ([start compare:end] == NSOrderedAscending) {
			// Include subset of objects between the range parameters.
			e = [self objectEnumeratorWithTraversalOrder:CHTraverseAscending];
			while ((anObject = [e nextObject]) &&
				   [anObject compare:start] == NSOrderedAscending)
				;
			do {
				[subset addObject:anObject];
			} while ((anObject = [e nextObject]) &&
					 [anObject compare:end] != NSOrderedDescending);
		}
		else {
			// Include subset of objects NOT between the range parameters.
			e = [self objectEnumeratorWithTraversalOrder:CHTraverseDescending];
			while ((anObject = [e nextObject]) &&
				   [anObject compare:start] != NSOrderedAscending)
				[subset addObject:anObject];
			e = [self objectEnumeratorWithTraversalOrder:CHTraverseAscending];
			while ((anObject = [e nextObject]) &&
				   [anObject compare:end] != NSOrderedDescending)
				[subset addObject:anObject];
		}
	}
	// If the start and/or end value is to be excluded, remove before returning.
	if (options & CHSubsetExcludeLowEndpoint)
		[subset removeObject:start];
	if (options & CHSubsetExcludeHighEndpoint)
		[subset removeObject:end];
	return subset;
}


- (NSString*) debugDescription {
	NSMutableString *description = [NSMutableString stringWithFormat:
	                                @"<%@: 0x%x> = {\n", [self class], self];
	CHBinaryTreeNode *current;
	CHBinaryTreeStack_DECLARE();
	CHBinaryTreeStack_INIT();
	
	sentinel->object = nil;
	if (header->right != sentinel)
		CHBinaryTreeStack_PUSH(header->right);	
	while (current = CHBinaryTreeStack_POP()) {
		if (current->right != sentinel)
			CHBinaryTreeStack_PUSH(current->right);
		if (current->left != sentinel)
			CHBinaryTreeStack_PUSH(current->left);
		// Append entry for the current node, including children
		[description appendFormat:@"\t%@ -> \"%@\" and \"%@\"\n",
		 [self debugDescriptionForNode:current],
		 current->left->object, current->right->object];
	}
	CHBinaryTreeStack_FREE(stack);
	[description appendString:@"}"];
	return description;
}

- (NSString*) debugDescriptionForNode:(CHBinaryTreeNode*)node {
	return [NSString stringWithFormat:@"\"%@\"", node->object];
}

// Uses an iterative reverse pre-order traversal to generate the diagram so that
// DOT tools will render the graph as a binary search tree is expected to look.
- (NSString*) dotGraphString {
	NSMutableString *graph = [NSMutableString stringWithFormat:
							  @"digraph %@\n{\n", NSStringFromClass([self class])];
	if (header->right == sentinel) {
		[graph appendFormat:@"  nil;\n"];
	} else {
		NSString *leftChild, *rightChild;
		NSUInteger sentinelCount = 0;
		sentinel->object = nil;
		
		CHBinaryTreeNode *current;
		CHBinaryTreeStack_DECLARE();
		CHBinaryTreeStack_INIT();
		CHBinaryTreeStack_PUSH(header->right);
		// Uses a reverse pre-order traversal to make the DOT output look right.
		while (current = CHBinaryTreeStack_POP()) {
			if (current->left != sentinel)
				CHBinaryTreeStack_PUSH(current->left);
			if (current->right != sentinel)
				CHBinaryTreeStack_PUSH(current->right);
			// Append entry for node with any subclass-specific customizations.
			[graph appendString:[self dotGraphStringForNode:current]];
			// Append entry for edges from current node to both its children.
			leftChild = (current->left->object == nil)
				? [NSString stringWithFormat:@"nil%lu", ++sentinelCount]
				: [NSString stringWithFormat:@"\"%@\"", current->left->object];
			rightChild = (current->right->object == nil)
				? [NSString stringWithFormat:@"nil%lu", ++sentinelCount]
				: [NSString stringWithFormat:@"\"%@\"", current->right->object];
			[graph appendFormat:@"  \"%@\" -> {%@;%@};\n",
			                    current->object, leftChild, rightChild];
		}
		CHBinaryTreeStack_FREE(stack);
		
		// Create entry for each null leaf node (each nil is modeled separately)
		for (NSUInteger i = 1; i <= sentinelCount; i++)
			[graph appendFormat:@"  nil%lu [shape=point,fillcolor=black];\n", i];
	}
	// Terminate the graph string, then return it
	[graph appendString:@"}\n"];
	return graph;
}

- (NSString*) dotGraphStringForNode:(CHBinaryTreeNode*)node {
	return [NSString stringWithFormat:@"  \"%@\";\n", node->object];
}

#pragma mark Unsupported Implementations

- (void) addObject:(id)anObject {
	CHUnsupportedOperationException([self class], _cmd);
}

- (void) removeObject:(id)element {
	CHUnsupportedOperationException([self class], _cmd);
}

@end
