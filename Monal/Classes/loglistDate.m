//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "loglistDate.h"


@implementation loglistDate  




-(void) setup:(NSString*) buddy
{
    
 
    
    SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
	
		db=[DataLayer sharedInstance];;
	chatwin=app.chatwin;
	accountno=app.accountno; 
    
   	thelist=[db messageHistoryListDates:buddy:accountno]; // change this to active account later when we have multiple acounts
	
    if((thelist==nil) || ([thelist count]==0))
    {
        ;
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
    
    
    currentTable =[[UITableView alloc] initWithFrame:CGRectNull style:UITableViewStylePlain];
    [currentTable setDelegate:self]; 
    [currentTable setDataSource:self];
    
    
    self.view=currentTable;
    
    thebuddy=buddy; 
    ;
}






-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}


-(void)viewDidAppear:(BOOL)animated 
{
	
	debug_NSLog(@"chat  log date list did appear");
	

	;

}

-(void)viewWillDisappear:(BOOL)animated
{
	debug_NSLog(@"chat log datelist will disappear");
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









//table view datasource methods

//required

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	
	
	static NSString *identifier = @"MyCell";
	UITableViewCell* thecell =[[UITableViewCell alloc] initWithStyle:  UITableViewCellStyleSubtitle  reuseIdentifier:identifier];
	
	
thecell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	thecell.textLabel.text=[[thelist objectAtIndex:[indexPath indexAtPosition:1]] objectAtIndex:0];
	

	;
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



//table view delegate methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
	debug_NSLog(@"selected log row %d max %d", [newIndexPath indexAtPosition:1], [thelist count]); 
		
	[chatwin showLogDate:thebuddy
					:@""
					:viewController
                        :[[thelist objectAtIndex:[newIndexPath indexAtPosition:1]] objectAtIndex:0]
	 
	];
    
	
		[tableView deselectRowAtIndexPath:newIndexPath animated:true];
 //slide in the date list
    
    
	
}






@end
