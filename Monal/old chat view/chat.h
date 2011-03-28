//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "xmpp.h"
#import "DataLayer.h"
#import "tools.h"



@interface chat : UIViewController <UITableViewDataSource,UITableViewDelegate,UITextFieldDelegate>{

	 UITextField *chatInput;
	UITableView *chatTable;
	xmpp* jabber;
	
		UINavigationController* navigationController;
	UIViewController* viewController; 
	
	//dataset for current chat window
	NSArray* thelist; 
	
	NSString*  myuser;
	
		DataLayer* db;
	bool alertShown;

	 NSString* iconPath; 
	 NSString* domain; 
	
	CGRect oldFrame;
	UIImage* myIcon; 
	UIImage* buddyIcon; 
	
	NSString* accountno; 
	

	

	
}


@property (nonatomic, retain) IBOutlet UITextField *chatInput;
@property (nonatomic, retain) IBOutlet UITableView *chatTable;
@property (nonatomic, retain)  NSString* accountno; 

-(void) init: (xmpp*) jabberIn:(UINavigationController*) nav:(NSString*)username: (DataLayer*) thedb; 
-(void) show:(NSString*) buddy;
-(void) showLog:(NSString*) buddy;
-(void) addMessage:(NSString*) to:(NSString*) message;
-(void) signalNewMessages; 
-(void) datarefresh; 
-(void) scrollCorrect;
-(UIImage*) setIcon:(NSString*) msguser; 

//textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
- (void)textFieldDidBeginEditing:(UITextField *)textField;
- (void)textFieldDidEndEditing:(UITextField *)textField;

//notification 
-(void) keyboardWillShow:(NSNotification *) note;
-(void) keyboardWillHide:(NSNotification *) note;

//table datasource functions
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath;


//table delegate
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;


@property (nonatomic, retain) NSString* iconPath; 
@property (nonatomic, retain) NSString* domain; 
@property (nonatomic, retain)	UIViewController* viewController; 
@end
