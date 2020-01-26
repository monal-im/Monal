//
//  MLChatInputContainer.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/20/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLChatInputContainer.h"

@implementation MLChatInputContainer


- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        self.autoresizingMask= UIViewAutoresizingFlexibleHeight;
        self.chatInput.scrollEnabled=NO;
        self.chatInput.contentInset = UIEdgeInsetsMake(5, 0, 5, 0);
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    CGSize size= CGSizeMake(self.bounds.size.width,  self.chatInput.intrinsicContentSize.height);
    return size;
}

@end
