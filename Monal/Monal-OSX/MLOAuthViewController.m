//
//  MLOAuthViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/1/16.
//  Copyright © 2016 Monal.im. All rights reserved.
//

#import "MLOAuthViewController.h"

@interface MLOAuthViewController ()

@end

@implementation MLOAuthViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

-(void) viewWillAppear
{
    [super viewWillAppear];
    
    NSURLRequest*request=[NSURLRequest requestWithURL:self.oAuthURL];
    [[self.webView mainFrame] loadRequest:request];
}


#pragma mark Web load delegate

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    
}
- (void)webView:(WebView *)senderd didFinishLoadForFrame:(WebFrame *)frame {
    
}

@end
