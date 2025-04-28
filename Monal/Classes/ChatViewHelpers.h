//
//  ChatViewHelpers.h
//  Monal
//
//  Created by lissine on 28/4/2025.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MLContact;

@interface ChatViewHelpers : NSObject

+(void) refreshCounterForContact:(MLContact*) contact;

@end

NS_ASSUME_NONNULL_END
