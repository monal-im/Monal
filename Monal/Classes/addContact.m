//
//  buddyDetails.m
//  SworIM
//
//  Created by Anurodh Pokharel on 6/21/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "addContact.h"
#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "MLButtonCell.h"
#import "MLTextInputCell.h"

@implementation addContact


-(void) closeView
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void) addPress
{
    if([[MLXMPPManager sharedInstance].connectedXMPP count]==0)
    {
        
        UIAlertView *addError = [[UIAlertView alloc]
                                 initWithTitle:@"No connected accounts"
                                 message:@"Please make sure at least one account has connected before trying to add a contact. "
                                 delegate:self cancelButtonTitle:@"Close"
                                 otherButtonTitles: nil] ;
        [addError show];
    }
    else  {
        
        if(self.contactName.text.length>0)
        {
            NSDictionary* contact =@{@"row":[NSNumber numberWithInteger:_selectedRow],@"buddy_name":self.contactName.text};
            [[MLXMPPManager sharedInstance] addContact:contact];
            
            UIAlertView *addError = [[UIAlertView alloc]
                                     initWithTitle:@"Permission Requested"
                                     message:@"The new contact will be added to your contacts list when the person you've added has approved your request."
                                     delegate:self cancelButtonTitle:@"Close"
                                     otherButtonTitles: nil] ;
            [addError show];
        }
        else
        {
            UIAlertView *addError = [[UIAlertView alloc]
                                     initWithTitle:@"Error"
                                     message:@"Name can't be empty"
                                     delegate:self cancelButtonTitle:@"Close"
                                     otherButtonTitles: nil] ;
            [addError show];
        }
        
    }
}




- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    
	return YES;
}


- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    
    _currentTextField=textField;
    return YES;
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return YES;
}

#pragma mark View life cycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title=@"Add Contact";
    _closeButton =[[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(closeView)];
    self.navigationItem.rightBarButtonItem=_closeButton;
        
    _accountPicker = [[ UIPickerView alloc] init];
    _accountPickerView= [[UIView alloc] initWithFrame: _accountPicker.frame];
    _accountPickerView.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    
    [_accountPickerView addSubview:_accountPicker];
    _accountPicker.delegate=self;
    _accountPicker.dataSource=self;
    _accountPicker.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLButtonCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ButtonCell"];
    
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLTextInputCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"TextCell"];
    
    
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
}

#pragma mark tableview datasource delegate

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if(section==0)
    {
        return @"Contacts are usually in the format: username@domain.something";
    }
    else return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger toreturn =0;
    switch (section) {
        case 0:
            toreturn =2;
            break;
        case 1:
            toreturn=1;
            break;
            
        default:
            break;
    }
    
    return toreturn;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell ;
  
    switch (indexPath.section) {
        case 0: {
            MLTextInputCell *textCell =[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
            if(indexPath.row ==0){
                self.accountName =textCell.textInput;
                self.accountName.placeholder = @"Account";
                self.accountName.inputView=_accountPickerView;
                self.contactName.delegate=self;
                
            }
            else   if(indexPath.row ==1){
                self.contactName =textCell.textInput;
                self.contactName.placeholder = @"Contact Name";
                self.contactName.delegate=self;
              
            }
            textCell.textInput.inputAccessoryView =_keyboardToolbar;
            
            cell= textCell;
            break;
        }
        case 1: {
            MLButtonCell *buttonCell ;
            buttonCell =[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
            buttonCell.buttonText.text=@"Add Contact";
            buttonCell.buttonText.textColor= [UIColor colorWithRed:128.0/255 green:203.0/255 blue:182.0/255 alpha:1.0f];
            cell=buttonCell;
            
            break;
        }
        default:
            break;
    }
    
  return cell;
    
}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch (indexPath.section) {
        case 0:
            break;
        case 1:
            [self addPress];
            
        default:
            break;
    }
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

#pragma mark toolbar actions

-(IBAction)toolbarDone:(id)sender
{
    if(_currentTextField ==self.contactName)
    {
        [self.contactName resignFirstResponder];
    }
    else {
        [self.accountName resignFirstResponder];
    }
    
}

- (IBAction)toolbarPrevious:(id)sender
{
    if(_currentTextField ==self.contactName)
    {
        [self.accountName becomeFirstResponder];
    }
    else {
        [self.contactName becomeFirstResponder];
    }
}

- (IBAction)toolbarNext:(id)sender
{
    if(_currentTextField ==self.contactName)
    {
        [self.accountName becomeFirstResponder];
    }
    else {
        [self.contactName becomeFirstResponder];
    }
}



@end
