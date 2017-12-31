//
//  MLNotificationSettingsViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/31/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLNotificationSettingsViewController.h"

NS_ENUM(NSInteger, kNotificationSettingSection)
{
    kNotificationSettingSectionApplePush=0,
    kNotificationSettingSectionUser,
    kNotificationSettingSectionMonalPush,
    kNotificationSettingSectionAccounts,
    kNotificationSettingSectionCount
};

@interface MLNotificationSettingsViewController ()
@property (nonatomic, strong) NSArray *sections;
@end

@implementation MLNotificationSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sections =@[@"Apple", @"Alerts", @"Monal Push", @"Accounts"];
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
    
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
            toreturn=0;// self.appRows.count;
            break;
        }
        case kNotificationSettingSectionApplePush: {
            toreturn=0;//  self.supportRows.count;
            break;
        }
        case kNotificationSettingSectionMonalPush: {
            toreturn= 0 ;//self.aboutRows.count;
            break;
        }
            
        case kNotificationSettingSectionAccounts: {
            toreturn= 0; //self.aboutRows.count;
            break;
        }
            
    }
    
    return toreturn;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *toreturn= self.sections[section];
    return toreturn;
}





@end
