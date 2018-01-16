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
    if(messageString.length<4)
    {
        attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:38.0f]};
    }
    NSSize size = NSMakeSize(kCellMaxWidth-(kCellDefaultPadding*2), MAXFLOAT);
    CGRect rect = [messageString boundingRectWithSize:size options:NSLineBreakByWordWrapping | NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
    rect.size.height+=10;
    return rect;
    
}

-(void) loadImageWithCompletion:(void (^)(void))completion
{
    NSMutableURLRequest *imageRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.link]];
    imageRequest.cachePolicy= NSURLRequestReturnCacheDataElseLoad;
    [[[NSURLSession sharedSession] dataTaskWithRequest:imageRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        self.imageData= data;
        dispatch_async(dispatch_get_main_queue(), ^{
            if(data) {
                self.attachmentImage.image = [[NSImage alloc] initWithData:data];
                
                if (  self.attachmentImage.image.size.height>  self.attachmentImage.image.size.width) {
                    self.imageHeight.constant = 360;
                    
                }
                else
                {
                    self.imageHeight.constant= 200;
                }
            } else  {
                self.attachmentImage.image=nil;
            }
            if(completion) completion();
        });
    }] resume];
}

-(void) updateDisplay
{
    self.messageRect = [MLChatViewCell sizeWithMessage:self.messageText.string];
    if (self.isInbound)
    {
        self.messageText.alignment= kCTTextAlignmentLeft;
        
    } else  {
        if( self.messageRect.size.width<kCellMaxWidth )//&& self.messageRect.size.height<=kCellMinHeight)
        {
            self.messageText.alignment= kCTTextAlignmentRight;
        }
        else  {
            self.messageText.alignment= kCTTextAlignmentLeft;
        }
    }
    self.messageText.font =[NSFont systemFontOfSize:13.0f];
    
     if(self.messageText.string.length<4)
     {
         self.messageText.font =[NSFont systemFontOfSize:38.0f];
     }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if(!self.messageText) return; 
    
   // NSLog(@"%@ %f", self.messageText.string, self.messageRect.size.width);
    
    if(self.attachmentImage) return; 
    
    CGRect bubbleFrame = self.frame;
    bubbleFrame.origin.y=0;
    bubbleFrame.size.height-=(kCellDefaultPadding);
    BOOL showingSender=NO;
    
    if(self.senderName){
        showingSender=!self.senderName.hidden;
    }
    
    if(!self.timeStamp.hidden || showingSender )
    {
        bubbleFrame.size.height-=(kCellTimeStampHeight+kCellDefaultPadding);
    }
    bubbleFrame.size.width= self.messageRect.size.width+kCellDefaultPadding*3;
    if (self.isInbound)
    {
        bubbleFrame.origin.x=+self.senderIcon.frame.size.width+kCellDefaultPadding*3;
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
