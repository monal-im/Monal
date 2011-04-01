//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "XMPPEdit.h"


@implementation XMPPEdit


@synthesize db;

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	
	return true; 
}

-(void)initList:(UINavigationController*) nav:(NSIndexPath*) indexPath:(NSString*)accountnum; 
{


	sectionArray =  [[NSArray arrayWithObjects:@"Account", @"Advanced Settings", nil] retain];
	navigationController=nav;
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(keyboardWillShow:) name: UIKeyboardWillShowNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object:nil];
	
		debug_NSLog(@"xmpp edit loading nib"); 
	[self initWithNibName:@"XMPPEdit" bundle:nil];

	originIndex=indexPath; 
	[originIndex retain];
	if(![accountnum isEqualToString:@"-1"])
	{
		accountno=accountnum; 
		[accountno retain];
			editing=true; 
	} else accountno=nil; 
	
	debug_NSLog(@"got account number %@", accountno); 
    
 
	
	
}

-(void) hideKeyboard
{
	[userText resignFirstResponder]; 
    [passText resignFirstResponder]; 
	 [enableSwitch resignFirstResponder]; 
	
    [serverText resignFirstResponder]; 
    [portText resignFirstResponder]; 
    [resourceText resignFirstResponder]; 
}

- (void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"view did hide"); 
	[self save];
	
}

- (void)viewDidLoad 
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  /*  UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; // hides the kkyeboard when you tap outside the editing area
    gestureRecognizer.cancelsTouchesInView=false; //this prevents it from blocking the button 
    
    [theTable addGestureRecognizer:gestureRecognizer];*/
    
    // gesture stuff worked in OS4 but not in OS3.. was preventing keybaord in textfield
    
	if(originIndex.section==0)
	{
		//edit
			debug_NSLog(@"reading account number %@", accountno); 
		NSArray* settings=[[db accountVals:accountno] objectAtIndex:0]; //only one row
		
        //allow blank domains.. dont show @ if so
	if([[settings objectAtIndex:9] length]>0)
		userText.text=[NSString stringWithFormat:@"%@@%@",[settings objectAtIndex:5],[settings objectAtIndex:9]];
		else
            userText.text=[NSString stringWithFormat:@"%@",[settings objectAtIndex:5]];
        
		PasswordManager* pass= [PasswordManager alloc] ; 
		[pass init:[NSString stringWithFormat:@"%@",accountno]];
		passText.text=[pass getPassword];	
		
		
		serverText.text=[settings objectAtIndex:3];
		
		portText.text=[NSString stringWithFormat:@"%@", [settings objectAtIndex:4]];
		resourceText.text=[settings objectAtIndex:8];
		
		if([[settings objectAtIndex:7] intValue]==1)
			sslSwitch.on=true; else sslSwitch.on=false; 
		
		
		if([[settings objectAtIndex:10] intValue]==1)
			enableSwitch.on=true; else enableSwitch.on=false; 
		
		debug_NSLog(@"SSL val %@", [settings objectAtIndex:7]); 
		if([[settings objectAtIndex:9] isEqualToString:@"gmail.com"])
		{
			JIDLabel.text=@"Gtalk ID"; 
		}
		
	}
	else
	{
		
		if(originIndex.row==1)
		{
			JIDLabel.text=@"Gtalk ID"; 
			serverText.text=@"talk.google.com"; 
			userText.text=@"@gmail.com"; 
		}
		
		portText.text=@"5222"; 
		resourceText.text=@"Monal"; 
		sslSwitch.on=true; 
		
	
		if(originIndex.row==3)
		{
			serverText.text=@"chat.facebook.com"; 
			userText.text=@"@chat.facebook.com"; 
			sslSwitch.on=false;
		}
		
		
		
	}
    [pool release];
}




-(void) save
{
	
	debug_NSLog(@"Saving"); 
	
	
	
	if([userText.text length]==0) 
	{
		return ; 
		
	}
	
	NSString* domain; 
	NSString* user; 
	
	/*	 if([elements count]<2)
	 {
	 return;
	 }
	 if([[elements objectAtIndex:0] length]==0) return; 
	 */
	
	
	if([userText.text characterAtIndex:0]=='@')
	{
		//first char =@ means no username in jid
		return; 
	}
											
											
	
	NSArray* elements=[userText.text componentsSeparatedByString:@"@"]; 
	
	
	
//default just use JID
	if([serverText.text length]==0) 
	{
		if([elements count]>1)
		serverText.text=[elements objectAtIndex:1];
	}
	
	
	//if it is a JID
	if([elements count]>1)
	{
		user= [elements objectAtIndex:0];
		domain = [elements objectAtIndex:1];
	}
	else
	{
		user=userText.text;
		domain= [NSString stringWithString:@""];
	}
	
	if(!editing)
	{
	
		if(([userText.text length]==0) && 
			 ([passText.text length]==0) 
			)
		{
			//ignoring blank
		}
		else
		{
			
			[db addAccount:
	 userText.text  :
	 @"1":
	user:
	 @"":
	 serverText.text:
	 portText.text :
	 sslSwitch.on:
	 resourceText.text:
			domain: enableSwitch.on];
			
			
			// save password 
			
			PasswordManager* pass= [PasswordManager alloc] ; 
			NSString* val = [NSString stringWithFormat:@"%@", [db executeScalar:@"select max(account_id) from account"]];
			[pass init:[NSString stringWithFormat:@"%@",val]];
			[pass setPassword:passText.text] ;
			
		}
	}
else
{
	
		
	[db updateAccount:
	userText.text  :
	 @"1":
	user :
	@"" :
	 serverText.text:
	 portText.text :
	 sslSwitch.on:
	 resourceText.text:					 
	  domain:
	 enableSwitch.on:
	 accountno];
	
	//save password 
	PasswordManager* pass= [PasswordManager alloc] ; 
	
	[pass init:[NSString stringWithFormat:@"%@",accountno]];
	[pass setPassword: passText.text] ;
	
}
	
	//[[NSNotificationCenter defaultCenter] postNotificationName: @"UpdateAccounts" object: self];
	
}



-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex 
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	if(buttonIndex==0)
	{
		[db removeAccount:accountno];
		[navigationController popViewControllerAnimated:true];
		//[[NSNotificationCenter defaultCenter] postNotificationName: @"UpdateAccounts" object: self];
	}
	
	[pool release];
}

- (IBAction) delClicked: (id) sender
{
 debug_NSLog(@"Deleting"); 	
	
	//ask if you want to delete
	

	
	
	UIActionSheet *popupQuery = [[[UIActionSheet alloc] initWithTitle:@"Delete this account?" delegate:self 
												   cancelButtonTitle:@"No" 
											  destructiveButtonTitle:@"Yes" 
												   otherButtonTitles:nil, nil] autorelease];
	
    popupQuery.actionSheetStyle =  UIActionSheetStyleBlackOpaque;
	
   // [popupQuery showInView:self.view];
	
    SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
    [popupQuery showFromTabBar:app.tabcontroller.tabBar];	
	
}





#pragma mark table view datasource methods

//required

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{

	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	debug_NSLog(@"xmpp edit view section %d, row %d", indexPath.section, indexPath.row); 

	UITableViewCell* thecell;
// load cells from interface builder	
	if(indexPath.section==0)
	{
		//the user
		switch (indexPath.row)
		{
			case 0: thecell=usernameCell; break;
			case 1: thecell=passwordCell ;break;
			case 2: thecell=enableCell ;break;
		}
	}
	else 
	{
		switch (indexPath.row)
		{
		//advanced
	case 0: thecell=serverCell; break;
	case 1: thecell=portCell ;break;

	case 2: thecell=resourceCell; break;
	case 3: thecell=SSLCell ;break;

				
			case 4: 
			{
				if(editing==true)
				{
				static NSString *identifier = @"MyCell";
				thecell = [[[UITableViewCell alloc]initWithFrame:CGRectZero reuseIdentifier:identifier] autorelease];
				//thecell.selection=false; 
				CGRect cellRectangle = CGRectMake(45,0,225,[tableView rowHeight]-3);  
				
				//Initialize the label with the rectangle.
				UIButton* theButton= [UIButton buttonWithType:UIButtonTypeRoundedRect];
					[theButton setBackgroundImage:[[UIImage imageNamed:@"delete_button.png"] 
										stretchableImageWithLeftCapWidth:10.0 topCapHeight:0.0] forState:UIControlStateNormal];
				theButton.frame=cellRectangle;
				
					[theButton setTitle:@"Delete" forState: UIControlStateNormal ];
					[theButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
					[theButton setFont:[UIFont boldSystemFontOfSize:14.0]];
				[theButton addTarget:self action:@selector(delClicked:) forControlEvents:UIControlEventTouchUpInside];
					
					
				
				//Add the label as a sub view to the cell.
				[thecell.contentView addSubview:theButton];
				//[theButton release];
				
				
				[thecell retain];
				}
				break;
			}
	
		}
	
	}

	

	[pool release];
	return thecell;
}



- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	
	//debug_NSLog(@"xmpp edit counting # of sections %d",  [sectionArray count]); 
	return [sectionArray count];
	
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	
	
	//debug_NSLog(@"xmpp edit title for  section %d", section); 
	return [sectionArray objectAtIndex:section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	//debug_NSLog(@"xmpp edit counting section %d", section); 
	
	if(section==0)
		return 3;
		else
		{
			if(editing==false)
			{if(section==1)
					return 4;
			}else return 5;
				 
		}
	
	return 0; //default
	
}


- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
	return YES;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath
{
}


 




//table view delegate methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
	debug_NSLog(@"selected log section %d , row %d", newIndexPath.section, newIndexPath.row); 
		
	
	
}



//text view delegate

-(void) keyboardWillHide:(NSNotification *) note
{
	
	 
	//move down
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.3];
	self.view.frame = oldFrame;
	
	[UIView commitAnimations];
	debug_NSLog(@"kbd will hide scroll: %f", oldFrame.size.height); 
	
	
}

-(void) keyboardWillShow:(NSNotification *) note
{
    
	CGRect r,t;
    [[note.userInfo valueForKey:UIKeyboardBoundsUserInfoKey] getValue: &t];
	r=self.view.frame;
	r.size.height -=  t.size.height-50; //tabbar

	//resizing frame for keyboard movie up
	[UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.3];
	oldFrame=self.view.frame;
	self.view.frame =r; 
	
	
	[UIView commitAnimations];
	
	debug_NSLog(@"kbd will show : %d  scroll: %f ", t.size.height, r.size.height); 
	

	
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
	/*debug_NSLog(@"scolling correct"); 
	
	if(textField==serverText)
	{
		debug_NSLog(@"editing server"); 
		unsigned  int  indexlist[] = { 1,0  };
		[theTable scrollToRowAtIndexPath:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]
						atScrollPosition:UITableViewScrollPositionNone animated:NO];
			
					
	}
	
	
	if(textField==portText)
	{
		debug_NSLog(@"editing port"); 
		unsigned  int  indexlist[] = { 1,1  };
		[theTable scrollToRowAtIndexPath:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]
						atScrollPosition:UITableViewScrollPositionNone animated:NO];
		}
	

	
	if(textField==resourceText)
	{
		debug_NSLog(@"editing resource"); 
		unsigned  int  indexlist[] = { 1,2  };
		[theTable scrollToRowAtIndexPath:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]
						atScrollPosition:UITableViewScrollPositionNone animated:NO];
	}	
	
*/

}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	
	[textField resignFirstResponder];
			

	return true;
}



-(void)dealloc
{
	[sectionArray release];
	[originIndex release]; 
	if(accountno!=nil) [accountno release];
	[super dealloc];
}


@end
