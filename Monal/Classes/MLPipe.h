//
//  MLPipe.h
//  Monal
//
//  Created by Thilo Molitor on 03.05.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <monalxmpp/MLConstants.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLPipe : NSObject<NSStreamDelegate>

-(id) initWithInputStream:(NSInputStream*) inputStream andOuterDelegate:(id <NSStreamDelegate>) outerDelegate;
-(void) close;
-(NSInputStream*) getNewOutputStream;
-(NSNumber*) drainInputStreamAndCloseOutputStream;

@end

NS_ASSUME_NONNULL_END
