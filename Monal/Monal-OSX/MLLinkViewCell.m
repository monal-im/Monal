//
//  MLLinkCell.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 12/6/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLLinkViewCell.h"
#import "MLMetaInfo.h"

@implementation MLLinkViewCell


- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    self.bubbleView.wantsLayer=YES;
    self.bubbleView.layer.cornerRadius=16.0f;
    self.bubbleView.layer.backgroundColor = [NSColor colorWithRed:218/255.0 green:219/255. blue:222/255.0 alpha:1.0].CGColor;
    
}


-(void) loadPreviewWithCompletion:(void (^)(void))completion
{
    self.messageText.string=@"";
    self.imageUrl=@"";
    
    if(self.link) {
        self.website.stringValue=self.link;
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
                self.previewText.stringValue=[MLMetaInfo ogContentWithTag:@"og:title" inHTML:body] ;
                self.imageUrl=[[MLMetaInfo ogContentWithTag:@"og:image" inHTML:body] stringByRemovingPercentEncoding];
                [self loadImage:self.imageUrl WithCompletion:^{
                    if(completion) completion();
                }];
            });
        }] resume];
    } else  if(completion) completion();
}


-(void) openlink: (id) sender
{
        //launchbrowser
}

@end
