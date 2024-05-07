//
//  MLWebViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/1/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLWebViewController.h"

@interface MLWebViewController ()
@property (weak, nonatomic) IBOutlet WKWebView* webview;
@property (nonatomic, strong) NSURL* urltoLoad;
@end

@implementation MLWebViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    self.webview.contentMode = UIViewContentModeScaleAspectFill;
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if(self.urltoLoad.fileURL)
        [self.webview loadFileURL:self.urltoLoad allowingReadAccessToURL:self.urltoLoad];
    else
    {
        NSMutableURLRequest* nsrequest = [NSMutableURLRequest requestWithURL: self.urltoLoad];
        if(@available(iOS 16.1, macCatalyst 16.1, *))
            nsrequest.requiresDNSSECValidation = YES;
        [self.webview loadRequest:nsrequest];
    }
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

-(void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

-(void) initEmptyPage
{
    [self initViewWithUrl:nil];
}

-(void) initViewWithUrl:(NSURL*) url
{
    self.urltoLoad = url;
}

@end
