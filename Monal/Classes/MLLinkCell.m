//
//  MLLinkCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 10/29/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLLinkCell.h"
#import "MLMetaInfo.h"
#import "UIImageView+WebCache.h"
#import "MonalAppDelegate.h"
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
        NSURL *url= [NSURL URLWithString:self.link];
        if([url.scheme isEqualToString:@"xmpp"] )
        {
            MonalAppDelegate* delegate =(MonalAppDelegate*) [UIApplication sharedApplication].delegate;
            [delegate handleURL:url];
        }
        
        else if ([url.scheme isEqualToString:@"http"] ||
                 [url.scheme isEqualToString:@"https"]) {
            SFSafariViewController *safariView = [[ SFSafariViewController alloc] initWithURL:url];
            [self.parent presentViewController:safariView animated:YES completion:nil];
        }
        
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

-(void) loadPreviewWithCompletion:(void (^)(void))completion
{
    self.messageTitle.text=nil;
    self.imageUrl=[NSURL URLWithString:@""];
    
    if(self.link) {
        /**
         <meta property="og:title" content="Nintendo recommits to “keep the business going” for 3DS">
         <meta property="og:image" content="https://cdn.arstechnica.net/wp-content/uploads/2016/09/3DS_SuperMarioMakerforNintendo3DS_char_01-760x380.jpg">
         facebookexternalhit/1.1
         */
        NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:self.link]];
        [request setValue:@"facebookexternalhit/1.1" forHTTPHeaderField:@"User-Agent"]; //required on somesites for og tages e.g. youtube
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.messageTitle.text=[MLMetaInfo ogContentWithTag:@"og:title" inHTML:body] ;
                self.imageUrl=[NSURL URLWithString:[[MLMetaInfo ogContentWithTag:@"og:image" inHTML:body] stringByRemovingPercentEncoding]];
                if(self.imageUrl) {
                    [self loadImageWithCompletion:^{
                        if(completion) completion();
                    }];
                }
            });
        }] resume];
    } else  if(completion) completion();
}

-(void) loadImageWithCompletion:(void (^)(void))completion
{
    if(self.imageUrl) {
        [self.previewImage sd_setImageWithURL:self.imageUrl completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
            if(error) {
                self.previewImage.image=nil;
            }
            
            if(completion) completion();
        }];
    } else  if(completion) completion();
}

@end
