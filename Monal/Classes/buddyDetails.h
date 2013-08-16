//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "xmpp.h"
#import "callScreen.h"


@interface buddyDetails : UIViewController{

	protocol* jabber;
	
	UINavigationController* navigationController;
	

	NSString*  myuser;
	
	DataLayer* db;
	bool alertShown;

	 NSString* iconPath; 
	
	   UIPopoverController* popOverController; 

	UIImageView* buddyIconView; 
	UIImageView* protocolImage; 
	UIImage* buddyIcon; 
	UILabel* buddyName;
	UILabel* fullName;
	UITextView* buddyMessage; 
	UILabel* buddyStatus; 
	

	IBOutlet UITableView* theTable; 
	IBOutlet UIView* top; 
	
	IBOutlet UITableViewCell* topcell; 
	IBOutlet UITableViewCell* bottomcell; 

    
    IBOutlet UIButton* callButton;
    
    callScreen*  call;
    
    
}




-(void) init: (protocol*) jabberIn:(UINavigationController*) nav:(NSString*)username; 
-(void) show:(NSString*) buddy:(NSString*) status:(NSString*) message:(NSString*) fullname:(NSString*) domain : (UITableView*) table: (CGRect) cellRect;
-(UIImage*) setIcon:(NSString*) msguser;

-(IBAction) callPress;


@property (nonatomic) NSString* iconPath; 
//@property (nonatomic, retain) NSString* domain; 

@property (nonatomic) IBOutlet UIImageView* buddyIconView;
@property (nonatomic) IBOutlet UIImageView* protocolImage;
@property (nonatomic) IBOutlet UILabel* buddyName;
@property (nonatomic) IBOutlet UILabel* fullName;
@property (nonatomic) IBOutlet UILabel* buddyStatus;
@property (nonatomic) IBOutlet UITextView* buddyMessage;

@property UISplitViewController* splitViewController;

@end
