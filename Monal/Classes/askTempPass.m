//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "askTempPass.h"


@implementation askTempPass




-(void) init:(UITabBarController*) tab; 
{
	
    tabbarcontroller=tab;
	[self initWithNibName:@"askTempPass" bundle:nil];
	 
	self.title=@"Enter Password"; 
   
  
}

-(IBAction) closePress
{
            [tabbarcontroller dismissModalViewControllerAnimated:YES];
//dont connect 
  //send login error signal  
    [[NSNotificationCenter defaultCenter] 
     postNotificationName: @"LoginFailed" object: self];
    
}

-(IBAction) addPress
{
   
    

  // [ [[UIApplication sharedApplication] delegate] setTempPass:[passwordField text]];

    SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
    [app setTempPass:[passwordField text]];
    
    [[NSNotificationCenter defaultCenter] 
	 postNotificationName: @"Reconnect" object: self];
    
        [tabbarcontroller dismissModalViewControllerAnimated:YES];

    
	
}




- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	
	[textField resignFirstResponder];
	
	
	return true;
}


-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}




-(void) show

{


	
   
        [tabbarcontroller presentModalViewController:self animated:YES];
    /*{
    [navigationController popViewControllerAnimated:false]; //  getof aythign on top 
	[navigationController pushViewController:self animated:YES];
	}*/
     
    //for ipad show differently 
    if([[tools machine] isEqualToString:@"iPad"])
    {
        self.modalPresentationStyle=UIModalPresentationFormSheet; 
    }

}



-(void) viewDidLoad
{
	DDLogVerbose(@" ask temp pass did  appear");
    
   
    
    if([[tools machine] isEqualToString:@"iPad"])
    {
        [scroll setContentSize:CGSizeMake(316, 203)];
  
    }
    else
    {
        //if iphone
       // if(tabbarcontroller==nil) 
        [scroll setContentSize:CGSizeMake(320, 440)];  
        //else
          //  [scroll setAlpha:.5]; 
    
    }
    
    }

-(void)viewDidDisappear:(BOOL)animated
{
	DDLogVerbose(@"ask temp pass did  disappear");
	

	
	
}




@end
