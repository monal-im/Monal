//
//  ContactDetails.h
//  Monal
//
//  Created by Anurodh Pokharel on 1/25/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DataLayer.h"
#import "IDMPhotoBrowser.h"

typedef void (^controllerCompletion)(void);

@interface ContactDetails : UITableViewController <UITextFieldDelegate, IDMPhotoBrowserDelegate>

@property (nonatomic, strong) MLContact* contact;
@property (nonatomic, strong) controllerCompletion completion;

-(IBAction) muteContact:(id) sender;
-(IBAction) toggleEncryption:(id) sender;


@end
