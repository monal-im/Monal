//
//  callScreen.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "callScreen.h"

@implementation callScreen

-(void) init:(UINavigationController*) nav
{
   navigationController=nav;
    
	//[self initWithNibName:@"callScreen" bundle:nil];
 
    
   
}

-(void) show:(xmpp*) conn:(NSString*) name
{
    
   
    
    //for ipad show differently 
    if([[tools machine] isEqualToString:@"iPad"])
    {
        self.modalPresentationStyle=UIModalPresentationFormSheet; 
    }
    
    
    [navigationController presentModalViewController:self animated:YES];
    
    
    buddyName.text=name; 
    
	
     
}


-(void) endPress
{
 debug_NSLog(@"end pressed"); 
    
      [navigationController dismissModalViewControllerAnimated:YES];
   //terminate voip call here too 
    
    [jabber endCall];
    
   
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    debug_NSLog(@"call screen did  appear");
    
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    endButton = [[UIButton alloc] initWithFrame:CGRectMake(20, self.view.frame.size.height-75, self.view.frame.size.width-40, 50)];
    [endButton setTitle:@"End Call" forState:UIControlStateNormal];
    [endButton setBackgroundImage:[UIImage imageNamed:@"red_button_gloss"] forState:UIControlStateNormal];
    [endButton addTarget:self action:@selector(endPress) forControlEvents:UIControlEventTouchUpInside];
   
    UILabel* messageLabel =[[UILabel alloc] initWithFrame:CGRectMake(0, 20,  self.view.frame.size.width, 50)];
    messageLabel.text=@"Calling";
    [messageLabel setFont:[UIFont systemFontOfSize:30]];
    messageLabel.backgroundColor = [UIColor blackColor];;
    messageLabel.textColor=[UIColor whiteColor];
    messageLabel.textAlignment=UITextAlignmentCenter;
    
    

    UILabel* nameLabel =[[UILabel alloc] initWithFrame:CGRectMake(0, 80,  self.view.frame.size.width, 50)];
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
 debug_NSLog(@"call screen did  unload");
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return NO;
}



-(void) viewDidAppear:(BOOL)animated
{
	debug_NSLog(@"call screen did  appear");
	
    [UIDevice currentDevice].proximityMonitoringEnabled=YES;
}

-(void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"call screen did  disappear");
    
    [UIDevice currentDevice].proximityMonitoringEnabled=NO;
    
	
	
}

@end
