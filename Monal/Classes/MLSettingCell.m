//
//  MLSettingCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/23/13.
//
//

#import "MLSettingCell.h"

@implementation MLSettingCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    self.selectionStyle=UITableViewCellSelectionStyleNone;
    
    _textField=[[UITextField alloc] initWithFrame:CGRectZero];
    _toggleSwitch=[[UISwitch alloc] initWithFrame:CGRectZero];
    return self;
}

- (void)layoutSubviews
{
    
    [super layoutSubviews];  //The default implementation of the layoutSubviews
     CGRect textLabelFrame = self.textLabel.frame;
  
    //this is to account for padding in the grouped tableview cell
    int padding =30;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        padding=80;
    }
    
    if(self.switchEnabled)
  {
   
       CGRect frame=CGRectMake(self.frame.size.width-_toggleSwitch.frame.size.width-padding,
                               textLabelFrame.origin.y+7,_toggleSwitch.frame.size.width,
                               textLabelFrame.size.height);
    _toggleSwitch.frame=frame;
    _toggleSwitch.on=  [[NSUserDefaults standardUserDefaults] boolForKey: _defaultKey];
      [ _toggleSwitch addTarget:self action:@selector(switchChange) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview: _toggleSwitch ];
      
    
  }
    
    if(self.textEnabled)
    {
        
        
        CGRect frame=CGRectMake(self.frame.size.width-79-padding,
                                textLabelFrame.origin.y+9,79,
                                textLabelFrame.size.height*2/3);
        _textField.frame=frame;
        _textField.returnKeyType=UIReturnKeyDone;
        _textField.delegate=self;
        _textField.text= [[NSUserDefaults standardUserDefaults] stringForKey: _defaultKey];
        [self.contentView addSubview: _textField ];
    }


}

-(void) switchChange
{
    [[NSUserDefaults standardUserDefaults]  setBool:_toggleSwitch.on forKey: _defaultKey];
}

#pragma mark uitextfield delegate
-(void)textFieldDidBeginEditing:(UITextField *)textField
{
    
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
     [[NSUserDefaults standardUserDefaults]  setObject:_textField.text forKey: _defaultKey];
    [textField resignFirstResponder];
    return YES;
}




@end
