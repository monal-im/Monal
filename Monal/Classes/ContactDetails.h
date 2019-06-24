//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"
#import "IDMPhotoBrowser.h"


@interface ContactDetails : UITableViewController <UITextFieldDelegate, IDMPhotoBrowserDelegate>

@property (nonatomic, strong) NSDictionary *contact;

-(IBAction) callContact:(id)sender;
-(IBAction) muteContact:(id)sender;
-(IBAction) toggleEncryption:(id)sender;


@end
