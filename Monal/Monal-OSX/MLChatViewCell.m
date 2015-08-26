//
//  MLChatViewCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLChatViewCell.h"

#define kBubbleOffset 10

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
        self.messageText.alignment= kCTTextAlignmentLeft;
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
    
//    NSImage* topLeftCorner ;
//    NSImage* topEdgeFill;
//    NSImage* topRightCorner;
//    NSImage* leftEdgeFill;
//    NSImage* centerFill;
//    NSImage* rightEdgeFill;
//    NSImage* bottomLeftCorner;
//    NSImage* bottomEdgeFill;
//    NSImage* bottomRightCorner;

    
    
    CGRect bubbleFrame = self.frame;
    if (self.messageRect.size.width<250) {
        bubbleFrame.size.width = self.messageRect.size.width+40;
    }
    else  {
        bubbleFrame.size.width = self.messageText.frame.size.width+20;
    }
    if (self.isInbound)
    {
//        bubbleFrame.origin.x= self.messageText.frame.origin.x+kBubbleOffset;
//        topLeftCorner =[NSImage imageNamed:@"topLeft_in"];
//        topEdgeFill= [NSImage imageNamed:@"topCenter_in"];
//        topRightCorner=[NSImage imageNamed:@"topRight_in"];
//        leftEdgeFill=[NSImage imageNamed:@"centerLeft_in"];
//        centerFill=[NSImage imageNamed:@"center_in"];
//        rightEdgeFill=[NSImage imageNamed:@"centerRight_in"];
//        bottomLeftCorner=[NSImage imageNamed:@"bottomLeft_in"];
//        bottomEdgeFill=[NSImage imageNamed:@"bottomCenter_in"];
//        bottomRightCorner=[NSImage imageNamed:@"bottomRight_in"];

    }
    else  {
        bubbleFrame.origin.x= self.frame.size.width -kBubbleOffset-  bubbleFrame.size.width;
        
//        topLeftCorner =[NSImage imageNamed:@"topLeft"];
//        topEdgeFill= [NSImage imageNamed:@"topCenter"];
//        topRightCorner=[NSImage imageNamed:@"topRight"];
//        leftEdgeFill=[NSImage imageNamed:@"centerLeft"];
//        centerFill=[NSImage imageNamed:@"center"];
//        rightEdgeFill=[NSImage imageNamed:@"centerRight"];
//        bottomLeftCorner=[NSImage imageNamed:@"bottomLeft"];
//        bottomEdgeFill=[NSImage imageNamed:@"bottomCenter"];
//        bottomRightCorner=[NSImage imageNamed:@"bottomRight"];
    }
   
//    NSDrawNinePartImage(bubbleFrame, topLeftCorner, topEdgeFill, topRightCorner,
//                        leftEdgeFill, centerFill, rightEdgeFill, bottomLeftCorner, bottomEdgeFill,
//                        bottomRightCorner, NSCompositeSourceOver, 1.0f, NO);
    
    
}

@end
