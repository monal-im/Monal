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



@interface loglistDate : UIViewController <UITableViewDataSource, UITableViewDelegate> {

		NSArray* thelist; 
	chat* chatwin;
	NSIndexPath* currentPath; 
	 UITableView* currentTable; 
	DataLayer* db; 
	NSString* iconPath; 
	 UINavigationController* viewController; 

	NSString* accountno; 
	int sheet;
    
    NSString* thebuddy; 
	

	
}

-(void) setup:(NSString*) buddy; 

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


-(int) indexofString:(NSString*)name;

-(NSInteger) count;


@end


