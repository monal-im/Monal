//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "buddyAdd.h"


@implementation buddyAdd

@synthesize bbiOpenPopOver; 
@synthesize popOverController; 



-(void) init:(UINavigationController*) nav:(UITabBarController*) tab
{
	navigationController=nav;
    tabbarcontroller=tab;
	[self initWithNibName:@"BuddyAdd" bundle:nil];
	
	
	self.title=@"Add Contact "; 
	
}


-(IBAction) addPress
{
   
    
	if([jabber addBuddy:[buddyName text]])
	{
		
	}
	else
	{
		UIAlertView *addError = [[UIAlertView alloc] 
								 initWithTitle:@"Contact Addition Error" 
								 message:@"Could not add contact."
								 delegate:self cancelButtonTitle:@"Close"
								 otherButtonTitles: nil] ;
		[addError show];
		[addError release];
	}

	 if(([[tools machine] isEqualToString:@"iPad"])
    &&(navigationController==nil))
    {
        if ([popOverController isPopoverVisible]) {
            
            [popOverController dismissPopoverAnimated:YES];
            
        } 
    }
    else
    {
	if(tabbarcontroller==nil)
        [navigationController popViewControllerAnimated:true];
	else
        [tabbarcontroller dismissModalViewControllerAnimated:YES];
    }
	
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


-(void) show:(protocol*)account:(NSString*) name
{
   NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
// always nav
    [navigationController pushViewController:self animated:YES];
	
    buddyName.text=name; 
    
	jabber=account;
    [pool release];
}

-(void) show:(protocol*)account

{

NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
   
        [navigationController presentModalViewController:self animated:YES];
    /*{
    [navigationController popViewControllerAnimated:false]; //  getof aythign on top 
	[navigationController pushViewController:self animated:YES];
	}*/
    
	jabber=account;
		
	[pool release];
}

-(void) showiPad:(protocol*)account
{
    popOverController = [[UIPopoverController alloc] initWithContentViewController:self];
  
    popOverController.popoverContentSize = CGSizeMake(316, 158);
    [popOverController presentPopoverFromBarButtonItem:bbiOpenPopOver permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
 	jabber=account;
    
    navigationController=nil; // so we know it is a popover
}

-(void) viewDidLoad
{
	debug_NSLog(@"buddy add did  appear");
    
   
    
    if([[tools machine] isEqualToString:@"iPad"])
    {
        [scroll setContentSize:CGSizeMake(316, 158)];
  
    }
    else
    {
        //if iphone
       // if(tabbarcontroller==nil) 
        [scroll setContentSize:CGSizeMake(320, 509)];  
        //else
          //  [scroll setAlpha:.5]; 
    
    }
    
    }

-(void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"buddy add did  disappear");
	

	
	
}




-(void) dealloc
{
			[super dealloc]; 
}
@end
