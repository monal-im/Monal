//
//  MLWebViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/1/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLWebViewController.h"
#import "HelperTools.h"

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
    
    UIBarButtonItem* openExternally = [[UIBarButtonItem alloc] init];
    openExternally.image = [UIImage systemImageNamed:@"safari"];
    [openExternally setTarget:self];
    [openExternally setAction:@selector(openExternally:)];
    [openExternally setIsAccessibilityElement:YES];
    [openExternally setAccessibilityLabel:NSLocalizedString(@"Open in default browser", @"")];
    self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:openExternally, nil];
}

-(void) openExternally:(id) sender
{
    DDLogDebug(@"Trying to open in default browser: %@", self.webview.URL);
    if(self.webview.URL.fileURL)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"") message:NSLocalizedString(@"This is an embedded file that can not be opened externally.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action __unused) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    else
        [[UIApplication sharedApplication] performSelector:@selector(openURL:) withObject:self.webview.URL];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if(self.urltoLoad.fileURL)
        [self.webview loadFileURL:self.urltoLoad allowingReadAccessToURL:self.urltoLoad];
    else
    {
        NSMutableURLRequest* nsrequest = [NSMutableURLRequest requestWithURL: self.urltoLoad];
        if([[HelperTools defaultsDB] boolForKey: @"useDnssecForAllConnections"])
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
