//
//  buddylist.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DataLayer.h"
#import "PasswordManager.h"
#import "SworIMAppDelegate.h"



@interface AIMEdit: UIViewController <UITableViewDataSource, UITableViewDelegate,UITextFieldDelegate,UIActionSheetDelegate> {


	DataLayer* db; 
	CGRect oldFrame;

	NSArray* sectionArray; 
	UINavigationController* navigationController;
	
	IBOutlet UITableView* theTable; 
IBOutlet UITableViewCell* usernameCell; 
 IBOutlet UITableViewCell* passwordCell; 
	 IBOutlet UITableViewCell* enableCell; 
	
	IBOutlet UITableViewCell* serverCell; 
	IBOutlet UITableViewCell* portCell; 

	
	
	IBOutlet UITextField* userText; 
		IBOutlet UITextField* passText; 
	IBOutlet UISwitch* enableSwitch; 
	
		IBOutlet UITextField* serverText; 
		IBOutlet UITextField* portText; 


	BOOL editing; 
	NSString* accountno;
	NSIndexPath* originIndex;
	
	
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


-(void) hideKeyboard;
- (IBAction) delClicked: (id) sender;

//others
-(void)initList:(UINavigationController*) nav:(NSIndexPath*) indexPath:(NSString*)accountnum; 
-(void) dealloc;

-(void) keyboardWillHide:(NSNotification *) note;
-(void) keyboardWillShow:(NSNotification *) note;
-(void) save; 


@property (nonatomic) DataLayer* db; 



@end


