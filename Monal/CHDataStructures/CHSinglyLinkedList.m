/*
 CHDataStructures.framework -- CHSinglyLinkedList.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHSinglyLinkedList.h"

static size_t kCHSinglyLinkedListNodeSize = sizeof(CHSinglyLinkedListNode);

/**
 An NSEnumerator for traversing a CHSinglyLinkedList from front to back.
 */
@interface CHSinglyLinkedListEnumerator : NSEnumerator {
	CHSinglyLinkedList *collection; // The source of enumerated objects.
	__strong CHSinglyLinkedListNode *current; // The next node to be enumerated.
	unsigned long mutationCount; // Stores the collection's initial mutation.
	unsigned long *mutationPtr; // Pointer for checking changes in mutation.
}

/**
 Create an enumerator which traverses a singly-linked list from front to back.
 
 @param list The linked list collection being enumerated. This collection is to be retained while the enumerator has not exhausted all its objects.
 @param startNode The node at which to begin the enumeration.
 @param mutations A pointer to the collection's mutation count, for invalidation.
 @return An initialized CHSinglyLinkedListEnumerator which will enumerate objects in @a list.
 */
- (id) initWithList:(CHSinglyLinkedList*)list
          startNode:(CHSinglyLinkedListNode*)startNode
    mutationPointer:(unsigned long*)mutations;

/**
 Returns the next object in the collection being enumerated.
 
 @return The next object in the collection being enumerated, or @c nil when all objects have been enumerated.
 */
- (id) nextObject;

/**
 Returns an array of objects the receiver has yet to enumerate. Invoking this method exhausts the remainder of the objects, such that subsequent invocations of #nextObject return @c nil.
 
 @return An array of objects the receiver has yet to enumerate.
 */
- (NSArray*) allObjects;

@end

#pragma mark -

@implementation CHSinglyLinkedListEnumerator

- (id) initWithList:(CHSinglyLinkedList*)list
          startNode:(CHSinglyLinkedListNode*)startNode
    mutationPointer:(unsigned long*)mutations;
{
	if ((self = [super init]) == nil) return nil;
	collection = (startNode != NULL) ? collection = [list retain] : nil;
	current = startNode; // If startNode == endNode, will always return nil.
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
	if (current == NULL) {
		[collection release];
		collection = nil;
		return nil;
	}
	id object = current->object;
	current = current->next;
	return object;
}

- (NSArray*) allObjects {
	if (mutationCount != *mutationPtr)
		CHMutatedCollectionException([self class], _cmd);
	NSMutableArray *array = [[NSMutableArray alloc] init];
	while (current != NULL) {
		[array addObject:current->object];
		current = current->next;
	}
	[collection release];
	collection = nil;
	return [array autorelease];
}

@end

#pragma mark -

@implementation CHSinglyLinkedList

- (void) dealloc {
	[self removeAllObjects];
	free(head);
	[super dealloc];
}

- (id) init {
	return [self initWithArray:nil];
}

// This is the designated initializer for CHSinglyLinkedList
- (id) initWithArray:(NSArray*)anArray {
	if ((self = [super init]) == nil) return nil;
	head = NSAllocateCollectable(kCHSinglyLinkedListNodeSize, NSScannedOption);
	head->next = NULL;
	tail = head;
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
	NSArray *array = [[self objectEnumerator] allObjects];
	[encoder encodeObject:array forKey:@"objects"];
}

#pragma mark <NSCopying>

- (id) copyWithZone:(NSZone*)zone {
	CHSinglyLinkedList *newList = [[CHSinglyLinkedList allocWithZone:zone] init];
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
	CHSinglyLinkedListNode *currentNode;
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
		currentNode = (CHSinglyLinkedListNode*) state->state;
	}
	
	// Accumulate objects from the list until we reach the tail, or the maximum
	NSUInteger batchCount = 0;
	while (currentNode != NULL && batchCount < len) {
		stackbuf[batchCount++] = currentNode->object;
		currentNode = currentNode->next;
	}
	if (currentNode == NULL)
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
	return (count == 0) ? nil : head->next->object;
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
	return (count == 0) ? nil : tail->object;
}

- (NSUInteger) indexOfObject:(id)anObject {
	CHSinglyLinkedListNode *current = head->next;
	NSUInteger index = 0;
	while (current && ![current->object isEqual:anObject]) {
		current = current->next;
		++index;
	}
	return (current == NULL) ? NSNotFound : index;
}

- (NSUInteger) indexOfObjectIdenticalTo:(id)anObject {
	CHSinglyLinkedListNode *current = head->next;
	NSUInteger index = 0;
	while (current && (current->object != anObject)) {
		current = current->next;
		++index;
	}
	return (current == NULL) ? NSNotFound : index;
}

/*
 Internal method to fetch a node at a specified index; uses per-instance cache.
 @throw NSRangeException if @a index exceeds the bounds of the receiver.
 */
- (CHSinglyLinkedListNode*) nodeAtIndex:(NSUInteger)index {
	if (index >= count)
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	if (index == count - 1)
		return tail;
	// Try starting from cached node (if one exists) and corresponding index
	CHSinglyLinkedListNode *node = cachedNode;
	NSUInteger nodeIndex = cachedIndex;
	// If the cached node is invalid or after the current index, don't use it
	if (node == NULL || nodeIndex > index) {
		node = head->next;
		nodeIndex = 0;
	}
	// Iterate through the list elements until we find the requested node index
	while (nodeIndex++ < index)
		node = node->next;
	// Update cached node and corresponding index
	if (node != NULL) {
		cachedNode = node;
		cachedIndex = index;
	}
	return node;
}

- (id) objectAtIndex:(NSUInteger)index {
	return [self nodeAtIndex:index]->object; // Checks ranges and caches index
}

- (NSEnumerator*) objectEnumerator {
	return [[[CHSinglyLinkedListEnumerator alloc]
              initWithList:self
                 startNode:head->next
           mutationPointer:&mutations] autorelease];
}

- (NSArray*) objectsAtIndexes:(NSIndexSet*)indexes {
	if (indexes == nil)
		CHNilArgumentException([self class], _cmd);
	if ([indexes count] && [indexes lastIndex] >= count)
		CHIndexOutOfRangeException([self class], _cmd, [indexes lastIndex], count);
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:[indexes count]];
	NSUInteger nextIndex = [indexes firstIndex];
	while (nextIndex != NSNotFound) {
		[objects addObject:[self nodeAtIndex:nextIndex]->object];
		nextIndex = [indexes indexGreaterThanIndex:nextIndex];
	}	
	return objects;
}

#pragma mark Modifying Contents

- (void) addObject:(id)anObject {
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	CHSinglyLinkedListNode *new;
	new = NSAllocateCollectable(kCHSinglyLinkedListNodeSize, NSScannedOption);
	new->object = [anObject retain];
	new->next = NULL;
	tail->next = new;
	tail = new;
	++count;
	++mutations;
}

- (void) addObjectsFromArray:(NSArray*)anArray {
	CHSinglyLinkedListNode *new;
	for (id anObject in anArray) {
		new = NSAllocateCollectable(kCHSinglyLinkedListNodeSize, NSScannedOption);
		new->object = [anObject retain];
		new->next = NULL;
		tail->next = new;
		tail = new;
	}
	count += [anArray count];
	++mutations;
}

- (void) exchangeObjectAtIndex:(NSUInteger)idx1 withObjectAtIndex:(NSUInteger)idx2 {
	if (idx1 >= count || idx2 >= count)
		CHIndexOutOfRangeException([self class], _cmd, MAX(idx1,idx2), count);
	if (idx1 != idx2) {
		CHSinglyLinkedListNode *node1 = [self nodeAtIndex:MIN(idx1,idx2)];
		CHSinglyLinkedListNode *node2 = [self nodeAtIndex:MAX(idx1,idx2)];
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
	CHSinglyLinkedListNode *new = NSAllocateCollectable(kCHSinglyLinkedListNodeSize, NSScannedOption);
	new->object = [anObject retain];
	if (index == count) {
		new->next = NULL;
		tail->next = new;
		tail = new;
	}
	else {
		// Find the node prior to the specified index adnd insert after it
		CHSinglyLinkedListNode *node = index ? [self nodeAtIndex:index-1] : head;
		new->next = node->next;
		node->next = new;
		cachedNode = new;
		cachedIndex = index;
	}
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
	CHSinglyLinkedListNode *new;
	new = NSAllocateCollectable(kCHSinglyLinkedListNodeSize, NSScannedOption);
	new->object = [anObject retain];
	new->next = head->next;
	head->next = new;
	if (tail == head)
		tail = new;
	++count;
	++mutations;
}

- (void) removeAllObjects {
	if (kCHGarbageCollectionNotEnabled && count > 0) {
		CHSinglyLinkedListNode *node;
		// Use tail pointer to iterate through all nodes, then reset it to head
		tail = head->next;
		while (tail != NULL) {
			node = tail;
			tail = tail->next;
			[node->object release];
			free(node);
		}
	}
	head->next = NULL;
	cachedNode = NULL;
	tail = head;
	count = 0;
	++mutations;
}

- (void) removeFirstObject {
	if (count > 0)
		[self removeObjectAtIndex:0];
}

/**
 Remove the last item in the receiver.
 
 @attention This operation is expensive for singly-linked lists since there are no reverse links to facilitate finding the penultimate node.
 
 @see lastObject
 @see removeFirstObject
 */
- (void) removeLastObject {
	if (count > 0)
		[self removeObjectAtIndex:(count-1)];
}

// Remove the node with a matching object, steal its 'next' link for my own.
- (void) removeNodeAfterNode:(CHSinglyLinkedListNode*)node {
	CHSinglyLinkedListNode *old = node->next;
	node->next = old->next;
	if (kCHGarbageCollectionNotEnabled) {
		[old->object release];
		free(old);
	}
	cachedNode = NULL;
}

// Private method that accepts a function pointer for testing object equality.
- (void) removeObject:(id)anObject withEqualityTest:(BOOL(*)(id,id))objectsMatch {
	if (count == 0 || anObject == nil)
		return;
	CHSinglyLinkedListNode *node = head;
	do {
		while (node->next != NULL && !objectsMatch(node->next->object, anObject))
			node = node->next;
		if (node->next != NULL) {
			[self removeNodeAfterNode:node];
			--count;
		}
	} while (node->next != NULL);
	tail = node;
	++mutations;
}

- (void) removeObject:(id)anObject {
	[self removeObject:anObject withEqualityTest:&objectsAreEqual];
}

- (void) removeObjectAtIndex:(NSUInteger)index {
	if (index >= count)
		CHIndexOutOfRangeException([self class], _cmd, index, count);
	// Find the node prior to the specified index and insert node after that
	CHSinglyLinkedListNode *node = index ? [self nodeAtIndex:index-1] : head;
	[self removeNodeAfterNode:node];
	if (index) {
		cachedNode = node->next;
		cachedIndex = index;
	}
	--count;
	++mutations;
	if (node->next == NULL)
		tail = node;
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
		// Indexes point to element one beyond the current element
		NSUInteger nextIndex = [indexes firstIndex];
		NSUInteger index = nextIndex;
		CHSinglyLinkedListNode *node = nextIndex ? [self nodeAtIndex:nextIndex-1] : head;
		while (nextIndex != NSNotFound) {
			while (index++ < nextIndex)
				node = node->next;
			[self removeNodeAfterNode:node];
			nextIndex = [indexes indexGreaterThanIndex:nextIndex];
		}
		if (node->next == NULL)
			tail = node;
		count -= [indexes count];
		++mutations;
	}
}

- (void) replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
	CHSinglyLinkedListNode *node = [self nodeAtIndex:index];
	[node->object autorelease];
	node->object = [anObject retain];
}

@end
