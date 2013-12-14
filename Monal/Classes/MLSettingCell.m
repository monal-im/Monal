//
//  MLSettingCell.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/23/13.
//
//

#import "MLSettingCell.h"
#import "MLXMPPManager.h"

@implementation MLSettingCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
  
    self.selectionStyle=UITableViewCellSelectionStyleNone;
    
    _textInputField=[[UITextField alloc] initWithFrame:CGRectZero];
    _toggleSwitch=[[UISwitch alloc] initWithFrame:CGRectZero];
          }
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
        if([_defaultKey isEqualToString:@"StatusMessage"])
        {
            frame=CGRectMake( self.contentView.frame.origin.x+10,
                             self.contentView.frame.origin.y,
                              self.contentView.frame.size. width-10,
                             self.contentView.frame.size.height);
        }
        
        _textInputField.frame=frame;
        _textInputField.returnKeyType=UIReturnKeyDone;
        _textInputField.delegate=self;
        _textInputField.text= [[NSUserDefaults standardUserDefaults] stringForKey: _defaultKey];
        [self.contentView addSubview: _textInputField ];
    }


}

-(void) switchChange
{
    [[NSUserDefaults standardUserDefaults]  setBool:_toggleSwitch.on forKey: _defaultKey];
    if([_defaultKey isEqualToString:@"Away"])
    {
        [[MLXMPPManager sharedInstance] setAway:_toggleSwitch.on];
    }
    else  if([_defaultKey isEqualToString:@"Visible"])
        {
            [[MLXMPPManager sharedInstance] setVisible:_toggleSwitch.on];
        }
  
}

#pragma mark uitextfield delegate
-(void)textFieldDidBeginEditing:(UITextField *)textField
{
    
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
     [[NSUserDefaults standardUserDefaults]  setObject:_textInputField.text forKey: _defaultKey];
    [textField resignFirstResponder];
    
    if([_defaultKey isEqualToString:@"XMPPPriority"])
    {
        NSInteger number =[textField.text integerValue];
        [[MLXMPPManager sharedInstance] setPriority:number];
    }
    
    else
        if([_defaultKey isEqualToString:@"StatusMessage"])
        {
            [[MLXMPPManager sharedInstance] setStatusMessage:textField.text];
        }
  
    return YES;
}




@end
