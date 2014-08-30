//
//  AboutViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "AboutViewController.h"

@interface AboutViewController ()

@end

@implementation AboutViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.navigationItem.title=NSLocalizedString(@"About",@"");
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    _webView=[[UIWebView alloc] init];
    self.view=_webView;
    
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    NSURL *websiteUrl = [NSURL URLWithString:@""];
    NSError* error = nil;
    NSString *path = [[NSBundle mainBundle] pathForResource: @"About" ofType: @"html"];
    NSString *res = [NSString stringWithContentsOfFile: path encoding:NSUTF8StringEncoding error: &error];
    NSString* withVer =[NSString stringWithFormat:res,
                         [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ,
                         [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] ];
    
    
    [_webView loadHTMLString:withVer baseURL:websiteUrl];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
