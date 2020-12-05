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

typedef NS_ENUM(NSInteger, NSNotificationPrivacyOptionRow) {
    DisplayNameAndMessageRow = 1,
    DisplayOnlyNameRow,
    DisplayOnlyPlaceholderRow
};

@interface MLPrivacySettingsViewController()

@property (nonatomic, strong) NSArray* sectionArray;
@property (nonatomic) BOOL isNotificationPrivacyOpened;

@end

@implementation MLPrivacySettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
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
            if (self.self.isNotificationPrivacyOpened)
            {
                return 11;
            }
            else
            {
                return 8;
            }
            break;
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
    
    MLSettingCell* cell = [[MLSettingCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AccountCell"];
    cell.parent = self;
    
    switch (indexPath.section) {
        case 0:
        {
            switch(indexPath.row)
            {
                case 0:
                {
                    cell = [[MLSettingCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"AccountCell"];
                    cell.textLabel.text = NSLocalizedString(@"Notification", @"");
                    NotificationPrivacySettingOption nOptions = (NotificationPrivacySettingOption)[[HelperTools defaultsDB] integerForKey:@"NotificationPrivacySetting"];
                    cell.detailTextLabel.text = [self getNsNotificationPrivacyOption:nOptions];
                    cell.switchEnabled = NO;
                    break;
                }
                //Notification options
                case 1:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell = [[MLSettingCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"AccountCell"];
                        cell.textLabel.text = [@" - " stringByAppendingString:NSLocalizedString(@"Display Name And Message", @"")];
                        cell.detailTextLabel.text = @"";
                        cell.switchEnabled = NO;
                        cell.textLabel.font = [UIFont systemFontOfSize:14.0];
                        [self checkStatusForCell:cell atIndexPath:indexPath];
                    }
                    else
                    {
                        cell.textLabel.text = NSLocalizedString(@"Show Inline Images", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Will make a HTTP HEAD call on all links", @"");
                        cell.defaultKey = @"ShowImages";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
                case 2:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell = [[MLSettingCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"AccountCell"];
                        cell.textLabel.text = [@" - " stringByAppendingString:NSLocalizedString(@"Display Only Name", @"")];
                        cell.detailTextLabel.text = @"";
                        cell.switchEnabled = NO;
                        cell.textLabel.font = [UIFont systemFontOfSize:14.0];
                        [self checkStatusForCell:cell atIndexPath:indexPath];
                    }
                    else
                    {
                        cell.textLabel.text = NSLocalizedString(@"Show Inline Geo Location", @"");
                        cell.detailTextLabel.text = @"";
                        cell.defaultKey = @"ShowGeoLocation";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
                case 3:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell = [[MLSettingCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"AccountCell"];
                        cell.textLabel.text = [@" - " stringByAppendingString:NSLocalizedString(@"Display Only Placeholder", @"")];
                        cell.detailTextLabel.text = @"";
                        cell.switchEnabled = NO;
                        cell.textLabel.font = [UIFont systemFontOfSize:14.0];
                        [self checkStatusForCell:cell atIndexPath:indexPath];
                    }
                    else
                    {
                        cell.textLabel.text = NSLocalizedString(@"Send Last Interaction Time", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Automatically send when you were online", @"");
                        cell.defaultKey = @"SendLastUserInteraction";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
                case 4:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell.textLabel.text = NSLocalizedString(@"Show Inline Images", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Will make a HTTP HEAD call on all links", @"");
                        cell.defaultKey = @"ShowImages";
                        cell.switchEnabled = YES;
                    }
                    else
                    {
                        cell.textLabel.text = NSLocalizedString(@"Send Typing Notifications", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Tell my contacts when I'm typing", @"");
                        cell.defaultKey = @"SendLastChatState";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
                case 5:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell.textLabel.text = NSLocalizedString(@"Show Inline Geo Location", @"");
                        cell.detailTextLabel.text = @"";
                        cell.defaultKey = @"ShowGeoLocation";
                        cell.switchEnabled = YES;
                    }
                    else
                    {
                        cell.textLabel.text = NSLocalizedString(@"Send message received state", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Tell my contacts if my device received a message", @"");
                        cell.defaultKey = @"SendReceivedMarkers";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
                case 6:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell.textLabel.text = NSLocalizedString(@"Send Last Interaction Time", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Automatically send when you were online", @"");
                        cell.defaultKey = @"SendLastUserInteraction";
                        cell.switchEnabled = YES;
                    }
                    else
                    {
                        cell.textLabel.text = NSLocalizedString(@"Sync Read-Markers", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Tell my contacts if I've read a message", @"");
                        cell.defaultKey = @"SendDisplayedMarkers";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
                case 7:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell.textLabel.text = NSLocalizedString(@"Send Typing Notifications", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Tell my contacts when I'm typing", @"");
                        cell.defaultKey = @"SendLastChatState";
                        cell.switchEnabled = YES;
                    }
                    else
                    {
                        cell.textLabel.text = NSLocalizedString(@"Show URL previews", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Automatically fetch previews of received links", @"");
                        cell.defaultKey = @"ShowURLPreview";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
                case 8:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell.textLabel.text = NSLocalizedString(@"Send message received state", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Tell my contacts if my device received a message", @"");
                        cell.defaultKey = @"SendReceivedMarkers";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
                case 9:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell.textLabel.text = NSLocalizedString(@"Sync Read-Markers", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Tell my contacts if I've read a message", @"");
                        cell.defaultKey = @"SendDisplayedMarkers";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
                case 10:
                {
                    if (self.isNotificationPrivacyOpened)
                    {
                        cell.textLabel.text = NSLocalizedString(@"Show URL previews", @"");
                        cell.detailTextLabel.text = NSLocalizedString(@"Automatically fetch previews of received links", @"");
                        cell.defaultKey = @"ShowURLPreview";
                        cell.switchEnabled = YES;
                    }
                    break;
                }
            }
            break;
        }
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0:
        {
            switch(indexPath.row)
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
                    if (self.isNotificationPrivacyOpened)
                    {
                        MLSettingCell* cell = [tableView cellForRowAtIndexPath:indexPath];
                        cell.accessoryType = UITableViewCellAccessoryCheckmark;
                        [self setNotificationPrivacyOption:indexPath];
                        [self openNotificationPrivacyFolder];
                    }
                    break;
                }
                case 4:
                case 5:
                case 6:
                case 7:
                case 8:
                {
                    break;
                }
                case 9:
                {
                    break;
                }
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

-(void)checkStatusForCell:(MLSettingCell*) settingCell atIndexPath:(NSIndexPath*) idxPath
{
    NotificationPrivacySettingOption privacySettionOption = (NotificationPrivacySettingOption)[[HelperTools defaultsDB] integerForKey:@"NotificationPrivacySetting"];
    
    switch (idxPath.row) {
        case DisplayNameAndMessageRow:
            if (privacySettionOption == DisplayNameAndMessage )
            {
                settingCell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            else
            {
                settingCell.accessoryType = UITableViewCellAccessoryNone;
            }
            break;
        case DisplayOnlyNameRow:
            if (privacySettionOption == DisplayOnlyName )
            {
                settingCell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            else
            {
                settingCell.accessoryType = UITableViewCellAccessoryNone;
            }
            break;
        case DisplayOnlyPlaceholderRow:
            if (privacySettionOption == DisplayOnlyPlaceholder )
            {
                settingCell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            else
            {
                settingCell.accessoryType = UITableViewCellAccessoryNone;
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
