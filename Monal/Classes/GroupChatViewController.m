//
//  GroupChatViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/14/13.
//
//

#import "GroupChatViewController.h"
#import "MLConstants.h"
#import "TPKeyboardAvoidingScrollView.h"
#import "MLXMPPManager.h"



@interface GroupChatViewController ()

@end

@implementation GroupChatViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.navigationItem.title=NSLocalizedString(@"Group Chat",@"");
    
    //for time input
    _accountPicker = [[ UIPickerView alloc] init];
    _accountPickerView= [[UIView alloc] initWithFrame: _accountPicker.frame];
    _accountPickerView.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    
    [_accountPickerView addSubview:_accountPicker];
    _accountPicker.delegate=self;
    _accountPicker.dataSource=self;
    _accountPicker.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    
    self.accountName.inputView=_accountPickerView;
    
    if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
    {
        
    }
    else
    {
         _accountPickerView.backgroundColor=[UIColor blackColor];
        [self.view setBackgroundColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"debut_dark"]]];
    }
    
    
        UIImage *buttonImage = [[UIImage imageNamed:@"blueButton"]
                                 resizableImageWithCapInsets:UIEdgeInsetsMake(18, 18, 18, 18)];
        UIImage *buttonImageHighlight = [[UIImage imageNamed:@"blueButtonHighlight"]
                                          resizableImageWithCapInsets:UIEdgeInsetsMake(18, 18, 18, 18)];
    
        [_joinButton setBackgroundImage:buttonImage forState:UIControlStateNormal];
        [_joinButton setBackgroundImage:buttonImageHighlight forState:UIControlStateSelected];
    
    
    self.roomName.inputAccessoryView=_keyboardToolbar;
    self.password.inputAccessoryView=_keyboardToolbar;
    self.accountName.inputAccessoryView=_keyboardToolbar;
    

    
}

-(void) viewWillAppear:(BOOL)animated
{
    [_accountPicker reloadAllComponents];
    
    if([[MLXMPPManager sharedInstance].connectedXMPP count]==1)
    {
        _accountName.text=[[MLXMPPManager sharedInstance] getNameForConnectedRow:0];
       [[MLXMPPManager sharedInstance] getServiceDetailsForAccount:0 ];
    }
}

#pragma mark picker view delegate
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    if(row< [[MLXMPPManager sharedInstance].connectedXMPP count])
    {
    _selectedAccount=[[MLXMPPManager sharedInstance].connectedXMPP objectAtIndex:row];
    }
    
    _accountName.text=[[MLXMPPManager sharedInstance] getNameForConnectedRow:row];
    
    [[MLXMPPManager sharedInstance] getServiceDetailsForAccount:row ];
    
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    if(row< [[MLXMPPManager sharedInstance].connectedXMPP count])
    {
        NSString* name =[[MLXMPPManager sharedInstance] getNameForConnectedRow:row];
        if(name)
        return name;
    }
    return @"Unnamed";
}

#pragma mark picker view datasource
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    return [[MLXMPPManager sharedInstance].connectedXMPP count];
}


#pragma mark textField delegate


- (void)textFieldDidEndEditing:(UITextField *)textField
{
    
    
}


-(BOOL)textFieldShouldReturn:(UITextField*)textField;
{
    
    [textField resignFirstResponder];
    return NO; // We do not want UITextField to insert line-breaks.
}

//date picker
- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    
    _currentTextField=textField;
    if(textField==self.accountName)
    {
    
       // return NO;
    }
    else
    {
    
      
    }
    
     return YES; 
}



#pragma mark toolbar actions

-(IBAction)toolbarDone:(id)sender
{
    [_currentTextField resignFirstResponder];
    
}

- (IBAction)toolbarPrevious:(id)sender
{
    NSInteger nextTag = _currentTextField.tag - 1;
    // Try to find next responder
    UIResponder* nextResponder = [_currentTextField.superview viewWithTag:nextTag];
    if (nextResponder) {
        // Found next responder, so set it.
        [nextResponder becomeFirstResponder];
    } else {
        // Not found, so remove keyboard.
        [_currentTextField resignFirstResponder];
    }
}

- (IBAction)toolbarNext:(id)sender
{
    NSInteger nextTag = _currentTextField.tag + 1;
    // Try to find next responder
    UIResponder* nextResponder = [_currentTextField.superview viewWithTag:nextTag];
    if (nextResponder) {
        // Found next responder, so set it.
        [nextResponder becomeFirstResponder];
    } else {
        // Not found, so remove keyboard.
        [_currentTextField resignFirstResponder];
    }
}



- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
