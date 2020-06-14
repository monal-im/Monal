//
//  MLAccountCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/8/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MLSwitchCell : UITableViewCell

/**
 Label to the left
 */
@property  (nonatomic, weak) IBOutlet UILabel* cellLabel;

/**
 UIswitch
 */
@property  (nonatomic, weak) IBOutlet  UISwitch* toggleSwitch;

/**
 Textinput field
 */
@property  (nonatomic, weak) IBOutlet UITextField* textInputField;

/**
Label to the right
*/
@property (weak, nonatomic) IBOutlet UILabel* labelRight;

@end
