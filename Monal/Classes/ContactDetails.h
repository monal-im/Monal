//
//  chat.h
//  SworIM
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"


@interface ContactDetails : UITableViewController

@property (nonatomic, strong) NSDictionary *contact;

-(IBAction) callContact:(id)sender;

@end
