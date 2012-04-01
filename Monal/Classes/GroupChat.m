//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "GroupChat.h"


@implementation GroupChat

@synthesize jabber;
@synthesize nav;




-(IBAction) join
{
	
    [room resignFirstResponder];
        [server resignFirstResponder];
        [password resignFirstResponder];
    
	debug_NSLog(@"join pressed");
    [jabber joinMuc:[NSString stringWithFormat:@"%@@%@", room.text, server.text]:password.text]; 
	
    //[nav popViewControllerAnimated:true];
    
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


-(void) hideKeyboard
{
    [room resignFirstResponder];
    [server resignFirstResponder];
    [password resignFirstResponder];
	
    
    
}

-(void) viewDidAppear:(BOOL)animated
{
    

	debug_NSLog(@"groupchat did  appear");
    	[scroll setContentSize:CGSizeMake(320, 509)];
    
    //this is only really for xmpp
    if([jabber isKindOfClass:[xmpp class]])
        server.text=jabber.chatServer; 
   /* 
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; // hides the kkyeboard when you tap outside the editing area
    gestureRecognizer.cancelsTouchesInView=false; //this prevents it from blocking the button 
    
    
     [scroll addGestureRecognizer:gestureRecognizer];*/
    
	;
}

-(void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"groupchat did  disappear");
	

	
	
}




@end
