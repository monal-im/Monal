/*
 CHDataStructures.framework -- CHListQueue.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 Copyright (c) 2002, Phillip Morelock <http://www.phillipmorelock.com>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHListQueue.h"
#import "CHSinglyLinkedList.h"

/**
 This implementation uses a CHSinglyLinkedList, since it's slightly faster than
 using a CHDoublyLinkedList, and requires a little less memory. Also, since it's
 a queue, it's unlikely that there is any need to enumerate over the object from
 back to front.
 */
@implementation CHListQueue

- (id) init {
	if ((self = [super init]) == nil) return nil;
	list = [[CHSinglyLinkedList alloc] init];
	return self;
}

- (void) addObject:(id)anObject {
	if (anObject == nil)
		CHNilArgumentException([self class], _cmd);
	[list addObject:anObject];
}

- (id) firstObject {
	return [list firstObject];
}

- (BOOL) isEqual:(id)otherObject {
	if ([otherObject conformsToProtocol:@protocol(CHQueue)])
		return [self isEqualToQueue:otherObject];
	else
		return NO;
}

- (BOOL) isEqualToQueue:(id<CHQueue>)otherQueue {
	return collectionsAreEqual(self, otherQueue);
}

- (id) lastObject {
	return [list lastObject];
}

- (void) removeFirstObject {
	[list removeFirstObject];
}

@end
