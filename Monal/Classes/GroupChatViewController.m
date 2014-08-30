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
#import "RoomListViewController.h"



@interface GroupChatViewController ()
    -(void)showRoomList;
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
    
    [_roomButton setBackgroundImage:buttonImage forState:UIControlStateNormal];
    [_roomButton setBackgroundImage:buttonImageHighlight forState:UIControlStateSelected];
    
    
    
    self.roomName.inputAccessoryView=_keyboardToolbar;
    self.password.inputAccessoryView=_keyboardToolbar;
    self.accountName.inputAccessoryView=_keyboardToolbar;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showRoomList) name:kMLHasRoomsNotice object:nil];

    
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [_accountPicker reloadAllComponents];
    
    if([[MLXMPPManager sharedInstance].connectedXMPP count]==1)
    {
        _accountName.text=[[MLXMPPManager sharedInstance] getNameForConnectedRow:0];
       [[MLXMPPManager sharedInstance] getServiceDetailsForAccount:0 ];
    }
    
    _hasRequestedRooms=NO; // reset when modal view goes away. Allows refresh
}


-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}



#pragma mark picker view delegate
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    _selectedRow=row;
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

#pragma mark actions


-(void)showRoomList
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       if(_hasRequestedRooms)
                       {
                           RoomListViewController* roomlist =[[RoomListViewController alloc] initWithRoomList:   [[MLXMPPManager sharedInstance] getRoomsListForAccountRow:_selectedRow ]];
                           
                           [self.navigationController pushViewController:roomlist animated:YES];
                       }
                   });
}

- (IBAction)getRooms:(id)sender
{
    [[MLXMPPManager sharedInstance] getRoomsForAccountRow:_selectedRow ];
    _hasRequestedRooms=YES;
}

- (IBAction)joinRoom:(id)sender
{
    NSString* password =_password.text;
    if([password length]<1) password=nil;
    [[MLXMPPManager sharedInstance] joinRoom:_roomName.text withPassword:password
                               forAccountRow:_selectedRow ];
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
