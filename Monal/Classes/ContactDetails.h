//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"


@interface ContactDetails : UITableViewController{
  
    IBOutlet UITableView* _theTable;
	IBOutlet UITableViewCell* _topcell;
	IBOutlet UITableViewCell* _bottomcell;
    IBOutlet UITableViewCell* _resourceCell;
    IBOutlet UIButton* _callButton;
    
    NSDictionary* _contact; 
    
}

@property (nonatomic,weak) IBOutlet UIImageView* buddyIconView;
@property (nonatomic,weak) IBOutlet UIImageView* protocolImage;
@property (nonatomic,weak) IBOutlet UITextView* buddyName;
@property (nonatomic,weak) IBOutlet UILabel* fullName;
@property (nonatomic,weak) IBOutlet UILabel* buddyStatus;
@property (nonatomic,weak) IBOutlet UITextView* buddyMessage;
@property (nonatomic,weak) IBOutlet UITextView* resourcesTextView;

-(id) initWithContact:(NSDictionary*) contact;
-(IBAction) callContact:(id)sender;


@end
