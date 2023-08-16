//
//  MLStreamRedirect.h
//  monalxmpp
//
//  Created by Thilo Molitor on 18.08.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <stdio.h>

#ifndef MLStreamRedirect_h
#define MLStreamRedirect_h

@interface MLStreamRedirect : NSObject
-(instancetype) initWithStream:(FILE*) stream;
-(void) flush;
-(void) flushWithTimeout:(double) timeout;
-(void) flushAndClose;
-(void) flushAndCloseWithTimeout:(NSTimeInterval) timeout;
@end

#endif /* MLStreamRedirect_h */
