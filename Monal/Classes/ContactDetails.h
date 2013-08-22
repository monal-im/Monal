//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"
//#import "callScreen.h"

@interface ContactDetails : UIViewController{
    
    UIPopoverController* _popOverController;
    
    IBOutlet UITableView* _theTable;
	IBOutlet UITableViewCell* _topcell;
	IBOutlet UITableViewCell* _bottomcell;
    IBOutlet UIButton* _callButton;
    
    NSDictionary* _contact; 
   // callScreen*  call;
    
}

@property (nonatomic) IBOutlet UIImageView* buddyIconView;
@property (nonatomic) IBOutlet UIImageView* protocolImage;
@property (nonatomic) IBOutlet UITextView* buddyName;
@property (nonatomic) IBOutlet UILabel* fullName;
@property (nonatomic) IBOutlet UILabel* buddyStatus;
@property (nonatomic) IBOutlet UITextView* buddyMessage;

-(id) initWithContact:(NSDictionary*) contact;
-(IBAction) callPress;


@end
