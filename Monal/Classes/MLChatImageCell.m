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
#import "MLDefinitions.h"

@import QuartzCore;
@import UIKit;

@interface MLChatImageCell()

@property (nonatomic, weak) IBOutlet UIImageView* thumbnailImage;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView* spinner;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint* imageHeight;

@end

@implementation MLChatImageCell

-(void)awakeFromNib
{
    [super awakeFromNib];
    
    // Initialization code
    self.thumbnailImage.layer.cornerRadius = 15.0f;
    self.thumbnailImage.layer.masksToBounds = YES;
}

// init a image cell if needed
-(void) initCellWithMLMessage:(MLMessage*) message
{
    // reset image view if we open a new message
    if(self.messageHistoryId != message.messageDBId)
    {
        self.thumbnailImage.image = nil;
    }
    // init base cell
    [super initCell:message];
    // load image and display it in the UI if needed
    [self loadImage:message];
}

/// Load the image from messageText (link) and display it in the UI
-(void) loadImage:(MLMessage*) msg
{
    if(msg.messageText && self.thumbnailImage.image == nil)
    {
        [self.spinner startAnimating];
        NSDictionary* info = [MLFiletransfer getFileInfoForMessage:msg];
        if(info && [info[@"mimeType"] hasPrefix:@"image/"])
        {
            // uses cached file if the file was already downloaded
            UIImage* image = [[UIImage alloc] initWithContentsOfFile:info[@"cacheFile"]];
            [self.thumbnailImage setImage:image];
            self.link = msg.messageText;
            if(image && image.size.height > image.size.width)
                self.imageHeight.constant = 360;
        }
        else
        {
            unreachable();
        }
        [self.spinner stopAnimating];
    }
}

-(UIImage*) getDisplayedImage
{
    return self.thumbnailImage.image;
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
    pboard.image = [self getDisplayedImage];
}

-(void) prepareForReuse
{
    [super prepareForReuse];
    self.imageHeight.constant = 200;
    [self.spinner stopAnimating];
}


@end
