//
//  MLDisabledScrollView.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/10/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLDisabledScrollView.h"

@implementation MLDisabledScrollView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
}

- (void)scrollWheel:(NSEvent *)theEvent
{
    [[self nextResponder] scrollWheel:theEvent];
}

@end
