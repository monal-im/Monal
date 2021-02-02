//
//  ContainsEmoji.h
//  monalxmpp
//
//  Created by Anurodh Pokharel on 2/2/21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EmojiUtilities : NSObject

+ (CFMutableCharacterSetRef)emojiCharacterSet;
+ (BOOL)containsEmoji:(NSString *)emoji;

@end

NS_ASSUME_NONNULL_END
