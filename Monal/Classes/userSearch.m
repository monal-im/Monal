//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "userSearch.h"


@implementation userSearch  





#pragma mark view stuff
- (void) hideKeyboard 
{
    [searchField resignFirstResponder]; 
    [serverField resignFirstResponder];
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}


-(void) showUsers:(id)sender
{
	debug_NSLog(@"Got user Search results" );
    //read db and load into table 
	thelist=jabber.userSearchItems; 
    [currentTable reloadData];
}


-(void)viewDidAppear:(BOOL)animated 
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	debug_NSLog(@"user search did appear");
	
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)];
    gestureRecognizer.cancelsTouchesInView=false; //this prevents it from blocking the button
    
    [self.view addGestureRecognizer:gestureRecognizer];
    
    
    SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
	
	db=app.db;
	jabber=(xmpp*) app.jabber;
	accountno=app.accountno; 
	
	serverField.text=jabber.userSearchServer; 
	
	
	if(accountno==nil) {
		[pool release];
		return; 
	}
    
//register to hear notification
   	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showUsers:) name: @"UserSearchResult" object:nil];	 
    
	[pool release];
    return;     

}

-(void)viewWillDisappear:(BOOL)animated
{
	debug_NSLog(@"user search will disappear");

}



-(NSInteger) count
{
	if(thelist==nil) return 0; 
	return [thelist count];
	
}





#pragma mark uitextfield delegate



//text delatgate fn
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	
	
    switch(textField.tag)
	{// status
        case 0:
        {
            
            debug_NSLog(@"Setting search server"); 
            
            break; 
            
            
        }
        case 1:
        {
            //priority
			debug_NSLog(@"Setting search term"); 
            [jabber userSearch:textField.text]; 
            
        }
	}
    
	//hide keyboard
	[textField resignFirstResponder];
	
	
	return true;
}




//table view datasource methods

//required

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	static NSString *identifier = @"MyCell";
	UITableViewCell* thecell =[[[UITableViewCell alloc] initWithStyle:  UITableViewCellStyleSubtitle  reuseIdentifier:identifier] autorelease];
	
	
thecell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		thecell.textLabel.text=[thelist objectAtIndex:indexPath.row];
	
	
		
	[thecell retain];
	[pool release];
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
    	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	debug_NSLog(@"selected log row %d max %d", [newIndexPath indexAtPosition:1], [thelist count]); 
		
// action here
	
    
    buddyAdd* addwin=[[buddyAdd alloc] autorelease];
	 SworIMAppDelegate *app=[[UIApplication sharedApplication] delegate];
    
	[addwin init:app.morenav:nil];
    
	
	
	[addwin show:jabber:[thelist objectAtIndex:[newIndexPath indexAtPosition:1]]];
    
    
		[tableView deselectRowAtIndexPath:newIndexPath animated:true];

	[pool release];
}




-(void)dealloc
{
	[thelist release];
	[super dealloc];
}


@end
