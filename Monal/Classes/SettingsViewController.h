//
//  SettingsViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import <UIKit/UIKit.h>
#import "MLSettingCell.h"

@interface SettingsViewController : UITableViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
{
    UITextField* _currentField;
}

@property (nonatomic, strong) UITableView* settingsTable;

@end
