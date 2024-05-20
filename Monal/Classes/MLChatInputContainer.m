//
//  MLChatInputContainer.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/20/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLChatInputContainer.h"

@implementation MLChatInputContainer
@synthesize chatInputActionDelegate;

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        self.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        self.chatInput.scrollEnabled = NO;
        self.chatInput.contentInset = UIEdgeInsetsMake(5, 0, 5, 0);
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    CGSize size = CGSizeMake(self.bounds.size.width, self.chatInput.intrinsicContentSize.height);
    return size;
}

- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    return [super hitTest:point withEvent:event];
}

-(BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    NSArray *subViews = self.subviews;
    for(UIView *subView in subViews) {
        if (CGRectContainsPoint(subView.frame, point) && subView.frame.origin.y < 0) {
            DDLogDebug(@"ScrollDown button tapped...");
            //without async dispatch this would do nothing
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.chatInputActionDelegate doScrollDownAction];
            });
        }
    }
    return [super pointInside:point withEvent:event];
}
@end
