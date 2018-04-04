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
   
    NSString *contactName ;
    if(self.contact) {
       contactName =  [self.contact objectForKey:@"user"]; //dic form incoming
        if(!contactName)
        {
            contactName =  [self.contact objectForKey:@"buddy_name"]; // dic form outgoing
        }
        
        if(!contactName) {
            contactName = @"No Contact Selected";
            
        }
    } 
    
        self.userName.text=contactName;
    NSString* accountNo=[NSString stringWithFormat:@"%@", [self.contact objectForKey:@"account_id"]];
    
    [[MLImageManager sharedInstance] getIconForContact:contactName andAccount:accountNo withCompletion:^(UIImage *image) {
        self.userImage.image=image;
    }];
    
    [[MLXMPPManager sharedInstance] callContact:self.contact];
    
}

-(void) viewDidAppear:(BOOL)animated
{
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        if(!granted)
        {
            UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:@"Please Allow Audio Access" message:@"If you want to use VOIP you will need to allow access in Settings->Privacy->Microphone." preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *closeAction =[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                
            }];
            
            [messageAlert addAction:closeAction];
            [self presentViewController:messageAlert animated:YES completion:nil];
        }
    }];
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
    [[MLXMPPManager sharedInstance] hangupContact:self.contact];
    
    [self dismissViewControllerAnimated:YES completion:nil];
  
}

@end
