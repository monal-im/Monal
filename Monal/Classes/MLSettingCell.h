//
//  MLSettingCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 7/23/13.
//
//

#import <UIKit/UIKit.h>

@protocol MLSettingCellDelegate

-(void)updateUI;

@end

@interface MLSettingCell : UITableViewCell <UITextFieldDelegate>

@property (nonatomic, assign) BOOL switchEnabled;
@property (nonatomic, assign) BOOL textEnabled;
@property (nonatomic, weak) UIViewController* parent; 
@property (nonatomic, weak) id <MLSettingCellDelegate> SettingCellDelegate;

/**
 NSuserdefault key to use
 */
@property (nonatomic, strong) NSString* defaultKey;

/**
 UIswitch
 */
@property (nonatomic, strong) UISwitch* toggleSwitch;

/**
 Textinput field
 */
@property (nonatomic, strong) UITextField* textInputField;

@end
