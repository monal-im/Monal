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
#import "MLXMPPManager.h"


@interface XMPPEdit: UITableViewController <UITextFieldDelegate,UIActionSheetDelegate> {
    
    
	CGRect oldFrame;
	
	IBOutlet UITableView* theTable;
    IBOutlet UITableViewCell* usernameCell;
    IBOutlet UITableViewCell* passwordCell;
    IBOutlet UITableViewCell* enableCell;
	
	IBOutlet UITableViewCell* serverCell;
	IBOutlet UITableViewCell* portCell;
	IBOutlet UITableViewCell* resourceCell;
	IBOutlet UITableViewCell* SSLCell;
    
    IBOutlet UITableViewCell* oldStyleSSLCell;
    IBOutlet UITableViewCell* checkCertCell;
    
    IBOutlet UITextField* userText;
    IBOutlet UITextField* passText;
	IBOutlet UISwitch* enableSwitch;
	
    IBOutlet UITextField* serverText;
    IBOutlet UITextField* portText;
    IBOutlet UITextField* resourceText;
    IBOutlet UISwitch* sslSwitch;
    
    IBOutlet UISwitch* oldStyleSSLSwitch;
    IBOutlet UISwitch* checkCertSwitch;
	
	IBOutlet UILabel* JIDLabel;
    
}


@property (nonatomic, strong) DataLayer* db;
@property (nonatomic, strong ) 	NSArray* sectionArray;

@property (nonatomic, assign) BOOL editing;
@property (nonatomic, strong)  NSString* accountno;
@property (nonatomic, strong)  NSIndexPath* originIndex;


-(void) hideKeyboard;
- (IBAction) delClicked: (id) sender;

-(void) keyboardWillHide:(NSNotification *) note;
-(void) keyboardWillShow:(NSNotification *) note;
-(void) save; 





@end


