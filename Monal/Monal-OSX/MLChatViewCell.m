//
//  MLChatViewCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLChatViewCell.h"

@implementation MLChatViewCell


+ (NSRect) sizeWithMessage:(NSString *)messageString
{
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:13.0f]};
    NSSize size = NSMakeSize(kCellMax, MAXFLOAT);
    CGRect rect = [messageString boundingRectWithSize:size options:NSLineBreakByWordWrapping | NSStringDrawingUsesLineFragmentOrigin attributes:attributes];

    return rect;
    
}

-(void) updateDisplay
{
    NSRect rect = [MLChatViewCell sizeWithMessage:self.messageText.string];
    if (self.isInbound)
    {
        if(rect.size.width<kCellMax)
        {
            self.messageText.alignment= kCTTextAlignmentLeft;
        }
        else  {
            self.messageText.alignment= kCTTextAlignmentRight;
        }
    } else  {
        if(rect.size.width<kCellMax)
        {
            self.messageText.alignment= kCTTextAlignmentRight;
        }
        else  {
            self.messageText.alignment= kCTTextAlignmentLeft;
        }
    }
}

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
         // self.messageText.backgroundColor = [NSColor clearColor];
    }
    
    CGRect bubbleFrame = self.frame;
    bubbleFrame.origin.x= self.frame.size.width -40 - self.messageText.frame.size.width-10;
    bubbleFrame.size.width = self.messageText.frame.size.width+25;
    
    
    NSDrawNinePartImage(bubbleFrame, topLeftCorner, topEdgeFill, topRightCorner,
                        leftEdgeFill, centerFill, rightEdgeFill, bottomLeftCorner, bottomEdgeFill,
                        bottomRightCorner, NSCompositeSourceOver, 1.0f, NO);
    
}

@end
