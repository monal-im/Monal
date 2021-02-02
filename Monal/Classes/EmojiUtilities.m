//
//  ContainsEmoji.m
//  monalxmpp
//
//  Created by Anurodh Pokharel on 2/2/21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "EmojiUtilities.h"

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

@implementation EmojiUtilities

+ (CFMutableCharacterSetRef)emojiCharacterSet {
    static CFMutableCharacterSetRef set = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = CFCharacterSetCreateMutableCopy(kCFAllocatorDefault, CTFontCopyCharacterSet(CTFontCreateWithName(CFSTR("AppleColorEmoji"), 0.0, NULL)));
        CFCharacterSetRemoveCharactersInString(set, CFSTR(" 0123456789#*"));
    });
    return set;
}

+ (BOOL)containsEmoji:(NSString *)emoji {
    return CFStringFindCharacterFromSet((CFStringRef)emoji, [self emojiCharacterSet], CFRangeMake(0, emoji.length), 0, NULL);
}

@end
