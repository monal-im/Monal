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
            return 9 + (self.isNotificationPrivacyOpened ? NotificationPrivacyOptionCnt : 0);
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
            row += self.isNotificationPrivacyOpened ? 0 : NotificationPrivacyOptionCnt;

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
                    [cell initCell:NSLocalizedString(@"Show Inline Images", @"") withToggleDefaultsKey:@"ShowImages"];
                    break;
                }
                case 5:
                {
                    [cell initCell:NSLocalizedString(@"Show Inline Geo Location", @"") withToggleDefaultsKey:@"ShowGeoLocation"];
                    break;
                }
                case 6:
                {
                    [cell initCell:NSLocalizedString(@"Send Last Interaction Time", @"") withToggleDefaultsKey:@"SendLastUserInteraction"];
                    break;
                }
                case 7:
                {
                    [cell initCell:NSLocalizedString(@"Send Typing Notifications", @"") withToggleDefaultsKey:@"SendLastChatState"];
                    break;
                }
                case 8:
                {
                    [cell initCell:NSLocalizedString(@"Send message received state", @"") withToggleDefaultsKey:@"SendReceivedMarkers"];
                    break;
                }
                case 9:
                {
                    [cell initCell:NSLocalizedString(@"Sync Read-Markers", @"") withToggleDefaultsKey:@"SendDisplayedMarkers"];
                    break;
                }
                case 10:
                {
                    [cell initCell:NSLocalizedString(@"Show URL previews", @"") withToggleDefaultsKey:@"ShowURLPreview"];
                    break;
                }
                case 11:
                {
                    MLSettingCell* mediaCell = [[MLSettingCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AutoDownloadMediaCell"];
                    mediaCell.textLabel.text = NSLocalizedString(@"Auto-Download Media", @"");
                    BOOL isAutoDownLoadFiletransfers = [[HelperTools defaultsDB] boolForKey:@"AutodownloadFiletransfers"];
                    if (!isAutoDownLoadFiletransfers) {
                        mediaCell.detailTextLabel.text = NSLocalizedString(@"Disabled", @"");
                    } else {
                        NSInteger maxSize = [[HelperTools defaultsDB] integerForKey:@"AutodownloadFiletransfersMaxSize"];
                        NSString *readableFileSize = [NSString stringWithFormat:@"%ld", maxSize/(1024*1024)];
                        mediaCell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@ MB", NSLocalizedString(@"Up to", @""), readableFileSize];
                    }
                    mediaCell.detailTextLabel.textColor = [UIColor lightGrayColor];
                    mediaCell.defaultKey = @"AutodownloadFiletransfers";
                    mediaCell.switchEnabled = NO;
                    mediaCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    return mediaCell;
                }
            }
            break;
        }
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
            row += self.isNotificationPrivacyOpened ? 0 : NotificationPrivacyOptionCnt;
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
                case 10:
                    break;
                case 11:
                {
                    [self performSegueWithIdentifier:@"fileTransferSettings" sender:nil];
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
