//
//  activechats.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/24/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "activechats.h"


@implementation activechats







-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}





-(void)viewDidAppear:(BOOL)animated 
{
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	debug_NSLog(@"active chats did appear");
	SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
	
	db=app.db;
	chatwin=app.chatwin;
	accountno=app.accountno; 
	viewController=app.activeNavigationController; 
	iconPath=app.iconPath; 
	tabcontroller=app.tabcontroller; 
    jabber=app.jabber; 
    
	[currentTable setDelegate:self]; 
	[currentTable setDataSource:self];
	
	
	// refresh log
	thelist=[db activeBuddies:accountno]; // change this to active account later when we have multiple acounts
	
	//refresh unread count 
	int totalunread=[db countUnreadMessages:accountno]; 	
	if(totalunread>0)
	{
		
		
		int usercount=0; 
		while (usercount<[thelist count])
		{
			int msgcount=
			[db countUserUnreadMessages:[[thelist objectAtIndex:usercount] objectAtIndex:0] 
									   :accountno] ;
			
			debug_NSLog(@"%@ old object %d new %d",[[thelist objectAtIndex:usercount] objectAtIndex:0],
						[[[thelist objectAtIndex:usercount] objectAtIndex:4] intValue], msgcount ); 
			
			// for each budfdy find out how many messages they have and set it in the list is differnt 
			if([[[thelist objectAtIndex:usercount] objectAtIndex:4] intValue]  !=msgcount)
			{
				
				[[thelist objectAtIndex:usercount] replaceObjectAtIndex:4 withObject:
				 [NSNumber numberWithInt:msgcount]];
				//NSUInteger indexArr[] = {0,usercount};
				
				//NSIndexPath *indexSet = [NSIndexPath indexPathWithIndexes:indexArr length:2];
				
				//[[buddyTable cellForRowAtIndexPath:indexSet] setNeedsLayout];
				
				//[indexPaths addObject:indexSet];
				
				
				
			}
			usercount++; 
		}
		
		app.activeTab.badgeValue=[NSString stringWithFormat:@"%d",totalunread]; 
	}else
	{
		//refresh badge
		app.activeTab.badgeValue=nil; 
	}
	
	[currentTable reloadData];
	[thelist retain];
	
	// hide + and edit buttons
	
	

	
	
	[viewController.navigationItem setLeftBarButtonItem:nil];
	[viewController.navigationItem setRightBarButtonItem:nil];
	
	
	
	//viewController.navigationItem.rightBarButtonItem=[app editButtonItem];
	
	
	debug_NSLog(@"exiting with acctno %@", accountno);
	[pool release];
	
}

-(void)viewDidDisappear:(BOOL)animated
{
	debug_NSLog(@"active chats  did disappear");
	if(thelist!=nil)
		[thelist release];
	thelist=nil; 
	
	viewController.navigationItem.leftBarButtonItem=nil; 
	viewController.navigationItem.rightBarButtonItem=nil; 
	//reset the edit button to not editing	
	/*[app setEditing:false animated:false]; // this changes it to Done
	 [currentTable setEditing:false animated:false];
	 */
}



-(NSInteger) count
{
	if(thelist==nil) return 0; 
	return [thelist count];
	
}

-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex 
{
	
	//button click handler
	

	
	
	
	//if yes pressed on delete
	if ( (buttonIndex==0) && (sheet=2))
	{
		debug_NSLog(@"closgin active chats for %@",[[thelist objectAtIndex:[currentPath indexAtPosition:1]] objectAtIndex:0]);
		
        //if it is muc close channel
        [jabber closeMuc:[[thelist objectAtIndex:[currentPath indexAtPosition:1]] objectAtIndex:0]];
        
		// delete from tables 
		if(	[db removeActiveBuddies:[[thelist objectAtIndex:[currentPath indexAtPosition:1]] objectAtIndex:0]:accountno])
		{
			
			//	delete from datasource
			[thelist removeObjectAtIndex:[currentPath indexAtPosition:1]];
						
			//del from table
			[currentTable deleteRowsAtIndexPaths:[NSArray arrayWithObject:currentPath] withRowAnimation:UITableViewRowAnimationLeft];			
		}
		else
		{
			
			//show deletion error message
			UIAlertView *deleteAlert = [[UIAlertView alloc] 
										initWithTitle:@"Chat Close Removal Error" 
										message:@"Could not clsoe this chat. Please report this to the developer. "
										delegate:self cancelButtonTitle:@"Close"
										otherButtonTitles: nil];
			[deleteAlert show];
			
		}
		
		
	}
	
	sheet=0; 
	
}







//table view datasource methods

//required

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	
	static NSString *identifier = @"MyCell";
	CustomCell* thecell = [[[CustomCell alloc]initWithFrame: CGRectMake(45,0,265,[tableView rowHeight]) reuseIdentifier:identifier] autorelease];
	
	thecell.accessoryType =  UITableViewCellAccessoryDisclosureIndicator;;
	
	
	if([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:3] length]>3)// at least extension 
	{
		NSFileManager* fileManager = [NSFileManager defaultManager]; 
		
		NSString* buddyfile = [NSString stringWithFormat:@"%@/%@", 
							   iconPath,[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:3]]; 
		if([fileManager fileExistsAtPath:buddyfile])
		{
			UIImage* image=[UIImage imageWithContentsOfFile:buddyfile];
			//	UIImageView *imageView = [ [ UIImageView alloc ] initWithImage: image ];
			//	imageView.frame = CGRectMake(2, 2, 38, 38); // Set the frame in which the UIImage should be drawn in.
			
			//[ thecell addSubview: imageView ]; // Draw the image in self.view. 
			thecell.imageView.image=[tools resizedImage:image: CGRectMake(0, 0, 44, 44)]; 
			thecell.imageView.contentMode = UIViewContentModeScaleAspectFit;
		}
		else
		{
			thecell.imageView.image=[UIImage imageNamed:@"noicon.png"];
		}
	}
	else
	{
		thecell.imageView.image=[UIImage imageNamed:@"noicon.png"];
	}
	
	
	NSInteger statusHeight=16;
	CGRect cellRectangle ; 
	
	
		cellRectangle = CGRectMake(51,0,187,[tableView rowHeight]);
	
	//Initialize the label with the rectangle.
	UILabel* buddyname = [[[UILabel alloc] initWithFrame:cellRectangle] autorelease];
	buddyname.font=[UIFont boldSystemFontOfSize:18.0f];
	
		buddyname.textColor = [UIColor blackColor];
		
	buddyname.autoresizingMask   = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;


	//Initialize the label with the rectangle.
	
	debug_NSLog([[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:0]); 
	
	if([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:2] isEqualToString:@""])
		buddyname.text =[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:0];
	else
		buddyname.text=[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:2];
	
	
	//Add the label as a sub view to the cell.
	thecell.buddyname=buddyname;
	[thecell.contentView addSubview:buddyname];
	
	
	//count 
	thecell.text=[NSString stringWithFormat:@"%@", [[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:4]];
	
	if([thecell.text isEqualToString:@"0"]) thecell.text=nil; 
	
	
	[thecell retain];
	[pool release];
	return thecell;
}



- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	
	return [self count];
}


- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
	return YES;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath
{
}


- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return @"Close"; 
}


- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		
		
		currentPath= indexPath;
		currentTable=tableView;
		//ask if sure
		UIActionSheet *popupQuery = [[UIActionSheet alloc] initWithTitle:@"Are you sure you want to close this chat?"
																delegate:self 
													   cancelButtonTitle:@"No" 
												  destructiveButtonTitle:@"Yes" 
													   otherButtonTitles:nil, nil];
		
		popupQuery.actionSheetStyle =  UIActionSheetStyleBlackOpaque;
		
		//[popupQuery showInView:tableView];
        	[popupQuery showFromTabBar:tabcontroller.tabBar];
		
		[popupQuery release];
		
		
		sheet=2; 
		
		// deletion should happen in the response handler.. which checks button pressed 
		
		
	}
}

#pragma mark table view delegate methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
	debug_NSLog(@"selected actve row %d max %d", [newIndexPath indexAtPosition:1], [thelist count]); 
	
	[chatwin show:[[thelist objectAtIndex:[newIndexPath indexAtPosition:1]] objectAtIndex:0]
					:[[thelist objectAtIndex:[newIndexPath indexAtPosition:1]] objectAtIndex:2]
				 :viewController
	 
	 ];
	
	[tableView deselectRowAtIndexPath:newIndexPath animated:true];
	
	
}




-(void)dealloc
{
	[thelist release];
	[super dealloc];
}


@end
