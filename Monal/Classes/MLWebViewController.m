//
//  MLWebViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/1/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLWebViewController.h"

@interface MLWebViewController ()

@end

@implementation MLWebViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    WKWebViewConfiguration *theConfiguration = [[WKWebViewConfiguration alloc] init];
    self.webview = [[WKWebView alloc] initWithFrame:self.view.frame configuration:theConfiguration];
    self.webview.navigationDelegate=self;
    [self.view addSubview:self.webview];
   
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if(self.urltoLoad.fileURL)
    {
        [self.webview loadFileURL:self.urltoLoad allowingReadAccessToURL:self.urltoLoad];
    } else  {
        NSURLRequest *nsrequest=[NSURLRequest requestWithURL: self.urltoLoad];
        [self.webview loadRequest:nsrequest];
    }
    
    if(@available(iOS 11.0, *))
    {
        self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
  
}



@end
