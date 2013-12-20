//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "userSearch.h"


@implementation userSearch  



-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}


-(void) showUsers:(id)sender
{
	DDLogVerbose(@"Got user Search results" );
    //read db and load into table 
	thelist=jabber.userSearchItems; 
    [currentTable reloadData];
    [self.searchDisplayController.searchResultsTableView reloadData];
}


-(void)viewDidAppear:(BOOL)animated 
{
	
	DDLogVerbose(@"user search did appear");
	
  /*  UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)];
    gestureRecognizer.cancelsTouchesInView=false; //this prevents it from blocking the button
    
    [self.view addGestureRecognizer:gestureRecognizer];
    */
    
    SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
	
		db=[DataLayer sharedInstance];
	jabber=(xmpp*) app.jabber;
	accountno=app.accountno; 
	
	
	if(accountno==nil) {
		;
		return; 
	}
    
//register to hear notification
   	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showUsers:) name: @"UserSearchResult" object:nil];	 
    
	;
    return;     

}

-(void)viewWillDisappear:(BOOL)animated
{
	DDLogVerbose(@"user search will disappear");

}



-(NSInteger) count
{
	if(thelist==nil) return 0; 
	return [thelist count];
	
}


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	
	DDLogVerbose(@"clicked button %d", buttonIndex); 
    if(buttonIndex==0)
    {
    //add
        [jabber addBuddy:contact];
    }
    
    ;
}

//clicked blue button
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    
	
    
	//add buddy
    DDLogVerbose(@"Clicked add contact");
    
    UIAlertView *addAlert = [[UIAlertView alloc] 
                                initWithTitle:@"Add Contact" 
                             message:[NSString stringWithFormat:@"Are you sure you want to add %@ as a contact?",
                                      [thelist objectAtIndex:indexPath.row]]
                                delegate:self cancelButtonTitle:@"Yes"
                                otherButtonTitles: @"No",nil];
    [addAlert show];
    
    contact=[thelist objectAtIndex:indexPath.row];
    
	;
}





- (void) accessoryButtonTapped: (UIControl *) button withEvent: (UIEvent *) event
{
    NSIndexPath * indexPath = [currentTable indexPathForRowAtPoint: [[[event touchesForView: button] anyObject] locationInView: currentTable]];
    if ( indexPath == nil )
        return;
    
    [currentTable.delegate tableView: currentTable accessoryButtonTappedForRowWithIndexPath: indexPath];
}


- (UIButton *) makeDetailDisclosureButton
{
    UIButton * button = [UIButton buttonWithType: UIButtonTypeContactAdd] ;
    
    
    [button addTarget: self
               action: @selector(accessoryButtonTapped:withEvent:)
     forControlEvents: UIControlEventTouchUpInside];
    
    return ( button );
}



#pragma mark table view datasource methods

//required

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	
	
	static NSString *identifier = @"MyCell";
	UITableViewCell* thecell =[[UITableViewCell alloc] initWithStyle:  UITableViewCellStyleSubtitle  reuseIdentifier:identifier];
	
	thecell.accessoryView=[self makeDetailDisclosureButton];


    //sanity check for sync is important
    if(indexPath.row<[thelist count])
    {
		thecell.textLabel.text=[thelist objectAtIndex:indexPath.row];
      
	}
	
		
	;
	return thecell;
}



- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	
	return [self count];
}




#pragma mark table view delegate methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
    	
	DDLogVerbose(@"selected log row %d max %d", [newIndexPath indexAtPosition:1], [thelist count]); 
		
// action here
	
  /*  
    buddyAdd* addwin=[[buddyAdd alloc] autorelease];
	 SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
    
    if([[tools machine] isEqualToString:@"iPad"])
    {
        [addwin init:app.morenav:nil];
    
    }
    else
    {
	[addwin init:app.morenav:nil];
    }
	
	
	[addwin show:jabber:[thelist objectAtIndex:[newIndexPath indexAtPosition:1]]];
    
    */

		[tableView deselectRowAtIndexPath:newIndexPath animated:true];

	;
}


#pragma mark search bar controller delegate

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)searchString
{
    
    
    // reload when we have data
    return NO;
}



#pragma mark search bar  delegate


- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    DDLogVerbose(@"Setting search term"); 
    [jabber userSearch:searchBar.text]; 
    // clear tables
    thelist=[[NSArray alloc] init];
     [currentTable reloadData];
     [self.searchDisplayController.searchResultsTableView reloadData];

}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
     DDLogVerbose(@"clicked cancel"); 
    //SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
    
  //  [app.morenav popViewControllerAnimated:YES];
}




@end
