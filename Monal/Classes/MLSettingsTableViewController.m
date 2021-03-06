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
#import "MLDefinitions.h"

@import SafariServices;

NS_ENUM(NSInteger, kSettingSection)
{
    kSettingSectionApp = 0,
    kSettingSectionSupport,
    kSettingSectionAbout,
    kSettingSectionCount
};

@interface MLSettingsTableViewController ()

@property (nonatomic, strong) NSArray* sections;
@property (nonatomic, strong) NSArray* appRows;
@property (nonatomic, strong) NSArray* supportRows;
@property (nonatomic, strong) NSArray* aboutRows;

@end

@implementation MLSettingsTableViewController 


- (IBAction)close:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"AccountCell"];

    self.sections = @[NSLocalizedString(@"App", @""), NSLocalizedString(@"Support", @""), NSLocalizedString(@"About", @"")];
    
    self.appRows = @[
        NSLocalizedString(@"Quick Setup", @""),
        NSLocalizedString(@"Accounts",@""),
        NSLocalizedString(@"Privacy Settings",@""),
        NSLocalizedString(@"Notifications",@""),
        NSLocalizedString(@"Backgrounds",@""),
        NSLocalizedString(@"Sounds",@""),
        NSLocalizedString(@"Chat Logs",@"")
    ];
    self.supportRows = @[
        NSLocalizedString(@"Email Support", @""),
        NSLocalizedString(@"Submit A Bug", @"")
    ];

    self.aboutRows = @[
        NSLocalizedString(@"Rate Monal", @""),
        NSLocalizedString(@"Open Source", @""),
        NSLocalizedString(@"Privacy", @""),
        NSLocalizedString(@"About", @""),
#ifdef DEBUG
        NSLocalizedString(@"Log", @""),
#endif
        NSLocalizedString(@"Version", @"")
    ];

    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
#if !TARGET_OS_MACCATALYST
    if (@available(iOS 13.0, *)) {
        self.splitViewController.primaryBackgroundStyle=UISplitViewControllerBackgroundStyleSidebar;
    } else {
        // Fallback on earlier versions
    }
#endif
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - key commands

-(BOOL)canBecomeFirstResponder {
    return YES;
}

- (NSArray<UIKeyCommand *>*)keyCommands {
    return @[
        [UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(close:)]
    ];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSettingSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch(section)
    {
        case kSettingSectionApp: return self.appRows.count;
        case kSettingSectionSupport: return self.supportRows.count;
        case kSettingSectionAbout: return self.aboutRows.count;
        default:
            unreachable();
    }
    return 0;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    MLSwitchCell* cell = [tableView dequeueReusableCellWithIdentifier:@"AccountCell" forIndexPath:indexPath];

    switch(indexPath.section)
    {
        case kSettingSectionApp: {
            [cell initTapCell:self.appRows[indexPath.row]];
            break;
        }
        case kSettingSectionSupport: {
            [cell initTapCell:self.supportRows[indexPath.row]];
            break;
        }
        case kSettingSectionAbout: {
            if(indexPath.row == (self.aboutRows.count - 1))
            {
                NSString* versionTxt = nil;
                NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
#if IS_ALPHA
                versionTxt = [NSString stringWithFormat:@"Alpha %@ (%s: %s UTC)", [infoDict objectForKey:@"CFBundleShortVersionString"], __DATE__, __TIME__];
#else
                versionTxt = [NSString stringWithFormat:@"%@ (%@)", [infoDict objectForKey:@"CFBundleShortVersionString"], [infoDict objectForKey:@"CFBundleVersion"]];
#endif
                [cell initCell:@"Version" withLabel:versionTxt];
            } else {
                [cell initTapCell:self.aboutRows[indexPath.row]];;
            }
            break;
        }
        default:
            unreachable();
    }
    return cell;
}


-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return (section != kSettingSectionApp) ? self.sections[section] : 0;
}


-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch(indexPath.section)
    {
        case kSettingSectionApp: {
            switch ((indexPath.row)) {
                case 0:
                    [self performSegueWithIdentifier:@"showLogin" sender:self];
                    break;

                case 1:
                    [self performSegueWithIdentifier:@"showAccounts" sender:self];
                    break;

                case 2:
                    [self performSegueWithIdentifier:@"showPrivacySettings" sender:self];
                    break;

                case 3:
                    [self performSegueWithIdentifier:@"showNotification" sender:self];
                    break;

                case 4:
                    [self performSegueWithIdentifier:@"showBackgrounds" sender:self];
                    break;

                case 5:
                    [self performSegueWithIdentifier:@"showSounds" sender:self];
                    break;

                case 6:
                    [self performSegueWithIdentifier:@"showChatLog" sender:self];
                    break;

                default:
                    unreachable();
                    break;
            }
            break;
        }
        case kSettingSectionSupport: {
            switch ((indexPath.row)) {
                case 0:
                    [self composeMail];
                    break;
                    
                case 1:
                     [self openLink:@"https://github.com/anurodhp/Monal/issues"];
                    break;
                default:
                    break;
            }
            break;
        }
        case kSettingSectionAbout: {
            switch ((indexPath.row)) {
                case 0:
                    [self openStoreProductViewControllerWithITunesItemIdentifier:317711500];
                    break;
                    
                case 1:
                    [self performSegueWithIdentifier:@"showOpenSource" sender:self];
                    break;
                    
                case 2:
                    [self openLink:@"https://monal.im/privacy-policy/"];
                    break;
                    
                case 3:
                    [self openLink:@"https://monal.im/about/"];
                    break;
                    
                case 4:
                    [self performSegueWithIdentifier:@"showLogs" sender:self];
                    break;
               
                default:
                    unreachable();
                    break;
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
        SFSafariViewController *safariView = [[ SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:safariView animated:YES completion:nil];
    }
}

#pragma mark - Actions


- (void)openStoreProductViewControllerWithITunesItemIdentifier:(NSInteger)iTunesItemIdentifier {
    SKStoreProductViewController *storeViewController = [[SKStoreProductViewController alloc] init];
    
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

-(void)composeMail
{
    if([MFMailComposeViewController canSendMail]) {
        MFMailComposeViewController* composeVC = [[MFMailComposeViewController alloc] init];
        composeVC.mailComposeDelegate = self;
        [composeVC setToRecipients:@[@"info@monal.im"]];
        [self presentViewController:composeVC animated:YES completion:nil];
    }
    else  {
        UIAlertController* messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"") message:NSLocalizedString(@"There is no configured email account. Please email info@monal.im .", @"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
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


-(void)  prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showOpenSource"])
    {
        UINavigationController *nav = (UINavigationController *)  segue.destinationViewController;
        MLWebViewController *web = (MLWebViewController *) nav.topViewController;
        
        NSBundle* mainBundle = [NSBundle mainBundle];
        NSString* myFile = [mainBundle pathForResource: @"opensource" ofType: @"html"];
    
        web.urltoLoad=[NSURL fileURLWithPath:myFile];
    }
}

@end
