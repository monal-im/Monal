//
//  buddylist.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "DataLayer.h"
#import "XMPPEdit.h"
#import "AIMEdit.h"

#import "SworIMAppDelegate.h"



@interface accounts : UIViewController <UITableViewDataSource, UITableViewDelegate> {

	IBOutlet UITableView* theTable; 
	NSMutableArray* thelist; //account list
	NSMutableArray* thelist2; //protocol list
	NSMutableArray* enabledList; //enabled accounts
	NSIndexPath* currentPath; 
	UITableView* currentTable; 
	DataLayer* db; 
	NSString* iconPath; 
	NSArray* sectionArray; 
	
	UINavigationController* viewController; 
	UIBarButtonItem* reconnect;
	UIBarButtonItem* logoff;
	bool first; 
	}


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
-(void)initList:(UINavigationController*) nav; 
-(void) dealloc;
- (void)refreshAccounts;


 
@property (nonatomic) IBOutlet UITableView* theTable;

@end


