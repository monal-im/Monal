//
//  MLNotificationSettingsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/31/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLNotificationSettingsViewController.h"
#import "MLSwitchCell.h"
#import "MLXMPPManager.h"
#import "xmpp.h"
#import "DataLayer.h"

@import UserNotifications;


enum {
    kNotificationSettingSectionApplePush,
    kNotificationSettingSectionNotifications,
    kNotificationSettingSectionMonalPush,
    kNotificationSettingSectionAccounts,
    kNotificationSettingSectionAdvanced,
    kNotificationSettingSectionCount
};

@interface MLNotificationSettingsViewController ()
@property (nonatomic, strong) NSArray* sectionsHeaders;
@property (nonatomic, strong) NSArray* sectionsFooters;
@property (nonatomic, strong) NSString* apple;
@property (nonatomic, strong) NSString* notifications;
@property (nonatomic, strong) NSString* monal;
@property (nonatomic, strong) NSString* advanced;
@property (nonatomic, assign) BOOL canShowNotifications;

@end

@implementation MLNotificationSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sectionsFooters = @[
        NSLocalizedString(@"Apple push service should always be on. If it is off, your device can not talk to Apple's server.", @""),
        NSLocalizedString(@"If Monal can't show notifications, you will not see alerts when a message arrives. This happens if you tapped 'Decline' when Monal first asked permission. Fix it by going to iOS Settings -> Monal -> Notifications and select 'Allow Notifications'.", @""),
        [NSString stringWithFormat:NSLocalizedString(@"If Monal push is off, your device could not talk to %@ through xmpp. This should also never be off. It requires Apple push service to work first.", @""), [HelperTools pushServer][@"jid"]],
        NSLocalizedString(@"If this is off your device could not activate push on your xmpp server, make sure to have configured it to support XEP-0357.", @""),
        @""
    ];
    
    self.sectionsHeaders = @[
        @"",
        @"",
        @"",
        NSLocalizedString(@"Accounts", @""),
        NSLocalizedString(@"Advanced", @"")
    ];
    
    self.apple = NSLocalizedString(@"Apple Push Service", @"");
    self.notifications = NSLocalizedString(@"Can Show Notifications", @"");
    self.monal = NSLocalizedString(@"Monal Push Server", @"");
    self.advanced = NSLocalizedString(@"Mark all messages as read", @"");

    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
}

-(void) viewWillAppear:(BOOL) animated
{
    [super viewWillAppear:animated];
    
    self.navigationItem.title = NSLocalizedString(@"Notification Settings", @"");
    UNUserNotificationCenter* notificationSettings = [UNUserNotificationCenter currentNotificationCenter];

    [notificationSettings getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
        if(settings.alertSetting == UNNotificationSettingEnabled)
            self.canShowNotifications = YES;
        else
            self.canShowNotifications = NO;
    }];
}


-(void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - Table view data source

-(NSInteger) numberOfSectionsInTableView:(UITableView*) tableView
{
    return kNotificationSettingSectionCount;
}

-(NSInteger) tableView:(UITableView*) tableView numberOfRowsInSection:(NSInteger) section
{
    switch(section)
    {
        case kNotificationSettingSectionNotifications: return 1;
        case kNotificationSettingSectionApplePush: return 1;
        case kNotificationSettingSectionMonalPush: return 1;
        case kNotificationSettingSectionAccounts: return [MLXMPPManager sharedInstance].connectedXMPP.count;
        case kNotificationSettingSectionAdvanced: return 1;
        default: unreachable(); return 0;
    }
}

-(NSString*) tableView:(UITableView*) tableView titleForHeaderInSection:(NSInteger) section
{
    return self.sectionsHeaders[section];
}

-(NSString*) tableView:(UITableView*) tableView titleForFooterInSection:(NSInteger) section
{
    return self.sectionsFooters[section];
}

-(UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    switch(indexPath.section)
    {
        case kNotificationSettingSectionNotifications: {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            cell.imageView.hidden = NO;
            cell.textLabel.text = self.notifications;
            if(self.canShowNotifications)
                cell.imageView.image = [UIImage imageNamed:@"888-checkmark"];
            else
               cell.imageView.image = [UIImage imageNamed:@"disabled"];
            return cell;
        }
        case kNotificationSettingSectionApplePush: {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            if([MLXMPPManager sharedInstance].hasAPNSToken)
                cell.imageView.image = [UIImage imageNamed:@"888-checkmark"];
            else
                cell.imageView.image = [UIImage imageNamed:@"disabled"];
            cell.imageView.hidden = NO;
            cell.textLabel.text = self.apple;
            return cell;
        }
        case kNotificationSettingSectionMonalPush: {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            BOOL ticked = YES;
            for(xmpp* xmppAccount in [MLXMPPManager sharedInstance].connectedXMPP)
                if(!xmppAccount.connectionProperties.registeredOnPushAppserver)
                    ticked = NO;
            if(ticked)
                cell.imageView.image = [UIImage imageNamed:@"888-checkmark"];
            else
               cell.imageView.image = [UIImage imageNamed:@"disabled"];
            cell.textLabel.text = self.monal;
            cell.imageView.hidden = NO;
            return cell;
        }
        case kNotificationSettingSectionAccounts: {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            xmpp* xmppAccount = [MLXMPPManager sharedInstance].connectedXMPP[indexPath.row];
            cell.textLabel.text = xmppAccount.connectionProperties.identity.jid;
            if(xmppAccount.connectionProperties.pushEnabled)
                cell.imageView.image = [UIImage imageNamed:@"888-checkmark"];
            else
                cell.imageView.image = [UIImage imageNamed:@"disabled"];
            cell.imageView.hidden = NO;
            return cell;
        }
        case kNotificationSettingSectionAdvanced: {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            cell.imageView.hidden = YES;
            cell.textLabel.text = self.advanced;
            return cell;
        }
        default:
            unreachable();
            return [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
    }
}


-(void) tableView:(UITableView*) tableView didSelectRowAtIndexPath:(NSIndexPath*) indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    switch(indexPath.section)
    {
        case kNotificationSettingSectionAdvanced: {
            switch(indexPath.row) {
                // Mark all messages as read
                case 0: {
                    [[DataLayer sharedInstance] setAllMessagesAsRead];
                    break;
                }
                default:
                    break;
            }
            break;
        }
    }
}


@end
