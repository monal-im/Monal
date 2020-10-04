//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "XMPPEdit.h"
#import "MLSwitchCell.h"
#import "MLButtonCell.h"
#import "MBProgressHUD.h"
#import "MLServerDetails.h"
#import "MLMAMPrefTableViewController.h"
#import "MLKeysTableViewController.h"
#import "MLPasswordChangeTableViewController.h"

@interface XMPPEdit()

@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, strong) NSString *resource;
@property (nonatomic, strong) NSString *server;
@property (nonatomic, strong) NSString *port;

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL directTLS;
@property (nonatomic, assign) BOOL selfSignedSSL;

@property (nonatomic, weak) UITextField *currentTextField;

@property (nonatomic, strong) NSDictionary *initialSettings;

@end


@implementation XMPPEdit


-(void) hideKeyboard
{
    [self.currentTextField resignFirstResponder];
}

#pragma mark view lifecylce

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"AccountCell"];
    
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLButtonCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ButtonCell"];
    
    _db = [DataLayer sharedInstance];
    
    if(![_accountno isEqualToString:@"-1"])
    {
        self.editMode = true;
    }
    
    DDLogVerbose(@"got account number %@", _accountno);
    
    UITapGestureRecognizer* gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; // hides the kkyeboard when you tap outside the editing area
    gestureRecognizer.cancelsTouchesInView = false; //this prevents it from blocking the button
    [self.tableView addGestureRecognizer:gestureRecognizer];
    
    
    if(_originIndex.section == 0)
    {
        //edit
        DDLogVerbose(@"reading account number %@", _accountno);
        NSDictionary* settings = [_db detailsForAccount:_accountno];
        if(!settings)
        {
            //present another UI here.
            return;
        }

        self.initialSettings = settings;

        self.jid = [NSString stringWithFormat:@"%@@%@", [settings objectForKey:@"username"], [settings objectForKey:@"domain"]];

        NSString* pass = [SAMKeychain passwordForService:@"Monal" account:[NSString stringWithFormat:@"%@", self.accountno]];

        if(pass) {
            self.password = pass;
        }

        self.server = [settings objectForKey:@"server"];

        self.port = [NSString stringWithFormat:@"%@", [settings objectForKey:@"other_port"]];
        self.resource = [settings objectForKey:kResource];

        self.enabled = [[settings objectForKey:kEnabled] boolValue];

        self.directTLS = [[settings objectForKey:@"directTLS"] boolValue];
        self.selfSignedSSL = [[settings objectForKey:@"selfsigned"] boolValue];
    }
    else
    {
        self.port = @"5222";
        self.resource = [HelperTools encodeRandomResource];
        self.directTLS = NO;
        self.selfSignedSSL = NO;
    }
    self.sectionArray = @[NSLocalizedString(@"Account", @""), NSLocalizedString(@"General", @""), NSLocalizedString(@"Advanced Settings", @""), @""];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    DDLogVerbose(@"xmpp edit view will appear");
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    DDLogVerbose(@"xmpp edit view will hide");
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark actions

-(IBAction) save:(id) sender
{
    [self.currentTextField resignFirstResponder];

    DDLogVerbose(@"Saving");

    if([self.jid length] == 0)
    {
        return;
    }

    NSString* domain;
    NSString* user;

    if([self.jid characterAtIndex:0] == '@')
    {
        //first char =@ means no username in jid
        return;
    }

    NSArray* elements = [self.jid componentsSeparatedByString:@"@"];

    //if it is a JID
    if([elements count] > 1)
    {
        user = [elements objectAtIndex:0];
        domain = [elements objectAtIndex:1];
    }
    else
    {
        user = self.jid;
        domain = @"";
    }

    NSMutableDictionary* dic = [[NSMutableDictionary alloc] init];
    [dic setObject:domain forKey:kDomain];

    if(user) [dic setObject:user forKey:kUsername];

    if(self.server) {
        [dic setObject:self.server  forKey:kServer];
    }
    if(self.port ) {
        [dic setObject:self.port forKey:kPort];
    }
    
    [dic setObject:self.resource forKey:kResource];

    [dic setObject:[NSNumber numberWithBool:self.enabled] forKey:kEnabled];
    [dic setObject:[NSNumber numberWithBool:self.selfSignedSSL] forKey:kSelfSigned];
    [dic setObject:[NSNumber numberWithBool:self.directTLS] forKey:kDirectTLS];
    [dic setObject:self.accountno forKey:kAccountID];

    if(!self.editMode)
    {

        if(([self.jid length] == 0) &&
           ([self.password length] == 0)
           )
        {
            //ignoring blank
        }
        else
        {
            BOOL accountExists = [[DataLayer sharedInstance] doesAccountExistUser:user andDomain:domain];
            if(!accountExists) {
                NSNumber* accountID = [[DataLayer sharedInstance] addAccountWithDictionary:dic];
                if(accountID) {
                    [self showSuccessHUD];
                    self.accountno = [NSString stringWithFormat:@"%@", accountID];
                    self.editMode = YES;
                    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
                    [SAMKeychain setPassword:self.password forService:@"Monal" account:self.accountno];
                    if(self.enabled)
                    {
                        DDLogVerbose(@"calling connect... ");
                        [[MLXMPPManager sharedInstance] connectAccount:self.accountno];
                    }
                    else
                    {
                        [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];
                    }
                }
            } else  {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController* alert= [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Account Exists",@ "") message:NSLocalizedString(@"This account already exists in Monal.", @"") preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [alert dismissViewControllerAnimated:YES completion:nil];
                    }]];
                    [self presentViewController:alert animated:YES completion:nil];
                });
            }
        }
    }
    else
    {
        BOOL updatedAccount = [[DataLayer sharedInstance] updateAccounWithDictionary:dic];
        if(updatedAccount) {
            [[MLXMPPManager sharedInstance] updatePassword:self.password forAccount:self.accountno];
            if(self.enabled)
            {
                [[MLXMPPManager sharedInstance] connectAccount:self.accountno];
            }
            else
            {
                [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];
            }
            [self showSuccessHUD];
        }

        [[DataLayer sharedInstance] resetContactsForAccount:self.accountno];
    }
}

-(void) showSuccessHUD
{
    dispatch_async(dispatch_get_main_queue(), ^{
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.mode = MBProgressHUDModeCustomView;
        hud.removeFromSuperViewOnHide = YES;
        hud.label.text = NSLocalizedString(@"Success", @"");
        hud.detailsLabel.text = NSLocalizedString(@"The account has been saved", @"");
        UIImage *image = [[UIImage imageNamed:@"success"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        hud.customView = [[UIImageView alloc] initWithImage:image];
        [hud hideAnimated:YES afterDelay:1.0f];
    });
}

- (IBAction) delClicked: (id) sender
{
    DDLogVerbose(@"Deleting");

    UIAlertController *questionAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete Account",@ "") message:NSLocalizedString(@"This will remove this account and the associated data from this device.",@ "") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        //do nothing when "no" was pressed
    }];
    UIAlertAction *yesAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {

        [SAMKeychain deletePasswordForService:@"Monal"  account:[NSString stringWithFormat:@"%@",self.accountno]];
        [self.db removeAccount:self.accountno];
        [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];


        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.mode = MBProgressHUDModeCustomView;
        hud.removeFromSuperViewOnHide=YES;
        hud.label.text =NSLocalizedString(@"Success", @"");
        hud.detailsLabel.text =NSLocalizedString(@"The account has been deleted", @"");
        UIImage *image = [[UIImage imageNamed:@"success"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        hud.customView = [[UIImageView alloc] initWithImage:image];
        [hud hideAnimated:YES afterDelay:1.0f];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });
    }];

    [questionAlert addAction:noAction];
    [questionAlert addAction:yesAction];
    questionAlert.popoverPresentationController.sourceView=sender;

    [self presentViewController:questionAlert animated:YES completion:nil];

}

#pragma mark table view datasource methods

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    return 40;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    DDLogVerbose(@"xmpp edit view section %ld, row %ld", indexPath.section, indexPath.row);

    MLSwitchCell* thecell = (MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];

    // load cells from interface builder
    if(indexPath.section == 0)
    {
        //the user
        switch (indexPath.row)
        {
            case 0: {
                thecell.cellLabel.text = NSLocalizedString(@"Jabber ID", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.tag = 1;
                thecell.textInputField.keyboardType = UIKeyboardTypeEmailAddress;
                thecell.textInputField.text = self.jid;
                break;
            }
            case 1: {
                thecell.cellLabel.text = NSLocalizedString(@"Password", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.secureTextEntry = YES;
                thecell.textInputField.tag = 2;
                thecell.textInputField.text = self.password;
                break;
            }
            case 2: {
                thecell.cellLabel.text = NSLocalizedString(@"Enabled", @"");
                thecell.textInputField.hidden = YES;
                thecell.toggleSwitch.tag = 1;
                thecell.toggleSwitch.on = self.enabled;
                break;
            }
        }
    }
    else if(indexPath.section == 1)
    {
        switch (indexPath.row)
        {
            // general
            case 0: {
                thecell.cellLabel.text = NSLocalizedString(@"Message Archive Pref", @"");
                thecell.toggleSwitch.hidden = YES;

                thecell.textInputField.hidden = YES;
                thecell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
            case 1: {
                thecell.cellLabel.text = NSLocalizedString(@"My Keys", @"");
                thecell.toggleSwitch.hidden = YES;

                thecell.textInputField.hidden = YES;
                thecell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
        }
    }
    else if(indexPath.section == 2)
    {
        switch (indexPath.row)
        {
            //advanced
            case 0:  {
                thecell.cellLabel.text = NSLocalizedString(@"Server", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.tag = 3;
                thecell.textInputField.text = self.server;
                thecell.textInputField.placeholder = NSLocalizedString(@"Hardcoded Hostname", @"");
                thecell.accessoryType = UITableViewCellAccessoryDetailButton;
                break;
            }
            case 1:  {
                thecell.cellLabel.text = NSLocalizedString(@"Port", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.tag = 4;
                thecell.textInputField.text = self.port;
                break;
            }
            case 2: {
                thecell.cellLabel.text = NSLocalizedString(@"Direct TLS", @"");
                thecell.textInputField.hidden = YES;
                thecell.toggleSwitch.tag = 2;
                thecell.toggleSwitch.on = self.directTLS;
                break;
            }
            case 3: {
                thecell.cellLabel.text = NSLocalizedString(@"Validate certificate", @"");
                thecell.textInputField.hidden = YES;
                thecell.toggleSwitch.tag = 3;
                thecell.toggleSwitch.on = !self.selfSignedSSL;
                break;
            }
            case 4: {
                thecell.cellLabel.text = NSLocalizedString(@"Change Password", @"");
                thecell.toggleSwitch.hidden = YES;

                thecell.textInputField.hidden = YES;
                thecell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
            case 5: {
                thecell.cellLabel.text = NSLocalizedString(@"Resource", @ "");
                thecell.labelRight.text = self.resource;
                thecell.labelRight.hidden = NO;
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.hidden = YES;
                break;
            }
        }
    }
    else if (indexPath.section == 3)
    {
        switch (indexPath.row) {
            case 0:
            {
                if(self.editMode == true)
                {

                    MLButtonCell* buttonCell = (MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
                    buttonCell.buttonText.text = NSLocalizedString(@"Delete",@ "");
                    buttonCell.buttonText.textColor = [UIColor redColor];
                    buttonCell.selectionStyle = UITableViewCellSelectionStyleNone;
                    return buttonCell;
                }
                break;
            }
        }
    }
    thecell.textInputField.delegate = self;
    if(thecell.textInputField.hidden == YES)
    {
        [thecell.toggleSwitch addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
    }
    thecell.selectionStyle = UITableViewCellSelectionStyleNone;
    return thecell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self.sectionArray count];
}

-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString* sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
    return [HelperTools MLCustomViewHeaderWithTitle:sectionTitle];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.sectionArray objectAtIndex:section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // account
    if(section == 0){
        return 3;
    }
    // General settings
    else if(section == 1) {
        return 2;
    }
    // Advanced settings
    else if(section == 2) {
        return 6;
    }
    else if(section == 3 &&  self.editMode == false)
    {
        return 0;
    }
    else
    {
        return 1;
    }
}

#pragma mark -  table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
    DDLogVerbose(@"selected log section %ld , row %ld", newIndexPath.section, newIndexPath.row);
    
    if(newIndexPath.section == 1)
    {
        switch(newIndexPath.row)
        {
            case 0:
                [self performSegueWithIdentifier:@"showMAMPref" sender:self];
                break;
            case 1:
                [self performSegueWithIdentifier:@"showKeyTrust" sender:self];
                break;
        }
    }
    else if(newIndexPath.section == 2)
    {
        switch(newIndexPath.row)
        {
            case 4:
                [self performSegueWithIdentifier:@"showPassChange" sender:self];
                break;
        }
    }
    else if(newIndexPath.section == 3)
    {
        [self delClicked:[tableView cellForRowAtIndexPath:newIndexPath]];
    }

}

-(void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath.section == 2)
    {
        switch(indexPath.row)
        {
            case 0:
                [self performSegueWithIdentifier:@"showServerDetails" sender:self];
                break;
        }
    }
}


#pragma mark - segeue

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"showServerDetails"])
    {
        MLServerDetails* server= (MLServerDetails*)segue.destinationViewController;
        server.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
    }

    else if ([segue.identifier isEqualToString:@"showMAMPref"])
    {
        MLMAMPrefTableViewController* mam = (MLMAMPrefTableViewController*)segue.destinationViewController;
        mam.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
    }
    else if ([segue.identifier isEqualToString:@"showKeyTrust"])
    {
        if(self.jid && self.accountno) {
            MLKeysTableViewController* keys = (MLKeysTableViewController*)segue.destinationViewController;
            keys.ownKeys = YES;
            MLContact *contact = [[MLContact alloc] init];
            contact.contactJid = self.jid;
            contact.accountId = self.accountno;
            keys.contact=contact;
        }
    }
    else if ([segue.identifier isEqualToString:@"showPassChange"])
    {
        if(self.jid && self.accountno) {
            MLPasswordChangeTableViewController* pwchange = (MLPasswordChangeTableViewController*)segue.destinationViewController;
           pwchange.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
        }
    }
}

#pragma mark -  text input  fielddelegate

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    self.currentTextField = textField;
    if(textField.tag == 1) //user input field
    {
        if(textField.text.length > 0) {
            UITextPosition* startPos = textField.beginningOfDocument;
            UITextRange* newRange = [textField textRangeFromPosition:startPos toPosition:startPos];

            // Set new range
            [textField setSelectedTextRange:newRange];
        }
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    switch (textField.tag) {
        case 1: {
            self.jid = textField.text;
            break;
        }
        case 2: {
            self.password = textField.text;
            break;
        }
        case 3: {
            self.server = textField.text;
            break;
        }
        case 4: {
            self.port = textField.text;
            break;
        }
        case 5: {
            self.resource = textField.text;
            break;
        }
        default:
            break;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{

    [textField resignFirstResponder];
    return true;
}


-(void) toggleSwitch:(id)sender
{
    UISwitch* toggle = (UISwitch*) sender;

    switch (toggle.tag) {
        case 1: {
            if(toggle.on)
            {
                self.enabled = YES;
            }
            else {
                self.enabled = NO;
            }
            break;
        }
        case 2: {
            if(toggle.on)
            {
                self.directTLS = YES;
            }
            else {
                self.directTLS = NO;
            }
            break;
        }
        case 3: {
            if(toggle.on)
            {
                self.selfSignedSSL = NO;
            }
            else {
                self.selfSignedSSL = YES;
            }
            break;
        }
    }
}


@end
