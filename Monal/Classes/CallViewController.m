//
//  CallViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/22/13.
//
//

#import "CallViewController.h"
#import "DDLog.h"

@interface CallViewController ()

@end

static const int ddLogLevel = LOG_LEVEL_ERROR;

@implementation CallViewController

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
    // Do any additional setup after loading the view from its nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark tableview datasource delegate
-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if(interfaceOrientation==UIInterfaceOrientationPortrait)
        return YES;
    else
        
        return NO;
}

-(void) viewWillAppear:(BOOL)animated
{
    
    DDLogVerbose(@"call screen will  appear");
    [UIDevice currentDevice].proximityMonitoringEnabled=YES;
    
}

-(void)viewDidDisappear:(BOOL)animated
{
	DDLogVerbose(@"call screen did  disappear");
    
    [UIDevice currentDevice].proximityMonitoringEnabled=NO;
    
	
	
}


-(IBAction)cancelCall:(id)sender
{
    [self dismissModalViewControllerAnimated:YES];
}

@end
