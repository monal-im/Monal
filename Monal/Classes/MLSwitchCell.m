//
//  MLAccountCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/8/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLSwitchCell.h"
#import <monalxmpp/HelperTools.h>

@interface MLSwitchCell ()

@property (nonatomic, strong) NSString* defaultsKey;
@property (nonatomic, strong) sliderUpdate sliderFilter;

@end

@implementation MLSwitchCell

-(void) clear
{
    self.defaultsKey = nil;
    self.sliderFilter = nil;

    self.cellLabel.text = nil;

    self.labelRight.text = nil;
    self.labelRight.hidden = YES;
    
    self.textInputField.text = nil;
    self.textInputField.hidden = YES;

    self.toggleSwitch.hidden = YES;
    
    self.slider.hidden = YES;

    self.imageView.image = nil;
    self.textLabel.text = nil;
    self.detailTextLabel.text = nil;
    self.accessoryView = nil;
    
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

-(void) initCell:(NSString*) leftLabel withTextFieldDefaultsKey:(NSString*) key andPlaceholder:(NSString*) placeholder
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

-(void) initCell:(NSString*) leftLabel withSliderDefaultsKey:(NSString*) key minValue:(float) minValue maxValue:(float) maxValue
{
    [self initCell:leftLabel withSliderDefaultsKey:key minValue:minValue maxValue:maxValue withLoadFunc:nil withUpdateFunc:nil];
}

-(void) initCell:(NSString*) leftLabel withSliderDefaultsKey:(NSString*) key minValue:(float) minValue maxValue:(float) maxValue withLoadFunc:(sliderUpdate) sliderLoad withUpdateFunc:(sliderUpdate) sliderUpdate
{
    [self clear];

    self.cellLabel.text = leftLabel;

    self.slider.minimumValue = minValue;
    self.slider.maximumValue = maxValue;

    if(sliderLoad)
        self.slider.value = sliderLoad(self.cellLabel, [[HelperTools defaultsDB] floatForKey:key]);
    else
        self.slider.value = [[HelperTools defaultsDB] floatForKey:key];

    [self.slider addTarget:self action:@selector(sliderChange) forControlEvents:UIControlEventValueChanged];
    _defaultsKey = key;
    self.sliderFilter = sliderUpdate;
    self.slider.hidden = NO;
}

#pragma mark uiswitch delegate

-(void) switchChange
{
    if(self.defaultsKey == nil)
        return;
    // save new switch state to defaultsDB
    [[HelperTools defaultsDB] setBool:_toggleSwitch.on forKey:self.defaultsKey];
}

#pragma mark uilabel delegate

-(void) sliderChange
{
    if(self.defaultsKey == nil)
        return;
    float filteredValue;

    if(self.sliderFilter == nil)
        filteredValue = self.slider.value;
    else
        filteredValue = self.sliderFilter(self.cellLabel, self.slider.value);

    // save new slider state to defaultsDB
    [[HelperTools defaultsDB] setFloat:filteredValue forKey:self.defaultsKey];
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
