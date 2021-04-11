//
//  MLChatViewHelper.h
//  Monal
//
//  Created by Friedrich Altheide on 04.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLContact.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLChatViewHelper<ClassType> : NSObject

+(void) toggleEncryptionForContact:(MLContact*) contact withKnownDevices:(NSArray*) knownDevices withSelf:(id) andSelf afterToggle:(void (^)(void)) afterToggle;

@end

NS_ASSUME_NONNULL_END
