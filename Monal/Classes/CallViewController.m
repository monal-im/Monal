//
//  CallViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/22/13.
//
//

#import "CallViewController.h"
#import "MLImageManager.h"
#import "MLXMPPManager.h"
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

-(id) initWithContact:(NSDictionary*) contact
{
    self=[super init];
    if(self) {
        _contact=contact;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}



-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    DDLogVerbose(@"call screen will  appear");
    [UIDevice currentDevice].proximityMonitoringEnabled=YES;
    
    self.userName.text=[_contact objectForKey:@"full_name"];
    NSString* accountNo=[NSString stringWithFormat:@"%@", [_contact objectForKey:@"account_id"]];
    
    self.userImage.image=[[MLImageManager sharedInstance] getIconForContact:[_contact objectForKey:@"buddy_name"] andAccount:accountNo];
    
    [[MLXMPPManager sharedInstance] callContact:_contact];
    
}

-(void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
	DDLogVerbose(@"call screen did  disappear");
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



-(IBAction)cancelCall:(id)sender
{
    [UIDevice currentDevice].proximityMonitoringEnabled=NO;
    [[MLXMPPManager sharedInstance] hangupContact:_contact];
    
    [self dismissModalViewControllerAnimated:YES];
  
}

@end
