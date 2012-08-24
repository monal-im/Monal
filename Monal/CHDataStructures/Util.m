/*
 CHDataStructures.framework -- Util.m
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "Util.h"
#import <objc/message.h>

// For iOS, define enum and dummy functions used for Garbage Collection.
#if (TARGET_OS_IPHONE || TARGET_OS_EMBEDDED || !TARGET_OS_MAC)

void* __strong NSAllocateCollectable(NSUInteger size, NSUInteger options) {
	return malloc(size);
}

void* __strong NSReallocateCollectable(void *ptr, NSUInteger size, NSUInteger options) {
	return realloc(ptr, size);
}

#endif

#pragma mark -

BOOL kCHGarbageCollectionNotEnabled; // A variable declared extern in Util.h
size_t kCHPointerSize = sizeof(void*); // A variable declared extern in Util.h

/**
 Determines GC status and sets @c kCHGarbageCollectionNotEnabled appropriately.
 The 'constructor' attribute causes the function to be called automatically
 before execution enters main(); in our case, when the shared library is loaded.
 See http://stackoverflow.com/questions/2053029/ for GCC constructor details.
 */
__attribute__((constructor))
void initializeGCStatus() {
	// Discover whether garbage collection is enabled (if running on 10.5+).
	// This bit of hackery avoids linking errors via indirect invocation.
	// If NSGarbageCollector doesn't exist, NSClassFromString() returns nil.
	// If it does exist, +defaultCollector will be non-nil if GC is enabled.
	kCHGarbageCollectionNotEnabled = (objc_msgSend(NSClassFromString(@"NSGarbageCollector"),
	                                               @selector(defaultCollector)) == nil);
}

BOOL objectsAreEqual(id o1, id o2) {
	return [o1 isEqual:o2];
}

BOOL objectsAreIdentical(id o1, id o2) {
	return (o1 == o2);
}

BOOL collectionsAreEqual(id collection1, id collection2) {
	if ((collection1 && ![collection1 respondsToSelector:@selector(count)]) ||
		(collection2 && ![collection2 respondsToSelector:@selector(count)]))
	{
		[NSException raise:NSInvalidArgumentException
		            format:@"Parameter does not respond to -count selector."];
	}
	if (collection1 == collection2)
		return YES;
	if ([collection1 count] != [collection2 count])
		return NO;
	NSEnumerator *otherObjects = [collection2 objectEnumerator];
	for (id anObject in collection1) {
		if (![anObject isEqual:[otherObjects nextObject]])
			return NO;
	}
	return YES;	
}

NSUInteger hashOfCountAndObjects(NSUInteger count, id object1, id object2) {
	NSUInteger hash = 17 * count ^ (count << 16);
	return hash ^ (31*[object1 hash]) ^ ((31*[object2 hash]) << 4);
}

#pragma mark -

void CHIndexOutOfRangeException(Class aClass, SEL method,
                                NSUInteger index, NSUInteger count) {
	[NSException raise:NSRangeException
	            format:@"[%@ %s] -- Index (%lu) beyond bounds for count (%lu)",
	                   aClass, sel_getName(method), index, count];
}

void CHInvalidArgumentException(Class aClass, SEL method, NSString *string) {
	[NSException raise:NSInvalidArgumentException
	            format:@"[%@ %s] -- %@",
	                   aClass, sel_getName(method), string];
}

void CHNilArgumentException(Class aClass, SEL method) {
	CHInvalidArgumentException(aClass, method, @"Invalid nil argument");
}

void CHMutatedCollectionException(Class aClass, SEL method) {
	[NSException raise:NSGenericException
	            format:@"[%@ %s] -- Collection was mutated during enumeration",
	                   aClass, sel_getName(method)];
}

void CHUnsupportedOperationException(Class aClass, SEL method) {
	[NSException raise:NSInternalInconsistencyException
	            format:@"[%@ %s] -- Unsupported operation",
	                   aClass, sel_getName(method)];
}

void CHQuietLog(NSString *format, ...) {
	if (format == nil) {
		printf("(null)\n");
		return;
	}
	// Get a reference to the arguments that follow the format parameter
	va_list argList;
	va_start(argList, format);
	// Do format string argument substitution, reinstate %% escapes, then print
	NSMutableString *string = [[NSMutableString alloc] initWithFormat:format
	                                                        arguments:argList];
	va_end(argList);
	NSRange range;
	range.location = 0;
	range.length = [string length];
	[string replaceOccurrencesOfString:@"%%" withString:@"%%%%" options:0 range:range];
	printf("%s\n", [string UTF8String]);
	[string release];
}
