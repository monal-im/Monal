//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "protocol.h"
#import "MyTabController.h"



@interface statusControl : UIViewController <UITextFieldDelegate>{


	

    NSString* iconPath; 
    protocol* jabber;  
	

	IBOutlet UIImageView* ownIcon; 

	IBOutlet UITableView* theTable; 
	
	
	IBOutlet UITableViewCell* topcell; 
    
    IBOutlet UITableViewCell* awaycell; 
    IBOutlet UITableViewCell* visiblecell; 
    IBOutlet UITableViewCell* prioritycell; 
    
    IBOutlet UITableViewCell* alertcell; 
    IBOutlet UITableViewCell* vibratecell; 
   
    
    IBOutlet UITableViewCell* musiccell; 
  IBOutlet UITableViewCell* statuscell; 
      IBOutlet UITableViewCell* previewcell; 
      IBOutlet UITableViewCell* loggingcell; 
    IBOutlet UITableViewCell* offlinecontactcell; 
    
    
    IBOutlet UISwitch *vibrateSwitch;
	IBOutlet UILabel *vibrateLabel;
	
	IBOutlet UISwitch *soundSwitch;
	IBOutlet UILabel *soundLabel;

	
    IBOutlet UILabel* currentStatus; 
    
IBOutlet UITextField* statusval; 
	IBOutlet UITextField* priority; 

	IBOutlet	UISwitch* Away; 
	IBOutlet	UISwitch* Visible; 
	 
	IBOutlet	UISwitch* MusicStatus; 
	IBOutlet	UISwitch* MessagePreview; 
    IBOutlet	UISwitch* Logging; 
	
    IBOutlet	UISwitch* OfflineContact; 
    
    
    
	
    
    
	IBOutlet  MyTabController* tabcontroller; 

    UITableView* contactsTable; 
 

}





-(IBAction) setAway; 
-(IBAction) invisible; 

-(IBAction) soundOn; 
-(IBAction) vibrateOn; 

-(IBAction) offlineContacs; 

-(IBAction) previewOn; 
-(IBAction) loggingOn; 


-(IBAction) musicOn;

@property (nonatomic, retain)  NSString*  iconPath; 


@property (nonatomic, retain)  protocol* jabber;

@property (nonatomic, retain)  UITableView* contactsTable; 


 
@end
