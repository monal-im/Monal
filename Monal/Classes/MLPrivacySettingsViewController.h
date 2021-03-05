//
//  MLPrivacySettingsViewController.h
//  Monal
//
//  Created by Friedrich Altheide on 06.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLSettingCell.h"
#import <Foundation/Foundation.h>
#import "MLAutoDownloadFiletransferSettingViewController.h"
NS_ASSUME_NONNULL_BEGIN

@interface MLPrivacySettingsViewController : UITableViewController <UITextFieldDelegate>
{
    UITextField* _currentField;
}

@property (nonatomic, strong) UITableView* settingsTable;

-(IBAction)close:(id)sender ;

@end

NS_ASSUME_NONNULL_END
