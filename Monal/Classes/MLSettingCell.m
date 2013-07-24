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

    if(self.switchEnabled)
  {
     

       CGRect frame=CGRectMake(self.frame.size.width-_toggleSwitch.frame.size.width-30,
                               textLabelFrame.origin.y+7,_toggleSwitch.frame.size.width,
                               textLabelFrame.size.height);
      _toggleSwitch.frame=frame; 
    [self.contentView addSubview: _toggleSwitch ];
  }
    
    if(self.textEnabled)
    {
        
        
        CGRect frame=CGRectMake(self.frame.size.width-79-30,
                                textLabelFrame.origin.y+9,79,
                                textLabelFrame.size.height*2/3);
      //  _textField.backgroundColor=[UIColor lightGrayColor];
        _textField.frame=frame;
        _textField.returnKeyType=UIReturnKeyDone;
        _textField.delegate=self;
        [self.contentView addSubview: _textField ];
    }
    
    
//    textLabelFrame.origin.x=51+13;
//    textLabelFrame.size.width = self.frame.size.width-51-13-35-45;
//    self.textLabel.frame = textLabelFrame;
//    
//   
//    detailLabelFrame.origin.x=51+13;
//    detailLabelFrame.size.width = self.frame.size.width-51-13-35-45;
//    self.detailTextLabel.frame = detailLabelFrame;

}

#pragma mark uitextfield delegate
-(void)textFieldDidBeginEditing:(UITextField *)textField
{
    
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}




@end
