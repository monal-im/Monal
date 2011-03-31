//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "xmpp.h"



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
 
    
}




-(void) init: (protocol*) jabberIn:(UINavigationController*) nav:(NSString*)username; 
-(void) show:(NSString*) buddy:(NSString*) status:(NSString*) message:(NSString*) fullname:(NSString*) domain : (UITableView*) table: (CGRect) cellRect;
-(UIImage*) setIcon:(NSString*) msguser;



@property (nonatomic, retain) NSString* iconPath; 
//@property (nonatomic, retain) NSString* domain; 

@property (nonatomic, retain) IBOutlet UIImageView* buddyIconView;
@property (nonatomic, retain) IBOutlet UIImageView* protocolImage;
@property (nonatomic, retain) IBOutlet UILabel* buddyName;
@property (nonatomic, retain) IBOutlet UILabel* fullName;
@property (nonatomic, retain) IBOutlet UILabel* buddyStatus;
@property (nonatomic, retain) IBOutlet UITextView* buddyMessage; 
@end
