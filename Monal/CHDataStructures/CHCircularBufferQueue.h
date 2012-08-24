/*
 CHDataStructures.framework -- CHCircularBufferQueue.h
 
 Copyright (c) 2009-2010, Quinn Taylor <http://homepage.mac.com/quinntaylor>
 
 This source code is released under the ISC License. <http://www.opensource.org/licenses/isc-license>
 
 Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
 
 The software is  provided "as is", without warranty of any kind, including all implied warranties of merchantability and fitness. In no event shall the authors or copyright holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or the use or other dealings in the software.
 */

#import "CHQueue.h"
#import "CHCircularBuffer.h"

/**
 @file CHCircularBufferQueue.h
 A simple CHQueue implemented using a CHCircularBuffer.
 */

/**
 A simple CHQueue implemented using a CHCircularBuffer.
 */
@interface CHCircularBufferQueue : CHCircularBuffer <CHQueue>

@end
