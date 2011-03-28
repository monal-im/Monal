//
//  chat.m
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "chat.h"


@implementation chat

@synthesize chatInput;
@synthesize chatTable;
@synthesize iconPath; 
@synthesize domain; 
@synthesize viewController;
@synthesize accountno;

-(void) init: (xmpp*) jabberIn:(UINavigationController*) nav:(NSString*)username: (DataLayer*) thedb
{
		navigationController=nav;
	[self initWithNibName:@"chatview" bundle:nil];
	jabber=jabberIn;
	thelist=[[NSMutableArray alloc] init];
	myuser=username;
	db=thedb;

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(keyboardWillShow:) name: UIKeyboardWillShowNotification object:nil];
	[nc addObserver:self selector:@selector(keyboardWillHide:) name: UIKeyboardWillHideNotification object:nil];

	buddyIcon=nil; 
	myIcon=nil; 

	

	
	
}





-(void) scrollCorrect
{
	//scroll to make last visible
	if([thelist count]>1)
	{
	unsigned  int  indexlist[] = { 0,[thelist count]-1  };
		
		//the index path here seems to not be correct for scrollign to the bottom
		
	[chatTable scrollToRowAtIndexPath:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]
					 atScrollPosition:UITableViewScrollPositionBottom animated:NO];
		
	}
	
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return YES;
}



-(void) signalNewMessages
{
	debug_NSLog(@"new message signal"); 
	
	//grab any messages for this user
	if([db markAsRead:self.title :accountno])
	{
	
	//populate the list
	[thelist release];
	thelist =[db messageHistory:self.title: accountno];
	[chatTable reloadData];
		[self scrollCorrect];
	}
	else
		debug_NSLog(@"could not mark new messages as read");
	
// if there are still messages	
		/*
	if(([db countOtherUnreadMessages:self.title:@"1"]>0) &&(alertShown==false)) //only show once
	{
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Other Messages"
													message:@"You hew new messages from other users."
												   delegate:self cancelButtonTitle:nil
										  otherButtonTitles:@"Close", nil];
	[alert show];
	[alert release];
		alertShown=true;
	}*/

	 
}

-(void) showLog:(NSString*) buddy
{
	self.title=buddy;
	alertShown=false; // reset every time we come back
	[navigationController pushViewController:self animated:YES];
	
	[chatInput setEnabled:false];
	[chatInput setText:@"Input disabled in log view"];
	
	
	[chatTable setDataSource:self];
	[chatTable setDelegate:self];
		
	//populate the list
	thelist =[db messageHistoryAll:self.title: accountno];
	
	if(myIcon!=nil) [myIcon release]; 
	if(buddyIcon!=nil) [buddyIcon release]; 
	
	myIcon = [self setIcon: [NSString stringWithFormat:@"%@@%@",myuser,domain]];
	buddyIcon= [self setIcon: buddy];

	
	[chatTable reloadData];
	[self scrollCorrect];
	
	
	
	
}


-(UIImage*) setIcon:(NSString*) msguser
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSFileManager* fileManager = [NSFileManager defaultManager]; 
	UIImage* theimage; 
	//note: default to png  we want to check a table/array to  look  up  what the file name really is...
	NSString* buddyfile = [NSString stringWithFormat:@"%@/%@.png", iconPath,msguser ]; 
	
	debug_NSLog(buddyfile);
	if([fileManager fileExistsAtPath:buddyfile])
	{
		
		 theimage= [tools resizedImage:[UIImage imageWithContentsOfFile:buddyfile]: CGRectMake(0, 0, 38, 38)];
		
	}
	
	else
	{
		//jpg
		
		NSString* buddyfile2 = [NSString stringWithFormat:@"%@/%@.jpg", iconPath,msguser]; 
		debug_NSLog(buddyfile2);
		if([fileManager fileExistsAtPath:buddyfile2])
		{
			theimage= [tools resizedImage:[UIImage imageWithContentsOfFile:buddyfile2]: CGRectMake(0, 0, 38, 38)];
		
		}
		else
		{
			 theimage= [UIImage imageNamed:@"noicon.png"];
		}
		
	}
	
	[theimage retain]; 
	[pool release]; 
	return theimage; 
}


-(void) show:(NSString*) buddy
{
	self.title=buddy;
	alertShown=false; // reset every time we come back
	[navigationController pushViewController:self animated:YES];
	
	[chatInput setText:@""];
	[chatInput setEnabled:true];
	[chatInput setDelegate:self];
	[chatTable setDataSource:self];
	[chatTable setDelegate:self];
	
	//mark any messages in from this user as  read
	[db markAsRead:self.title :accountno];
	
	//populate the list
	thelist =[db messageHistory:self.title: accountno];
	
	
	//get icons 
	// need a faster methos here.. 
	if(myIcon!=nil) [myIcon release]; 
	if(buddyIcon!=nil) [buddyIcon release]; 
	
	
	myIcon = [self setIcon: [NSString stringWithFormat:@"%@@%@",myuser,domain]];
	buddyIcon= [self setIcon: buddy];

	
	[chatInput resignFirstResponder];
 
	[chatTable reloadData];
	[self scrollCorrect];
	
	
	
	
}

//always messages going out
-(void) addMessage:(NSString*) to:(NSString*) message
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
/*	NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "]; 
	
	NSArray* objects	=[NSArray arrayWithObjects:from,message, [parts objectAtIndex:1],nil];
	NSArray* keys =[NSArray arrayWithObjects:@"from", @"message", @"time",nil];
	
	
	NSDictionary* row =[NSDictionary dictionaryWithObjects:objects  forKeys:keys]; 

	
		[thelist addObject:row];*/	
	


	
	if([db addMessageHistory:myuser:to:accountno:message])
	{
		debug_NSLog(@"added message"); 
	
	//refresh this list with table dump
		[thelist release];
	thelist =[db messageHistory:to:accountno];
		if(thelist!=nil)
		[chatTable reloadData];
		else  debug_NSLog(@"Failed to query  message history lsit"); 
	}
	else
		debug_NSLog(@"failed to add message"); 
	
	//do it after keybaord is gone for me
//	if(![from isEqualToString:myuser])
	//	[self scrollCorrect];
	
	
	
	[pool release];
	
}



/**** Textview delegeate functions ****/

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	if(([textField text]!=nil) && (![[textField text] isEqualToString:@""]) )
	{
	debug_NSLog(@"Sending message"); 
	// this should call the xmpp message 
	
if([jabber message:self.title:[textField text]])
{
	
	[self addMessage:self.title:[textField text]];

	
	//clear the message text
	[chatInput setText:@""];
		
	//hide keyboard.. 
	//not hiudden for rapid chat
		//[textField resignFirstResponder];
	
	
	[self scrollCorrect];
}
		else
		{
			debug_NSLog(@"Message failed to send"); 
			
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Message Send Failed"
															message:@"Could not send the message."
														   delegate:self cancelButtonTitle:nil
												  otherButtonTitles:@"Close", nil];
			[alert show];
			[alert release];
		}
	}
	
	//keyboard not hidden while chatting
//	else [textField resignFirstResponder];
		

	
	return true;
}


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
	r.size.height -=  t.size.height;
	

	
	//resizing frame for keyboard movie up
	[UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.3];
	oldFrame=self.view.frame;
	self.view.frame =r; 
	
	
	[UIView commitAnimations];
	[self scrollCorrect];
	debug_NSLog(@"kbd will show : %d  scroll: %f", t.size.height, r.size.height); 
	
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
	
		[chatInput setFont:[UIFont systemFontOfSize:14]];

	
}


- (void)textFieldDidEndEditing:(UITextField *)textField
	{
	
		
			
	}




//table view datasource methods
//required
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	//debug_NSLog(@"showing"); 
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	static NSString *identifier = @"MyCell";
	UITableViewCell* thecell = [[[UITableViewCell alloc]initWithFrame:CGRectZero reuseIdentifier:identifier] autorelease];
	
		NSArray* dic =[thelist objectAtIndex:[indexPath indexAtPosition:1]]; 
	
	//[thecell setText:[thelist objectAtIndex:[indexPath indexAtPosition:1]]];
	

	if([[dic objectAtIndex:0] isEqualToString:myuser])
	{
		UIImageView *imageView = [ [ UIImageView alloc ] initWithImage: myIcon ];
		imageView.frame = CGRectMake(2, 2, 38, 38); // Set the frame in which the UIImage should be drawn in.
		
		[ thecell addSubview: imageView ]; // Draw the image in self.view. 		
	}
	else
	{
		UIImageView *imageView = [ [ UIImageView alloc ] initWithImage: buddyIcon ];
		imageView.frame = CGRectMake(2, 2, 38, 38); // Set the frame in which the UIImage should be drawn in.
		
		[ thecell addSubview: imageView ]; // Draw the image in self.view. 	
	}
	

	NSInteger statusHeight=20;
	
	CGRect cellRectangle = CGRectMake(45,-8,chatTable.frame.size.width-45,[tableView rowHeight]-statusHeight); 
	
	//Initialize the label with the rectangle.
	UITextView* buddyname = [[UITextView alloc] initWithFrame:cellRectangle];
	 
	buddyname.editable=false; 
	buddyname.scrollEnabled=false; 
	buddyname.showsHorizontalScrollIndicator=false; 
	buddyname.showsVerticalScrollIndicator=false; 
	
	
	buddyname.text=[NSString stringWithFormat:@"%@  %@",[dic objectAtIndex:2],[dic objectAtIndex:0]   ];
	
	if([[dic objectAtIndex:0]  isEqualToString:myuser])
	buddyname.textColor=[UIColor blueColor];
	else
		buddyname.textColor=[UIColor redColor];
		
	buddyname.font=[UIFont systemFontOfSize:13];
	//Add the label as a sub view to the cell.

	
	//this is the message
	NSString* message=[dic objectAtIndex:1] ;
	//get height based on the message size
	UIFont* font=[UIFont systemFontOfSize:14];
	float lineHeight = [ @"Fake line" sizeWithFont: font ].height;
	int numlines=[ message sizeWithFont: font constrainedToSize: CGSizeMake(chatTable.frame.size.width-45, lineHeight*1000.0f) 
						 lineBreakMode: UILineBreakModeTailTruncation ].height ;
	
	cellRectangle = CGRectMake(45,[tableView rowHeight]-statusHeight-12,chatTable.frame.size.width-45,numlines+10); 
	
	UITextView* buddystatus = [[UITextView alloc] initWithFrame:cellRectangle];
	//buddystatus.numberOfLines=0; //unlimited lines
	
	buddystatus.text=message;
	buddystatus.font=font;
	buddystatus.editable=false;
	buddystatus.scrollEnabled=false; 
	buddystatus.showsVerticalScrollIndicator=false; 
	buddystatus.showsHorizontalScrollIndicator=false;
	
	//Add the label as a sub view to the cell.
	[thecell.contentView addSubview:buddystatus];
	[buddystatus release]; 
	
	//add it second so it is on top of the top part white space
	[thecell.contentView addSubview:buddyname];
	[buddyname release];
	
	
	[thecell.contentView sizeToFit]; //make it all fit
	thecell.selectionStyle=UITableViewCellSelectionStyleNone; 
	



	[thecell retain]; 
	[pool release];
	return thecell;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	
	return [thelist count];
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
	return YES;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath
{
}

//table delegate
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString* message=[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:1]; 

	//get height based on the message size
	UIFont* font=[UIFont systemFontOfSize:14];
	float lineHeight = [ @"Fake line" sizeWithFont: font ].height;
	int numlines=[ message sizeWithFont: font constrainedToSize: CGSizeMake(chatTable.frame.size.width-45, lineHeight*1000.0f) 
						  lineBreakMode: UILineBreakModeTailTruncation ].height ;
	
	
	[pool release];
	return (CGFloat) numlines+30; // 16 for top line

	
	
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{

	[chatInput resignFirstResponder];

	return;
}


-(void) dealloc
{
	[thelist release];
		[super dealloc]; 
}
@end
