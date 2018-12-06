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


-(void) loadPreviewWithCompletion:(void (^)(void))completion
{
    self.messageText.string=@"";
    self.imageUrl=@"";
    
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
                self.messageText.string=[MLMetaInfo ogContentWithTag:@"og:title" inHTML:body] ;
                self.imageUrl=[[MLMetaInfo ogContentWithTag:@"og:image" inHTML:body] stringByRemovingPercentEncoding];
                [self loadImageWithCompletion:^{
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
