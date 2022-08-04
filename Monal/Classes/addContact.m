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
#import "MBProgressHUD.h"
#import "MLMucProcessor.h"

@class MLQRCodeScanner;

@interface addContact ()
@property (nonatomic, strong) MLTextInputCell* contactField;
@property (nonatomic, strong) MBProgressHUD* joinHUD;
@property (nonatomic, strong) MBProgressHUD* checkHUD;
@end

@implementation addContact


-(void) closeView
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void) displayJoinHUD
{
    // setup HUD
    if(!self.joinHUD)
    {
        self.joinHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.joinHUD.removeFromSuperViewOnHide = NO;
        self.joinHUD.label.text = NSLocalizedString(@"Joining Group", @"addContact - Join Group HUD");
        self.joinHUD.detailsLabel.text = NSLocalizedString(@"Trying to join group", @"addContact - Join Group HUD");
    }
    self.joinHUD.hidden = NO;
}

-(void) hideJoinHUD
{
    if(self.joinHUD)
        self.joinHUD.hidden = YES;
}

-(void) displayCheckHUD
{
    // setup HUD
    if(!self.checkHUD)
    {
        self.checkHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.checkHUD.removeFromSuperViewOnHide = NO;
        self.checkHUD.label.text = NSLocalizedString(@"Checking", @"addContact - checking HUD");
        self.checkHUD.detailsLabel.text = NSLocalizedString(@"Checking if the jid you provided is correct", @"addContact - checking HUD");
    }
    self.checkHUD.hidden = NO;
}

-(void) hideCheckHUD
{
    if(self.checkHUD)
        self.checkHUD.hidden = YES;
}

-(IBAction) addPress:(id)sender
{
    if([[MLXMPPManager sharedInstance].connectedXMPP count] == 0)
    {
        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No connected accounts", @"") message:NSLocalizedString(@"Please make sure at least one account has connected before trying to add a contact or channel.", @"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
        }];
        [messageAlert addAction:closeAction];
        
        [self presentViewController:messageAlert animated:YES completion:nil];
        return;
    }
    
    NSDictionary<NSString*, NSString*>* jidComponents = [HelperTools splitJid:[self.contactField getText]];
    DDLogVerbose(@"Jid validity: node(%lu)='%@', host(%lu)='%@'", (unsigned long)[jidComponents[@"node"] length], jidComponents[@"node"], (unsigned long)[jidComponents[@"host"] length], jidComponents[@"host"]);
    //check jid to have at least a node and host value to make a correct user and alert otherwise
    if(!jidComponents[@"node"] || jidComponents[@"node"].length == 0 || jidComponents[@"host"].length == 0)
    {
        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Jid Invalid", @"") message:NSLocalizedString(@"The jid has to be in the form 'user@domain.tld' to be correct.", @"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
        }];
        [messageAlert addAction:closeAction];
        [self presentViewController:messageAlert animated:YES completion:nil];
        return;
    }
    //use the canonized jid from now on (lowercased, resource removed etc.)
    NSString* jid = jidComponents[@"user"];
    
    [self addJid:jid];
}

-(void) addJid:(NSString*) jid
{
    [self displayCheckHUD];
    xmpp* account = [[MLXMPPManager sharedInstance].connectedXMPP objectAtIndex:_selectedRow];
    [account checkJidType:jid withCompletion:^(NSString* type, NSString* _Nullable errorMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hideCheckHUD];
            if([type isEqualToString:@"account"])
            {
                MLContact* contactObj = [MLContact createContactFromJid:jid andAccountNo:account.accountNo];
                [[MLXMPPManager sharedInstance] addContact:contactObj];

                UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Permission Requested", @"") message:NSLocalizedString(@"The new contact will be added to your contacts list when the person you've added has approved your request.", @"") preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                    if(self.completion)
                        self.completion(contactObj);
                    [self dismissViewControllerAnimated:YES completion:nil];
                }];
                [messageAlert addAction:closeAction];
                [self presentViewController:messageAlert animated:YES completion:nil];
            }
            else if([type isEqualToString:@"muc"])
            {
                [self displayJoinHUD];
                NSNumber* accountNo = account.accountNo;            //needed to not retain 'account' in the block below
                [account.mucProcessor addUIHandler:^(id _data) {
                    NSDictionary* data = (NSDictionary*)_data;
                    [self hideJoinHUD];
                    if([data[@"success"] boolValue])
                    {
                        if(self.completion)
                            self.completion([MLContact createContactFromJid:jid andAccountNo:accountNo]);
                        [self dismissViewControllerAnimated:YES completion:nil];
                    }
                    else
                    {
                        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error entering groupchat", @"") message:data[@"errorMessage"] preferredStyle:UIAlertControllerStyleAlert];
                        [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                        }]];
                        [self presentViewController:messageAlert animated:YES completion:nil];
                    }
                } forMuc:jid];
                [account joinMuc:jid];
            }
            else
            {
                UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"") message:errorMessage preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                }];
                [messageAlert addAction:closeAction];
                [self presentViewController:messageAlert animated:YES completion:nil];
            }
        });
    }];
}

-(void) showGroupPasswordForm
{
    UIAlertController* passwordForm = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Group requires a password", @"") message:nil preferredStyle:UIAlertControllerStyleAlert];
    // add password field to alert
    [passwordForm addTextFieldWithConfigurationHandler:^(UITextField* passwordField) {
        passwordField.secureTextEntry = YES;
        passwordField.placeholder = NSLocalizedString(@"Group Password", @"MLJoinGroupViewController - Group Password Form");
    }];

    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"") style:UIAlertActionStyleDefault
       handler:^(UIAlertAction* action __unused) {
        [self displayJoinHUD];
        // TODO: thilo check password
        [passwordForm dismissViewControllerAnimated:YES completion:nil];
        [self hideJoinHUD];
    }];
    [passwordForm addAction:defaultAction];
    [self presentViewController:passwordForm animated:YES completion:nil];
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
    self.navigationItem.title = NSLocalizedString(@"Add Contact or Channel", @"");
        
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
        return NSLocalizedString(@"Contact and Channel Jids  are usually in the format: name@domain.tld", @"");
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
        if(indexPath.row == 0)
        {
            UITableViewCell* accountCell = [tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
            accountCell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Using Account: %@", @""), [[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:_selectedRow]];
            accountCell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;

            return accountCell;
        }
        MLTextInputCell* textCell = [tableView dequeueReusableCellWithIdentifier:@"TextCell"];
        [textCell initMailCell:self.contactName andPlaceholder:NSLocalizedString(@"Contact or Channel Jid", @"") andDelegate:self];
        self.contactField = textCell;
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
        MLQRCodeScannerController* qrCodeScanner = (MLQRCodeScannerController *) segue.destinationViewController;
        qrCodeScanner.contactDelegate = self;
    }
}

-(void) MLQRCodeContactScannedWithJid:(NSString *)jid fingerprints:(NSDictionary<NSNumber *,NSString *> *)fingerprints
{
    self.contactName = [jid copy];
    // Close QR-Code scanner
    [self.navigationController popViewControllerAnimated:YES];
}

@end
