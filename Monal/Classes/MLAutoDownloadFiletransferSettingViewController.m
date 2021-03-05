//
//  MLAutoDownloadFiletransferSettingViewController.m
//  Monal
//
//  Created by jim on 2021/3/5.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLAutoDownloadFiletransferSettingViewController.h"

@interface MLAutoDownloadFiletransferSettingViewController ()
{
    UITableView *filetransferSettingTableView;
    UILabel *sliderResultLabel;
    UISlider *slider;
}
@end

@implementation MLAutoDownloadFiletransferSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = NSLocalizedString(@"Auto-Download Media", @"");
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    //CGFloat navHeight = self.navigationController.navigationBar.frame.size.height;
    filetransferSettingTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, [[UIScreen mainScreen] bounds].size.width, [[UIScreen mainScreen] bounds].size.height) style:UITableViewStyleGrouped];
    filetransferSettingTableView.delegate = self;
    filetransferSettingTableView.dataSource = self;
    
    [filetransferSettingTableView registerClass:[UITableViewCell self] forCellReuseIdentifier:@"settingsCell"];
    [self.view addSubview:filetransferSettingTableView];
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *sectionTitle = @"";
    switch (section) {
        
        case 1:
            sectionTitle = NSLocalizedString(@"Maximum File Transfer Size", @"");
            break;
        default:
            break;
    }
    
    return sectionTitle;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"settingsCell" forIndexPath:indexPath];
    
    switch (indexPath.section) {
        case 0:
        {
            cell = [[MLSettingCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"AccountCell"];                        
            MLSettingCell *autoDownloadCell = (MLSettingCell *)cell;
            autoDownloadCell.SettingCellDelegate = self;
            autoDownloadCell.defaultKey = @"AutodownloadFiletransfers";
            autoDownloadCell.switchEnabled = YES;
            autoDownloadCell.textLabel.text = NSLocalizedString(@"Auto-Download Media", @"");
        }
            break;
        case 1:
        {
            UILabel *minLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 50, 15)];
            [minLabel setText:NSLocalizedString(@"1 MB", @"")];
            [minLabel adjustsFontSizeToFitWidth];
            [minLabel setTextColor:[UIColor grayColor]];
            [cell.contentView addSubview:minLabel];
            
            UILabel *maxLabel = [[UILabel alloc] initWithFrame:CGRectMake(290, 20, 70, 15)];
            [maxLabel setText:NSLocalizedString(@"100 MB", @"")];
            [maxLabel adjustsFontSizeToFitWidth];
            [maxLabel setTextColor:[UIColor grayColor]];
            [cell.contentView addSubview:maxLabel];
            
            sliderResultLabel = [[UILabel alloc] initWithFrame:CGRectMake(120, 1, 100, 13)];
            [sliderResultLabel setTextAlignment:NSTextAlignmentCenter];
            [sliderResultLabel setTextColor:[UIColor grayColor]];
            
            [cell.contentView addSubview:sliderResultLabel];
            
            slider = [[UISlider alloc] init];
            slider.frame = CGRectMake(80, 20, 200, 20);
            [self updateUI];
            
            slider.minimumValue = 1;
            slider.maximumValue = 100;
            NSInteger maxSize = [[HelperTools defaultsDB] integerForKey:@"AutodownloadFiletransfersMaxSize"];
            slider.value = maxSize/(1024*1024);
            
            NSString *readableFileSize = [NSString stringWithFormat:@"%ld", maxSize/(1024*1024)];
            
            [sliderResultLabel setText:[NSString stringWithFormat:@"%@ MB", readableFileSize]];
            [sliderResultLabel adjustsFontSizeToFitWidth];
            
            [slider setContinuous:YES];
            
            [slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:slider];
        }
            break;
        default:
            break;
    }
    return cell;
}

-(void)sliderValueChanged:(UISlider*) slider
{
    float sliderValue = slider.value;
    float maxValue = (int)sliderValue;
    [sliderResultLabel setText:[NSString stringWithFormat:@"%ld MB", (long)maxValue]];
    [sliderResultLabel adjustsFontSizeToFitWidth];
    [[HelperTools defaultsDB] setInteger:(maxValue*1024*1024) forKey:@"AutodownloadFiletransfersMaxSize"];
}

-(void)updateUI{
    BOOL isAutodownloadFiletransfers = [[HelperTools defaultsDB] boolForKey:@"AutodownloadFiletransfers"];
    if (isAutodownloadFiletransfers){
        [slider setUserInteractionEnabled:YES];
    } else {
        [slider setUserInteractionEnabled:NO];
    }
}

@end
