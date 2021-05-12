//
//  MLTextInputCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 4/10/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLTextInputCell.h"

@interface MLTextInputCell()
@property (nonatomic, weak) IBOutlet UITextField* textInput;
@end

@implementation MLTextInputCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
    self.textInput.clearButtonMode=UITextFieldViewModeUnlessEditing; 
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

-(void) setupCellWithText:(NSString*) text andPlaceholder:(NSString*) placeholder
{
    self.textInput.text = text;
    self.textInput.secureTextEntry = NO;
    self.textInput.placeholder = placeholder;
    self.textInput.enabled = YES;
    // enable autocorrection
    self.textInput.autocorrectionType = UITextAutocorrectionTypeYes;
}

-(void) initTextCell:(NSString*) text andPlaceholder:(NSString*) placeholder andDelegate:(id) delegate;
{
    [self setupCellWithText:text andPlaceholder:placeholder];
    [self.textInput setKeyboardType:UIKeyboardTypeDefault];
}

-(void) initMailCell:(NSString*) text andPlaceholder:(NSString*) placeholder andDelegate:(id) delegate;
{
    [self setupCellWithText:text andPlaceholder:placeholder];
    [self.textInput setKeyboardType:UIKeyboardTypeEmailAddress];
    // disable autocorrection
    self.textInput.autocorrectionType = UITextAutocorrectionTypeNo;
}

-(void) initPasswordCell:(NSString*) text andPlaceholder:(NSString*) placeholder andDelegate:(id) delegate;
{
    [self setupCellWithText:text andPlaceholder:placeholder];
    self.textInput.secureTextEntry = YES;
    [self.textInput setKeyboardType:UIKeyboardTypeDefault];
}

-(void) disableEditMode
{
    self.textInput.enabled = NO;
}

-(NSString*) getText
{
    return [self.textInput.text copy];
}

@end
