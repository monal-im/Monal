//
//  MLChatImageCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/24/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "FLAnimatedImage.h"
#import "MLChatImageCell.h"
#import "MLImageManager.h"
#import "MLFiletransfer.h"
#import "MLMessage.h"
#import "HelperTools.h"

@import QuartzCore;
@import UIKit;

@interface MLChatImageCell() {
    FLAnimatedImageView* _animatedImageView;
}

@property (nonatomic, weak) IBOutlet UIImageView* thumbnailImage;
@property (nonatomic, weak) IBOutlet UIActivityIndicatorView* spinner;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint* imageWidth;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint* imageHeight;

@end

@implementation MLChatImageCell

-(void) awakeFromNib
{
    [super awakeFromNib];
    
    // Initialization code
    self.thumbnailImage.layer.cornerRadius = 15.0f;
    self.thumbnailImage.layer.masksToBounds = YES;
}

// init a image cell if needed
-(void) initCellWithMLMessage:(MLMessage*) message
{
    if(_animatedImageView != nil)
        [_animatedImageView removeFromSuperview];
    // reset image view if we open a new message
    if(self.messageHistoryId != message.messageDBId)
        self.thumbnailImage.image = nil;
    // init base cell
    [super initCell:message];
    // load image and display it in the UI if needed
    [self loadImage:message];
}

/// Load the image from messageText (link) and display it in the UI
-(void) loadImage:(MLMessage*) msg
{
    if(_animatedImageView != nil)
        [_animatedImageView removeFromSuperview];
    if(msg.messageText && self.thumbnailImage.image == nil)
    {
        [self.spinner startAnimating];
        NSDictionary* info = [MLFiletransfer getFileInfoForMessage:msg];
        if(info && [info[@"mimeType"] hasPrefix:@"image/gif"])
        {
            self.link = msg.messageText;
            // uses cached file if the file was already downloaded
            FLAnimatedImage* image = [FLAnimatedImage animatedImageWithGIFData:[NSData dataWithContentsOfFile:info[@"cacheFile"]]];
            if(!image)
                return;
            _animatedImageView = [FLAnimatedImageView new];
            DDLogVerbose(@"image: %fx%f", image.size.height, image.size.width);
            CGFloat wi = image.size.width;
            CGFloat hi = image.size.height;
            CGFloat ws = 225.0;
            CGFloat hs = 200.0;
            CGFloat ri = wi / hi;
            CGFloat rs = ws / hs;
            if(rs > ri)
                _animatedImageView.frame = CGRectMake(0.0, 0.0, wi * hs/hi, hs);
            else
                _animatedImageView.frame = CGRectMake(0.0, 0.0, ws, hi * ws/wi);
            self.imageWidth.constant = _animatedImageView.frame.size.width;
            self.imageHeight.constant = _animatedImageView.frame.size.height;
            _animatedImageView.animatedImage = image;
            [self.thumbnailImage addSubview:_animatedImageView];
            self.thumbnailImage.contentMode = UIViewContentModeScaleAspectFit;
        }
        else if(info && [info[@"mimeType"] hasPrefix:@"image/"])
        {
            self.link = msg.messageText;
            // uses cached file if the file was already downloaded
            UIImage* image = [[UIImage alloc] initWithContentsOfFile:info[@"cacheFile"]];
            if(!image)
                return;
            DDLogVerbose(@"image: %fx%f", image.size.height, image.size.width);
            CGFloat wi = image.size.width;
            CGFloat hi = image.size.height;
            CGFloat ws = 225.0;
            CGFloat hs = 200.0;
            CGFloat ri = wi / hi;
            CGFloat rs = ws / hs;
            if(rs > ri)
                self.thumbnailImage.frame = CGRectMake(0.0, 0.0, wi * hs/hi, hs);
            else
                self.thumbnailImage.frame = CGRectMake(0.0, 0.0, ws, hi * ws/wi);
            self.imageWidth.constant = self.thumbnailImage.frame.size.width;
            self.imageHeight.constant = self.thumbnailImage.frame.size.height;
            [self.thumbnailImage setImage:image];
        }
        else
            unreachable();
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
    if(_animatedImageView != nil)
        [_animatedImageView removeFromSuperview];
}


@end
