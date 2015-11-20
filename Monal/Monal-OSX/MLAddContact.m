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
       NSDictionary* contact =@{@"row":[NSNumber numberWithInteger:self.accounts.indexOfSelectedItem],@"buddy_name":self.contactName.stringValue};
        [[MLXMPPManager sharedInstance] addContact:contact];
  
     
        
        NSAlert *userAddAlert = [[NSAlert alloc] init];
          userAddAlert.messageText=@"Permission Requested";
        userAddAlert.informativeText =[NSString stringWithFormat:@"The new contact will be added to your contacts list when the person you've added has approved your request."];
        userAddAlert.alertStyle=NSInformationalAlertStyle;
        [userAddAlert addButtonWithTitle:@"Close"];
        
        [userAddAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
                  [self dismissController:self];
        }];

    }
    else
    {
        NSAlert *userAddAlert = [[NSAlert alloc] init];
        userAddAlert.messageText = @"Error";
        userAddAlert.informativeText =[NSString stringWithFormat:@"Name can't be empty"];
        userAddAlert.alertStyle=NSInformationalAlertStyle;
        [userAddAlert addButtonWithTitle:@"Close"];
        
        [userAddAlert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
                  [self dismissController:self];
        }];
    }
}

@end
