//
//  MLTextView.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 5/23/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLTextView.h"

@implementation MLTextView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}


- (NSSize) intrinsicContentSize {
    NSTextContainer* textContainer = [self textContainer];
    NSLayoutManager* layoutManager = [self layoutManager];
    [layoutManager ensureLayoutForTextContainer: textContainer];
    return [layoutManager usedRectForTextContainer: textContainer].size;
}

- (void) didChangeText {
    [super didChangeText];
    [self invalidateIntrinsicContentSize];
}

@end
