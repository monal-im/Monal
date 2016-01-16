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
    NSSize size = NSMakeSize(kCellMax-(kdefaultPadding*2), MAXFLOAT);
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
        if( self.messageRect.size.width<240 )//&& self.messageRect.size.height<=kCellMinHeight)
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
    if (self.messageRect.size.width<240) {
        bubbleFrame.size.width = self.messageRect.size.width+40;
    }
    else  {
        bubbleFrame.size.width = self.messageText.frame.size.width+20;
    }
    
    if (self.isInbound)
    {
        bubbleFrame.origin.x= self.messageText.frame.origin.x+kBubbleOffset*2;
        bubbleFrame.size.width-=kBubbleOffset*2;
        [[NSColor controlHighlightColor] setFill];
    }
    else  {
        bubbleFrame.origin.x= self.frame.size.width -kBubbleOffset-  bubbleFrame.size.width;
        
        [[NSColor colorWithCalibratedRed:57.0/255 green:118.0f/255 blue:253.0/255 alpha:1.0] setFill];
        if(self.deliveryFailed) {
            self.retry.hidden=NO;
        }
        else{
            self.retry.hidden=YES;
        }
    }
    
    bubbleFrame.origin.y+=5;
    bubbleFrame.size.height-=10;
    
    NSBezierPath *bezierPath= [NSBezierPath bezierPathWithRoundedRect:bubbleFrame xRadius:5.0 yRadius:5.0];
    
    
    [bezierPath fill];
    
}


@end
