//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "loglist.h"


@implementation loglist  









-(void) clearLogs
{
	
	debug_NSLog(@"Clear Logs");
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	

	
	UIActionSheet *popupQuery = [[UIActionSheet alloc] initWithTitle:@"Are you sure you want to clear ALL conversation logs?"
															delegate:self 
												   cancelButtonTitle:@"No" 
											  destructiveButtonTitle:@"Yes" 
												   otherButtonTitles:nil, nil];
	
	popupQuery.actionSheetStyle =  UIActionSheetStyleBlackOpaque;
	
	//[popupQuery showInView:self.view];
    SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
    [popupQuery showFromTabBar:app.tabcontroller.tabBar];
    
	[popupQuery release];
	
	
	sheet=1; 
	[pool release];
	
	
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}


-(void)viewDidAppear:(BOOL)animated 
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	debug_NSLog(@"chat log did appear");
	
	SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
	
	db=app.db;
	chatwin=app.chatwin;
	accountno=app.accountno; 
	
	
	
	
	if(accountno==nil) {
		[pool release];
		return; 
	}
// refresh log
	if(thelist==nil)
	thelist=[db messageHistoryBuddies:accountno]; // change this to active account later when we have multiple acounts
	
		if((thelist==nil) || ([thelist count]==0))
		{
			[pool release];
			return; 
		}
	
	NSString* machine=[tools machine]; 
	if([machine hasPrefix:@"iPad"] )
	{//if pad..
		viewController=app.logsNavigationControlleriPad;
	}
	else
		
	{
		//if iphone
		viewController=app.morenav; 
		
	}
	
	iconPath=app.iconPath; 
	
	
	[currentTable setDelegate:self]; 
	[currentTable setDataSource:self];
	[currentTable reloadData];

	
// hide + and edit buttons

	UIBarButtonItem* clearLogButton = [UIBarButtonItem alloc]; 
	[clearLogButton initWithTitle:@"Clear Logs" style:UIBarButtonItemStylePlain
										 
										 target:self action:@selector(clearLogs)];
	
	
	
	//[viewController.navigationBar.topItem setLeftBarButtonItem:nil];
	viewController.navigationBar.topItem.rightBarButtonItem=clearLogButton;
	
	
	
	//viewController.navigationItem.rightBarButtonItem=[app editButtonItem];
	

	debug_NSLog(@"exiting with acctno %@", accountno);
	[pool release];

}

-(void)viewWillDisappear:(BOOL)animated
{
	debug_NSLog(@"chat log will disappear");
	//if(thelist!=nil)
	//[thelist release];
	//thelist=nil;
		
	
	// viewController.navigationBar.topItem.leftBarButtonItem=nil; 
	viewController.navigationBar.topItem.rightBarButtonItem=nil; 
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
	
	// add buddy
	if ( (buttonIndex==0) && (sheet==1))
	{
		debug_NSLog(@"deleting buddy logs all");
		
		// delete from tables 
		if(	[db messageHistoryCleanAll:accountno])
		{
			
			//	delete from datasource
			//[thelist removeObjectAtIndex:[currentPath indexAtPosition:1]];
			[thelist removeAllObjects]; 
			//thelist=[[NSMutableArray alloc] init] ; 
			
			[currentTable reloadData];
			//del from table
			//[currentTable deleteRowsAtIndexPaths:[NSArray arrayWithObject:currentPath] withRowAnimation:UITableViewRowAnimationLeft];			
		}
		else
		{
			
			//show deletion error message
			UIAlertView *deleteAlert = [[UIAlertView alloc] 
										initWithTitle:@"Log Removal Error" 
										message:@"Could not remove logs ."
										delegate:self cancelButtonTitle:@"Close"
										otherButtonTitles: nil];
			[deleteAlert show];
			
		}
		
	}
	
	
	
	//if yes pressed on delete
	if ( (buttonIndex==0) && (sheet==2))
	{
		debug_NSLog(@"deleting buddy logs for %@",[[thelist objectAtIndex:[currentPath indexAtPosition:1]] objectAtIndex:0]);
	
		// delete from tables 
		if(	[db messageHistoryClean:[[thelist objectAtIndex:[currentPath indexAtPosition:1]] objectAtIndex:0]:accountno])
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
										initWithTitle:@"Contact Log Removal Error" 
										message:@"Could not remove logs for  contact."
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
	UITableViewCell* thecell =[[[UITableViewCell alloc] initWithStyle:  UITableViewCellStyleSubtitle  reuseIdentifier:identifier] autorelease];
	
	
thecell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	//[thecell setText:[thelist objectAtIndex:[indexPath indexAtPosition:1]]];
	
	// need a faster methos here.. 
	
	if([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:3] length]>3)// at least extension 
	{
		NSFileManager* fileManager = [NSFileManager defaultManager]; 
		//note: default to png  we want to check a table/array to  look  up  what the file name really is...
		//NSString* filename=[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:3];
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
	

	
	debug_NSLog([[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:0]); 
	
	if([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:2] isEqualToString:@""])
		thecell.textLabel.text =[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:0];
	else
		thecell.textLabel.text=[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:2];
	
	
		
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
	return @"Clear"; 
}

 
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
  if (editingStyle == UITableViewCellEditingStyleDelete) {
	
		
		currentPath= indexPath;
          [currentPath retain];
		currentTable=tableView;
		//ask if sure
	  UIActionSheet *popupQuery = [[UIActionSheet alloc] initWithTitle:@"Are you sure you want to clear  logs for his contact?"
															  delegate:self 
													 cancelButtonTitle:@"No" 
												destructiveButtonTitle:@"Yes" 
													 otherButtonTitles:nil, nil];
	  
	  popupQuery.actionSheetStyle =  UIActionSheetStyleBlackOpaque;
	  
	//  [popupQuery showInView:tableView];
      SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
      [popupQuery showFromTabBar:app.tabcontroller.tabBar];
      
	  [popupQuery release];
	  
		
	  sheet=2; 
		
		// deletion should happen in the response handler.. which checks button pressed 

		
	}
}

//table view delegate methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
	debug_NSLog(@"selected log row %d max %d", [newIndexPath indexAtPosition:1], [thelist count]); 
		
	[chatwin showLog:[[thelist objectAtIndex:[newIndexPath indexAtPosition:1]] objectAtIndex:0]
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
