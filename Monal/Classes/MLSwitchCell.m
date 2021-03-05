//
//  MLAccountCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/8/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLSwitchCell.h"
#import "HelperTools.h"

@interface MLSwitchCell ()

@property (nonatomic, strong) NSString* defaultsKey;

@end

@implementation MLSwitchCell

-(void) clear
{
    self.defaultsKey = nil;

    self.cellLabel.text = nil;

    self.labelRight.text = nil;
    self.labelRight.hidden = YES;
    
    self.textInputField.text = nil;
    self.textInputField.hidden = YES;

    self.toggleSwitch.hidden = YES;
    
    self.slider.hidden = YES;
    
    self.accessoryType = UITableViewCellAccessoryNone;
}

-(void) initTapCell:(NSString*) leftLabel
{
    [self clear];
    
    self.cellLabel.text = leftLabel;
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

-(void) initCell:(NSString*) leftLabel withLabel:(NSString*) rightLabel
{
    [self clear];

    self.cellLabel.text = leftLabel;
    self.labelRight.text = rightLabel;
    self.labelRight.hidden = NO;
}

-(void) initCell:(NSString*) leftLabel withTextField:(NSString*) rightText    andPlaceholder:(NSString*) placeholder andTag:(uint16_t) tag
{
    [self initCell:leftLabel withTextField:rightText secureEntry:NO andPlaceholder:placeholder andTag:tag];
}

-(void) initCell:(NSString*) leftLabel withTextField:(NSString*) rightText secureEntry:(BOOL) secureEntry andPlaceholder:(NSString*) placeholder andTag:(uint16_t) tag
{
    [self clear];

    self.cellLabel.text = leftLabel;
    self.textInputField.text = rightText;
    self.textInputField.placeholder = placeholder;
    self.textInputField.tag = tag;
    self.textInputField.secureTextEntry = secureEntry;
    self.textInputField.hidden = NO;
}

-(void) initCell:(NSString*) leftLabel withTextFieldDefaultsKey:(NSString*) key andPlaceholder:(NSString*) placeholder;
{
    [self initCell:leftLabel withTextField:[[HelperTools defaultsDB] stringForKey:key] andPlaceholder:placeholder andTag:0];
    self.defaultsKey = key;
}

-(void) initCell:(NSString*) leftLabel withToggle:(BOOL) toggleValue andTag:(uint16_t) tag
{
    [self clear];
    
    self.cellLabel.text = leftLabel;
    self.toggleSwitch.on = toggleValue;
    self.toggleSwitch.tag = tag;
    self.toggleSwitch.hidden = NO;
}

-(void) initCell:(NSString*) leftLabel withToggleDefaultsKey:(NSString*) key
{
    [self initCell:leftLabel withToggle:[[HelperTools defaultsDB] boolForKey:key] andTag:0];
    [self.toggleSwitch addTarget:self action:@selector(switchChange) forControlEvents:UIControlEventValueChanged];
    self.defaultsKey = key;
}

#pragma mark uiswitch delegate

-(void) switchChange
{
    if(self.defaultsKey == nil)
        return;
    // save new switch state to defaultsDB
    [[HelperTools defaultsDB] setBool:_toggleSwitch.on forKey:self.defaultsKey];
}

#pragma mark uitextfield delegate
-(void) textFieldDidBeginEditing:(UITextField*) textField
{
}

-(BOOL) textFieldShouldReturn:(UITextField*) textField
{
    if(self.defaultsKey == nil)
        return YES;
    // save new value to defaultsDB
    [[HelperTools defaultsDB] setObject:_textInputField.text forKey: self.defaultsKey];
    [textField resignFirstResponder];
    return YES;
}


@end
