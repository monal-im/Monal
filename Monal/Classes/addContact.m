//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "addContact.h"
#import "MLConstants.h"

@implementation addContact


-(void) closeView
{
    [self dismissModalViewControllerAnimated:YES];
}

-(IBAction) addPress
{
   
//    
//	if([jabber addBuddy:[buddyName text]])
//	{
//		
//	}
//	else
	{
		UIAlertView *addError = [[UIAlertView alloc] 
								 initWithTitle:@"Contact Addition Error" 
								 message:@"Could not add contact."
								 delegate:self cancelButtonTitle:@"Close"
								 otherButtonTitles: nil] ;
		[addError show];
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



-(void) viewDidLoad
{
    self.navigationItem.title=@"Add Contact";
    _closeButton =[[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(closeView)];
    self.navigationItem.rightBarButtonItem=_closeButton;

     if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
     {
         _caption.textColor=[UIColor blackColor];
         self.view.backgroundColor =[UIColor whiteColor];
     }
     else{
         self.view.backgroundColor = [[UIColor alloc] initWithPatternImage:[UIImage imageNamed:@"debut_dark"]];
     }
    

}

-(void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"buddy add did  disappear");
	
}




@end
