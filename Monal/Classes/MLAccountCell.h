//
//  MLAccountCell.h
//  Monal
//
//  Created by Anurodh Pokharel on 2/8/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MLAccountCell : UITableViewCell

@property (nonatomic, assign) BOOL switchEnabled;
@property (nonatomic, assign) BOOL textEnabled;

/**
 UIswitch
 */
@property (nonatomic, strong) UISwitch* toggleSwitch;

/**
 Textinput field
 */
@property (nonatomic, strong) UITextField* textInputField;

@end
