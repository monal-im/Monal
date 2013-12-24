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
  
    IBOutlet UITableView* _theTable;
	IBOutlet UITableViewCell* _topcell;
	IBOutlet UITableViewCell* _bottomcell;
    IBOutlet UITableViewCell* _resourceCell;
    IBOutlet UIButton* _callButton;
    
    NSDictionary* _contact; 
   // callScreen*  call;
    
}

@property (nonatomic,weak) IBOutlet UIImageView* buddyIconView;
@property (nonatomic,weak) IBOutlet UIImageView* protocolImage;
@property (nonatomic,weak) IBOutlet UITextView* buddyName;
@property (nonatomic,weak) IBOutlet UILabel* fullName;
@property (nonatomic,weak) IBOutlet UILabel* buddyStatus;
@property (nonatomic,weak) IBOutlet UITextView* buddyMessage;
@property (nonatomic,weak) IBOutlet UITextView* resourcesTextView;

/**
 The popover controller presenting this on ipad
 */
@property (nonatomic, weak) UIPopoverController* popOverController;
/**
 This is the main nav controller of the app. may not be the one in the pop out (ipad)
 */
@property (nonatomic, weak)  UINavigationController* currentNavController;

-(id) initWithContact:(NSDictionary*) contact;
-(IBAction) callContact:(id)sender;


@end
