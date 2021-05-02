//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "addContact.h"
#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "MLButtonCell.h"
#import "MLTextInputCell.h"
#import "MLAccountPickerViewController.h"
#import "DataLayer.h"
#import "xmpp.h"
#import "MLOMEMO.h"

@class MLQRCodeScanner;

@implementation addContact


-(void) closeView
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction) addPress:(id)sender
{
    if([[MLXMPPManager sharedInstance].connectedXMPP count] == 0)
    {
        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No connected accounts", @"") message:NSLocalizedString(@"Please make sure at least one account has connected before trying to add a contact.", @"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        }];
        [messageAlert addAction:closeAction];
        
        [self presentViewController:messageAlert animated:YES completion:nil];
    }
    else  {
        if(self.contactName.text.length > 0)
        {
            xmpp* account = [[MLXMPPManager sharedInstance].connectedXMPP objectAtIndex:_selectedRow];

            MLContact* contactObj = [MLContact contactFromJid:self.contactName.text andAccountNo:account.accountNo];

            [[MLXMPPManager sharedInstance] addContact:contactObj];
            BOOL approve = NO;
            // approve contact ahead of time if possible
            if(account.connectionProperties.supportsRosterPreApproval) {
                approve = YES;
            } else if([[DataLayer sharedInstance] hasContactRequestForAccount:account.accountNo andBuddyName:contactObj.contactJid]) {
                approve = YES;
            }
            if(approve) {
                // delete existing contact request if exists
                [[DataLayer sharedInstance] deleteContactRequest:contactObj];
                // and approve the new contact
                [[MLXMPPManager sharedInstance] approveContact:contactObj];
            }
#ifndef DISABLE_OMEMO
            // Request omemo devicelist
            [account.omemo queryOMEMODevices:contactObj.contactJid];
#endif// DISABLE_OMEMO

            UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Permission Requested", @"") message:NSLocalizedString(@"The new contact will be added to your contacts list when the person you've added has approved your request.", @"") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                if(self.completion) self.completion(contactObj);
                [self dismissViewControllerAnimated:YES completion:nil];
            }];
            [messageAlert addAction:closeAction];

            [self presentViewController:messageAlert animated:YES completion:nil];
        }
        else
        {
            UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error",@"") message:NSLocalizedString(@"Name can't be empty", @"") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                
            }];
            [messageAlert addAction:closeAction];
            
            [self presentViewController:messageAlert animated:YES completion:nil];
        }
    }
}

#pragma mark - textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    
	return YES;
}


- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    
    _currentTextField = textField;
    return YES;
}


#pragma mark View life cycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = NSLocalizedString(@"Add Contact", @"");
        
    [self.tableView registerNib:[UINib nibWithNibName:@"MLTextInputCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"TextCell"];
    
    _selectedRow = 0; //TODO in the future maybe remember least used
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if([[MLXMPPManager sharedInstance].connectedXMPP count]==1)
        _selectedRow=0;
}

#pragma mark tableview datasource delegate

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if(section == 0)
        return NSLocalizedString(@"Contacts are usually in the format: username@dom.ain", @"");
    else
        return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger toreturn = 0;
    switch (section)
    {
        case 0:
            toreturn = 2;
            break;
        case 1:
            toreturn = 1;
            break;
            
        default:
            break;
    }
    
    return toreturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath.section == 0)
    {
        if(indexPath.row == 0){
            UITableViewCell* accountCell = [tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
            accountCell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Using Account: %@", @""), [[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:_selectedRow]];
            accountCell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;

            return accountCell;
        }
        
        MLTextInputCell* textCell = [tableView dequeueReusableCellWithIdentifier:@"TextCell"];
        self.contactName = textCell.textInput;
        self.contactName.placeholder = NSLocalizedString(@"Contact Jid", @"");
        self.contactName.delegate=self;

        return textCell;
    }
    else
        return [tableView dequeueReusableCellWithIdentifier:@"addButton"];
}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0: {
            if(indexPath.row == 0){
                [self performSegueWithIdentifier:@"showAccountPicker" sender:self];
            }
        }
    }
}

- (void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if([segue.identifier isEqualToString:@"showAccountPicker"])
    {
        MLAccountPickerViewController* accountPicker = (MLAccountPickerViewController *) segue.destinationViewController;
        accountPicker.completion = ^(NSInteger accountRow) {
            self->_selectedRow = accountRow;
            NSIndexPath* indexpath = [NSIndexPath indexPathForRow:0 inSection:0];
            [self.tableView reloadRowsAtIndexPaths:@[indexpath] withRowAnimation:UITableViewRowAnimationNone];
        };
    }
    else if([segue.identifier isEqualToString:@"qrContactScan"])
    {
        MLQRCodeScanner* qrCodeScanner = (MLQRCodeScanner *) segue.destinationViewController;
        qrCodeScanner.contactDelegate = self;
    }
}

-(void) MLQRCodeContactScannedWithJid:(NSString *)jid fingerprints:(NSDictionary<NSNumber *,NSString *> *)fingerprints
{
    self.contactName.text = jid;
    // Close QR-Code scanner
    [self.navigationController popViewControllerAnimated:YES];
}

@end
