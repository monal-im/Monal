//
//  MLJoinGroupViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 4/1/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//
#import "MLJoinGroupViewController.h"

#import "MBProgressHUD.h"
#import "MLAccountPickerViewController.h"
#import "MLButtonCell.h"
#import "MLSwitchCell.h"
#import "MLTextInputCell.h"
#import "MLXMPPManager.h"
#import "SAMKeychain.h"
#import "UIColor+Theme.h"
#import "xmpp.h"
#import "MLMucProcessor.h"

@interface MLJoinGroupViewController ()
@property (nonatomic, weak)  UITextField* accountName;
@property (nonatomic, weak) UITextField* roomField;
@property (nonatomic, strong) UIBarButtonItem* closeButton;

@property (nonatomic, strong) MBProgressHUD* joinHUD;

-(IBAction) addPress:(id)sender;

@end

@implementation MLJoinGroupViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.tableView registerNib:[UINib nibWithNibName:@"MLTextInputCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"TextCell"];

    [self.tableView registerNib:[UINib nibWithNibName:@"MLButtonCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"ButtonCell"];

    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) displayJoinHUD
{
    // setup HUD
    if(!self.joinHUD)
    {
        self.joinHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.joinHUD.removeFromSuperViewOnHide = NO;
        self.joinHUD.label.text = NSLocalizedString(@"Joining Group", @"Join GroupViewController - HUD");
        self.joinHUD.detailsLabel.text = NSLocalizedString(@"Trying to join group", @"Join GroupViewController - Join Group HUD");
    }
    self.joinHUD.hidden = NO;
}

-(void) hideJoinHUD
{
    if(self.joinHUD)
    {
        self.joinHUD.hidden = YES;
    }
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
       handler:^(UIAlertAction * action) {
        [self displayJoinHUD];
        // TODO: thilo check password
        [passwordForm dismissViewControllerAnimated:YES completion:nil];
        [self hideJoinHUD];
    }];
    [passwordForm addAction:defaultAction];
    [self presentViewController:passwordForm animated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section)
    {
        case 0:
        {
            return 1;
        }
        case 1:
        {
            return 1;
        }
        case 2:
        {
            return 1;
        }
    }
    return 0;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section)
    {
        case 0:
        {
            return NSLocalizedString(@"Account To Use", @"");
        }
        case 1:
        {
            return NSLocalizedString(@"Group Information", @"");
        }
        default:
        {
            return @"";
        }
    }
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.section == 0)
    {
        UITableViewCell* accountCell = [tableView dequeueReusableCellWithIdentifier:@"AccountPickerCell"];
        accountCell.textLabel.text = [[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:_selectedRow];
        accountCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return accountCell;
    }
    else if(indexPath.section == 1)
    {
        MLTextInputCell* thecell = (MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
        thecell.textInput.placeholder = NSLocalizedString(@"Room", @"");

        thecell.textInput.keyboardType = UIKeyboardTypeEmailAddress;
        thecell.textInput.delegate = self;
        self.roomField = thecell.textInput;
        self.roomField.text = [_groupData objectForKey:@"room"];
        return thecell;
    }
    else
    {
        //save button
        UITableViewCell* buttonCell = [tableView dequeueReusableCellWithIdentifier:@"addButton"];
        return buttonCell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0:
        {
            if(indexPath.row == 0){
                [self performSegueWithIdentifier:@"showAccountPicker" sender:self];
            }
        }
    }
}


#pragma  mark - toggle

#pragma mark actions

-(IBAction) addPress:(id)sender
{
    if([[MLXMPPManager sharedInstance].connectedXMPP count] == 0)
    {
        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No connected accounts", @"") message:NSLocalizedString(@"Please make sure at least one account has connected before trying to add a contact.", @"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {}];
        [messageAlert addAction:closeAction];

        [self presentViewController:messageAlert animated:YES completion:nil];
    }
    else
    {
        xmpp* account = [MLXMPPManager sharedInstance].connectedXMPP[_selectedRow];

        NSString* room = [self.roomField.text copy];

        NSString* combinedRoom = room;
        if([combinedRoom componentsSeparatedByString:@"@"].count == 1) {
            combinedRoom = [NSString stringWithFormat:@"%@@%@", room, account.connectionProperties.conferenceServer];
        }
        // TODO: thilo
        /*
            - combinedRoom -> room name incl conference server
            - [self showGroupPasswordForm];
        */
        combinedRoom = [combinedRoom lowercaseString];
        [self displayJoinHUD];
        [MLMucProcessor addUIHandler:^(id _data) {
            NSDictionary* data = (NSDictionary*)_data;
            if([data[@"success"] boolValue])
                [self hideJoinHUD];
            else
            {
                [self hideJoinHUD];
                
                UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error entering groupchat", @"") message:data[@"errorMessage"] preferredStyle:UIAlertControllerStyleAlert];
                [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {}]];
                [self presentViewController:messageAlert animated:YES completion:nil];
            }
        } forMuc:combinedRoom];
        [account joinMuc:combinedRoom];
    }
}


#pragma mark - textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}


- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    return YES;
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
}

@end
