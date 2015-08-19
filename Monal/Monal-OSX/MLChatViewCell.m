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
    self.messageRect = [MLChatViewCell sizeWithMessage:self.messageText.string];
    if (self.isInbound)
    {
        if( self.messageRect.size.width<kCellMax)
        {
            self.messageText.alignment= kCTTextAlignmentLeft;
        }
        else  {
            self.messageText.alignment= kCTTextAlignmentRight;
        }
    } else  {
        if( self.messageRect.size.width<kCellMax)
        {
            self.messageText.alignment= kCTTextAlignmentRight;
        }
        else  {
            self.messageText.alignment= kCTTextAlignmentLeft;
        }
    }
    self.messageText.font =[NSFont systemFontOfSize:13.0f];
    
   
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
    
    
    CGRect bubbleFrame = self.frame;
    if (self.messageRect.size.width<250) {
        bubbleFrame.size.width = self.messageRect.size.width+40;
    }
    else  {
        bubbleFrame.size.width = self.messageText.frame.size.width+20;
    }
    if (self.isInbound)
    {
        bubbleFrame.origin.x= self.messageText.frame.origin.x+25;
    }
    else  {
        bubbleFrame.origin.x= self.frame.size.width -25-  bubbleFrame.size.width;
    }
   
    NSDrawNinePartImage(bubbleFrame, topLeftCorner, topEdgeFill, topRightCorner,
                        leftEdgeFill, centerFill, rightEdgeFill, bottomLeftCorner, bottomEdgeFill,
                        bottomRightCorner, NSCompositeSourceOver, 1.0f, NO);
    
}

@end
