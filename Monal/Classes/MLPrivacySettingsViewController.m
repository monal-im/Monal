//
//  MLPrivacySettingsViewController.m
//  Monal
//
//  Created by Friedrich Altheide on 06.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPrivacySettingsViewController.h"
#import "HelperTools.h"
#import "MLConstants.h"
#import "MLSwitchCell.h"

typedef NS_ENUM(NSInteger, NSNotificationPrivacyOptionRow) {
    DisplayNameAndMessageRow = 1,
    DisplayOnlyNameRow = 2,
    DisplayOnlyPlaceholderRow = 3
};
const long NotificationPrivacyOptionCnt = 3;

@interface MLPrivacySettingsViewController()

@property (nonatomic, strong) NSArray* sectionArray;
@property (nonatomic) BOOL isNotificationPrivacyOpened;

@end

@implementation MLPrivacySettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"AccountCell"];

    // Do any additional setup after loading the view.
    self.navigationItem.title = NSLocalizedString(@"Privacy Settings", @"");
   
    _settingsTable = self.tableView;
    _settingsTable.delegate = self;
    _settingsTable.dataSource = self;
    _settingsTable.backgroundView = nil;
    [_settingsTable setAllowsSelection:YES];
    self.isNotificationPrivacyOpened = NO;
    
    self.sectionArray = @[NSLocalizedString(@"General", @"")];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[HelperTools defaultsDB] setObject:@YES forKey:@"HasSeenPrivacySettings"];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

#pragma mark tableview datasource delegate


-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self.sectionArray count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [self.sectionArray objectAtIndex:section];
}

-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSString* sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
    return [HelperTools MLCustomViewHeaderWithTitle:sectionTitle];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0:
        {
#ifdef DISABLE_OMEMO
            return 12 + (self.isNotificationPrivacyOpened ? NotificationPrivacyOptionCnt : 0);
#else// DISABLE_OMEMO
            return 13 + (self.isNotificationPrivacyOpened ? NotificationPrivacyOptionCnt : 0);
#endif// DISABLE_OMEMO
        }
        default:
        {
            return 0;
        }
        break;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    MLSwitchCell* cell = (MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
    [cell clear];

    switch (indexPath.section) {
        case 0:
        {
            long row = indexPath.row;
            // + non expanded notification options
            row += (self.isNotificationPrivacyOpened || row == 0) ? 0 : NotificationPrivacyOptionCnt;

            switch(row)
            {
                case 0:
                {
                    NotificationPrivacySettingOption nOptions = (NotificationPrivacySettingOption)[[HelperTools defaultsDB] integerForKey:@"NotificationPrivacySetting"];
                    [cell initCell:NSLocalizedString(@"Notification", @"") withLabel:[self getNsNotificationPrivacyOption:nOptions]];
                    break;
                }
                //Notification options
                case 1:
                {
                    [cell initCell:[@" - " stringByAppendingString:NSLocalizedString(@"Display Name And Message", @"")] withLabel:nil];
                    [self checkStatusForCell:cell atIndexPath:indexPath];
                    break;
                }
                case 2:
                {
                    [cell initCell:[@" - " stringByAppendingString:NSLocalizedString(@"Display Only Name", @"")] withLabel:nil];
                    [self checkStatusForCell:cell atIndexPath:indexPath];
                    break;
                }
                case 3:
                {
                    [cell initCell:[@" - " stringByAppendingString:NSLocalizedString(@"Display Only Placeholder", @"")] withLabel:nil];
                    [self checkStatusForCell:cell atIndexPath:indexPath];
                    break;
                }
                case 4:
                {
                    [cell initCell:NSLocalizedString(@"Show Inline Geo Location", @"") withToggleDefaultsKey:@"ShowGeoLocation"];
                    break;
                }
                case 5:
                {
                    [cell initCell:NSLocalizedString(@"Send Last Interaction Time", @"") withToggleDefaultsKey:@"SendLastUserInteraction"];
                    break;
                }
                case 6:
                {
                    [cell initCell:NSLocalizedString(@"Send Typing Notifications", @"") withToggleDefaultsKey:@"SendLastChatState"];
                    break;
                }
                case 7:
                {
                    [cell initCell:NSLocalizedString(@"Send message received state", @"") withToggleDefaultsKey:@"SendReceivedMarkers"];
                    break;
                }
                case 8:
                {
                    [cell initCell:NSLocalizedString(@"Sync Read-Markers", @"") withToggleDefaultsKey:@"SendDisplayedMarkers"];
                    break;
                }
                case 9:
                {
                    [cell initCell:NSLocalizedString(@"Show URL previews", @"") withToggleDefaultsKey:@"ShowURLPreview"];
                    break;
                }
                case 10:
                {
                    [cell initTapCell:NSLocalizedString(@"Auto-Download Media Settings", @"")];
                    break;
                }
                case 11:
                {
                    [cell initCell:NSLocalizedString(@"Autodelete all messages after 3 days", @"") withToggleDefaultsKey:@"AutodeleteAllMessagesAfter3Days"];
                    break;
                }
                case 12:
                {
                    [cell initCell:NSLocalizedString(@"Calls: Allow P2P sessions", @"") withToggleDefaultsKey:@"webrtcAllowP2P"];
                    break;
                }
                case 13:
                {
                    [cell initCell:NSLocalizedString(@"Calls: Allow TURN fallback to Monal-Servers", @"") withToggleDefaultsKey:@"webrtcUseFallbackTurn"];
                    break;
                }
                case 14:
                {
                    [cell initCell:NSLocalizedString(@"Allow approved contacts to query my Monal and iOS version", @"") withToggleDefaultsKey:@"allowVersionIQ"];
                    break;
                }
                case 15:
                {
//flow into default case for non-omemo builds
#ifndef DISABLE_OMEMO
                    [cell initCell:NSLocalizedString(@"Enable encryption by default for new chats", @"") withToggleDefaultsKey:@"OMEMODefaultOn"];
                    break;
#endif// DISABLE_OMEMO
                }
                default:
                    unreachable();
                    break;
            }
            break;
        }
        default:
            unreachable();
            break;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0:
        {
            long row = indexPath.row;
            // + non expanded notification options
            row += (self.isNotificationPrivacyOpened || row == 0) ? 0 : NotificationPrivacyOptionCnt;
            switch(row)
            {
                case 0:
                {
                    [self openNotificationPrivacyFolder];
                    break;
                }
                case 1:
                case 2:
                case 3:
                {
                    MLSwitchCell* cell = [tableView cellForRowAtIndexPath:indexPath];
                    cell.accessoryType = UITableViewCellAccessoryCheckmark;
                    [self setNotificationPrivacyOption:indexPath];
                    [self openNotificationPrivacyFolder];
                    break;
                }
                case 4:
                case 5:
                case 6:
                case 7:
                case 8:
                case 9:
                    break;
                case 10:
                {
                    [self performSegueWithIdentifier:@"fileTransferSettings" sender:nil];
                    break;
                }
                case 11:
                case 12:
                case 13:
                case 14:
                case 15:
                    break;
            }
            break;
        }
        default:
        {
            break;
        }
    }
}

-(IBAction)close:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

-(void)openNotificationPrivacyFolder
{
    if (self.isNotificationPrivacyOpened)
    {
        self.isNotificationPrivacyOpened = NO;
    }
    else
    {
        self.isNotificationPrivacyOpened = YES;
    }
    [self refershTable];
}

-(void)refershTable
{
    [_settingsTable reloadData];
}

-(void)checkStatusForCell:(MLSwitchCell*) cell atIndexPath:(NSIndexPath*) idxPath
{
    NotificationPrivacySettingOption privacySettionOption = (NotificationPrivacySettingOption)[[HelperTools defaultsDB] integerForKey:@"NotificationPrivacySetting"];
    // default: remove checkmark
    cell.accessoryType = UITableViewCellAccessoryNone;
    
    switch (idxPath.row) {
        case DisplayNameAndMessageRow:
            if(privacySettionOption == DisplayNameAndMessage)
            {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            break;
        case DisplayOnlyNameRow:
            if(privacySettionOption == DisplayOnlyName)
            {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            break;
        case DisplayOnlyPlaceholderRow:
            if(privacySettionOption == DisplayOnlyPlaceholder)
            {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            break;
        default:
            break;
    }
}

-(NSString*)getNsNotificationPrivacyOption:(NotificationPrivacySettingOption) option
{
    NSString *optionStr = @"";
    switch (option) {
        case DisplayNameAndMessage:
            optionStr = NSLocalizedString(@"Display Name And Message", @"");
            break;
        case DisplayOnlyName:
            optionStr = NSLocalizedString(@"Display Only Name", @"");
            break;
        case DisplayOnlyPlaceholder:
            optionStr = NSLocalizedString(@"Display Only Placeholder", @"");
            break;
        default:
            break;
    }
    
    return optionStr;
}

-(void)setNotificationPrivacyOption:(NSIndexPath*) idxPath
{
    switch (idxPath.row) {
        case DisplayNameAndMessageRow:
            [[HelperTools defaultsDB] setInteger:DisplayNameAndMessage forKey:@"NotificationPrivacySetting"];
            break;
        case DisplayOnlyNameRow:
            [[HelperTools defaultsDB] setInteger:DisplayOnlyName forKey:@"NotificationPrivacySetting"];
            break;
        case DisplayOnlyPlaceholderRow:
            [[HelperTools defaultsDB] setInteger:DisplayOnlyPlaceholder forKey:@"NotificationPrivacySetting"];
            break;
            
        default:
            break;
    }
    [[HelperTools defaultsDB] synchronize];
}
@end
