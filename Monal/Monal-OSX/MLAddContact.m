//
//  MLAddContact.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/18/15.
//  Copyright © 2015 Monal.im. All rights reserved.
//

#import "MLAddContact.h"
#import "MLXMPPManager.h"


@interface MLAddContact ()

@end

@implementation MLAddContact

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}


-(void) viewWillAppear
{
    NSInteger pos=0;
    while (pos<[MLXMPPManager sharedInstance].connectedXMPP.count)
    {
      [self.accounts addItemWithObjectValue:[[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:pos]];
        pos++;
    }
    
}

-(IBAction)add:(id)sender
{
    if(self.contactName.stringValue.length>0)
    {
//        NSDictionary* contact =@{@"row":[NSNumber numberWithInteger:_selectedRow],@"buddy_name":self.contactName.text};
//        [[MLXMPPManager sharedInstance] addContact:contact];
        
//        UIAlertView *addError = [[UIAlertView alloc]
//                                 initWithTitle:@"Permission Requested"
//                                 message:@"The new contact will be added to your contacts list when the person you've added has approved your request."
//                                 delegate:self cancelButtonTitle:@"Close"
//                                 otherButtonTitles: nil] ;
//        [addError show];
    }
    else
    {
//        UIAlertView *addError = [[UIAlertView alloc]
//                                 initWithTitle:@"Error"
//                                 message:@"Name can't be empty"
//                                 delegate:self cancelButtonTitle:@"Close"
//                                 otherButtonTitles: nil] ;
//        [addError show];
    }
}

@end
