//
//  HelpViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "HelpViewController.h"

@interface HelpViewController ()

@end

@implementation HelpViewController

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
    self.navigationItem.title=NSLocalizedString(@"Help",@"");
    self.view.backgroundColor=[UIColor lightGrayColor];
    self.view.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;

    _webView=[[UIWebView alloc] init];
    _webView.delegate=self; 
    self.view=_webView;

}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    NSURL *websiteUrl = [NSURL URLWithString:kMonalHelpURL];
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:websiteUrl];
    [_webView loadRequest:urlRequest];
    
    UIBarButtonItem* rightButton =[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"765-arrow-left"] style:UIBarButtonItemStyleBordered target:self action:@selector(goBack)];
    self.navigationItem.rightBarButtonItem=rightButton; 
     
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) goBack
{
    [_webView goBack];
}

@end
