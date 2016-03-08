//
//  MLChatViewCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLChatViewCell.h"

#define kBubbleOffset 10
#define kdefaultPadding 5

@implementation MLChatViewCell


+ (NSRect) sizeWithMessage:(NSString *)messageString 
{
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:13.0f]};
    NSSize size = NSMakeSize(kCellMaxWidth-(kdefaultPadding*2), MAXFLOAT);
    CGRect rect = [messageString boundingRectWithSize:size options:NSLineBreakByWordWrapping | NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
    rect.size.height+=10;
    return rect;
    
}

-(void) updateDisplay
{
    self.messageRect = [MLChatViewCell sizeWithMessage:self.messageText.string];
    if (self.isInbound)
    {
        self.messageText.alignment= kCTTextAlignmentLeft;
    } else  {
        if( self.messageRect.size.width<=kCellMaxWidth )//&& self.messageRect.size.height<=kCellMinHeight)
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
   // NSLog(@"%@ %f", self.messageText.string, self.messageRect.size.width);
    
    CGRect bubbleFrame = self.frame;
    bubbleFrame.origin.y=0;
    bubbleFrame.size.height-=(kCellTimeStampHeight+kCellHeightOffset);
    bubbleFrame.size.width= self.messageRect.size.width+kdefaultPadding*3;
    if (self.isInbound)
    {
        bubbleFrame.origin.x=+20;
        [[NSColor controlHighlightColor] setFill];
    }
    else  {
        bubbleFrame.origin.x= self.frame.size.width -bubbleFrame.size.width-20;

        [[NSColor colorWithCalibratedRed:57.0/255 green:118.0f/255 blue:253.0/255 alpha:1.0] setFill];
        if(self.deliveryFailed) {
            self.retry.hidden=NO;
        }
        else{
            self.retry.hidden=YES;
        }
    }
    
    NSBezierPath *bezierPath= [NSBezierPath bezierPathWithRoundedRect:bubbleFrame xRadius:5.0 yRadius:5.0];
    
    
    [bezierPath fill];
    
}


@end
