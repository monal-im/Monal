//
//  MLLinkCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 10/29/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLLinkCell.h"
#import "UIImageView+WebCache.h"
#import "MonalAppDelegate.h"
#import "HelperTools.h"

@import SafariServices;


@implementation MLLinkCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
    self.bubbleView.layer.cornerRadius=16.0f;
    self.bubbleView.clipsToBounds=YES;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}



-(void) openlink: (id) sender {
    
    if(self.link)
    {
        NSURL* url = [NSURL URLWithString:self.link];
        DDLogInfo(@"Opening link (inline=%@): %@", bool2str([[HelperTools defaultsDB] boolForKey: @"useInlineSafari"]), url);
        if([[HelperTools defaultsDB] boolForKey: @"useInlineSafari"] && ([url.scheme.lowercaseString isEqualToString:@"http"] || [url.scheme.lowercaseString isEqualToString:@"https"]))
        {
            SFSafariViewController *safariView = [[ SFSafariViewController alloc] initWithURL:url];
            [self.parent presentViewController:safariView animated:YES completion:nil];
        }
        else
            [[UIApplication sharedApplication] performSelector:@selector(openURL:) withObject:url];
    }
}

-(BOOL) canPerformAction:(SEL)action withSender:(id)sender
{
    if(action == @selector(openlink:))
    {
        if(self.link)
            return  YES;
    }
    return (action == @selector(copy:)) ;
}

-(void) copy:(id)sender {
    UIPasteboard *pboard = [UIPasteboard generalPasteboard];
    pboard.string =self.link;
}


-(void) loadImageWithCompletion:(void (^)(void))completion
{
    if(self.imageUrl) {
        [self.previewImage sd_setImageWithURL:self.imageUrl completed:^(UIImage *image __unused, NSError *error, SDImageCacheType cacheType __unused, NSURL *imageURL __unused) {
            if(error) {
                self.previewImage.image=nil;
            }
            
            if(completion) completion();
        }];
    } else  {
        self.previewImage.image=nil;
        if(completion) completion();
    }
}

-(void)prepareForReuse
{
    [super prepareForReuse];
    self.messageTitle.text=nil;
    self.imageUrl=[NSURL URLWithString:@""];
    self.previewImage.image=nil;
}

@end
