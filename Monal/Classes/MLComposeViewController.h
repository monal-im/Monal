//
//  MLComposeViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/2/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLComposeViewController : UITableViewController <UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate> {
    UITextField* _currentTextField;
    UIPickerView* _accountPicker;
    UIView* _accountPickerView;
    NSInteger _selectedRow;
}

@property (nonatomic, weak)  UITextField* contactName;
@property (nonatomic, weak)  UITextField* accountName;
@property (nonatomic, weak) IBOutlet UIToolbar* keyboardToolbar;

- (IBAction)close:(id)sender;

- (IBAction)toolbarDone:(id)sender;
- (IBAction)toolbarPrevious:(id)sender;
- (IBAction)toolbarNext:(id)sender;

@end

NS_ASSUME_NONNULL_END
