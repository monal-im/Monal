//
//  MLChatImageCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLChatImageCell.h"
#import "MLImageManager.h"
#import "MLFiletransfer.h"
#import "MLMessage.h"
@import QuartzCore;
@import UIKit;

@implementation MLChatImageCell

-(void)awakeFromNib
{
    [super awakeFromNib];
    
    // Initialization code
    self.thumbnailImage.layer.cornerRadius = 15.0f;
    self.thumbnailImage.layer.masksToBounds = YES;
}

-(void) loadImage
{
    if(self.msg.messageText && self.thumbnailImage.image == nil && !self.loading)
    {
        [self.spinner startAnimating];
        self.loading=YES;
        NSString* currentLink = self.msg.messageText;
        NSDictionary* info = [MLFiletransfer getFileInfoForMessage:self.msg];
        if(info && [info[@"mimeType"] hasPrefix:@"image/"])
        {
            if([currentLink isEqualToString:self.msg.messageText])
            {
                UIImage* image = [[UIImage alloc] initWithContentsOfFile:info[@"cacheFile"]];
                [self.thumbnailImage setImage:image];
                self.link = currentLink;
                if(image && image.size.height > image.size.width)
                    self.imageHeight.constant = 360;
                self.loading = NO;
                [self.spinner stopAnimating];
            }
        }
    }
}

-(void) setSelected:(BOOL) selected animated:(BOOL) animated
{
    [super setSelected:selected animated:animated];
    // Configure the view for the selected state
}

-(BOOL) canPerformAction:(SEL) action withSender:(id) sender
{
    return (action == @selector(copy:));
}

-(void) copy:(id) sender
{
    UIPasteboard* pboard = [UIPasteboard generalPasteboard];
    pboard.image = self.thumbnailImage.image; 
}

-(void) prepareForReuse
{
    [super prepareForReuse];
    self.imageHeight.constant = 200;
    [self.spinner stopAnimating];
}


@end
