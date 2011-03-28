//
//  buddylist.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "chat.h"
#import "DataLayer.h"
#import "tools.h"

#import "SworIMAppDelegate.h"
#import "xmpp.h"
#import "buddyAdd.h"


@interface userSearch : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {

  
    IBOutlet UITableView* currentTable; 
  
    IBOutlet UITextField* serverField; 
    IBOutlet UITextField* searchField; 
    
    NSArray* thelist; 
    DataLayer* db; 
    NSString* accountno; 
    xmpp* jabber; 
    
	/*chat* chatwin;
	NSIndexPath* currentPath; 
	
	
	NSString* iconPath; 
	 UINavigationController* viewController; 

	
	int sheet;
	*/

	
}

-(void) showUsers:(id)sender; 

//table view delegat methods
//required
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath;


//table view datasource methods
//required
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
//- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;

//table manipulation functions


//others
-(void) dealloc;


//buddylist functions



-(NSInteger) count;


@end


