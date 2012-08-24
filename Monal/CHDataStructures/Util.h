/*
 CHDataStructures.framework -- Util.h
 
 Copyright (c) 2008-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import <Foundation/Foundation.h>

/**
 @file Util.h
 A group of utility C functions for simplifying common exceptions and logging.
 */

/** Macro for reducing visibility of symbol names not indended to be exported. */
#define HIDDEN __attribute__((visibility("hidden")))

/** Macro for designating symbols as being unused to suppress compile warnings. */
#define UNUSED __attribute__((unused))

#pragma mark -

// NSInteger/NSUInteger are new in Leopard; define if on an earlier OS version.
#ifndef NSINTEGER_DEFINED
	#if __LP64__ || NS_BUILD_32_LIKE_64
		typedef long NSInteger;
		typedef unsigned long NSUInteger;
	#else
		typedef int NSInteger;
		typedef unsigned int NSUInteger;
	#endif

	#define NSIntegerMax    LONG_MAX
	#define NSIntegerMin    LONG_MIN
	#define NSUIntegerMax   ULONG_MAX

	#define NSINTEGER_DEFINED 1
#endif

#pragma mark -

// For iOS, define enum and dummy functions used for Garbage Collection.
#if (TARGET_OS_IPHONE || TARGET_OS_EMBEDDED || !TARGET_OS_MAC)

enum {
    NSScannedOption = (1UL << 0), 
    NSCollectorDisabledOption = (1UL << 1),
};

void* __strong NSAllocateCollectable(NSUInteger size, NSUInteger options);

void* __strong NSReallocateCollectable(void *ptr, NSUInteger size, NSUInteger options);

#define objc_memmove_collectable memmove

#else

// This is declared in <objc/objc-auto.h>, but importing the header is overkill.
HIDDEN void* objc_memmove_collectable(void *dst, const void *src, size_t size);

#endif

#pragma mark -

/** Global variable to simplify checking if garbage collection is enabled. */
OBJC_EXPORT BOOL kCHGarbageCollectionNotEnabled;

/** Global variable to store the size of a pointer only once. */
HIDDEN size_t kCHPointerSize;

/**
 Simple function for checking object equality, to be used as a function pointer.
 
 @param o1 The first object to be compared.
 @param o2 The second object to be compared.
 @return <code>[o1 isEqual:o2]</code>
 */
HIDDEN BOOL objectsAreEqual(id o1, id o2);

/**
 Simple function for checking object identity, to be used as a function pointer.
 
 @param o1 The first object to be compared.
 @param o2 The second object to be compared.
 @return <code>o1 == o2</code>
 */
HIDDEN BOOL objectsAreIdentical(id o1, id o2);

/**
 Determine whether two collections enumerate the equivalent objects in the same order.
 
 @param collection1 The first collection to be compared.
 @param collection2 The second collection to be compared.
 @return Whether the collections are equivalent.
 
 @throw NSInvalidArgumentException if one of both of the arguments do not respond to the @c -count or @c -objectEnumerator selectors.
 */
OBJC_EXPORT BOOL collectionsAreEqual(id collection1, id collection2);

/**
 Generate a hash for a collection based on the count and up to two objects. If objects are provided, the result of their -hash method will be used.
 
 @param count The number of objects in the collection.
 @param o1 The first object to include in the hash.
 @param o2 The second object to include in the hash.
 @return An unsigned integer that can be used as a table address in a hash table structure.
 */
HIDDEN NSUInteger hashOfCountAndObjects(NSUInteger count, id o1, id o2);

#pragma mark -

/**
 Convenience function for raising an exception for an invalid range (index).
 
 Currently, there is no support for calling this function from a C function.
 
 @param aClass The class object for the originator of the exception. Callers should pass the result of <code>[self class]</code> for this parameter.
 @param method The method selector where the problem originated. Callers should pass @c _cmd for this parameter.
 @param index The offending index passed to the receiver.
 @param elements The number of elements present in the receiver.
 
 @throw NSRangeException
 
 @see \link NSException#raise:format: +[NSException raise:format:]\endlink
 */
OBJC_EXPORT void CHIndexOutOfRangeException(Class aClass, SEL method,
                                       NSUInteger index, NSUInteger elements);

/**
 Convenience function for raising an exception on an invalid argument.
 
 Currently, there is no support for calling this function from a C function.
 
 @param aClass The class object for the originator of the exception. Callers should pass the result of <code>[self class]</code> for this parameter.
 @param method The method selector where the problem originated. Callers should pass @c _cmd for this parameter.
 @param str An NSString describing the offending invalid argument.
 
 @throw NSInvalidArgumentException
 
 @see \link NSException#raise:format: +[NSException raise:format:]\endlink
 */
OBJC_EXPORT void CHInvalidArgumentException(Class aClass, SEL method, NSString *str);

/**
 Convenience function for raising an exception on an invalid nil object argument.
 
 Currently, there is no support for calling this function from a C function.
 
 @param aClass The class object for the originator of the exception. Callers should pass the result of <code>[self class]</code> for this parameter.
 @param method The method selector where the problem originated. Callers should pass @c _cmd for this parameter.
 
 @throw NSInvalidArgumentException
 
 @see CHInvalidArgumentException()
 */
OBJC_EXPORT void CHNilArgumentException(Class aClass, SEL method);

/**
 Convenience function for raising an exception when a collection is mutated.
 
 Currently, there is no support for calling this function from a C function.
 
 @param aClass The class object for the originator of the exception. Callers should pass the result of <code>[self class]</code> for this parameter.
 @param method The method selector where the problem originated. Callers should pass @c _cmd for this parameter.
 
 @throw NSGenericException
 
 @see \link NSException#raise:format: +[NSException raise:format:]\endlink
 */
OBJC_EXPORT void CHMutatedCollectionException(Class aClass, SEL method);

/**
 Convenience function for raising an exception for un-implemented functionality.
 
 Currently, there is no support for calling this function from a C function.
 
 @param aClass The class object for the originator of the exception. Callers should pass the result of <code>[self class]</code> for this parameter.
 @param method The method selector where the problem originated. Callers should pass @c _cmd for this parameter.
 
 @throw NSInternalInconsistencyException
 
 @see \link NSException#raise:format: +[NSException raise:format:]\endlink
 */
OBJC_EXPORT void CHUnsupportedOperationException(Class aClass, SEL method);

/**
 Provides a more terse alternative to NSLog() which accepts the same parameters. The output is made shorter by excluding the date stamp and process information which NSLog prints before the actual specified output.
 
 @param format A format string, which must not be nil.
 @param ... A comma-separated list of arguments to substitute into @a format.
 
 Read <b>Formatting String Objects</b> and <b>String Format Specifiers</b> on <a href="http://developer.apple.com/documentation/Cocoa/Conceptual/Strings/"> this webpage</a> for details about using format strings. Look for examples that use @c NSLog() since the parameters and syntax are idential.
 */
OBJC_EXPORT void CHQuietLog(NSString *format, ...);

/**
 A macro for including the source file and line number where a log occurred.
 
 @param format A format string, which must not be nil.
 @param ... A comma-separated list of arguments to substitute into @a format.
 
 This is defined as a compiler macro so it can automatically fill in the file name and line number where the call was made. After printing these values in brackets, this macro calls #CHQuietLog with @a format and any other arguments supplied afterward.
 
 @see CHQuietLog
 */
#ifndef CHLocationLog
#define CHLocationLog(format,...) \
{ \
	NSString *file = [[NSString alloc] initWithUTF8String:__FILE__]; \
	printf("[%s:%d] ", [[file lastPathComponent] UTF8String], __LINE__); \
	[file release]; \
	CHQuietLog((format),##__VA_ARGS__); \
}
#endif
