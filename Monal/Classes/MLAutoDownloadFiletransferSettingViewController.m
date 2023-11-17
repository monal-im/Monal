//
//  MLAutoDownloadFiletransferSettingViewController.m
//  Monal
//
//  Created by jim on 2021/3/5.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLAutoDownloadFiletransferSettingViewController.h"
#import "MLSwitchCell.h"

enum MLAutoDownloadFiletransferSettingViewController {
    FiletransferSettingsGeneralSettings,
    FiletransferSettingsAdvancedDownloadSettings,
    FiletransferSettingsAdvancedUploadSettings,
    FiletransferSettingSectionCnt
};

@interface MLAutoDownloadFiletransferSettingViewController ()
{
    UITableView* filetransferSettingTableView;
    UILabel* sliderResultLabel;
    UISlider* slider;
}
@end

@implementation MLAutoDownloadFiletransferSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell" bundle:[NSBundle mainBundle]] forCellReuseIdentifier:@"AccountCell"];
    
    self.navigationItem.title = NSLocalizedString(@"Auto-Download Media", @"");
}

-(nullable NSString*) tableView:(UITableView*) tableView titleForHeaderInSection:(NSInteger) section
{
    NSString* sectionTitle = nil;
    switch(section)
    {
        case FiletransferSettingsGeneralSettings:
            sectionTitle = NSLocalizedString(@"General File Transfer Settings", @"");
            break;
        case FiletransferSettingsAdvancedDownloadSettings:
            sectionTitle = NSLocalizedString(@"Download Settings", @"");
            break;
        case FiletransferSettingsAdvancedUploadSettings:
            sectionTitle = NSLocalizedString(@"Upload Settings", @"");
            break;
        default:
            break;
    }
    
    return sectionTitle;
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return FiletransferSettingSectionCnt;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch(section)
    {
        case FiletransferSettingsGeneralSettings:
            return 1;
        case FiletransferSettingsAdvancedDownloadSettings:
            return 2;
        case FiletransferSettingsAdvancedUploadSettings:
            return 1;
        default:
            unreachable();
            break;
    }
    unreachable();
    return 0;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLSwitchCell* cell = (MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
    [cell clear];

    switch(indexPath.section)
    {
        case FiletransferSettingsGeneralSettings:
            switch(indexPath.row)
            {
                case 0:
                {
                    [cell initCell:NSLocalizedString(@"Auto-Download Media", @"") withToggleDefaultsKey:@"AutodownloadFiletransfers"];
                    break;
                }
                default:
                    unreachable();
            }
            break;
        case FiletransferSettingsAdvancedDownloadSettings:
            switch(indexPath.row)
            {
                case 0:
                {
                    [cell initCell:NSLocalizedString(@"Load over WiFi upto", @"") withSliderDefaultsKey:@"AutodownloadFiletransfersWifiMaxSize" minValue:1.0 maxValue:100.0 withLoadFunc:^(UILabel* labelToUpdate, float sliderValue) {
                        // byte -> mb
                        float mb = sliderValue / 1024 / 1024;
                        labelToUpdate.text = [NSString stringWithFormat:NSLocalizedString(@"Load over WiFi upto: %.fMB", @""), mb];

                        return mb;
                    } withUpdateFunc:^(UILabel* labelToUpdate, float sliderValue) {
                        float newValue = roundf(sliderValue);
                        labelToUpdate.text = [NSString stringWithFormat:NSLocalizedString(@"Load over WiFi upto: %.fMB", @""), newValue];
                        return newValue * 1024 * 1024;
                    }];
                    break;
                }
                case 1:
                {
                    [cell initCell:NSLocalizedString(@"Load over cellular upto", @"") withSliderDefaultsKey:@"AutodownloadFiletransfersMobileMaxSize" minValue:1.0 maxValue:100.0  withLoadFunc:^(UILabel* labelToUpdate, float sliderValue) {
                        // byte -> mb
                        float mb = sliderValue / 1024 / 1024;
                        labelToUpdate.text = [NSString stringWithFormat:NSLocalizedString(@"Load over cellular upto: %.fMB", @""), mb];
                        
                        return mb;
                    } withUpdateFunc:^(UILabel* labelToUpdate, float sliderValue) {
                        float newValue = roundf(sliderValue);
                        labelToUpdate.text = [NSString stringWithFormat:NSLocalizedString(@"Load over cellular upto: %.fMB", @""), newValue];
                        // save in MB
                        return newValue * 1024 * 1024;
                    }];
                    break;
                }
                default:
                    unreachable();
                    break;
            }
            break;
        case FiletransferSettingsAdvancedUploadSettings:
            switch(indexPath.row)
            {
                case 0:
                {
                    [cell initCell:NSLocalizedString(@"Image Upload Quality", @"") withSliderDefaultsKey:@"ImageUploadQuality" minValue:0.33f maxValue:1.0  withLoadFunc:^(UILabel* labelToUpdate, float sliderValue) {
                        float rate = roundf(sliderValue * 100) / 100;
                        labelToUpdate.text = [NSString stringWithFormat:NSLocalizedString(@"Image Upload Quality: %.2f", @""), rate];
                        return rate;
                    } withUpdateFunc:^(UILabel* labelToUpdate, float sliderValue) {
                        float rate = roundf(sliderValue * 100) / 100;
                        labelToUpdate.text = [NSString stringWithFormat:NSLocalizedString(@"Image Upload Quality: %.2f", @""), rate];
                        return rate;
                    }];
                    break;
                }
                default:
                    unreachable();
                    break;
            }
            break;
        default:
            unreachable();
    }
    return cell;
}

-(void) sliderValueChanged:(UISlider*) slider
{
    int maxFileSize = (int)slider.value;
    [sliderResultLabel setText:[NSString stringWithFormat:@"%d MB", maxFileSize]];
    [sliderResultLabel adjustsFontSizeToFitWidth];
    [[HelperTools defaultsDB] setInteger:(maxFileSize * 1024 * 1024) forKey:@"AutodownloadFiletransfersMaxSize"];
}

-(void) updateUI
{
    BOOL isAutodownloadFiletransfers = [[HelperTools defaultsDB] boolForKey:@"AutodownloadFiletransfers"];
    [slider setUserInteractionEnabled:isAutodownloadFiletransfers];
}

@end
