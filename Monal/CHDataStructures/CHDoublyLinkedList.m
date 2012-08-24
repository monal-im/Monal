/*
 CHDataStructures.framework -- CHDoublyLinkedList.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHDoublyLinkedList.h"

static size_t kCHDoublyLinkedListNodeSize = sizeof(CHDoublyLinkedListNode);

/**
 An NSEnumerator for traversing a CHDoublyLinkedList in forward or reverse order.
 */
@interface CHDoublyLinkedListEnumerator : NSEnumerator {
	CHDoublyLinkedList *collection; // The source of enumerated objects.
	__strong CHDoublyLinkedListNode *current; // The next node to be enumerated.
	__strong CHDoublyLinkedListNode *sentinel; // Node that signifies completion.
	BOOL reverse; // Whether the enumerator is proceeding from back to front.
	unsigned long mutationCount; // Stores the collection's initial mutation.
	unsigned long *mutationPtr; // Pointer for checking changes in mutation.
}

/**
 Create an enumerator which traverses a list in either forward or revers order.
 
 @param list The linked list collection being enumerated. This collection is to be retained while the enumerator has not exhausted all its objects.
 @param startNode The node at which to begin the enumeration.
 @param endNode The node which signifies that enumerations should terminate.
 @param direction The direction in which to enumerate. (@c NSOrderedDescending is back-to-front).
 @param mutations A pointer to the collection's mutation count, for invalidation.
 @return An initialized CHDoublyLinkedListEnumerator which will enumerate objects in @a list in the order specified by @a direction.
 
 The enumeration direction is inferred from the state of the provided start node. If @c startNode->next is @c NULL, enumeration proceeds from back to front; otherwise, enumeration proceeds from front to back. This works since the head and tail nodes always have @c NULL for their @c prev and @c next links, respectively. When there is only one node, order won't matter anyway.
 
 This enumerator doesn't support enumerating over a sub-list of nodes. (When a node from the middle is provided, enumeration will proceed towards the tail.)
 */
- (id) initWithList:(CHDoublyLinkedList*)list
          startNode:(CHDoublyLinkedListNode*)startNode
            endNode:(CHDoublyLinkedListNode*)endNode
          direction:(NSComparisonResult)direction
    mutationPointer:(unsigned long*)mutations;

/**
 Returns the next object in the collection being enumerated.
 
 @return The next object in the collection being enumerated, or @c nil when all objects have been enumerated.
 */
- (id) nextObject;

/**
 Returns an array of objects the receiver has yet to enumerate.
 
 @return An array of objects the receiver has yet to enumerate.
 
 Invoking this method exhausts the remainder of the objects, such that subsequent invocations of #nextObject return @c nil.
 */
- (NSArray*) allObjects;

@end

#pragma mark -

@implementation CHDoublyLinkedListEnumerator

- (id) initWithList:(CHDoublyLinkedList*)list
          startNode:(CHDoublyLinkedListNode*)startNode
            endNode:(CHDoublyLinkedListNode*)endNode
          direction:(NSComparisonResult)direction
    mutationPointer:(unsigned long*)mutations;
{
	if ((self = [super init]) == nil) return nil;
	collection = ([list count] > 0) ? [list retain] : nil;
	current = startNode;
	sentinel = endNode;
	reverse = (direction == NSOrderedDescending);
	mutationCount = *mutations;
	mutationPtr = mutations;
	return self;
}

- (void) dealloc {
	[collection release];
	[super dealloc];
}

- (id) nextObject {
	if (mutationCount != *mutationPtr)
		CHMutatedCollectionException([self class], _cmd);
	if (current == sentinel) {
		[collection release];
		collection = nil;
		return nil;
	}
	id object = current->object;
	current = (reverse) ? current->prev : current->next;
	return object;
}

- (NSArray*) allObjects {
	if (mutationCount != *mutationPtr)
		CHMutatedCollectionException([self class], _cmd);
	NSMutableArray *array = [[NSMutableArray alloc] init];
	while (current != sentinel) {
		[array addObject:current->object];
		current = (reverse) ? current->prev : current->next;
	}
	[collection release];
	collection = nil;
	return [array autorelease];
}

@end

#pragma mark -

/** A macro for easily finding the absolute difference between two values. */
#define ABS_DIF(A,B) \
({ __typeof__(A) a = (A); __typeof__(B) b = (B); (a > b) ? (a - b) : (b - a); })

@implementation CHDoublyLinkedList

// An internal method for locating a node at a specific position in the list.
// If the index is invalid, an NSRangeException is raised.
- (CHDoublyLinkedListNode*) nodeAtIndex:(NSUInteger)index {
	if (index > count) // If it's equal to count, we return the dummy tail node
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	// Start with the end of the linked list (head or tail) closest to the index
	BOOL closerToHead = (index < count/2);
	CHDoublyLinkedListNode *node = closerToHead ? head->next : tail;
	NSUInteger nodeIndex = closerToHead ? 0 : count;
	// If a node is cached and it's closer to the index, start there instead
	if (cachedNode != NULL && ABS_DIF(index,cachedIndex) < ABS_DIF(index,nodeIndex)) {
		node = cachedNode;
		nodeIndex = cachedIndex;
	}
	// Iterate through the list elements until we find the requested node index
	if (index > nodeIndex) {
		while (index > nodeIndex++)
			node = node->next;
	} else {
		while (index < nodeIndex--)
			node = node->prev;
	}
	// Update cached node and corresponding index (it can never be null here)
	cachedNode = node;
	cachedIndex = index;
	return node;
}

// An internal method for removing a given node and patching up neighbor links.
// Since we use dummy head and tail nodes, there is no need to check for null.
- (void) removeNode:(CHDoublyLinkedListNode*)node {
	node->prev->next = node->next;
	node->next->prev = node->prev;
	if (kCHGarbageCollectionNotEnabled) {
		[node->object release];
		free(node);
	}
	cachedNode = NULL;
	--count;
	++mutations;
}

#pragma mark -

- (void) dealloc {
	[self removeAllObjects];
	free(head);
	free(tail);
	[super dealloc];
}

- (id) init {
	return [self initWithArray:nil];
}

// This is the designated initializer for CHDoublyLinkedList
- (id) initWithArray:(NSArray*)anArray {
	if ((self = [super init]) == nil) return nil;
	head = NSAllocateCollectable(kCHDoublyLinkedListNodeSize, NSScannedOption);
	tail = NSAllocateCollectable(kCHDoublyLinkedListNodeSize, NSScannedOption);
	head->object = tail->object = nil;
	head->next = tail;
	head->prev = NULL;
	tail->next = NULL;
	tail->prev = head;
	count = 0;
	mutations = 0;
	for (id anObject in anArray) {
		[self addObject:anObject];
	}
	return self;
}

- (NSString*) description {
	return [[self allObjects] description];
}

#pragma mark <NSCoding>

- (id) initWithCoder:(NSCoder*)decoder {
	return [self initWithArray:[decoder decodeObjectForKey:@"objects"]];
}

- (void) encodeWithCoder:(NSCoder*)encoder {
	[encoder encodeObject:[[self objectEnumerator] allObjects] forKey:@"objects"];
}

#pragma mark <NSCopying>

- (id) copyWithZone:(NSZone*)zone {
	CHDoublyLinkedList *newList = [[CHDoublyLinkedList allocWithZone:zone] init];
	for (id anObject in self) {
		[newList addObject:anObject];
	}
	return newList;
}

#pragma mark <NSFastEnumeration>

- (NSUInteger) countByEnumeratingWithState:(NSFastEnumerationState*)state
                                   objects:(id*)stackbuf
                                     count:(NSUInteger)len
{
	CHDoublyLinkedListNode *currentNode;
	// On the first call, start at head, otherwise start at last saved node
	if (state->state == 0) {
		currentNode = head->next;
		state->itemsPtr = stackbuf;
		state->mutationsPtr = &mutations;
	}
	else if (state->state == 1) {
		return 0;		
	}
	else {
		currentNode = (CHDoublyLinkedListNode*) state->state;
	}
	
	// Accumulate objects from the list until we reach the tail, or the maximum
    NSUInteger batchCount = 0;
    while (currentNode != tail && batchCount < len) {
        stackbuf[batchCount] = currentNode->object;
        currentNode = currentNode->next;
		batchCount++;
    }
	if (currentNode == tail)
		state->state = 1; // used as a termination flag
	else
		state->state = (unsigned long)currentNode;
    return batchCount;
}

#pragma mark Querying Contents

- (NSArray*) allObjects {
	return [[self objectEnumerator] allObjects];
}

- (BOOL) containsObject:(id)anObject {
	return ([self indexOfObject:anObject] != NSNotFound);
}

- (BOOL) containsObjectIdenticalTo:(id)anObject {
	return ([self indexOfObjectIdenticalTo:anObject] != NSNotFound);
}

- (NSUInteger) count {
	return count;
}

- (id) firstObject {
	tail->object = nil;
	return head->next->object; // nil if there are no objects between head/tail
}

- (NSUInteger) hash {
	return hashOfCountAndObjects(count, [self firstObject], [self lastObject]);
}

- (BOOL) isEqual:(id)otherObject {
	if ([otherObject conformsToProtocol:@protocol(CHLinkedList)])
		return [self isEqualToLinkedList:otherObject];
	else
		return NO;
}

- (BOOL) isEqualToLinkedList:(id<CHLinkedList>)otherLinkedList {
	return collectionsAreEqual(self, otherLinkedList);
}

- (id) lastObject {
	head->object = nil;
	return tail->prev->object; // nil if there are no objects between head/tail
}

- (NSUInteger) indexOfObject:(id)anObject {
	NSUInteger index = 0;
	tail->object = anObject;
	CHDoublyLinkedListNode *current = head->next;
	while (![current->object isEqual:anObject]) {
		current = current->next;
		++index;
	}
	return (current == tail) ? NSNotFound : index;
}

- (NSUInteger) indexOfObjectIdenticalTo:(id)anObject {
	NSUInteger index = 0;
	tail->object = anObject;
	CHDoublyLinkedListNode *current = head->next;
	while (current->object != anObject) {
		current = current->next;
		++index;
	}
	return (current == tail) ? NSNotFound : index;
}

- (id) objectAtIndex:(NSUInteger)index {
	if (index >= count)
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	return [self nodeAtIndex:index]->object;
}

- (NSEnumerator*) objectEnumerator {
	return [[[CHDoublyLinkedListEnumerator alloc]
	          initWithList:self
	             startNode:head->next
	               endNode:tail
	             direction:NSOrderedAscending
	       mutationPointer:&mutations] autorelease];
}

- (NSArray*) objectsAtIndexes:(NSIndexSet*)indexes {
	if (indexes == nil)
		CHNilArgumentException([self class], _cmd);
	if ([indexes count] && [indexes lastIndex] >= count)
		CHIndexOutOfRangeException([self class], _cmd, [indexes lastIndex], count);
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:[indexes count]];
	CHDoublyLinkedListNode *current = head;
	NSUInteger nextIndex = [indexes firstIndex], index = 0;
	while (nextIndex != NSNotFound) {
		do
			current = current->next;
		while (index++ < nextIndex);
		[objects addObject:current->object];
		nextIndex = [indexes indexGreaterThanIndex:nextIndex];
	}
	return objects;
}

- (NSEnumerator*) reverseObjectEnumerator {
	return [[[CHDoublyLinkedListEnumerator alloc]
	          initWithList:self
	             startNode:tail->prev
	               endNode:head
	             direction:NSOrderedDescending
	       mutationPointer:&mutations] autorelease];
}

#pragma mark Modifying Contents

- (void) addObject:(id)anObject {
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	[self insertObject:anObject atIndex:count];
}

- (void) addObjectsFromArray:(NSArray*)anArray {
	for (id anObject in anArray) {
		[self insertObject:anObject atIndex:count];
	}
}

- (void) exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2 {
	if (idx1 >= count || idx2 >= count)
		CHIndexOutOfRangeException([self class], _cmd, MAX(idx1,idx2), count);
	if (idx1 != idx2) {
		// Find the nodes as the provided indexes
		CHDoublyLinkedListNode *node1 = [self nodeAtIndex:idx1];
		CHDoublyLinkedListNode *node2 = [self nodeAtIndex:idx2];
		// Swap the objects at the provided indexes
		id tempObject = node1->object;
		node1->object = node2->object;
		node2->object = tempObject;
		++mutations;
	}
}

- (void) insertObject:(id)anObject atIndex:(NSUInteger)index {
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	CHDoublyLinkedListNode *node = [self nodeAtIndex:index];
	CHDoublyLinkedListNode *newNode;
	newNode = NSAllocateCollectable(kCHDoublyLinkedListNodeSize, NSScannedOption);
	newNode->object = [anObject retain];
	newNode->next = node;          // point forward to displaced node
	newNode->prev = node->prev;    // point backward to preceding node
	newNode->prev->next = newNode; // point preceding node forward to new node
	node->prev = newNode;          // point displaced node backward to new node
	cachedNode = newNode;
	cachedIndex = index;
	++count;
	++mutations;
}

- (void) insertObjects:(NSArray *)objects atIndexes:(NSIndexSet *)indexes {
	if (objects == nil || indexes == nil)
		CHNilArgumentException([self class], _cmd);
	if ([objects count] != [indexes count])
		CHInvalidArgumentException([self class], _cmd, @"Unequal object and index counts.");
	NSUInteger index = [indexes firstIndex];
	for (id anObject in objects) {
		[self insertObject:anObject atIndex:index];
		index = [indexes indexGreaterThanIndex:index];
	}
}

- (void) prependObject:(id)anObject {
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	[self insertObject:anObject atIndex:0];
}

- (void) removeAllObjects {
	if (kCHGarbageCollectionNotEnabled && count > 0) {
		// Only bother with free() calls if garbage collection is NOT enabled.
		CHDoublyLinkedListNode *node = head->next, *temp;
		while (node != tail) {
			temp = node->next;
			[node->object release];
			free(node);
			node = temp;
		}
	}
	head->next = tail;
	tail->prev = head;
	cachedNode = NULL;
	count = 0;
	++mutations;
}

- (void) removeFirstObject {
	if (count > 0)
		[self removeNode:head->next];
}

- (void) removeLastObject {
	if (count > 0)
		[self removeNode:tail->prev];
}

// Private method that accepts a function pointer for testing object equality.
- (void) removeObject:(id)anObject withEqualityTest:(BOOL(*)(id,id))objectsMatch {
	if (count == 0 || anObject == nil)
		return;
	tail->object = anObject;
	CHDoublyLinkedListNode *node = head->next, *temp;
	do {
		while (!objectsMatch(node->object, anObject))
			node = node->next;
		if (node != tail) {
			temp = node->next;
			[self removeNode:node];
			node = temp;
		}
	} while (node != tail);
}

- (void) removeObject:(id)anObject {
	[self removeObject:anObject withEqualityTest:&objectsAreEqual];
}

- (void) removeObjectAtIndex:(NSUInteger)index {
	if (index >= count)
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	[self removeNode:[self nodeAtIndex:index]];
}

- (void) removeObjectIdenticalTo:(id)anObject {
	[self removeObject:anObject withEqualityTest:&objectsAreIdentical];
}

- (void) removeObjectsAtIndexes:(NSIndexSet*)indexes {
	if (indexes == nil)
		CHNilArgumentException([self class], _cmd);
	if ([indexes count]) {
		if ([indexes lastIndex] >= count)
			CHIndexOutOfRangeException([self class], _cmd, [indexes lastIndex], count);
		NSUInteger nextIndex = [indexes firstIndex], index = 0;
		CHDoublyLinkedListNode *current = head->next, *temp;
		while (nextIndex != NSNotFound) {
			while (index++ < nextIndex)
				current = current->next;
			temp = current->next;
			[self removeNode:current];
			current = temp;
			nextIndex = [indexes indexGreaterThanIndex:nextIndex];
		}	
	}
}

- (void) replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
	if (index >= count)
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	CHDoublyLinkedListNode *node = [self nodeAtIndex:index];
	[node->object autorelease];
	node->object = [anObject retain];
}

@end
