//
//  buddylist.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/21/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "XMPPEdit.h"
#import "xmpp.h"
#import "MBProgressHUD.h"
#import "MLBlockedUsersTableViewController.h"
#import "MLButtonCell.h"
#import "MLImageManager.h"
#import "MLSwitchCell.h"
#import "MLOMEMO.h"
#import "MLNotificationQueue.h"
#import "MonalAppDelegate.h"
#import "ActiveChatsViewController.h"
#import "Monal-Swift.h"

@import MobileCoreServices;
@import AVFoundation;
@import UniformTypeIdentifiers.UTCoreTypes;
@import Intents;

enum kSettingSection {
    kSettingSectionAvatar,
    kSettingSectionAccount,
    kSettingSectionGeneral,
    kSettingSectionAdvanced,
    kSettingSectionEdit,
    kSettingSectionCount
};

enum kSettingsAvatarRows {
    SettingsAvatarRowsCnt
};

enum kSettingsAccountRows {
    SettingsEnabledRow,
    SettingsDisplayNameRow,
    SettingsStatusMessageRow,
    SettingsServerDetailsRow,
    SettingsAccountRowsCnt
};

enum kSettingsGeneralRows {
    SettingsChangePasswordRow,
    SettingsOmemoKeysRow,
    SettingsBlockedUsersRow,
    SettingsGeneralRowsCnt
};

enum kSettingsAdvancedRows {
    SettingsJidRow,
    SettingsPasswordRow,
    SettingsServerRow,
    SettingsPortRow,
    SettingsDirectTLSRow,
    SettingsPlainActivatedRow,
    SettingsResourceRow,
    SettingsAdvancedRowsCnt
};

enum kSettingsEditRows {
    SettingsClearHistoryRow,
    SettingsRemoveAccountRow,
    SettingsDeleteAccountRow,
    SettingsEditRowsCnt
};

//this will hold all disabled rows of all enums (this is needed because the code below still references these rows)
enum DummySettingsRows {
    DummySettingsRowsBegin = 100,
};


@interface MLXMPPConnection ()
@property (nonatomic) MLXMPPServer* server;
@property (nonatomic) MLXMPPIdentity* identity;
@end

@interface XMPPEdit()
@property (nonatomic, strong) DataLayer* db;
@property (nonatomic, strong) NSMutableDictionary* sectionDictionary;

@property (nonatomic, assign) BOOL editMode;
// Used for QR-Code scanning
@property (nonatomic, strong) NSString* jid;
@property (nonatomic, strong) NSString* password;

@property (nonatomic, strong) NSString* accountType;

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
@property (nonatomic) BOOL detailsChanged;

@property (nonatomic) BOOL plainActivated;

@property (nonatomic) BOOL deactivateSave;
@end

@implementation XMPPEdit

-(void) hideKeyboard
{
    [self.currentTextField resignFirstResponder];
}

#pragma mark view lifecylce

-(void) viewDidLoad
{
    self.deactivateSave = NO;
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"AccountCell"];
    
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLButtonCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ButtonCell"];
    
    _db = [DataLayer sharedInstance];
    
    if(self.accountID.intValue != -1)
        self.editMode = YES;
    
    DDLogVerbose(@"got account number %@", self.accountID);
    
    UITapGestureRecognizer* gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)]; // hides the kkyeboard when you tap outside the editing area
    gestureRecognizer.cancelsTouchesInView = false; //this prevents it from blocking the button
    [self.tableView addGestureRecognizer:gestureRecognizer];
    
    self.avatarChanged = NO;
    self.rosterNameChanged = NO;
    self.statusMessageChanged = NO;
    
    //default strings used for edit and new mode
    self.sectionDictionary = [NSMutableDictionary new];
    for(int entry = 0; entry < kSettingSectionCount; entry++)
        switch(entry)
        {
            case kSettingSectionAvatar:
                self.sectionDictionary[@(entry)] = @""; break;
            case kSettingSectionAccount:
                self.sectionDictionary[@(entry)] = @""; break;
            case kSettingSectionGeneral:
                self.sectionDictionary[@(entry)] = NSLocalizedString(@"General", @"");
                break;
            case kSettingSectionAdvanced:
                self.sectionDictionary[@(entry)] = NSLocalizedString(@"Advanced Settings", @"");
                break;
            case kSettingSectionEdit:
                self.sectionDictionary[@(entry)] = @"";
                break;
            default:
                self.sectionDictionary[@(entry)] = @"";
                break;
        }
    
    if(self.originIndex && self.originIndex.section == 0)
    {
        //edit
        DDLogVerbose(@"reading account number %@", self.accountID);
        NSDictionary* settings = [_db detailsForAccount:self.accountID];
        MLAssert(settings != nil, @"Settings dict should never be nil here!");

        self.jid = [NSString stringWithFormat:@"%@@%@", [settings objectForKey:@"username"], [settings objectForKey:@"domain"]];
        NSString* pass = [SAMKeychain passwordForService:kMonalKeychainName account:self.accountID.stringValue];

        if(pass)
            self.password = pass;

        self.server = [settings objectForKey:@"server"];

        self.port = [NSString stringWithFormat:@"%@", [settings objectForKey:@"other_port"]];
        self.resource = [settings objectForKey:kResource];

        self.enabled = [[settings objectForKey:kEnabled] boolValue];

        self.directTLS = [[settings objectForKey:@"directTLS"] boolValue];
        
        self.rosterName = [settings objectForKey:kRosterName];
        self.statusMessage = [settings objectForKey:@"statusMessage"];
        
        self.plainActivated = [[settings objectForKey:kPlainActivated] boolValue];
        
        //overwrite account section heading in edit mode
        self.sectionDictionary[@(kSettingSectionAccount)] = [NSString stringWithFormat:NSLocalizedString(@"Account (%@)", @""), self.jid];
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
        self.plainActivated = NO;
        
        //overwrite account section heading in new mode
        self.sectionDictionary[@(kSettingSectionAccount)] = NSLocalizedString(@"Account (new)", @"");
    }
#if TARGET_OS_MACCATALYST
    self.imagePicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage]];
    self.imagePicker.allowsMultipleSelection = NO;
    self.imagePicker.delegate = self;
#endif
}

-(void) viewWillAppear:(BOOL) animated
{
    [super viewWillAppear:animated];
    DDLogVerbose(@"xmpp edit view will appear");
}

-(void) viewWillDisappear:(BOOL) animated
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
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark actions

-(IBAction) save:(id) sender
{
    if(self.deactivateSave)
    {
        DDLogWarn(@"Save pressed but already deactivated!");
        return;
    }
    
    NSError* error;
    [self.currentTextField resignFirstResponder];

    DDLogVerbose(@"Saving");

    NSString* lowerJid = [self.jid.lowercaseString copy];
    NSString* domain;
    NSString* user;

    if([lowerJid length] == 0)
    {
        [self alertWithTitle:NSLocalizedString(@"XMPP ID missing", @"") andMsg:NSLocalizedString(@"You have not entered your XMPP ID yet", @"")];
        return;
    }

    if([lowerJid characterAtIndex:0] == '@')
    {
        //first char =@ means no username in jid
        [self alertWithTitle:NSLocalizedString(@"Username missing", @"") andMsg:NSLocalizedString(@"Your entered XMPP ID is missing the username", @"")];
        return;
    }
    
    //check if our keychain contains a password
    if(self.enabled && self.password.length == 0)
    {
        [SAMKeychain passwordForService:kMonalKeychainName account:self.accountID.stringValue error:&error];
        if(error != nil)
        {
            DDLogError(@"Keychain error: %@", error);
            self.enabled = NO;
            [self.tableView reloadData];
            [self alertWithTitle:NSLocalizedString(@"Password missing", @"") andMsg:NSLocalizedString(@"Please enter a password below before activating this account.", @"")];
            return;
        }
    }
    
    NSArray* elements = [lowerJid componentsSeparatedByString:@"@"];

    //if it is a JID
    if([elements count] > 1)
    {
        user = [elements objectAtIndex:0];
        domain = [elements objectAtIndex:1];
    }
    else
    {
        user = lowerJid;
        domain = @"";
    }
    if([domain isEqualToString:@""])
    {
        [self alertWithTitle:NSLocalizedString(@"Domain missing", @"") andMsg:NSLocalizedString(@"Your entered XMPP ID is missing the domain", @"")];
        return;
    }

    NSMutableDictionary* dic = [NSMutableDictionary new];
    [dic setObject:[domain.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] forKey:kDomain];
    if(user)
        [dic setObject:[user.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] forKey:kUsername];
    if(self.server)
        [dic setObject:[self.server stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] forKey:kServer];
    if(self.port)
        [dic setObject:self.port forKey:kPort];
    [dic setObject:self.resource forKey:kResource];
    [dic setObject:[NSNumber numberWithBool:self.enabled] forKey:kEnabled];
    [dic setObject:[NSNumber numberWithBool:self.directTLS] forKey:kDirectTLS];
    [dic setObject:self.accountID forKey:kAccountID];
    if(self.rosterName)
        [dic setObject:[self.rosterName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] forKey:kRosterName];
    if(self.statusMessage)
        [dic setObject:[self.statusMessage stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] forKey:@"statusMessage"];
    
    //conversations.im already supports sasl2 and scram ## TODO: use SCRAM preload list
    [dic setObject:([domain.lowercaseString isEqualToString:@"conversations.im"] ? @NO : @(self.plainActivated)) forKey:kPlainActivated];
    
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
            if(!accountExists)
            {
                DDLogVerbose(@"Creating account: %@", dic);
                NSNumber* accountID = [[DataLayer sharedInstance] addAccountWithDictionary:dic];
                if(accountID != nil)
                {
                    self.accountID = accountID;
                    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
                    [SAMKeychain setPassword:self.password forService:kMonalKeychainName account:self.accountID.stringValue];
                    if(self.enabled)
                    {
                        DDLogVerbose(@"Now connecting newly created account: %@", self.accountID);
                        [[MLXMPPManager sharedInstance] connectAccount:self.accountID];
                        xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.accountID];
                        [account publishStatusMessage:self.statusMessage];
                        [account publishRosterName:self.rosterName];
                        [account publishAvatar:self.selectedAvatarImage];
                    }
                    else
                    {
                        DDLogVerbose(@"Making sure newly created account is not connected and deleting all SiriKit interactions: %@", self.accountID);
                        [[MLXMPPManager sharedInstance] disconnectAccount:self.accountID withExplicitLogout:YES];
                        [HelperTools removeAllShareInteractionsForAccountID:self.accountID];
                    }
                    //trigger view updates to make sure enabled/disabled account state propagates to all ui elements
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
                    [self showSuccessHUD];
                }
            }
            else
                [self alertWithTitle:NSLocalizedString(@"Account Exists", @"") andMsg:NSLocalizedString(@"This account already exists in Monal.", @"")];
        }
    }
    else
    {
        [dic setObject:[NSNumber numberWithBool:NO] forKey:kNeedsPasswordMigration];
        DDLogVerbose(@"Updating existing account: %@", dic);
        //disconnect account before disabling it in db, to avoid assertions when trying to create MLContact instances
        //for the disabled account (for notifications etc.)
        if(!self.enabled)
        {
            DDLogVerbose(@"Account is not enabled anymore, deleting all SiriKit interactions and making sure it's disconnected: %@", self.accountID);
            [[MLXMPPManager sharedInstance] disconnectAccount:self.accountID withExplicitLogout:YES];
            [HelperTools removeAllShareInteractionsForAccountID:self.accountID];
        }
        //this case makes sure we recreate a completely new account instance below (using our new settings) if the account details changed
        else if(self.detailsChanged)
            [[MLXMPPManager sharedInstance] disconnectAccount:self.accountID withExplicitLogout:NO];
        
        DDLogVerbose(@"Now updating DB with account dict...");
        [[DataLayer sharedInstance] updateAccounWithDictionary:dic];
        if(self.password.length)
        {
            DDLogVerbose(@"Now setting password for account %@ in SAMKeychain...", self.accountID);
            [[MLXMPPManager sharedInstance] updatePassword:self.password forAccount:self.accountID];
        }
        if(self.enabled)
        {
            DDLogVerbose(@"Account is (still) enabled, connecting it: %@", self.accountID);
            [[MLXMPPManager sharedInstance] connectAccount:self.accountID];
            xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.accountID];
            if(self.statusMessageChanged)
                [account publishStatusMessage:self.statusMessage];
            if(self.rosterNameChanged)
                [account publishRosterName:self.rosterName];
            if(self.avatarChanged)
                [account publishAvatar:self.selectedAvatarImage];
        }
        //trigger view updates to make sure enabled/disabled account state propagates to all ui elements
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
        [self showSuccessHUD];
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
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    });
}

- (IBAction) removeAccountClicked: (id) sender
{
    UIAlertController* questionAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete Account", @"") message:NSLocalizedString(@"This will remove this account and the associated data from this device.", @"") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction* noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
        //do nothing when "no" was pressed
    }];
    UIAlertAction* yesAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
        DDLogVerbose(@"Removing accountID %@", self.accountID);
        self.deactivateSave = YES;
        [[MLXMPPManager sharedInstance] removeAccountForAccountID:self.accountID];

        MBProgressHUD* hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.mode = MBProgressHUDModeCustomView;
        hud.removeFromSuperViewOnHide = YES;
        hud.label.text = NSLocalizedString(@"Success", @"");
        hud.detailsLabel.text = NSLocalizedString(@"The account has been removed", @"");
        UIImage* image = [[UIImage imageNamed:@"success"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        hud.customView = [[UIImageView alloc] initWithImage:image];
        [hud hideAnimated:YES afterDelay:1.0f];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES completion:^{
                //we want to start fresh instead of doing a "password migration"-restore directly triggering an sms
                [[HelperTools defaultsDB] removeObjectForKey:@"Quicksy_phoneNumber"];
                [[HelperTools defaultsDB] removeObjectForKey:@"Quicksy_country"];
                //make sure we show account creation view etc. after removing the last account
                MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
                [appDelegate.activeChats segueToIntroScreensIfNeeded];
            }];
        });
    }];
    [questionAlert addAction:noAction];
    [questionAlert addAction:yesAction];
    
    UIPopoverPresentationController* popPresenter = [questionAlert popoverPresentationController];
    popPresenter.sourceView = self.view;
    
    [self presentViewController:questionAlert animated:YES completion:nil];
}

-(IBAction) deleteAccountClicked:(id) sender
{
    xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.accountID];
    if(xmppAccount.accountState < kStateBound)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error Removing Account", @"")
                                                                        message:NSLocalizedString(@"Your account must be enabled and connected, to be removed from the server!", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UIAlertController* questionAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete Account", @"") message:NSLocalizedString(@"This will delete this account and the associated data from the server and this device. Data might still be retained on other devices, though.", @"") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction* noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
        //do nothing when "no" was pressed
    }];
    UIAlertAction* yesAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
        DDLogVerbose(@"Deleting account on server: %@", xmppAccount);
        self.deactivateSave = YES;
        [xmppAccount removeFromServerWithCompletion:^(NSString* error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(error != nil)
                {
                    UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error Removing Account", @"")
                                                                        message:error preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
                        [alert dismissViewControllerAnimated:YES completion:nil];
                    }]];
                    [self presentViewController:alert animated:YES completion:nil];
                }
                else
                {
                    MBProgressHUD* hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
                    hud.mode = MBProgressHUDModeCustomView;
                    hud.removeFromSuperViewOnHide = YES;
                    hud.label.text = NSLocalizedString(@"Success", @"");
                    hud.detailsLabel.text = NSLocalizedString(@"The account has been deleted", @"");
                    UIImage* image = [[UIImage imageNamed:@"success"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    hud.customView = [[UIImageView alloc] initWithImage:image];
                    [hud hideAnimated:YES afterDelay:1.0f];
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self dismissViewControllerAnimated:YES completion:^{
                            //we want to start fresh instead of doing a "password migration"-restore directly triggering an sms
                            [[HelperTools defaultsDB] removeObjectForKey:@"Quicksy_phoneNumber"];
                            [[HelperTools defaultsDB] removeObjectForKey:@"Quicksy_country"];
                            //make sure we show account creation view etc. after removing the last account
                            MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
                            [appDelegate.activeChats segueToIntroScreensIfNeeded];
                        }];
                    });
                }
            });
        }];
    }];
    [questionAlert addAction:noAction];
    [questionAlert addAction:yesAction];
    
    UIPopoverPresentationController* popPresenter = [questionAlert popoverPresentationController];
    popPresenter.sourceView = self.view;
    
    [self presentViewController:questionAlert animated:YES completion:nil];
}

- (IBAction) clearHistoryClicked: (id) sender
{
    DDLogVerbose(@"Deleting History");

    UIAlertController *questionAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Clear Chat History", @"") message:NSLocalizedString(@"This will clear the whole chat history of this account from this device.", @"") preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"No", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
        //do nothing when "no" was pressed
    }];
    UIAlertAction *yesAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Yes", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {

        [self.db clearMessages:self.accountID];
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];

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
    
    UIPopoverPresentationController* popPresenter = [questionAlert popoverPresentationController];
    popPresenter.sourceView = self.view;
    
    [self presentViewController:questionAlert animated:YES completion:nil];

}

#pragma mark table view datasource methods

-(CGFloat) tableView:(UITableView*) tableView heightForHeaderInSection:(NSInteger) section
{
    if (section == 0)
        return 100;
    else
        return UITableViewAutomaticDimension;
}

-(CGFloat) tableView:(UITableView*) tableView heightForRowAtIndexPath:(NSIndexPath*) indexPath
{
    return 40;
}

-(UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    DDLogVerbose(@"xmpp edit view section %ld, row %ld", indexPath.section, indexPath.row);

    MLSwitchCell* thecell = (MLSwitchCell*)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
    [thecell clear];

    // load cells from interface builder
    if(indexPath.section == kSettingSectionAccount)
    {
        //the user
        switch (indexPath.row)
        {
            case SettingsEnabledRow: {
                [thecell initCell:NSLocalizedString(@"Enabled", @"") withToggle:self.enabled andTag:1];
                break;
            }
            case SettingsDisplayNameRow: {
                [thecell initCell:NSLocalizedString(@"Display Name", @"") withTextField:self.rosterName andPlaceholder:@"" andTag:1];
                thecell.cellLabel.text = NSLocalizedString(@"Display Name", @"");
                thecell.textInputField.keyboardType = UIKeyboardTypeAlphabet;
                break;
            }
            case SettingsStatusMessageRow: {
                [thecell initCell:NSLocalizedString(@"Status Message", @"") withTextField:self.statusMessage andPlaceholder:NSLocalizedString(@"Your status", @"") andTag:6];
                break;
            }
            case SettingsServerDetailsRow: {
                [thecell initTapCell:NSLocalizedString(@"Protocol support of your server (XEPs)", @"")];
                thecell.accessoryType = UITableViewCellAccessoryDetailButton;
                break;
            }
        }
    }
    else if(indexPath.section == kSettingSectionGeneral)
    {
        switch (indexPath.row)
        {
            case SettingsChangePasswordRow: {
#ifdef IS_QUICKSY
                [thecell initTapCell:NSLocalizedString(@"Change/View Password", @"")];
#else
                [thecell initTapCell:NSLocalizedString(@"Change Password", @"")];
#endif
                thecell.cellLabel.text = NSLocalizedString(@"Change Password", @"");
                break;
            }
            case SettingsOmemoKeysRow: {
                [thecell initTapCell:NSLocalizedString(@"Encryption Keys (OMEMO)", @"")];
                break;
            }
            case SettingsBlockedUsersRow: {
                [thecell initTapCell:NSLocalizedString(@"Blocked Users", @"")];
                break;
            }
        }
    }
    else if(indexPath.section == kSettingSectionAdvanced)
    {
        switch (indexPath.row)
        {
            case SettingsJidRow: {
                if(self.editMode)
                {
                    // don't allow jid editing
                    [thecell initCell:NSLocalizedString(@"XMPP ID", @"") withLabel:self.jid];
                }
                else
                {
                    // allow entering jid on account creation
                    [thecell initCell:NSLocalizedString(@"XMPP ID", @"") withTextField:self.jid andPlaceholder:NSLocalizedString(@"Enter your XMPP ID here", @"") andTag:2];
                    thecell.textInputField.keyboardType = UIKeyboardTypeEmailAddress;
                    thecell.textInputField.autocorrectionType = UITextAutocorrectionTypeNo;
                    thecell.textInputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
                }
                break;
            }
            case SettingsPasswordRow: {
                [thecell initCell:NSLocalizedString(@"Password", @"") withTextField:self.password secureEntry:YES andPlaceholder:NSLocalizedString(@"Enter your password here", @"") andTag:3];
                break;
            }
            case SettingsServerRow:  {
                [thecell initCell:NSLocalizedString(@"Server", @"") withTextField:self.server andPlaceholder:NSLocalizedString(@"Optional Hardcoded Hostname", @"") andTag:4];
                break;
            }
            case SettingsPortRow:  {
                [thecell initCell:NSLocalizedString(@"Port", @"") withTextField:self.port andPlaceholder:NSLocalizedString(@"Optional Port", @"") andTag:5];
                break;
            }
            case SettingsDirectTLSRow: {
                [thecell initCell:NSLocalizedString(@"Always use direct TLS, not STARTTLS", @"") withToggle:self.directTLS andTag:2];
                break;
            }
            case SettingsPlainActivatedRow: {
                [thecell initCell:NSLocalizedString(@"Allow MITM-prone PLAIN authentication", @"") withToggle:self.plainActivated andTag:3];
                if(self.editMode)
                    [thecell.toggleSwitch setEnabled:NO];
                break;
            }
            case SettingsResourceRow: {
                [thecell initCell:NSLocalizedString(@"Resource", @"") withLabel:self.resource];
                break;
            }
        }
    }
    else if (indexPath.section == kSettingSectionEdit && self.editMode == YES)
    {
        switch (indexPath.row) {
            case SettingsClearHistoryRow:
            {
                MLButtonCell* buttonCell = (MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
                buttonCell.buttonText.text = NSLocalizedString(@"Clear Chat History", @"");
                buttonCell.buttonText.textColor = [UIColor redColor];
                buttonCell.selectionStyle = UITableViewCellSelectionStyleNone;
                buttonCell.tag = SettingsClearHistoryRow;
                return buttonCell;
            }
            case SettingsRemoveAccountRow:
            {
                MLButtonCell* buttonCell = (MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
                buttonCell.buttonText.text = NSLocalizedString(@"Remove Account from this Device", @"");
                buttonCell.buttonText.textColor = [UIColor redColor];
                buttonCell.selectionStyle = UITableViewCellSelectionStyleNone;
                buttonCell.tag = SettingsRemoveAccountRow;
                return buttonCell;
            }
            case SettingsDeleteAccountRow:
            {
                MLButtonCell* buttonCell = (MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
                buttonCell.buttonText.text = NSLocalizedString(@"Delete Account on Server", @"");
                buttonCell.buttonText.textColor = [UIColor redColor];
                buttonCell.selectionStyle = UITableViewCellSelectionStyleNone;
                buttonCell.tag = SettingsDeleteAccountRow;
                return buttonCell;
            }
        }
    }
    thecell.textInputField.delegate = self;
    if(thecell.textInputField.hidden == YES)
        [thecell.toggleSwitch addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
    return thecell;
}

-(NSInteger) numberOfSectionsInTableView:(UITableView*) tableView
{
    return kSettingSectionCount;
}

-(UIView*) tableView:(UITableView*) tableView viewForHeaderInSection:(NSInteger) section
{
    if (section == 0)
    {
        UIView* avatarView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, 100)];
        avatarView.backgroundColor = [UIColor clearColor];
        avatarView.userInteractionEnabled = YES;
        
        self.userAvatarImageView = [[UIImageView alloc] initWithFrame:CGRectMake((self.tableView.frame.size.width - 90)/2 , 25, 90, 90)];
        self.userAvatarImageView.layer.cornerRadius =  self.userAvatarImageView.frame.size.height / 2;
        self.userAvatarImageView.layer.borderWidth = 2.0f;
        self.userAvatarImageView.layer.borderColor = ([UIColor clearColor]).CGColor;
        self.userAvatarImageView.clipsToBounds = YES;
        self.userAvatarImageView.userInteractionEnabled = YES;
        
        UITapGestureRecognizer* touchUserAvatarRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(getPhotoAction:)];
        [self.userAvatarImageView addGestureRecognizer:touchUserAvatarRecognizer];
        
        if(self.editMode == YES && self.jid != nil && self.accountID.intValue >= 0)
            [[MLImageManager sharedInstance] getIconForContact:[MLContact createContactFromJid:self.jid andAccountID:self.accountID] withCompletion:^(UIImage *image) {
                [self.userAvatarImageView setImage:image];
            }];
        else
        {
            //use noicon image for account creation
            [self.userAvatarImageView setImage:[MLImageManager circularImage:[UIImage imageNamed:@"noicon"]]];
        }
        [avatarView addSubview:self.userAvatarImageView];
        
        return avatarView;
    }
    else
    {
        NSString* sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
        return [HelperTools MLCustomViewHeaderWithTitle:sectionTitle];
    }
}

-(NSString*) tableView:(UITableView*) tableView titleForHeaderInSection:(NSInteger) section
{
    return self.sectionDictionary[@(section)];
}

-(NSInteger) tableView:(UITableView*) tableView numberOfRowsInSection:(NSInteger) section
{
    if(section == kSettingSectionAvatar)
        return SettingsAvatarRowsCnt;
    else if(section == kSettingSectionAccount)
        return SettingsAccountRowsCnt;
    else if(section == kSettingSectionGeneral && self.editMode)
        return SettingsGeneralRowsCnt;
    else if(section == kSettingSectionAdvanced)
        return SettingsAdvancedRowsCnt;
    else if(section == kSettingSectionEdit && self.editMode)
        return SettingsEditRowsCnt;
    else
        return 0;
}

#pragma mark -  table view delegate
-(void) tableView:(UITableView*) tableView didSelectRowAtIndexPath:(NSIndexPath*) newIndexPath
{
    DDLogVerbose(@"selected log section %ld , row %ld", newIndexPath.section, newIndexPath.row);
    
    if(newIndexPath.section == kSettingSectionAccount)
    {
        switch(newIndexPath.row)
        {
            case SettingsServerDetailsRow: {
                xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.accountID];
                UIViewController* serverDetailsView = [[SwiftuiInterface new] makeServerDetailsViewFor:xmppAccount];
                [self showDetailViewController:serverDetailsView sender:self];
                break;
            }
        }
    }
    else if(newIndexPath.section == kSettingSectionGeneral)
    {
        switch(newIndexPath.row)
        {
            case SettingsChangePasswordRow: {
                UIViewController* changePasswordView = [[SwiftuiInterface new] makeChangePasswordViewFor:self.accountID];
                [self showDetailViewController:changePasswordView sender:self];
                break;
            }
            case SettingsOmemoKeysRow: {
                UIViewController* ownOmemoKeysView;
                xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.accountID];
                if(self.jid == nil || self.accountID == nil || xmppAccount == nil)
                {
                    ownOmemoKeysView = [[SwiftuiInterface new] makeOwnOmemoKeyView:nil];
                } else {
                    MLContact* ownContact = [MLContact createContactFromJid:self.jid andAccountID:self.accountID];
                    ownOmemoKeysView = [[SwiftuiInterface new] makeOwnOmemoKeyView:ownContact];
                }
                [self showDetailViewController:ownOmemoKeysView sender:self];
                break;
            }
            case SettingsBlockedUsersRow:
                [self performSegueWithIdentifier:@"showBlockedUsers" sender:self];
                break;
        }
    }
    else if(newIndexPath.section == kSettingSectionAdvanced)
    {
        // nothing to do here
    }
    else if(newIndexPath.section == kSettingSectionEdit)
    {
        switch(newIndexPath.row)
        {
            case SettingsClearHistoryRow:
                [self clearHistoryClicked:[tableView cellForRowAtIndexPath:newIndexPath]];
                break;
            case SettingsRemoveAccountRow:
                [self removeAccountClicked:[tableView cellForRowAtIndexPath:newIndexPath]];
                break;
            case SettingsDeleteAccountRow:
                [self deleteAccountClicked:[tableView cellForRowAtIndexPath:newIndexPath]];
                break;
        }
    }
}

-(void) tableView:(UITableView*) tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath*) indexPath
{
    if(indexPath.section == kSettingSectionAccount)
    {
        switch(indexPath.row)
        {
            case SettingsServerDetailsRow: {
                xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.accountID];
                UIViewController* serverDetailsView = [[SwiftuiInterface new] makeServerDetailsViewFor:xmppAccount];
                [self showDetailViewController:serverDetailsView sender:self];
                break;
            }
        }
    }
}


#pragma mark - segeue

-(void) prepareForSegue:(UIStoryboardSegue*) segue sender:(id) sender
{
    if([segue.identifier isEqualToString:@"showBlockedUsers"])
    {
        xmpp* xmppAccount = [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.accountID];
        // force blocklist update
        [xmppAccount fetchBlocklist];
        MLBlockedUsersTableViewController* blockedUsers = (MLBlockedUsersTableViewController*)segue.destinationViewController;
        blockedUsers.xmppAccount = xmppAccount;
    }
}

#pragma mark -  text input  fielddelegate

-(void) textFieldDidBeginEditing:(UITextField*) textField
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

-(void) textFieldDidEndEditing:(UITextField*) textField
{
    switch (textField.tag) {
        case 1: {
            self.rosterName = textField.text;
            self.rosterNameChanged = YES;
            break;
        }
        case 2: {
            self.jid = textField.text;
            self.detailsChanged = YES;
            break;
        }
        case 3: {
            self.password = textField.text;
            self.detailsChanged = YES;
            break;
        }
        case 4: {
            self.server = textField.text;
            self.detailsChanged = YES;
            break;
        }
        case 5: {
            self.port = textField.text;
            self.detailsChanged = YES;
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

-(BOOL) textFieldShouldReturn:(UITextField*) textField
{
    [textField resignFirstResponder];
    return true;
}


-(void) toggleSwitch:(id) sender
{
    UISwitch* toggle = (UISwitch*) sender;

    switch (toggle.tag) {
        case 1: {
            self.enabled = toggle.on;
            break;
        }
        case 2: {
            self.directTLS = toggle.on;
            self.detailsChanged = YES;
            break;
        }
        case 3: {
            self.plainActivated = toggle.on;
            self.detailsChanged = YES;
            if(self.plainActivated)
            {
                UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Warning", @"")
                                                                    message:NSLocalizedString(@"If you turn this on, you will no longer be safe from man-in-the-middle attacks. Such attacks enable the adversary to manipulate your incoming and outgoing messages, add their own OMEMO keys, change your account details and even know or change your password!\n\nYou should rather switch to another server than turning this on.", @"") preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Understood", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
                    [alert dismissViewControllerAnimated:YES completion:nil];
                }]];
                [self presentViewController:alert animated:YES completion:nil];
            }
            break;
        }
    }
}

#pragma mark - doc picker
-(void) pickImgFile:(id) sender
{
    [self presentViewController:self.imagePicker animated:YES completion:nil];
    return;
}

-(void) documentPicker:(UIDocumentPickerViewController*) controller didPickDocumentsAtURLs:(NSArray<NSURL*>*) urls
{
    NSFileCoordinator* coordinator = [NSFileCoordinator new];
    [coordinator coordinateReadingItemAtURL:urls.firstObject options:NSFileCoordinatorReadingForUploading error:nil byAccessor:^(NSURL* _Nonnull newURL) {
        NSData* data =[NSData dataWithContentsOfURL:newURL];
        UIImage* pickImg = [UIImage imageWithData:data];
        [self useAvatarImage:pickImg];
    }];
}

-(void) getPhotoAction:(UIGestureRecognizer*) recognizer
{
    xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:self.accountID];
    if (!account)
        return;
    UIAlertController* actionControll = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select Action", @"")
                                                                            message:nil preferredStyle:UIAlertControllerStyleActionSheet];

#if TARGET_OS_MACCATALYST
    [self pickImgFile:nil];
#else
    UIImagePickerController* imagePicker = [UIImagePickerController new];
    imagePicker.delegate = self;

    UIAlertAction* cameraAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Camera", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
        imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        [self presentViewController:imagePicker animated:YES completion:nil];
    }];

    UIAlertAction* photosAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Photos", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
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
    [cameraAction setValue:[[UIImage systemImageNamed:@"camera"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [photosAction setValue:[[UIImage systemImageNamed:@"photo"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [actionControll addAction:cameraAction];
    [actionControll addAction:photosAction];
#endif
    
    // Set image
    [actionControll addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
        [actionControll dismissViewControllerAnimated:YES completion:nil];
    }]];

    actionControll.popoverPresentationController.sourceView = self.userAvatarImageView;
    [self presentViewController:actionControll animated:YES completion:nil];
}

-(void) imagePickerController:(UIImagePickerController*) picker didFinishPickingMediaWithInfo:(NSDictionary<NSString*, id>*) info
{
    NSString* mediaType = info[UIImagePickerControllerMediaType];
    if([mediaType isEqualToString:UTTypeImage.identifier]) {
        UIImage* selectedImage = info[UIImagePickerControllerEditedImage];
        if(!selectedImage) selectedImage = info[UIImagePickerControllerOriginalImage];
        
        TOCropViewController* cropViewController = [[TOCropViewController alloc] initWithImage:selectedImage];
        cropViewController.delegate = self;
        cropViewController.transitioningDelegate = nil;
        //set square aspect ratio and don't let the user change that (this is a avatar which should be square for maximum compatibility with other clients)
        cropViewController.aspectRatioPreset = TOCropViewControllerAspectRatioPresetSquare;
        cropViewController.aspectRatioLockEnabled = YES;
        cropViewController.aspectRatioPickerButtonHidden = YES;
        
        UINavigationController* cropRootController = [[UINavigationController alloc] initWithRootViewController:cropViewController];
        [picker dismissViewControllerAnimated:YES completion:^{
            [self presentViewController:cropRootController animated:YES completion:nil];
        }];
    }
    else
        [picker dismissViewControllerAnimated:YES completion:nil];
}

-(void) imagePickerControllerDidCancel:(UIImagePickerController*) picker
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
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}


#pragma mark -- TOCropViewController delagate

-(void) cropViewController:(nonnull TOCropViewController*) cropViewController didCropToImage:(UIImage* _Nonnull) image withRect:(CGRect) cropRect angle:(NSInteger) angle
{
    [self useAvatarImage:image];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
