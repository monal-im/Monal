//
//  MLSettingsTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/26/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLSettingsTableViewController.h"
#import "MLWebViewController.h"
#import "MLSwitchCell.h"
#import "HelperTools.h"
#import "DataLayer.h"
#import "MLXMPPManager.h"
#import "XMPPEdit.h"
#import <Monal-Swift.h>

@import SafariServices;

enum kSettingSection {
    kSettingSectionAccounts,
    kSettingSectionApp,
    kSettingSectionSupport,
    kSettingSectionAbout,
    kSettingSectionCount
};

enum SettingsAccountRows {
    QuickSettingsRow,
    AdvancedSettingsRow,
    SettingsAccountRowsCnt
};

enum SettingsAppRows {
    GeneralSettingsRow,
    SoundsRow,
    SettingsAppRowsCnt
};

enum SettingsSupportRow {
    EmailRow,
    SubmitABugRow,
    SettingsSupportRowCnt
};

enum SettingsAboutRows {
    RateMonalRow,
    OpenSourceRow,
    PrivacyRow,
    AboutRow,
#ifdef DEBUG
    LogRow,
#endif
    VersionRow,
    SettingsAboutRowsCntORLogRow,
    SettingsAboutRowsWithLogCnt
};

//this will hold all disabled rows of all enums (this is needed because the code below still references these rows)
enum DummySettingsRows {
    DummySettingsRowsBegin = 100,
};

@interface MLSettingsTableViewController () {
    int _tappedVersionInfo;
}

@property (nonatomic, strong) NSArray* sections;
@property (nonatomic, strong) NSArray* accountRows;
@property (nonatomic, strong) NSArray* appRows;
@property (nonatomic, strong) NSArray* supportRows;
@property (nonatomic, strong) NSDateFormatter* uptimeFormatter;

@property (nonatomic, strong) NSIndexPath* selected;

@end

@implementation MLSettingsTableViewController 


-(IBAction) close:(id) sender
{
    _tappedVersionInfo = 0;
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    [self setupAccountsView];

    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"AccountCell"];

    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
#if !TARGET_OS_MACCATALYST
    self.splitViewController.primaryBackgroundStyle = UISplitViewControllerBackgroundStyleSidebar;
#endif
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshAccountList];

    _tappedVersionInfo = 0;
    self.selected = nil;
}

#pragma mark - key commands

-(BOOL) canBecomeFirstResponder
{
    return YES;
}

-(NSArray<UIKeyCommand*>*) keyCommands
{
    return @[[UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(close:)]];
}

#pragma mark - Table view data source

-(NSInteger) numberOfSectionsInTableView:(UITableView*) tableView
{
    return kSettingSectionCount;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch(section)
    {
        case kSettingSectionAccounts: return [self getAccountNum] + SettingsAccountRowsCnt;
        case kSettingSectionApp: return SettingsAppRowsCnt;
        case kSettingSectionSupport: return SettingsSupportRowCnt;
#ifndef DEBUG
        case kSettingSectionAbout: return [[HelperTools defaultsDB] boolForKey:@"showLogInSettings"] ? SettingsAboutRowsWithLogCnt : SettingsAboutRowsCntORLogRow;
#else
        case kSettingSectionAbout: return SettingsAboutRowsCntORLogRow;
#endif
        default:
            unreachable();
    }
    return 0;
}

-(void) prepareForSegue:(UIStoryboardSegue*) segue sender:(id) sender
{
    if([segue.identifier isEqualToString:@"showOpenSource"])
    {
        UINavigationController* nav = (UINavigationController*) segue.destinationViewController;
        MLWebViewController* web = (MLWebViewController*) nav.topViewController;

        NSBundle* mainBundle = [NSBundle mainBundle];
        NSString* myFile = [mainBundle pathForResource: @"opensource" ofType: @"html"];

        [web initViewWithUrl:[NSURL fileURLWithPath:myFile]];
    }
    else if([segue.identifier isEqualToString:@"showAbout"])
    {
        UINavigationController* nav = (UINavigationController*) segue.destinationViewController;
        MLWebViewController* web = (MLWebViewController*) nav.topViewController;

        [web initViewWithUrl:[NSURL URLWithString:@"https://monal-im.org/about"]];
    }
    else if([segue.identifier isEqualToString:@"showPrivacy"])
    {
        UINavigationController* nav = (UINavigationController*) segue.destinationViewController;
        MLWebViewController* web = (MLWebViewController*) nav.topViewController;

        [web initViewWithUrl:[NSURL URLWithString:@"https://monal-im.org/privacy"]];
    }
    else if([segue.identifier isEqualToString:@"showBug"])
    {
        UINavigationController* nav = (UINavigationController*) segue.destinationViewController;
        MLWebViewController* web = (MLWebViewController*) nav.topViewController;

        [web initViewWithUrl:[NSURL URLWithString:@"https://github.com/monal-im/Monal/issues"]];
    }
    else if([segue.identifier isEqualToString:@"editXMPP"])
    {
        XMPPEdit* editor = (XMPPEdit*) segue.destinationViewController.childViewControllers.firstObject; // segue.destinationViewController;

        if(self.selected && self.selected.row >= (int) [self getAccountNum])
        {
            editor.accountNo = [NSNumber numberWithInt:-1];
        }
        else
        {
            MLAssert(self.selected != nil, @"self.selected must not be nil");
            editor.originIndex = self.selected;
            editor.accountNo = [self getAccountNoByIndex:self.selected.row];
        }
    }
}

-(UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    MLSwitchCell* cell = [tableView dequeueReusableCellWithIdentifier:@"AccountCell" forIndexPath:indexPath];
    switch((int)indexPath.section)
    {
        case kSettingSectionAccounts: {
            if(indexPath.row < (int) [self getAccountNum])
            {
                // User selected an account
                [self initContactCell:cell forAccNo:indexPath.row];
            }
            else
            {
                MLAssert(indexPath.row - [self getAccountNum] < SettingsAccountRowsCnt, @"Tried to tap onto a row ment to be for a concrete account, not for quick or advanced settings");
                // User selected one of the 'add account' promts
                switch(indexPath.row - [self getAccountNum]) {
                    case QuickSettingsRow:
                        [cell initTapCell:NSLocalizedString(@"Add Account", @"")];
                        break;
                    case AdvancedSettingsRow:
                        [cell initTapCell:NSLocalizedString(@"Add Account (advanced)", @"")];
                        break;
                    default:
                        unreachable();
                }
            }
            break;
        }
        case kSettingSectionApp: {
            switch(indexPath.row) {
                case GeneralSettingsRow:
                    [cell initTapCell:NSLocalizedString(@"General Settings", @"")];
                    break;
                case SoundsRow:
                    [cell initTapCell:NSLocalizedString(@"Sounds", @"")];
                    break;
                default:
                    unreachable();
            }
            break;
        }
        case kSettingSectionSupport: {
            switch(indexPath.row) {
                case EmailRow:
                    [cell initTapCell:NSLocalizedString(@"Email Support", @"")];
                    break;
                case SubmitABugRow:
                    [cell initTapCell:NSLocalizedString(@"Submit A Bug", @"")];
                    break;
                default:
                    unreachable();
            }
            break;
        }
        case kSettingSectionAbout: {
            switch(indexPath.row) {
                case RateMonalRow: {
                    [cell initTapCell:NSLocalizedString(@"Rate Monal", @"")];
                    break;
                }
                case OpenSourceRow: {
                    [cell initTapCell:NSLocalizedString(@"Open Source", @"")];
                    break;
                }
                case PrivacyRow: {
                    [cell initTapCell:NSLocalizedString(@"Privacy", @"")];
                    break;
                }
                case AboutRow: {
                    [cell initTapCell:NSLocalizedString(@"About", @"")];
                    break;
                }
                case VersionRow: {
                    [cell initCell:NSLocalizedString(@"Version", @"") withLabel:[HelperTools appBuildVersionInfoFor:MLVersionTypeIQ]];
                    break;
                }
#ifdef DEBUG
                case LogRow:
#endif
                case SettingsAboutRowsCntORLogRow: {
                    [cell initTapCell:NSLocalizedString(@"Debug", @"")];
                    break;
                }
                default: {
                    unreachable();
                }
            }
            break;
        }
        default:
            unreachable();
    }
    return cell;
}

-(NSString*) tableView:(UITableView*) tableView titleForHeaderInSection:(NSInteger) section
{
    switch(section) {
        case kSettingSectionAccounts:
            return nil;             //the account section does not need a heading (its the first one)
        case kSettingSectionApp:
            return NSLocalizedString(@"App", @"");
        case kSettingSectionSupport:
            return NSLocalizedString(@"Support", @"");
        case kSettingSectionAbout:
            return NSLocalizedString(@"About", @"");
        default:
            unreachable();
    }
    return nil;     //needed to make the compiler happy
}

-(void)tableView:(UITableView*) tableView didSelectRowAtIndexPath:(NSIndexPath*) indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch(indexPath.section)
    {
        case kSettingSectionAccounts: {
            self.selected = indexPath;
            if(indexPath.row < (int) [self getAccountNum])
                [self performSegueWithIdentifier:@"editXMPP" sender:self];
            else
            {
                switch(indexPath.row - [self getAccountNum]) {
                    case QuickSettingsRow:
                    {
                        UIViewController* loginView = [[SwiftuiInterface new] makeViewWithName:@"LogIn"];
                        [self showDetailViewController:loginView sender:self];
                        break;
                    }
                    case AdvancedSettingsRow:
                        [self performSegueWithIdentifier:@"editXMPP" sender:self];
                        break;
                    default:
                        unreachable();
                }
            }
            break;
        }
        case kSettingSectionApp: {
            switch(indexPath.row) {
                    
                case GeneralSettingsRow: {
                    UIViewController* privacyViewController = [[SwiftuiInterface new] makeViewWithName:@"GeneralSettings"];
                    [self showDetailViewController:privacyViewController sender:self];
                    break;
                }
                case SoundsRow:
                    [self performSegueWithIdentifier:@"showSounds" sender:self];
                    break;
                default:
                    unreachable();
            }
            break;
        }
        case kSettingSectionSupport: {
            switch(indexPath.row) {
                case EmailRow:
                    [self composeMail];
                    break;
                case SubmitABugRow:
                    [self performSegueWithIdentifier:@"showBug" sender:self];
                    break;
                default:
                    unreachable();
            }
            break;
        }
        case kSettingSectionAbout: {
            switch(indexPath.row) {
                case RateMonalRow:
                    [self openStoreProductViewControllerWithITunesItemIdentifier:317711500];
                    break;
                case OpenSourceRow:
                    [self performSegueWithIdentifier:@"showOpenSource" sender:self];
                    break;
                case PrivacyRow:
                    [self performSegueWithIdentifier:@"showPrivacy" sender:self];
                    break;
                case AboutRow:
                    [self performSegueWithIdentifier:@"showAbout" sender:self];
                    break;
#ifdef DEBUG
                case LogRow:
#endif
                case SettingsAboutRowsCntORLogRow:{
                    UIViewController* logView = [[SwiftuiInterface new] makeViewWithName:@"DebugView"];
                    [self showDetailViewController:logView sender:self];
                    break;
                }
                case VersionRow: {
#ifndef DEBUG
                    if(_tappedVersionInfo >= 16)
                    {
                        [[HelperTools defaultsDB] setBool:YES forKey:@"showLogInSettings"];
                        [tableView reloadData];
                    }
                    else
                        _tappedVersionInfo++;
#endif
                    UIPasteboard* pastboard = UIPasteboard.generalPasteboard;
                    pastboard.string = [HelperTools appBuildVersionInfoFor:MLVersionTypeIQ];
                    break;
                }
                default:
                    unreachable();
            }
            break;
        }
        default:
            unreachable();
    }
}

-(void) openLink:(NSString *) link
{
    NSURL* url = [NSURL URLWithString:link];
    
    if ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"]) {
        SFSafariViewController* safariView = [[ SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:safariView animated:YES completion:nil];
    }
}

#pragma mark - Actions


-(void) openStoreProductViewControllerWithITunesItemIdentifier:(NSInteger) iTunesItemIdentifier {
    SKStoreProductViewController *storeViewController = [SKStoreProductViewController new];
    
    storeViewController.delegate = self;
    
    NSNumber* identifier = [NSNumber numberWithInteger:iTunesItemIdentifier];
    //, @"action":@"write-review"
    NSDictionary* parameters = @{ SKStoreProductParameterITunesItemIdentifier:identifier};
    
    [storeViewController loadProductWithParameters:parameters
                                   completionBlock:^(BOOL result, NSError *error) {
                                       if (result)
                                           [self presentViewController:storeViewController
                                                              animated:YES
                                                            completion:nil];
                                       else NSLog(@"SKStoreProductViewController: %@", error);
                                   }];
    
    
}

-(void) composeMail
{
    if([MFMailComposeViewController canSendMail]) {
        MFMailComposeViewController* composeVC = [MFMailComposeViewController new];
        composeVC.mailComposeDelegate = self;
        [composeVC setToRecipients:@[@"info@monal-im.org"]];
        [self presentViewController:composeVC animated:YES completion:nil];
    }
    else
    {
        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"") message:NSLocalizedString(@"There is no configured email account. Please email info@monal-im.org .", @"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
        }];
        [messageAlert addAction:closeAction];
        
        [self presentViewController:messageAlert animated:YES completion:nil];
    }
    
}

#pragma mark - Message ui delegate
- (void)mailComposeController:(MFMailComposeViewController *)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error
{
    [controller dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - SKStoreProductViewControllerDelegate

-(void)productViewControllerDidFinish:(SKStoreProductViewController *)viewController {
    [viewController dismissViewControllerAnimated:YES completion:nil];
}
@end
