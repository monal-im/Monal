//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "buddyDetails.h"


@implementation buddyDetails


@synthesize iconPath; 
//@synthesize domain; 
@synthesize buddyIconView;
@synthesize protocolImage;
@synthesize buddyName;
@synthesize fullName;
@synthesize buddyStatus;
@synthesize buddyMessage;


-(void) init: (protocol*) jabberIn:(UINavigationController*) nav:(NSString*)username
{
		navigationController=nav;
	[self initWithNibName:@"BuddyDetails" bundle:nil];
	jabber=jabberIn;

	myuser=username;
	

	buddyIcon=nil; 
    protocolImage=nil; 
	
	self.title=@"Contact Details"; 
	//fullName.font=[UIFont boldSystemFontOfSize:16];

	
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}

-(IBAction) callPress
{      
    callScreen* call = [callScreen alloc] ;
    [call init:navigationController];
    [call show:jabber:buddyName.text];
    
    // send jingle stuff
    [jabber startCallUser:buddyName.text];
    
  
     /* NSString* machine=[tools machine]; 
   
  if([machine hasPrefix:@"iPad"] )
       {
       //nothign rightn ow
       }
       else
       {
           [navigationController popViewControllerAnimated:false];
       }
  */
    
}


#pragma mark tableview stuff

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	
	
	
	UITableViewCell* thecell; 
	
	
	
	if(indexPath.section==0) //top
	{
		thecell=topcell; 
	}
	else 
		if(indexPath.section==1) //bottom
		{
			thecell=bottomcell; 
		}

	;

	
//tableView.frame.size.width;
	
	return thecell; 

}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if(indexPath.section==0) //top
	{
		return topcell.frame.size.height; 
	}
	else 
		if(indexPath.section==1) //bottom
		{
			return bottomcell.frame.size.height; 
		}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
	return 1; 
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	
	
	return 2;
	
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	
	
	
	
	if(section==0)
		return @"";
	else
		if(section==1)
			return @"Message";
}

#pragma mark setting values  

-(UIImage*) setIcon:(NSString*) msguser
{
	
	
	NSFileManager* fileManager = [NSFileManager defaultManager]; 
	UIImage* theimage; 
	//note: default to png  we want to check a table/array to  look  up  what the file name really is...
	NSString* buddyfile = [NSString stringWithFormat:@"%@/%@.png", iconPath,msguser ]; 
	if([fileManager fileExistsAtPath:buddyfile])
	{
		 theimage= [UIImage imageWithContentsOfFile:buddyfile];
		
	}
	
	else
	{
		//jpg
		
		NSString* buddyfile2 = [NSString stringWithFormat:@"%@/%@.jpg", iconPath,msguser]; 
		if([fileManager fileExistsAtPath:buddyfile2])
		{
			theimage= [UIImage imageWithContentsOfFile:buddyfile2];
		
		}
		else
		{
			 theimage= [UIImage imageNamed:@"noicon_64.png"];
		}
		
	}
	
	; 
	return theimage; 
}


-(void) show:(NSString*) buddy:(NSString*) status:(NSString*) message:(NSString*) fullname:(NSString*) domain : (UITableView*) table: (CGRect) cellRect
{


    
    
    
    // for ipad  use popout
    
    NSString* machine=[tools machine]; 
    UIInterfaceOrientation orientation =[[UIApplication sharedApplication] statusBarOrientation];
    if(([machine hasPrefix:@"iPad"] )
	
       // &&
        //    (((orientation==UIInterfaceOrientationLandscapeLeft) || 
       //        (orientation==UIInterfaceOrientationLandscapeRight)
          //     ))
        )
        {
            
            
            popOverController = [[UIPopoverController alloc] initWithContentViewController:self];
            
            popOverController.popoverContentSize = CGSizeMake(320, 480);
            
           // if(orientation==UIInterfaceOrientationLandscapeRight)
            [popOverController presentPopoverFromRect:cellRect 
                                               inView:table permittedArrowDirections:UIPopoverArrowDirectionLeft animated:YES];
            
           /* if(orientation==UIInterfaceOrientationLandscapeLeft)
            [popOverController presentPopoverFromRect:cellRect 
                                               inView:table permittedArrowDirections:UIPopoverArrowDirectionLeft animated:YES];*/
            
        }
    else
    {
    
	[navigationController popViewControllerAnimated:false]; //  getof aythign on top 
	[navigationController pushViewController:self animated:YES];
	}
	
	buddyIcon=[self setIcon: buddy];
    
	buddyIconView.image= buddyIcon;
	fullName.text=fullname;
	buddyName.text=buddy;
	
	
	buddyMessage.text=message;
		buddyStatus.text=status;

	if([domain isEqualToString:@"AIM"])
	{
		//gtalk
		protocolImage.image=[UIImage imageNamed:@"AIM.png"];
	}
	else
	if([domain isEqualToString:@"gmail.com"])
	{
		//gtalk
		protocolImage.image=[UIImage imageNamed:@"google_g.png"];
	}
	else
	if([domain isEqualToString:@"chat.facebook.com"])
	{
		//gtalk
		protocolImage.image=[UIImage imageNamed:@"Facebook.png"];
	}
	else
	{
		//xmpp
		protocolImage.image=[UIImage imageNamed:@"XMPP.png"];
	}
	//we want to put other protcols here later
    
    
    
	;
}

-(void) viewDidLoad
{
	debug_NSLog(@"buddy details did  load");
	//[scroll setContentSize:CGSizeMake(320, 509)];
}

-(void) viewDidAppear:(BOOL)animated
{
	debug_NSLog(@"buddy details did  appear");
	//[scroll setContentSize:CGSizeMake(320, 509)];
}

-(void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"buddy details did  disappear");
	
   
	
	
}


@end
