 //
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "buddylist.h"


@implementation buddylist  

@synthesize thelist; 
@synthesize jabber; 
@synthesize iconPath; 
@synthesize plusButton;
@synthesize viewController; 
@synthesize tabcontroller;
@synthesize theOfflineList;

@synthesize splitViewController;
@synthesize refresh; 

-(void)initList:(chat*) chatWin
{

	thelist=nil ;
	theOfflineList=nil ;
	//[thelist addObject:@"test"];
	
	chatwin=chatWin;
	
    
	//self.tableView=currentTable;
	
	
}


#pragma mark online table 

-(int) indexofString:(NSString*)name
{
	
	int counter=0; 
	while(counter<[thelist count])
	{
		if([name isEqualToString:[[thelist objectAtIndex:counter] objectAtIndex:0]])
		{
			return counter;
		}
		
		
		counter++;
	}
	return -1; 
	
}

-(NSArray*) add:(NSArray*) list:(NSArray*) dblist
{
	NSMutableArray* indexes= [[NSMutableArray alloc] init];
	int counter=0; 
	[self setList:dblist];
	while(counter<[list count])
	{
		int pos=[self indexofString:[[list objectAtIndex:counter] objectAtIndex:0]];
		
		if((pos<[thelist count]) && (pos>=0)) // account for no match and a random pos
		{	
			unsigned  int  indexlist[] = { 0,pos };
			[indexes addObject:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]];
			
			debug_NSLog(@"added  indexes: %d %d",[[indexes objectAtIndex: [indexes count]-1] indexAtPosition:0],
						[[indexes objectAtIndex: [indexes count]-1] indexAtPosition:1]);
			
			//	[thelist removeObjectAtIndex:pos];
			
		}
		counter++; 
	}
	
	;
	return indexes ;
}





-(NSArray*) remove:(NSArray*) list:(NSArray*) dblist
{
NSMutableArray* indexes= [[NSMutableArray alloc] init];
	int counter=0; 
	
	while(counter<[list count])
	{
			int pos=[self indexofString:[[list objectAtIndex:counter] objectAtIndex:0]];
				
		if((pos<[thelist count]) && (pos>=0)) // account for no match and a random pos
		{	
			unsigned  int  indexlist[] = { 0,pos };
			[indexes addObject:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]];
		
			debug_NSLog(@"removed  indexes: %d %d",[[indexes objectAtIndex: [indexes count]-1] indexAtPosition:0],
				  [[indexes objectAtIndex: [indexes count]-1] indexAtPosition:1]);
			
	
		
		}
		counter++; 
	}

	[self setList:dblist]; // set to new list with everything removed
	;
	return indexes ;
}


-(NSArray*) update:(NSArray*) list;
{
	NSMutableArray* indexes= [[NSMutableArray alloc] init];
	int counter=0; 
	while(counter<[list count])
	{
		
		
		NSString* username=[[list objectAtIndex:counter] objectAtIndex:0];
		
		int pos=[self indexofString:username];
		
		
		
		if((pos<[thelist count]) && (pos>=0)) // account for no match and a random pos
		{	
			unsigned  int  indexlist[] = { 0,pos };
			[indexes addObject:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]];
			
			debug_NSLog(@"update  indexes: %d %d",[[indexes objectAtIndex: [indexes count]-1] indexAtPosition:0],
				  [[indexes objectAtIndex: [indexes count]-1] indexAtPosition:1]);
			
			[thelist insertObject:[list objectAtIndex:counter]  atIndex:pos]; //add
			
			[thelist removeObjectAtIndex:pos+1]; //remove 
			
			
			
			
		}
		counter++; 
	}
	
	; 
	return indexes ;
}




-(NSInteger) count
{
	
	return [thelist count];
	
}

#pragma mark offline table 

-(int) indexofStringOffline:(NSString*)name
{
	
	int counter=0; 
	while(counter<[theOfflineList count])
	{
		if([name isEqualToString:[[theOfflineList objectAtIndex:counter] objectAtIndex:0]])
		{
			return counter;
		}
		
		
		counter++;
	}
	return -1; 
	
}

-(NSArray*) addOffline:(NSArray*) list:(NSArray*) dblist
{
	NSMutableArray* indexes= [[NSMutableArray alloc] init];
	int counter=0; 
	[self setOfflineList:dblist];
	while(counter<[list count])
	{
		int pos=[self indexofStringOffline:[[list objectAtIndex:counter] objectAtIndex:0]];
		
		if((pos<[theOfflineList count]) && (pos>=0)) // account for no match and a random pos
		{	
			unsigned  int  indexlist[] = { 1,pos };
			[indexes addObject:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]];
			
			debug_NSLog(@"added offline indexes: %d %d",[[indexes objectAtIndex: [indexes count]-1] indexAtPosition:0],
						[[indexes objectAtIndex: [indexes count]-1] indexAtPosition:1]);
			
			//	[thelist removeObjectAtIndex:pos];
			
		}
		counter++; 
	}
	
	;
	return indexes ;
}





-(NSArray*) removeOffline:(NSArray*) list:(NSArray*) dblist
{
	NSMutableArray* indexes= [[NSMutableArray alloc] init];
	int counter=0; 
	
	while(counter<[list count])
	{
		int pos=[self indexofStringOffline:[[list objectAtIndex:counter] objectAtIndex:0]];
		
		if((pos<[theOfflineList count]) && (pos>=0)) // account for no match and a random pos
		{	
			unsigned  int  indexlist[] = { 1,pos };
			[indexes addObject:[NSIndexPath indexPathWithIndexes:indexlist length:2 ]];
			
			debug_NSLog(@"removed  indexes: %d %d",[[indexes objectAtIndex: [indexes count]-1] indexAtPosition:0],
						[[indexes objectAtIndex: [indexes count]-1] indexAtPosition:1]);
			
			
			
		}
		counter++; 
	}
	
	[self setOfflineList:dblist]; // set to new list with everything removed
	;
	return indexes ;
}



//tableview controller


		



#pragma mark table view datasource methods
//optional 

//clicked blue button
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {

	


 
    
	buddyDetails* detailwin=[buddyDetails alloc];
	
    detailwin.splitViewController=splitViewController;
    
	[detailwin init:jabber:viewController:@""];
	detailwin.iconPath=iconPath; 
	
	NSArray* row=[thelist objectAtIndex:[indexPath indexAtPosition:1]] ;
	
	[detailwin show:[row objectAtIndex:0]
				   :[row objectAtIndex:1]
				   :[row objectAtIndex:2]
	 :[row objectAtIndex:5]
	 :jabber.domain
                   :tableView
                   :[tableView rectForRowAtIndexPath:indexPath] 
	 ];

	;
}






//required

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	
	
	
	
	static NSString *identifier = @"MyCell";   
    CustomCell *thecell = [tableView dequeueReusableCellWithIdentifier:identifier];
    
    if (thecell == nil)
    {
        thecell = [[CustomCell alloc]initWithFrame: CGRectMake(45,0,tableView.frame.size.width,[tableView rowHeight]) reuseIdentifier:identifier]; debug_NSLog(@"new cell ");
    }
    else
    {
        debug_NSLog(@"reused cell");
    }
    
	
	int cellwidth=tableView.frame.size.width;
	
	if(indexPath.section==0) //online
	{
	thecell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
	
	
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
	
	
	UIImage* statusOrb; 
	CGRect orbRectangle = CGRectMake(51-13+8,([tableView rowHeight]/2) -7,15,15);
	
	NSInteger statusHeight=16;
	CGRect cellRectangle ; 
	
	// if there is a status
	if([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:2] length]>0)
	{
	 cellRectangle = CGRectMake(51+13,0,cellwidth-51-13-35-40,[tableView rowHeight]-statusHeight-2);  // 285 ->290 is basically my imaginary  border
		
		
	}
	else
	{
		 cellRectangle = CGRectMake(51+13,0,cellwidth-51-13-35-40,[tableView rowHeight]);
		
	}
	//51 icon 
	//13 orb
	//35 disclosure badge
	//37 counter
	
	
	//Initialize the label with the rectangle.
	UILabel* buddyname = [[UILabel alloc] initWithFrame:cellRectangle];
	buddyname.font=[UIFont boldSystemFontOfSize:18.0f];
	if([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:5] isEqualToString:@""])
		buddyname.text=[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:0];
	else
		buddyname.text=[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:5];
	//if the person is away change the text color 
	if(([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:1] isEqualToString:@"Away"])||
	   ([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:1] isEqualToString:@"away"])||
	   ([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:1] isEqualToString:@"dnd"]) ||
	   ([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:1] isEqualToString:@"xa"]) ||
	   ([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:1] isEqualToString:@"Do Not Disturb"]))
	{
		statusOrb=[UIImage imageNamed:@"away.png"];
			
		buddyname.textColor = [UIColor grayColor];
	} else
	{
		
		statusOrb=[UIImage imageNamed:@"available.png"];
		buddyname.textColor = [UIColor blackColor];
		
		
	}
	
	UIImageView* orbView = [ [ UIImageView alloc ] initWithImage: statusOrb ];
	orbView.frame = orbRectangle; // Set the frame in which the UIImage should be drawn in.
	
	[ thecell addSubview: orbView ];
	
	
	//buddyname.font=[UIFont SystemFontOfSize:16];
	debug_NSLog(@"cell status: %@",[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:1]); 
	
	buddyname.autoresizingMask   = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;	
	//Add the label as a sub view to the cell.
	thecell.buddyname=buddyname;
	[thecell.contentView addSubview:buddyname];
	
	
	if([[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:2] length]>0)
	{
	//add a  message
	
	cellRectangle = CGRectMake(51+13,[tableView rowHeight]-statusHeight-4,cellwidth-51-13-35-40,statusHeight); 
	
	
	
	UILabel* buddystatus = [[UILabel alloc] initWithFrame:cellRectangle];
		buddystatus.autoresizingMask   = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
	
	buddystatus.text=[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:2];
	debug_NSLog(@"cell message: %@",buddystatus.text); 
	buddystatus.font=[UIFont systemFontOfSize:13];
	buddystatus.textColor= [UIColor grayColor];
	//buddystatus.textColor=[UIColor darkGrayColor];
	//Add the label as a sub view to the cell.
	thecell.buddystatus=buddystatus;
	[thecell.contentView addSubview:buddystatus];
	}
	
		// add the count label 
		
		thecell.text=[NSString stringWithFormat:@"%@", [[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:4]];
		
		if([thecell.text isEqualToString:@"0"]) thecell.text=nil; 
		
		
		
	}
	else 
		if(indexPath.section==1)//offline
		{
			
			
			
			if([[[theOfflineList objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:3] length]>3)// at least extension 
			{
				NSFileManager* fileManager = [NSFileManager defaultManager]; 
				
				NSString* buddyfile = [NSString stringWithFormat:@"%@/%@", 
									   iconPath,[[theOfflineList objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:3]]; 
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
			
			[thecell.imageView setAlpha:YES];
			thecell.imageView.alpha=0.5; 
			
			UIImage* statusOrb; 
			CGRect orbRectangle = CGRectMake(51-13+8,([tableView rowHeight]/2) -7,15,15);
			
			NSInteger statusHeight=16;
			CGRect cellRectangle ; 
			
			
				cellRectangle = CGRectMake(51+13,0,cellwidth-51-13-35-45,[tableView rowHeight]);
				
			
			//51 icon 
			//13 orb
			//35 disclosure badge
			//45 counter
			
			
			//Initialize the label with the rectangle.
			UILabel* buddyname = [[UILabel alloc] initWithFrame:cellRectangle];
			buddyname.font=[UIFont boldSystemFontOfSize:18.0f];
			if([[[theOfflineList objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:5] isEqualToString:@""])
				buddyname.text=[[theOfflineList objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:0];
			else
				buddyname.text=[[theOfflineList objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:5];
			//if the person is away change the text color 
			
				buddyname.textColor = [UIColor grayColor];
			buddyname.autoresizingMask   = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin;
			
			
			
			statusOrb=[UIImage imageNamed:@"offline.png"];
			UIImageView* orbView = [ [ UIImageView alloc ] initWithImage: statusOrb ];
			orbView.frame = orbRectangle; // Set the frame in which the UIImage should be drawn in.
			
			
			
			[ thecell addSubview: orbView ];
			
			
			
			//Add the label as a sub view to the cell.
			thecell.buddyname=buddyname;
			[thecell.contentView addSubview:buddyname];
			
			
		}


	
	;
	return thecell;
}


#pragma mark section stuff

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OfflineContact"])
	return 2;
    else
        return 1;
	
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	
	if(section==0)
		return [self count];
	else
		if(section==1)
			return [theOfflineList count]; 
	
	
	return 0; //default
	
	
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	
	
	
	
	if(section==0)
		return @"Online";
	else
		if(section==1)
			return @"Offline";
}



#pragma mark tableview delegate 

-(void) showChatForUser:(NSString*)user withFullName:(NSString*)fullname
{
	[chatwin show:user				 :fullname
				 :viewController];
    
   
}


//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
	debug_NSLog(@"selected row %d max %d", [newIndexPath indexAtPosition:1], [thelist count]); 

    
    chatwin.contactList=tableView; 
	// ipad stuff
	if(tabcontroller.selectedIndex!=0)
		@try
	{
		tabcontroller.selectedIndex = 0;
	}
	@catch(NSException* err) {}

	
	if(newIndexPath.section==0) //online
	{
	
	
	if(([newIndexPath indexAtPosition:1]>=0) && 
		([newIndexPath indexAtPosition:1]<[thelist count])
		) 		
	{
		
		
	[self showChatForUser: [[thelist objectAtIndex:[newIndexPath indexAtPosition:1]] objectAtIndex:0]
				 withFullName:[[thelist objectAtIndex:[newIndexPath indexAtPosition:1]] objectAtIndex:5]
     ];
	}
	}
	else if(newIndexPath.section==1) //online
	{
		if(([newIndexPath indexAtPosition:1]>=0) && 
		   ([newIndexPath indexAtPosition:1]<[theOfflineList count])
		   ) 		
		{
            
            [self showChatForUser: [[theOfflineList objectAtIndex:[newIndexPath indexAtPosition:1]] objectAtIndex:0]
                     withFullName:[[theOfflineList objectAtIndex:[newIndexPath indexAtPosition:1]] objectAtIndex:5]
             ];
	}
	}
	
	@try
	{
	[tableView deselectRowAtIndexPath:newIndexPath animated:true];
	}
	@catch(NSException* err){debug_NSLog(@"error deselecting row");}
	
	CustomCell* cell = [tableView cellForRowAtIndexPath:newIndexPath];
	//cell.highlighted=false; 
	
	
	
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return @"Remove"; 
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    
	debug_NSLog(@"received command to remove contact");
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		
		
		currentPath= indexPath;
		currentTable=tableView;
		//ask if sure
		UIActionSheet *popupQuery = [[UIActionSheet alloc] initWithTitle:@"Are you sure you want to remove this contact?"
																delegate:self 
													   cancelButtonTitle:@"No" 
												  destructiveButtonTitle:@"Yes" 
													   otherButtonTitles:nil, nil];
		
		popupQuery.actionSheetStyle =  UIActionSheetStyleBlackOpaque;
		
		//[popupQuery showInView:tableView];
        //done to prevent clipping.. had problems with no button
		[popupQuery showFromTabBar:tabcontroller.tabBar];
        
        
		
		
		
		
		// deletion should happen in the response handler.. which checks button pressed 
		
		
	}
}

//alert view delegate
-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex 
{
	//button click handler
	
	
	
	
	//if yes pressed on delete
	if ( buttonIndex==0 )
	{
		debug_NSLog(@"deleting buddy %d", currentPath.section);
		
		NSMutableArray* theArray; 
		if(currentPath.section==0) theArray = thelist; 
		else theArray=theOfflineList; 
		
		// send  an xmpp unsubscribe notice... 
		if(	[jabber removeBuddy:[[theArray objectAtIndex:[currentPath indexAtPosition:1]] objectAtIndex:0]])
		{
			
			//	delete from datasource
			
			[theArray removeObjectAtIndex:[currentPath indexAtPosition:1]];
			
			
			//del from table
			[currentTable deleteRowsAtIndexPaths:[NSArray arrayWithObject:currentPath] withRowAnimation:UITableViewRowAnimationLeft];
			
			
			
			
		}
		else
		{
			
			//show deletion error message
			UIAlertView *deleteAlert = [[UIAlertView alloc] 
										initWithTitle:@"Buddy Removal Error" 
										message:@"Could not remove buddy."
										delegate:self cancelButtonTitle:@"Close"
										otherButtonTitles: nil];
			[deleteAlert show];
			
		}
		
		
	}
	
}



#pragma mark view stuff
-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}

-(void)viewDidAppear:(BOOL)animated
{
	debug_NSLog(@"buddy list did  appear");
	
    
    //needed to remove for ARC 
	//id *app=[[UIApplication sharedApplication] delegate];
	
	// show +
	viewController.navigationBar.topItem.leftBarButtonItem=plusButton;
	viewController.navigationBar.topItem.rightBarButtonItem=[self editButtonItem];
    viewController.navigationBar.topItem.rightBarButtonItem.title=@"Remove";

	
}

-(void)viewWillDisappear:(BOOL)animated
{
	debug_NSLog(@"buddy list will  disappear");
	//reset the edit button to not editing
	/*[app setEditing:false animated:false]; // this changes it to Done
	[currentTable setEditing:false animated:false];*/

	viewController.navigationBar.topItem.leftBarButtonItem=nil; 
	viewController.navigationBar.topItem.rightBarButtonItem=nil; 
}


-(void) setList:(NSArray*) list
{
	thelist =list;
}

-(void) setOfflineList:(NSArray*) list
{
	theOfflineList =list;
}


- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    
	debug_NSLog(@"Set editing called "); 
    
    if(viewController.navigationBar.topItem.rightBarButtonItem.style==UIBarStyleBlack)
    {
    viewController.navigationBar.topItem.rightBarButtonItem.style = UIBarButtonItemStyleDone;
     viewController.navigationBar.topItem.rightBarButtonItem.title=@"Done";
    }
    else {
        viewController.navigationBar.topItem.rightBarButtonItem.style = UIBarStyleBlack;
             viewController.navigationBar.topItem.rightBarButtonItem.title=@"Remove";
    }
    
    
	[[NSNotificationCenter defaultCenter] 
     postNotificationName: @"buddyEdit" object: self];
}



@end
