//
//  MLOAuthViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/16/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import "MLOAuthViewController.h"

@implementation MLOAuthViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    NSURLRequest*request=[NSURLRequest requestWithURL:self.oAuthURL];
    [self.webView loadRequest:request];
}


#pragma mark Web load delegate


- (void)webViewDidStartLoad:(UIWebView *)webView{
    
}

- (void)webViewDidFinishLoad:(UIWebView *)webView;
{
    
    NSString *title = [webView stringByEvaluatingJavaScriptFromString:@"document.title"];
    
    NSArray *components =[title componentsSeparatedByString:@"="];
    
    if(components.count>0)
    {
    
        if([[components objectAtIndex:0] isEqualToString:@"Success code"])
        {
            if(components.count>1)
            {
                NSString *token = [components objectAtIndex:1];
                if(self.completionHandler)
                {
                    self.completionHandler(token);
                }
                
            }
        }
    }
    
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(nullable NSError *)error{
    
}



@end
