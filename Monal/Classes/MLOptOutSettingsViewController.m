//
//  MLCloudSettingsTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/31/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLOptOutSettingsViewController.h"
#import "MLSettingCell.h"

@interface MLOptOutSettingsViewController ()

@end

@implementation MLOptOutSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=NSLocalizedString(@"Opt Out",@ "");
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

-(NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return NSLocalizedString(@"Select services to opt out of",@ "");
}

-(NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return NSLocalizedString(@"Monal uses Crashlytics to track crashes. These are anonymous, GDPR compliant and help debug issues. Per GDPR, you may opt out of this logging. Because I will not be able to see the cause of your crashes, opting out here effectively opts you out of receiving support if you encounter issues.",@ "") ;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    MLSettingCell* cell=[[MLSettingCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AccountCell"];
    cell.parent= self;
    cell.switchEnabled=YES;
    cell.defaultKey=@"CrashlyticsOptOut";
    cell.textLabel.text=@"Crashlytics";
    
    return cell;
}









@end
