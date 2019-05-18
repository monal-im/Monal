//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"
#import "MWPhotoBrowser.h"


@interface ContactDetails : UITableViewController <UITextFieldDelegate, MWPhotoBrowserDelegate>

@property (nonatomic, strong) NSDictionary *contact;

-(IBAction) callContact:(id)sender;
-(IBAction) muteContact:(id)sender;
-(IBAction) toggleEncryption:(id)sender;


@end
