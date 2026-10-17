//
//  MLResizingTextView.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/2/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import "MLResizingTextView.h"
#import <monalxmpp/HelperTools.h>

@implementation MLResizingTextView

- (void) layoutSubviews
{
    [super layoutSubviews];
    
    if (!CGSizeEqualToSize(self.bounds.size, [self intrinsicContentSize])) {
        [self invalidateIntrinsicContentSize];
    }
    if([[HelperTools defaultsDB] boolForKey: @"showKeyboardOnChatOpen"])
        [self becomeFirstResponder];
}

- (CGSize)intrinsicContentSize
{
    CGSize intrinsicContentSize = self.contentSize;
    
    intrinsicContentSize.width += (self.textContainerInset.left + self.textContainerInset.right ) / 2.0f;
   // intrinsicContentSize.height += (self.textContainerInset.top + self.textContainerInset.bottom) / 2.0f;
    
    return intrinsicContentSize;
}

-(NSArray<UIKeyCommand*>*) keyCommands
{
    UIKeyCommand* const tabCommand = [UIKeyCommand keyCommandWithInput: @"\t" modifierFlags: 0 action:@selector(ignore)];
    return @[tabCommand];
}

-(void) ignore
{
}

@end
