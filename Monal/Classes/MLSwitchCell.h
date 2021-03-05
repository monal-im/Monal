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
 UIswitch
 */
@property  (nonatomic, weak) IBOutlet  UISlider* slider;

/**
 Textinput field
 */
@property  (nonatomic, weak) IBOutlet UITextField* textInputField;

/**
Label to the right
*/
@property (weak, nonatomic) IBOutlet UILabel* labelRight;

-(void) clear;

-(void) initTapCell:(NSString*) leftLabel;

-(void) initCell:(NSString*) leftLabel withLabel:(NSString*) rightLabel;

-(void) initCell:(NSString*) leftLabel withTextField:(NSString*) rightText andPlaceholder:(NSString*) placeholder andTag:(uint16_t) tag;

-(void) initCell:(NSString*) leftLabel withTextField:(NSString*) rightText secureEntry:(BOOL) secureEntry andPlaceholder:(NSString*) placeholder andTag:(uint16_t) tag;

-(void) initCell:(NSString*) leftLabel withToggle:(BOOL) toggleValue andTag:(uint16_t) tag;

@end
