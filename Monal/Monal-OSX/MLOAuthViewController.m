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
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    
}

- (void)webView:(WebView *)sender willCloseFrame:(WebFrame *)frame
{

}

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
   
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
@end
