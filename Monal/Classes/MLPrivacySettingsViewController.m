//
//  MLPrivacySettingsViewController.m
//  Monal
//
//  Created by Friedrich Altheide on 06.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPrivacySettingsViewController.h"
#import "HelperTools.h"

@interface MLPrivacySettingsViewController()

@property (nonatomic, strong) NSArray* sectionArray;

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

    self.sectionArray = @[NSLocalizedString(@"General", @"")];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
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
            return 6;
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
                    cell.textLabel.text = NSLocalizedString(@"Show Inline Images", @"");
                    cell.detailTextLabel.text = NSLocalizedString(@"Will make a HTTP HEAD call on all links", @"");
                    cell.defaultKey = @"ShowImages";
                    cell.switchEnabled = YES;
                    break;
                }
                case 1:
                {
                    cell.textLabel.text = NSLocalizedString(@"Show Inline Geo Location", @"");
                    cell.detailTextLabel.text = @"";
                    cell.defaultKey = @"ShowGeoLocation";
                    cell.switchEnabled = YES;
                    break;
                }
                case 2:
                {
                    cell.textLabel.text = NSLocalizedString(@"Send Last Interaction Time", @"");
                    cell.detailTextLabel.text = NSLocalizedString(@"Automatically send when you were online", @"");
                    cell.defaultKey = @"SendLastUserInteraction";
                    cell.switchEnabled = YES;
                    break;
                }
                case 3:
                {
                    cell.textLabel.text = NSLocalizedString(@"Send Typing Notifications", @"");
                    cell.detailTextLabel.text = NSLocalizedString(@"Tell my contacts when I'm typing", @"");
                    cell.defaultKey = @"SendLastChatState";
                    cell.switchEnabled = YES;
                    break;
                }
                case 4:
                {
                    cell.textLabel.text = NSLocalizedString(@"Send message received state", @"");
                    cell.detailTextLabel.text = NSLocalizedString(@"Tell my contacts if my device received a message", @"");
                    cell.defaultKey = @"SendReceivedMarkers";
                    cell.switchEnabled = YES;
                    break;
                }
                case 5:
                {
                    cell.textLabel.text = NSLocalizedString(@"Sync Read-Markers", @"");
                    cell.detailTextLabel.text = NSLocalizedString(@"Tell my contacts if I've read a message", @"");
                    cell.defaultKey = @"SendDisplayedMarkers";
                    cell.switchEnabled = YES;
                    break;
                }
            }
            break;
        }
        default:
        {
            return nil;
            break;
        }
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

-(IBAction)close:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
