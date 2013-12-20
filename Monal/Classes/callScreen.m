//
//  callScreen.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "callScreen.h"

@implementation callScreen
@synthesize navigationController;
@synthesize splitViewController;



-(void) show:(xmpp*) conn:(NSString*) name
{
    
  //for ipad show differently 
    if([[tools machine] isEqualToString:@"iPad"])
    {
        
    modalNav = [[UINavigationController alloc] init];
       [ modalNav.view addSubview:self.view];
     
        modalNav.modalPresentationStyle=UIModalPresentationFormSheet;
  
        [splitViewController presentModalViewController:modalNav animated:YES];
    }
    
    else
    {
    
    
    [navigationController presentModalViewController:self animated:YES];
    }
    
    nameLabel.text=name;
    
    jabber=conn; 
    // check for two resources here.. for for now jsut grab the first
    //need to change the xmpp function to take  resource
    
    
    [jabber startCallUser:name];
	
     
}


-(void) endPress
{
 DDLogVerbose(@"end pressed"); 
    
     
   //terminate voip call here too 
    
    if([[tools machine] isEqualToString:@"iPad"])
    {
        [splitViewController dismissModalViewControllerAnimated:YES];
    }
    
    else
    {
        
        
         [navigationController dismissModalViewControllerAnimated:YES];
    }
    
    
    [jabber endCall];
    
   
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    DDLogVerbose(@"call screen did  load");
    
   // [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    self.view.autoresizesSubviews=YES;
    
   
    endButton = [[UIButton alloc] initWithFrame:CGRectMake(20, self.view.frame.size.height-75, self.view.frame.size.width-40, 50)];
    [endButton setTitle:@"End Call" forState:UIControlStateNormal];
    [endButton setBackgroundImage:[UIImage imageNamed:@"red_button_gloss"] forState:UIControlStateNormal];
    [endButton addTarget:self action:@selector(endPress) forControlEvents:UIControlEventTouchUpInside];
    
    messageLabel =[[UILabel alloc] initWithFrame:CGRectMake(0, 20,  self.view.frame.size.width, 50)];
    messageLabel.text=@"Calling";
    [messageLabel setFont:[UIFont systemFontOfSize:30]];
    messageLabel.backgroundColor = [UIColor blackColor];;
    messageLabel.textColor=[UIColor whiteColor];
    messageLabel.textAlignment=UITextAlignmentCenter;
    
    
    
    nameLabel =[[UILabel alloc] initWithFrame:CGRectMake(0, 80,  self.view.frame.size.width, 50)];
    nameLabel.text=@"contactname";
    [nameLabel setFont:[UIFont systemFontOfSize:25]];
    nameLabel.backgroundColor = [UIColor blackColor];;
    nameLabel.textColor=[UIColor whiteColor];
    nameLabel.textAlignment=UITextAlignmentCenter;
    
    
    
    [self.view addSubview:nameLabel];
    [self.view addSubview:messageLabel];
    [self.view addSubview:endButton];
    
}

- (void)viewDidUnload
{
 DDLogVerbose(@"call screen did  unload");
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if(interfaceOrientation==UIInterfaceOrientationPortrait)
        return YES;
        else
    
    return NO;
}


-(void)proximityStateDidChange
{
   DDLogVerbose(@"proximity %d", [ [UIDevice currentDevice] proximityState]) ;
}

-(void) viewWillAppear:(BOOL)animated
{
    
      
	DDLogVerbose(@"call screen will  appear");
	
    if([[tools machine] isEqualToString:@"iPad"])
    {
    self.view.frame = modalNav.view.frame;
    }
    
    endButton.frame=CGRectMake(20, self.view.frame.size.height-75, self.view.frame.size.width-40, 50);
    messageLabel.frame=CGRectMake(0, 20,  self.view.frame.size.width, 50);
  
    
    
    nameLabel.frame=CGRectMake(0, 80,  self.view.frame.size.width, 50);
    
    
    
   [UIDevice currentDevice].proximityMonitoringEnabled=YES;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(proximityStateDidChange)
                                                 name:@"ProximityChange'" object:nil];

    
}

-(void)viewDidDisappear:(BOOL)animated
{
	DDLogVerbose(@"call screen did  disappear");
    
    [UIDevice currentDevice].proximityMonitoringEnabled=NO;
    
	
	
}

@end
