//
//  CallViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/22/13.
//
//

#import <AVFoundation/AVFoundation.h>
#import "CallViewController.h"
#import "MLImageManager.h"
#import "MLXMPPManager.h"

@interface CallViewController ()

@end



@implementation CallViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}



-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    DDLogVerbose(@"call screen will appear");
    [UIDevice currentDevice].proximityMonitoringEnabled = YES;
   
    NSString *contactName ;
    if(self.contact) {
        contactName = self.contact.contactJid;
    }
    if(!contactName) {
        contactName = NSLocalizedString(@"No Contact Selected", @ "");
    }
    
    self.userName.text = contactName;
  
    [[MLImageManager sharedInstance] getIconForContact:contactName andAccount:self.contact.accountId withCompletion:^(UIImage *image) {
        self.userImage.image = image;
    }];
    
    [[MLXMPPManager sharedInstance] callContact:self.contact];
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        if(!granted)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Please Allow Audio Access",@ "") message:NSLocalizedString(@"If you want to use VOIP you will need to allow access in Settings-> Privacy-> Microphone.",@ "") preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction *closeAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@ "") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                    
                }];
                
                [messageAlert addAction:closeAction];
                [self presentViewController:messageAlert animated:YES completion:nil];
            });
        }
    }];
}

-(void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
	DDLogVerbose(NSLocalizedString(@"call screen did disappear",@ ""));
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
