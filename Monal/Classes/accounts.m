//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "accounts.h"


@implementation accounts  






 -(void)logoffClicked
{
	[[NSNotificationCenter defaultCenter] 
	 postNotificationName: @"Disconnect" object: self];
}

 -(void)reconnectClicked
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	if(enabledList!=nil)[enabledList release]; 

	NSArray* enabledAccounts=[db enabledAccountList]; 
		enabledList=enabledAccounts;
	
	[[NSNotificationCenter defaultCenter] 
	 postNotificationName: @"Reconnect" object: self];
	
	[pool release];
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}

- (void)viewDidAppear:(BOOL)animated
{
	debug_NSLog(@"accuounts appeared"); 
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
	
	
	sectionArray =  [[NSArray arrayWithObjects:@"Accounts\n(Only one can be set to login)", @"Add New Account", nil] retain];
	viewController=app.accountsNavigationController;
	
	db=app.db;
	iconPath=app.iconPath; 
	
	/*thelist=[db accountList]; //accounts*/

if(first!=true)
{
	thelist2=[db protocolList]; // protocols
	enabledList=[db enabledAccountList];
	first=true; 
}
	
	reconnect= [[[UIBarButtonItem alloc] initWithTitle:@"Reconnect"
style:UIBarButtonItemStyleBordered
									   target:self action:@selector(reconnectClicked)] autorelease];

	
	logoff= [[[UIBarButtonItem alloc] initWithTitle:@"Logoff"
												style:UIBarButtonItemStyleBordered
											   target:self action:@selector(logoffClicked)] autorelease];
	
	
	
	
	viewController.navigationBar.topItem.rightBarButtonItem=reconnect;
		viewController.navigationBar.topItem.leftBarButtonItem=logoff;
	
	debug_NSLog(@" accounts did appear"); 
	[self refreshAccounts]; 
	
	
	// if all disabled then disconnect 
	debug_NSLog(@" enabled list count:%d",[enabledList count]); 
	if([enabledList count]<1)
	{
		debug_NSLog(@" posting disconnect"); 
		//disconnect current account
		[[NSNotificationCenter defaultCenter] 
		 postNotificationName: @"Disconnect" object: self];
	}
	
	[theTable reloadData];
	[pool release]; 
	
}


-(void)viewDidDisappear:(BOOL)animated
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];


	
	viewController.navigationBar.topItem.leftBarButtonItem=nil; 
	viewController.navigationBar.topItem.rightBarButtonItem=nil; 
	
	[pool release]; 
	return;
}



- (void)refreshAccounts
{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	debug_NSLog(@"refreshing accounts "); 
	thelist=[db accountList];
	
	//[theTable reloadData];
	
	debug_NSLog(@"check to see if enabled account changed"); 
	
	NSArray* enabledAccounts=[db enabledAccountList]; 
	
	// seperate enumeration of if to stop crashing
	if(enabledAccounts!=nil)
	if([enabledAccounts count]>0)
	{
	if( ( (enabledList==nil) || ([enabledList count]<1) ) ||
	([[[enabledList objectAtIndex:0] objectAtIndex: 0] intValue]!= [[[enabledAccounts objectAtIndex:0] objectAtIndex: 0] intValue]))
	{
		if((enabledList!=nil) && ([enabledList count]>0))
	{
			debug_NSLog(@"enabed has changed. from %d to %d sending notification to disconnect and reconnect",
						[[[enabledList objectAtIndex:0] objectAtIndex: 0] intValue], [[[enabledAccounts objectAtIndex:0] objectAtIndex: 0] intValue] ); 
		[enabledList release]; 
	
	}
		enabledList=enabledAccounts;
		[enabledList retain];

		[[NSNotificationCenter defaultCenter] 
		 postNotificationName: @"Reconnect" object: self];
	}	
	} else
	{
		[enabledList release]; 
		enabledList= enabledAccounts;
		[enabledList retain];
	}
 [pool release]; 
		return; 
}




//table view datasource methods

//required

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{

	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	static NSString *identifier = @"MyCell";
	UITableViewCell* thecell = [[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease];
thecell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	

	

	UILabel* buddyname ;
	

	if(indexPath.section==0)
	{
		//NSInteger statusHeight=15;
		
		//CGRect cellRectangle = CGRectMake(45,0,240,[tableView rowHeight]-statusHeight-3);  // 285 ->290 is basically my imaginary  border
		
		//Initialize the label with the rectangle.
		//buddyname = [[[UILabel alloc] initWithFrame:cellRectangle] autorelease];
		
		thecell.textLabel.text=[NSString stringWithFormat:@"%@@%@",[[thelist objectAtIndex:indexPath.row] objectAtIndex:1],
						[[thelist objectAtIndex:indexPath.row] objectAtIndex:9]];
		//buddyname.font=[UIFont boldSystemFontOfSize:14];
		//cellRectangle = CGRectMake(45,[tableView rowHeight]-statusHeight-3,230,statusHeight); 
		
       // buddyname.backgroundColor = [UIColor clearColor];
        
		//UILabel* buddystatus = [[[UILabel alloc] initWithFrame:cellRectangle] autorelease];
		
		//buddystatus.text=[[thelist objectAtIndex:indexPath.row] objectAtIndex:9];
	
		//buddystatus.font=[UIFont systemFontOfSize:12];
	
		//Add the label as a sub view to the cell.
		//[thecell.contentView addSubview:buddystatus];
		
		
		UIImage* image;
		if([[[thelist objectAtIndex:indexPath.row] objectAtIndex:10] intValue]==true)
		{
		image=[UIImage imageNamed:@"enabled.png"];
		}
		else
		{
		image=[UIImage imageNamed:@"disabled.png"];
		}
			thecell.imageView.image=image;  
		
		
		
		
	}
	else 
		if(indexPath.section==1)
		{
			
		//	CGRect cellRectangle = CGRectMake(45,0,250,[tableView rowHeight]-3);  
			
			//Initialize the label with the rectangle.
			// buddyname = [[[UILabel alloc] initWithFrame:cellRectangle] autorelease];
			thecell.textLabel.text=[[thelist2 objectAtIndex:indexPath.row] objectAtIndex:1];
            if([thecell.textLabel.text isEqualToString:@"XMPP"])
            {
                thecell.detailTextLabel.text=@"Jabber,WebEx,OpenFire, etc."; 
            }
            
            if([thecell.textLabel.text isEqualToString:@"GTalk"])
            {
                thecell.detailTextLabel.text=@"Gtalk,Google Apps, etc. "; 
            }
            
           // buddyname.backgroundColor = [UIColor clearColor];

			NSString* buddyfile = [NSString stringWithFormat:@"%@.png", thecell.textLabel.text]; 
			debug_NSLog(buddyfile);
			if([buddyfile isEqualToString:@"GTalk.png"])
				buddyfile=[NSString stringWithString:@"google.png"];
			
           
            
		UIImage* image=[UIImage imageNamed:buddyfile];
		
			//thecell.imageView.image=[tools resizedImage:image: CGRectMake(0, 0, 38, 38)]; 
			
			//UIImageView *imageView = [ [ UIImageView alloc ] initWithImage: image ];
			
			//imageView.frame = CGRectMake(12, 5, 38, 38); // Set the frame in which the UIImage should be drawn in.
		
			thecell.imageView.image=image; 
			thecell.imageView.frame=CGRectMake(12, 5, 38, 38); 
			
			
		//[ thecell addSubview: imageView ]; // Draw the image in self.view. 
	
		}
	

		
	[thecell retain];
	[pool release];
	return thecell;
}



- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if(section==0)
		return [thelist count];
		else
	if(section==1)
	return [thelist2 count];
	
	
	return 0; //default
	
}


- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
	return YES;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath
{
}


 


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	
	
	return [sectionArray count];
	
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	
	
	
	return [sectionArray objectAtIndex:section];
}


//table view delegate methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
	debug_NSLog(@"selected log section %d , row %d,  max %d", newIndexPath.section, newIndexPath.row, [thelist count]); 
		
	//	[chatwin showLog:[[thelist objectAtIndex:[newIndexPath indexAtPosition:1]] objectAtIndex:0]];
	
	
	
	if(newIndexPath.section==0)
	{
		debug_NSLog(@"selected account with protocol %d", [[[thelist objectAtIndex:newIndexPath.row] objectAtIndex:2] intValue]);
		//identify protocol
		if([[[thelist objectAtIndex:newIndexPath.row] objectAtIndex:2] intValue]!=3) //proocol 3 is AIM (counts from 1)
		{
			XMPPEdit* xmppedit=[[XMPPEdit alloc] retain]; 
			xmppedit.db=db;
		[xmppedit initList:viewController:newIndexPath:[NSString stringWithFormat:@"%@",[[thelist objectAtIndex:newIndexPath.row] objectAtIndex:0]]];
		[viewController pushViewController:xmppedit animated:YES];	
		}
		else
		{
			AIMEdit* aimedit=[[AIMEdit alloc] retain]; 
			aimedit.db=db;
			[aimedit initList:viewController:newIndexPath:[NSString stringWithFormat:@"%@",[[thelist objectAtIndex:newIndexPath.row] objectAtIndex:0]]];
			[viewController pushViewController:aimedit animated:YES];	
		}
	}
	else
	{
		if(newIndexPath.row!=2) //  row 2 is AIM
		{
		XMPPEdit* xmppedit=[[XMPPEdit alloc] retain]; 
		xmppedit.db=db;
		[xmppedit initList:viewController:newIndexPath:@"-1"];
		[viewController pushViewController:xmppedit animated:YES];
		}
		else
		{
		AIMEdit* aimedit=[[AIMEdit alloc] retain]; 
		aimedit.db=db;
		[aimedit initList:viewController:newIndexPath:@"-1"];
			[viewController pushViewController:aimedit animated:YES];
		}
			
	}
		
	
	
	
		[tableView deselectRowAtIndexPath:newIndexPath animated:true];
	

	
}




-(void)dealloc
{
	[sectionArray release];
	[thelist2 release];
	[thelist release];
	[super dealloc];
}


@end
