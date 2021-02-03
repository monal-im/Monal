//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "XMPPEdit.h"
#import "MBProgressHUD.h"
#import "MLBlockedUsersTableViewController.h"
#import "MLButtonCell.h"
#import "MLImageManager.h"
#import "MLKeysTableViewController.h"
#import "MLMAMPrefTableViewController.h"
#import "MLPasswordChangeTableViewController.h"
#import "MLServerDetails.h"
#import "MLSwitchCell.h"

@import MobileCoreServices;
@import AVFoundation;

@interface XMPPEdit()

@property (nonatomic, strong) NSString *rosterName;
@property (nonatomic, strong) NSString *statusMessage;
@property (nonatomic, strong) NSString *resource;
@property (nonatomic, strong) NSString *server;
@property (nonatomic, strong) NSString *port;

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL directTLS;

@property (nonatomic, weak) UITextField *currentTextField;

@property (nonatomic, strong) UIDocumentPickerViewController *imagePicker;

@property (nonatomic, strong) UIImageView *userAvatarImageView;
@property (nonatomic, strong) UIImage *selectedAvatarImage;
@property (nonatomic) BOOL avatarChanged;
@property (nonatomic) BOOL rosterNameChanged;
@property (nonatomic) BOOL statusMessageChanged;
@property (nonatomic) BOOL usedCamera;
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
        self.editMode = YES;
    }
    
    DDLogVerbose(@"got account number %@", _accountno);
    
    UITapGestureRecognizer* gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; // hides the kkyeboard when you tap outside the editing area
    gestureRecognizer.cancelsTouchesInView = false; //this prevents it from blocking the button
    [self.tableView addGestureRecognizer:gestureRecognizer];
    
    self.avatarChanged = NO;
    self.rosterNameChanged = NO;
    self.statusMessageChanged = NO;
    
    if(self.originIndex && self.originIndex.section == 0)
    {
        //edit
        DDLogVerbose(@"reading account number %@", _accountno);
        NSDictionary* settings = [_db detailsForAccount:_accountno];
        if(!settings)
        {
            //present another UI here.
            return;
        }

        self.jid = [NSString stringWithFormat:@"%@@%@", [settings objectForKey:@"username"], [settings objectForKey:@"domain"]];

        NSString* pass = [SAMKeychain passwordForService:kMonalKeychainName account:[NSString stringWithFormat:@"%@", self.accountno]];

        if(pass) {
            self.password = pass;
        }

        self.server = [settings objectForKey:@"server"];

        self.port = [NSString stringWithFormat:@"%@", [settings objectForKey:@"other_port"]];
        self.resource = [settings objectForKey:kResource];

        self.enabled = [[settings objectForKey:kEnabled] boolValue];

        self.directTLS = [[settings objectForKey:@"directTLS"] boolValue];
        
        self.rosterName = [settings objectForKey:kRosterName];
        self.statusMessage = [settings objectForKey:@"statusMessage"];
        self.sectionArray = @[
            @"",
            [NSString stringWithFormat:NSLocalizedString(@"Account (%@)", @""), self.jid],
            NSLocalizedString(@"General", @""),
            NSLocalizedString(@"Advanced Settings", @""),
            @""
        ];
    }
    else
    {
        self.title = NSLocalizedString(@"New Account", @"");
        self.port = @"5222";
        self.resource = [HelperTools encodeRandomResource];
        self.directTLS = NO;
        self.rosterName = @"";
        self.statusMessage = @"";
        self.enabled = YES;
        self.sectionArray = @[
            @"",
            NSLocalizedString(@"Account (new)", @""),
            NSLocalizedString(@"General", @""),
            NSLocalizedString(@"Advanced Settings", @""),
            @""
        ];
    }
    
#if TARGET_OS_MACCATALYST
    //UTI @"public.data" for everything
    NSString *images = (NSString *)kUTTypeImage;
    self.imagePicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[images] inMode:UIDocumentPickerModeImport];
    self.imagePicker.allowsMultipleSelection = NO;
    self.imagePicker.delegate = self;
#endif
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

-(void) alertWithTitle:(NSString*) title andMsg:(NSString*) msg
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark actions

-(IBAction) save:(id) sender
{
    [self.currentTextField resignFirstResponder];

    DDLogVerbose(@"Saving");

    if([self.jid length] == 0)
    {
        [self alertWithTitle:NSLocalizedString(@"XMPP ID missing", @"") andMsg:NSLocalizedString(@"You have not entered your XMPP ID yet", @"")];
        return;
    }

    NSString* domain;
    NSString* user;

    if([self.jid characterAtIndex:0] == '@')
    {
        //first char =@ means no username in jid
        [self alertWithTitle:NSLocalizedString(@"Username missing", @"") andMsg:NSLocalizedString(@"Your entered XMPP ID is missing the username", @"")];
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
    if([domain isEqualToString:@""] && !self.server)
    {
        [self alertWithTitle:NSLocalizedString(@"Domain missing", @"") andMsg:NSLocalizedString(@"Your entered XMPP ID is missing the domain", @"")];
        return;
    }

    NSMutableDictionary* dic = [[NSMutableDictionary alloc] init];
    [dic setObject:domain.lowercaseString forKey:kDomain];

    if(user) [dic setObject:user.lowercaseString forKey:kUsername];

    if(self.server) {
        [dic setObject:self.server  forKey:kServer];
    }
    if(self.port ) {
        [dic setObject:self.port forKey:kPort];
    }
    
    [dic setObject:self.resource forKey:kResource];

    [dic setObject:[NSNumber numberWithBool:self.enabled] forKey:kEnabled];
    [dic setObject:[NSNumber numberWithBool:self.directTLS] forKey:kDirectTLS];
    [dic setObject:self.accountno forKey:kAccountID];
    if(self.rosterName)
        [dic setObject:self.rosterName forKey:kRosterName];
    if(self.statusMessage)
    [dic setObject:self.statusMessage forKey:@"statusMessage"];

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
                    self.accountno = [NSString stringWithFormat:@"%@", accountID];
                    self.editMode = YES;
                    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
                    [SAMKeychain setPassword:self.password forService:kMonalKeychainName account:self.accountno];
                    if(self.enabled)
                    {
                        [[MLXMPPManager sharedInstance] connectAccount:self.accountno];
                        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
                        [account publishStatusMessage:self.statusMessage];
                        [account publishRosterName:self.rosterName];
                        [account publishAvatar:self.selectedAvatarImage];
                    }
                    else
                        [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];
                    [self showSuccessHUD];
                }
            } else {
                [self alertWithTitle:NSLocalizedString(@"Account Exists", @"") andMsg:NSLocalizedString(@"This account already exists in Monal.", @"")];
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
                xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
                if(self.statusMessageChanged)
                    [account publishStatusMessage:self.statusMessage];
                if(self.rosterNameChanged)
                    [account publishRosterName:self.rosterName];
                if(self.avatarChanged)
                    [account publishAvatar:self.selectedAvatarImage];
            }
            else
                [[MLXMPPManager sharedInstance] disconnectAccount:self.accountno];
            [self showSuccessHUD];
        }
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });
    });
}

- (IBAction) deleteAccountClicked: (id) sender
{
    DDLogVerbose(@"Deleting");

    UIAlertController *questionAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete Account", @"") message:NSLocalizedString(@"This will remove this account and the associated data from this device.", @"") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        //do nothing when "no" was pressed
    }];
    UIAlertAction *yesAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {

        [SAMKeychain deletePasswordForService:kMonalKeychainName account:[NSString stringWithFormat:@"%@",self.accountno]];
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
    questionAlert.popoverPresentationController.sourceView = sender;

    [self presentViewController:questionAlert animated:YES completion:nil];

}

- (IBAction) clearHistoryClicked: (id) sender
{
    DDLogVerbose(@"Deleting History");

    UIAlertController *questionAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Clear Chat History", @"") message:NSLocalizedString(@"This will clear the whole chat history of this account from this device.", @"") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        //do nothing when "no" was pressed
    }];
    UIAlertAction *yesAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {

        [self.db clearMessages:self.accountno];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalRefresh object:nil userInfo:nil];

        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.mode = MBProgressHUDModeCustomView;
        hud.removeFromSuperViewOnHide=YES;
        hud.label.text =NSLocalizedString(@"Success", @"");
        hud.detailsLabel.text =NSLocalizedString(@"The chat history has been cleared", @"");
        UIImage *image = [[UIImage imageNamed:@"success"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        hud.customView = [[UIImageView alloc] initWithImage:image];
        [hud hideAnimated:YES afterDelay:1.0f];
    }];

    [questionAlert addAction:noAction];
    [questionAlert addAction:yesAction];
    questionAlert.popoverPresentationController.sourceView = sender;

    [self presentViewController:questionAlert animated:YES completion:nil];

}

#pragma mark table view datasource methods

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == 0)
    {
        return 100;
    }
    else
    {
        return UITableViewAutomaticDimension;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 40;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    DDLogVerbose(@"xmpp edit view section %ld, row %ld", indexPath.section, indexPath.row);

    MLSwitchCell* thecell = (MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];

    // load cells from interface builder
    if(indexPath.section == 1)
    {
        //the user
        switch (indexPath.row)
        {
            case 0: {
                thecell.cellLabel.text = NSLocalizedString(@"Enabled", @"");
                thecell.textInputField.hidden = YES;
                thecell.toggleSwitch.tag = 1;
                thecell.toggleSwitch.on = self.enabled;
                break;
            }
            case 1: {
                thecell.cellLabel.text = NSLocalizedString(@"Display Name", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.tag = 1;
                thecell.textInputField.keyboardType = UIKeyboardTypeAlphabet;
                thecell.textInputField.text = self.rosterName;
                break;
            }
            case 2: {
                thecell.cellLabel.text = NSLocalizedString(@"Status Message", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.tag = 6;
                thecell.textInputField.keyboardType = UIKeyboardTypeAlphabet;
                thecell.textInputField.text = self.statusMessage;
                break;
            }
        }
    }
    else if(indexPath.section == 2)
    {
        switch (indexPath.row)
        {
            // general
            case 0: {
                thecell.cellLabel.text = NSLocalizedString(@"Change Password", @"");
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
            case 2: {
                thecell.cellLabel.text = NSLocalizedString(@"Message Archive Pref", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.hidden = YES;
                thecell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
            case 3: {
                thecell.cellLabel.text = NSLocalizedString(@"Blocked Users", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.hidden = YES;
                thecell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            }
        }
    }
    else if(indexPath.section == 3)
    {
        switch (indexPath.row)
        {
            //advanced
            case 0: {
                thecell.cellLabel.text = NSLocalizedString(@"XMPP ID", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.tag = 2;
                thecell.textInputField.keyboardType = UIKeyboardTypeEmailAddress;
                thecell.textInputField.text = self.jid;
                break;
            }
            case 1: {
                thecell.cellLabel.text = NSLocalizedString(@"Password", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.secureTextEntry = YES;
                thecell.textInputField.tag = 3;
                thecell.textInputField.text = self.password;
                break;
            }
            case 2:  {
                thecell.cellLabel.text = NSLocalizedString(@"Server", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.tag = 4;
                thecell.textInputField.text = self.server;
                thecell.textInputField.placeholder = NSLocalizedString(@"Hardcoded Hostname", @"");
                thecell.accessoryType = UITableViewCellAccessoryDetailButton;
                break;
            }
            case 3:  {
                thecell.cellLabel.text = NSLocalizedString(@"Port", @"");
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.tag = 5;
                thecell.textInputField.text = self.port;
                break;
            }
            case 4: {
                thecell.cellLabel.text = NSLocalizedString(@"Direct TLS", @"");
                thecell.textInputField.hidden = YES;
                thecell.toggleSwitch.tag = 2;
                thecell.toggleSwitch.on = self.directTLS;
                break;
            }
            case 5: {
                thecell.cellLabel.text = NSLocalizedString(@"Resource", @"");
                thecell.labelRight.text = self.resource;
                thecell.labelRight.hidden = NO;
                thecell.toggleSwitch.hidden = YES;
                thecell.textInputField.hidden = YES;
                break;
            }
        }
    }
    else if (indexPath.section == 4 && self.editMode == YES)
    {
        switch (indexPath.row) {
            case 0:
            {
                MLButtonCell* buttonCell = (MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
                buttonCell.buttonText.text = NSLocalizedString(@"Clear Chat History", @"");
                buttonCell.buttonText.textColor = [UIColor redColor];
                buttonCell.selectionStyle = UITableViewCellSelectionStyleNone;
                buttonCell.tag = 0;
                return buttonCell;
            }
            case 1:
            {
                MLButtonCell* buttonCell = (MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
                buttonCell.buttonText.text = NSLocalizedString(@"Delete Account", @"");
                buttonCell.buttonText.textColor = [UIColor redColor];
                buttonCell.selectionStyle = UITableViewCellSelectionStyleNone;
                buttonCell.tag = 1;
                return buttonCell;
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
    if (section == 0)
    {
        UIView *avatarView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, 100)];
        avatarView.backgroundColor = [UIColor clearColor];
        avatarView.userInteractionEnabled = YES;
        
        self.userAvatarImageView = [[UIImageView alloc] initWithFrame:CGRectMake((self.tableView.frame.size.width - 90)/2 , 25, 90, 90)];
        self.userAvatarImageView.layer.cornerRadius =  self.userAvatarImageView.frame.size.height / 2;
        self.userAvatarImageView.layer.borderWidth = 2.0f;
        self.userAvatarImageView.layer.borderColor = ([UIColor clearColor]).CGColor;
        self.userAvatarImageView.clipsToBounds = YES;
        self.userAvatarImageView.userInteractionEnabled = YES;
        
        UITapGestureRecognizer *touchUserAvatarRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(getPhotoAction:)];
        [self.userAvatarImageView addGestureRecognizer:touchUserAvatarRecognizer];
        
        [[MLImageManager sharedInstance] getIconForContact:self.jid andAccount:self.accountno withCompletion:^(UIImage *image) {
            [self.userAvatarImageView setImage:image];
        }];
        
        [avatarView addSubview:self.userAvatarImageView];
        
        return avatarView;
    }
    else
    {
        NSString* sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
        return [HelperTools MLCustomViewHeaderWithTitle:sectionTitle];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.sectionArray objectAtIndex:section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    //avatar image
    if(section == 0)
        return 0;
    // account
    else if(section == 1)
        return 3;
    // General settings
    else if(section == 2)
        return 4;
    // Advanced settings
    else if(section == 3)
        return 6;
    else
        return self.editMode ? 2 : 0;
}

#pragma mark -  table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath
{
    DDLogVerbose(@"selected log section %ld , row %ld", newIndexPath.section, newIndexPath.row);
    
    if(newIndexPath.section == 2)
    {
        switch(newIndexPath.row)
        {
            case 0:
                [self performSegueWithIdentifier:@"showPassChange" sender:self];
                break;
            case 1:
                [self performSegueWithIdentifier:@"showKeyTrust" sender:self];
                break;
            case 2:
                [self performSegueWithIdentifier:@"showMAMPref" sender:self];
                break;
            case 3:
                [self performSegueWithIdentifier:@"showBlockedUsers" sender:self];
                break;
        }
    }
    else if(newIndexPath.section == 4)
    {
        switch(newIndexPath.row)
        {
            case 0:
                [self clearHistoryClicked:[tableView cellForRowAtIndexPath:newIndexPath]];
                break;
            case 1:
                [self deleteAccountClicked:[tableView cellForRowAtIndexPath:newIndexPath]];
                break;
        }
    }

}

-(void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    if(indexPath.section == 3)
    {
        switch(indexPath.row)
        {
            case 2:
                [self performSegueWithIdentifier:@"showServerDetails" sender:self];
                break;
        }
    }
}


#pragma mark - segeue

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showServerDetails"])
    {
        MLServerDetails* server= (MLServerDetails*)segue.destinationViewController;
        server.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
    }
    else if([segue.identifier isEqualToString:@"showMAMPref"])
    {
        MLMAMPrefTableViewController* mam = (MLMAMPrefTableViewController*)segue.destinationViewController;
        mam.xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
    }
    else if([segue.identifier isEqualToString:@"showBlockedUsers"])
    {
        xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];
        // force blocklist update
        [xmppAccount fetchBlocklist];
        MLBlockedUsersTableViewController* blockedUsers = (MLBlockedUsersTableViewController*)segue.destinationViewController;
        blockedUsers.xmppAccount = xmppAccount;
    }
    else if([segue.identifier isEqualToString:@"showKeyTrust"])
    {
        if(self.jid && self.accountno)
        {
            MLKeysTableViewController* keys = (MLKeysTableViewController*)segue.destinationViewController;
            keys.ownKeys = YES;
            MLContact *contact = [[MLContact alloc] init];
            contact.contactJid = self.jid;
            contact.accountId = self.accountno;
            keys.contact=contact;
        }
    }
    else if([segue.identifier isEqualToString:@"showPassChange"])
    {
        if(self.jid && self.accountno)
        {
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
            self.rosterName = textField.text;
            self.rosterNameChanged = YES;
            break;
        }
        case 2: {
            self.jid = textField.text;
            break;
        }
        case 3: {
            self.password = textField.text;
            break;
        }
        case 4: {
            self.server = textField.text;
            break;
        }
        case 5: {
            self.port = textField.text;
            break;
        }
        case 6: {
            self.statusMessage = textField.text;
            self.statusMessageChanged = YES;
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
    }
}

#pragma mark - doc picker
-(void)pickImgFile:(id)sender
{
    [self presentViewController:self.imagePicker animated:YES completion:nil];

    return;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    [coordinator coordinateReadingItemAtURL:urls.firstObject options:NSFileCoordinatorReadingForUploading error:nil byAccessor:^(NSURL * _Nonnull newURL) {
        NSData *data =[NSData dataWithContentsOfURL:newURL];
        UIImage *pickImg = [UIImage imageWithData:data];
        [self useAvatarImage:pickImg];
    }];
}

-(void)getPhotoAction:(UIGestureRecognizer *) recognizer
{
    xmpp* account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.accountno];

    if (!account) return;
    
    UIAlertController *actionControll = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select Action", @"")
                                                                            message:nil preferredStyle:UIAlertControllerStyleActionSheet];

#if TARGET_OS_MACCATALYST
    [self pickImgFile:nil];
#else
    UIImagePickerController *imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.delegate = self;

    UIAlertAction* cameraAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Camera", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        [self presentViewController:imagePicker animated:YES completion:nil];
    }];

    UIAlertAction* photosAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Photos", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if(granted)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self presentViewController:imagePicker animated:YES completion:nil];
                });
            }
        }];
    }];

    // Set image
    if (@available(iOS 13.0, *)) {
        [cameraAction setValue:[[UIImage systemImageNamed:@"camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [photosAction setValue:[[UIImage systemImageNamed:@"photo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    } else {
        [cameraAction setValue:[[UIImage imageNamed:@"714-camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    }
    [actionControll addAction:cameraAction];
    [actionControll addAction:photosAction];
#endif
    
    // Set image
    [actionControll addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [actionControll dismissViewControllerAnimated:YES completion:nil];
    }]];

    actionControll.popoverPresentationController.sourceView = self.userAvatarImageView;
    [self presentViewController:actionControll animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info
{
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if([mediaType isEqualToString:(NSString*) kUTTypeImage]) {
        UIImage *selectedImage = info[UIImagePickerControllerEditedImage];
        if(!selectedImage) selectedImage = info[UIImagePickerControllerOriginalImage];
        
        TOCropViewController *cropViewController = [[TOCropViewController alloc] initWithImage:selectedImage];
        cropViewController.delegate = self;
        //set square aspect ratio and don't let the user change that (this is a avatar which should be square for maximum compatibility with other clients)
        cropViewController.aspectRatioPreset = TOCropViewControllerAspectRatioPresetSquare;
        cropViewController.aspectRatioLockEnabled = YES;
        cropViewController.aspectRatioPickerButtonHidden = YES;
        
        if (picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
            [picker dismissViewControllerAnimated:YES completion:^{
                self.usedCamera = YES;
                [self presentViewController:cropViewController animated:YES completion:nil];
            }];
        } else {
            self.usedCamera = NO;
            [picker pushViewController:cropViewController animated:YES];
        }
    }
    else
        [picker dismissViewControllerAnimated:YES completion:nil];
}

-(void) imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];
}

-(void) useAvatarImage:(UIImage*) selectedImg
{
    /*
    //small sample image
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(200, 200)];
    selectedImg = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [[UIColor darkGrayColor] setStroke];
        [context strokeRect:renderer.format.bounds];
        [[UIColor colorWithRed:158/255.0 green:215/255.0 blue:245/255.0 alpha:1] setFill];
        [context fillRect:CGRectMake(1, 1, 140, 140)];
    }];
    */
    
    //check if conversion can be done and display error if not
    if(selectedImg && UIImageJPEGRepresentation(selectedImg, 1.0))
    {
        self.selectedAvatarImage = selectedImg;
        [self.userAvatarImageView setImage:self.selectedAvatarImage];
        self.avatarChanged = YES;
    }
    else
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"")
                                                                       message:NSLocalizedString(@"Can't convert the image to jpeg format.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}


#pragma mark -- TOCropViewController delagate

- (void)cropViewController:(nonnull TOCropViewController *)cropViewController
    didCropToImage:(nonnull UIImage *)image withRect:(CGRect)cropRect
                     angle:(NSInteger)angle
{
    [self useAvatarImage:image];
    if(self.usedCamera)
        [self dismissViewControllerAnimated:YES completion:nil];
    else
        [cropViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
