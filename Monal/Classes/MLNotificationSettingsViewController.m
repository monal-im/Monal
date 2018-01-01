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
@import UserNotificationsUI;

NS_ENUM(NSInteger, kNotificationSettingSection)
{
    kNotificationSettingSectionApplePush=0,
    kNotificationSettingSectionUser,
    kNotificationSettingSectionMonalPush,
    kNotificationSettingSectionAccounts,
    kNotificationSettingSectionCount
};

@interface MLNotificationSettingsViewController ()
@property (nonatomic, strong) NSArray *sectionsHeaders;
@property (nonatomic, strong) NSArray *sectionsFooters;
@property (nonatomic, strong) NSArray *apple;
@property (nonatomic, strong) NSArray *user;
@property (nonatomic, strong) NSArray *monal;


@property (nonatomic, assign) BOOL canShowNotifications;

@end

@implementation MLNotificationSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sectionsFooters =@[@"Apple push service should always be on. If it is off, your device can not talk to Apple's server.",
                     @"If Monal can't show notifications, you will not see alerts when a message arrives. This happens if you tapped 'Decline' when Monal first asked permission.  Fix it by going to iOS Settings -> Monal -> Notifications and select 'Allow Notifications'. ",
                     @"If Monal push is off, your device could not talk to push.monal.im. This should also never be off. It requires Apple push service to work first. ",
                     @""];
    
    self.sectionsHeaders =@[@"",
                            @"",
                            @"",
                            @"Accounts"];
    
    self.apple=@[@"Apple Push Service"];
     self.user=@[@"Can Show Notifications"];
     self.monal=@[@"Monal Push Server"];
   
    
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
    
}

-(void) viewWillAppear:(BOOL)animated
{
    self.navigationItem.title = NSLocalizedString(@"Notification Settings",@"");

    //TODO when ios 9 is dropped switch this to new API
    // [UNUserNotificationCenter getNotificationSettingsWithCompletionHandler:]
    UIUserNotificationSettings *notificationSettings= [[UIApplication sharedApplication] currentUserNotificationSettings];
    
    if (notificationSettings.types == UIUserNotificationTypeNone) {
        self.canShowNotifications=NO;
    }
    else if (notificationSettings.types  & UIUserNotificationTypeAlert){
      self.canShowNotifications=YES;
    }
    
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
    NSInteger toreturn=0;
    switch(section)
    {
        case kNotificationSettingSectionUser: {
            toreturn=self.user.count;
            break;
        }
        case kNotificationSettingSectionApplePush: {
            toreturn=self.apple.count;
            break;
        }
        case kNotificationSettingSectionMonalPush: {
            toreturn= self.monal.count;
            break;
        }
            
        case kNotificationSettingSectionAccounts: {
            toreturn= [MLXMPPManager sharedInstance].connectedXMPP.count;
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
    NSString *toreturn= self.sectionsFooters[section];
    return toreturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell *toreturn=[tableView dequeueReusableCellWithIdentifier:@"descriptionCell"];
    switch(indexPath.section)
    {
        case kNotificationSettingSectionUser: {
            
            MLSwitchCell *cell= [tableView dequeueReusableCellWithIdentifier:@"switchCell"];
            cell.toggleSwitch.enabled=NO;
            cell.cellLabel.text = self.user[0];
            if(self.canShowNotifications) {
                cell.toggleSwitch.on=YES;
            }
            else  {
                cell.toggleSwitch.on=NO;
            }
            toreturn=cell;
            break;
        }
        case kNotificationSettingSectionApplePush: {
            MLSwitchCell *cell= [tableView dequeueReusableCellWithIdentifier:@"switchCell"];
            cell.toggleSwitch.enabled=NO;
            cell.cellLabel.text = self.apple[0];
            
            if([MLXMPPManager sharedInstance].hasAPNSToken) {
                cell.toggleSwitch.on=YES;
            }
            else  {
                cell.toggleSwitch.on=NO;
            }
            
            toreturn=cell;
            break;
        }
        case kNotificationSettingSectionMonalPush: {
            MLSwitchCell *cell= [tableView dequeueReusableCellWithIdentifier:@"switchCell"];
            cell.toggleSwitch.enabled=NO;
         
            if([MLXMPPManager sharedInstance].pushNode) {
                cell.toggleSwitch.on=YES;
            }
            else  {
                cell.toggleSwitch.on=NO;
            }
            cell.cellLabel.text = self.monal[0];
            toreturn=cell;
            break;
        }
            
        case kNotificationSettingSectionAccounts: {
            MLSwitchCell *cell= [tableView dequeueReusableCellWithIdentifier:@"switchCell"];
            cell.toggleSwitch.enabled=NO;
            NSDictionary  *row = [MLXMPPManager sharedInstance].connectedXMPP[indexPath.row];
            xmpp *xmppAccount = [row objectForKey:@"xmppAccount"];
            cell.cellLabel.text =xmppAccount.fulluser;
            
            cell.toggleSwitch.on = xmppAccount.pushEnabled; 
            
            toreturn=cell;
            break;
        }
            
    }
    
    return toreturn;
    
}





@end
