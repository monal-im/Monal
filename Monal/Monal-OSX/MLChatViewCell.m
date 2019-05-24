//
//  MLChatViewCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLChatViewCell.h"
#import "MLImageManager.h"

#define kBubbleOffset 10


@implementation MLChatViewCell


+ (NSRect) sizeWithMessage:(NSString *)messageString 
{
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:13.0f]};
    if([messageString lengthOfBytesUsingEncoding:NSUTF32StringEncoding]<4)
    {
        attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:38.0f]};
    }
    NSSize size = NSMakeSize(kCellMaxWidth-(kCellDefaultPadding*2), MAXFLOAT);
    CGRect rect = [messageString boundingRectWithSize:size options:NSLineBreakByWordWrapping | NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
    rect.size.height+=10;
    return rect;
    
}

-(void) loadImage:(NSString *) link WithCompletion:(void (^)(void))completion
{
    if([self.link isEqualToString:link] &&  self.attachmentImage.image) {
        if(completion) completion();
        return;
    }
    self.link=link;
    NSString *currentLink = link;
    [[MLImageManager sharedInstance] imageForAttachmentLink:self.link withCompletion:^(NSData * _Nullable data) {
        NSImage *image=[[NSImage alloc] initWithData:data];
        dispatch_async(dispatch_get_main_queue(), ^{
            if([currentLink isEqualToString:self.link]){
                    if(data) {
                        self.attachmentImage.image = image;
                        
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
            }
            else  if(completion) completion();
            
        });
    }];
    
  
}

-(void) updateDisplay
{
     BOOL isDark=[self isDark];
    self.messageRect = [MLChatViewCell sizeWithMessage:self.messageText.string];
    if (self.isInbound)
    {
        self.messageText.alignment= kCTTextAlignmentLeft;
        if(isDark) {
            self.messageText.textColor = [NSColor whiteColor];
        } else  {
            self.messageText.textColor = [NSColor blackColor];
        }
        
    } else  {
        self.messageText.textColor = [NSColor whiteColor];
        if( self.messageRect.size.width<kCellMaxWidth )//&& self.messageRect.size.height<=kCellMinHeight)
        {
            self.messageText.alignment= kCTTextAlignmentRight;
        }
        else  {
            self.messageText.alignment= kCTTextAlignmentLeft;
        }
    }
    self.messageText.font =[NSFont systemFontOfSize:13.0f];
    
     if([self.messageText.string lengthOfBytesUsingEncoding:NSUTF32StringEncoding]<4)
     {
         self.messageText.font =[NSFont systemFontOfSize:38.0f];
     }
}

-(BOOL) isDark {
    NSAppearance *appearance = NSAppearance.currentAppearance;
    BOOL isDark=NO;
    if (@available(*, macOS 10.14)) {
        if(appearance.name == NSAppearanceNameDarkAqua) {
            isDark=YES;
        }
    }
    return isDark;
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
    
    BOOL isDark=[self isDark];
    
    bubbleFrame.size.width= self.messageRect.size.width+40+kCellDefaultPadding*3;
    if (self.isInbound)
    {
        bubbleFrame.origin.x=+self.senderIcon.frame.size.width+kCellDefaultPadding*3;
        if(isDark) {
            [[NSColor colorWithCalibratedRed:84.0/255 green:84.0f/255 blue:84.0/255 alpha:1.0] setFill];
        } else  {
            [[NSColor colorWithCalibratedRed:233.0/255 green:232.0f/255 blue:233.0/255 alpha:1.0] setFill];
        }
    }
    else  {
        bubbleFrame.origin.x= self.frame.size.width -bubbleFrame.size.width-20;
        
        if(isDark) {
            [[NSColor colorWithCalibratedRed:0.0/255 green:107.0f/255 blue:243.0/255 alpha:1.0] setFill];
        }
        else {
            [[NSColor colorWithCalibratedRed:57.0/255 green:118.0f/255 blue:253.0/255 alpha:1.0] setFill];
        }
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
