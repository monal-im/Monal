#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "TPCircularBuffer+AudioBufferList.h"
#import "TPCircularBuffer.h"

FOUNDATION_EXPORT double TPCircularBufferVersionNumber;
FOUNDATION_EXPORT const unsigned char TPCircularBufferVersionString[];

