//
//  MLChatViewCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLChatViewCell.h"

@implementation MLChatViewCell

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    NSImage* topLeftCorner =[NSImage imageNamed:@"topLeft"];
    NSImage* topEdgeFill= [NSImage imageNamed:@"topCenter"];
    NSImage* topRightCorner=[NSImage imageNamed:@"topRight"];
    NSImage* leftEdgeFill=[NSImage imageNamed:@"centerLeft"];
    NSImage* centerFill=[NSImage imageNamed:@"center"];
    NSImage* rightEdgeFill=[NSImage imageNamed:@"centerRight"];
    NSImage* bottomLeftCorner=[NSImage imageNamed:@"bottomLeft"];
    NSImage* bottomEdgeFill=[NSImage imageNamed:@"bottomCenter"];
    NSImage* bottomRightCorner=[NSImage imageNamed:@"bottomRight"];
    
    if(self.isInbound)
    {
    
    } else  {
        
    }
    
    CGRect bubbleFrame = self.frame;
    bubbleFrame.origin.x= self.messageText.frame.origin.x;
    bubbleFrame.size.width = self.messageText.frame.size.width;
    
    
    NSDrawNinePartImage(bubbleFrame, topLeftCorner, topEdgeFill, topRightCorner,
                        leftEdgeFill, centerFill, rightEdgeFill, bottomLeftCorner, bottomEdgeFill,
                        bottomRightCorner, NSCompositeSourceOver, 1.0f, NO);
    
}

@end
