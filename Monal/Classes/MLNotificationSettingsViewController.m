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
#import "MLPush.h"
#import "DataLayer.h"

@import UserNotifications;


NS_ENUM(NSInteger, kNotificationSettingSection)
{
    kNotificationSettingSectionApplePush=0,
    kNotificationSettingSectionUser,
    kNotificationSettingSectionMonalPush,
    kNotificationSettingSectionAccounts,
    kNotificationSettingSectionAdvanced,
    kNotificationSettingSectionCount
};



@interface MLNotificationSettingsViewController ()
@property (nonatomic, strong) NSArray* sectionsHeaders;
@property (nonatomic, strong) NSArray* sectionsFooters;
@property (nonatomic, strong) NSArray* apple;
@property (nonatomic, strong) NSArray* user;
@property (nonatomic, strong) NSArray* monal;
@property (nonatomic, strong) NSArray* advanced;


@property (nonatomic, assign) BOOL canShowNotifications;

@end

@implementation MLNotificationSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sectionsFooters = @[NSLocalizedString(@"Apple push service should always be on. If it is off, your device can not talk to Apple's server.", @""),
                     NSLocalizedString(@"If Monal can't show notifications, you will not see alerts when a message arrives. This happens if you tapped 'Decline' when Monal first asked permission.  Fix it by going to iOS Settings -> Monal -> Notifications and select 'Allow Notifications'. ", @""),
                     NSLocalizedString(@"If Monal push is off, your device could not talk to push.monal.im. This should also never be off. It requires Apple push service to work first. ", @""),
                     NSLocalizedString(@"Rebuilding is useful if you are experiencing problems. This will require an app restart to work.", @""),
                            @""];
    
    self.sectionsHeaders = @[@"",
                            @"",
                            @"",
                            NSLocalizedString(@"Accounts", @""),
                            NSLocalizedString(@"Advanced", @"")];
    
    self.apple = @[NSLocalizedString(@"Apple Push Service", @"")];
    self.user = @[NSLocalizedString(@"Can Show Notifications", @"")];
    self.monal = @[NSLocalizedString(@"Monal Push Server", @"")];

    self.advanced = @[NSLocalizedString(@"Rebuild Tokens", @ ""),
                    NSLocalizedString(@"Mark all messages as read", @ "")];

    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.navigationItem.title = NSLocalizedString(@"Notification Settings", @"");
    UNUserNotificationCenter* notificationSettings = [UNUserNotificationCenter currentNotificationCenter];

    [notificationSettings getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
        if(settings.alertSetting == UNNotificationSettingEnabled) {
            self.canShowNotifications = YES;
        } else {
            self.canShowNotifications = NO;
        }
    }];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kNotificationSettingSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger toreturn = 0;
    switch(section)
    {
        case kNotificationSettingSectionUser: {
            toreturn = self.user.count;
            break;
        }
        case kNotificationSettingSectionApplePush: {
            toreturn = self.apple.count;
            break;
        }
        case kNotificationSettingSectionMonalPush: {
            toreturn = self.monal.count;
            break;
        }
            
        case kNotificationSettingSectionAccounts: {
            toreturn = [MLXMPPManager sharedInstance].connectedXMPP.count;
            break;
        }
        case kNotificationSettingSectionAdvanced: {
            toreturn = self.advanced.count;
            break;
        }
            
    }
    
    return toreturn;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *toreturn= self.sectionsHeaders[section];
    return toreturn;
}

-(NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString* toreturn = self.sectionsFooters[section];
    return toreturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell* toreturn = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
    switch(indexPath.section)
    {
        case kNotificationSettingSectionUser: {
            
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            cell.imageView.hidden = NO;
            cell.textLabel.text = self.user[0];
            if(self.canShowNotifications) {
                cell.imageView.image = [UIImage imageNamed:@"888-checkmark"];
            }
            else  {
               cell.imageView.image = [UIImage imageNamed:@"disabled"];
            }
            toreturn=cell;
            break;
        }
        case kNotificationSettingSectionApplePush: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
           
            cell.textLabel.text = self.apple[0];
            
            if([MLXMPPManager sharedInstance].hasAPNSToken) {
                 cell.imageView.image = [UIImage imageNamed:@"888-checkmark"];
            }
            else  {
                cell.imageView.image = [UIImage imageNamed:@"disabled"];
            }
            cell.imageView.hidden = NO;
            toreturn = cell;
            break;
        }
        case kNotificationSettingSectionMonalPush: {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            if([MLXMPPManager sharedInstance].pushNode) {
                cell.imageView.image=[UIImage imageNamed:@"888-checkmark"];
            }
            else  {
               cell.imageView.image=[UIImage imageNamed:@"disabled"];
            }
            cell.imageView.hidden = NO;
            cell.textLabel.text = self.monal[0];
            toreturn = cell;
            break;
        }
            
        case kNotificationSettingSectionAccounts: {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            cell.imageView.hidden=NO;
            xmpp* xmppAccount = [MLXMPPManager sharedInstance].connectedXMPP[indexPath.row];
            cell.textLabel.text = xmppAccount.connectionProperties.identity.jid;
            
            if(xmppAccount.connectionProperties.pushEnabled) {
                cell.imageView.image = [UIImage imageNamed:@"888-checkmark"];
            }
            else  {
                cell.imageView.image = [UIImage imageNamed:@"disabled"];
            }
            
            toreturn = cell;
            break;
        }
            
        case kNotificationSettingSectionAdvanced: {
            UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
            cell.imageView.hidden = YES;
            cell.textLabel.text = self.advanced[indexPath.row];

            toreturn = cell;
            break;
        }
    }
    return toreturn;
}


-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    switch(indexPath.section)
    {
        case kNotificationSettingSectionAdvanced: {
            switch(indexPath.row) {
                // Rebuild Tokens
                case 0: {
                    MLPush* push = [[MLPush alloc] init];
                    [push unregisterPush];
                    break;
                }
                // Mark all messages as read
                case 1: {
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
