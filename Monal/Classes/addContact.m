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

@implementation addContact


-(void) closeView
{
    [self dismissModalViewControllerAnimated:YES];
}

-(IBAction) addPress
{
	if(_buddyName.text.length>0)
	{
        NSDictionary* contact =@{@"row":[NSNumber numberWithInteger:_selectedRow],@"buddy_name":_buddyName.text};
		[[MLXMPPManager sharedInstance] addContact:contact];
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




- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
        [textField resignFirstResponder];

	return true;
}


-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return YES;
}

#pragma mark View life cycle

-(void) viewDidLoad
{
    self.navigationItem.title=@"Add Contact";
    _closeButton =[[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(closeView)];
    self.navigationItem.rightBarButtonItem=_closeButton;

     if(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0"))
     {
         _caption.textColor=[UIColor blackColor];
         self.view.backgroundColor =[UIColor whiteColor];
     }
     else{
         self.view.backgroundColor = [[UIColor alloc] initWithPatternImage:[UIImage imageNamed:@"debut_dark"]];
     }
    
    
    _accountPicker = [[ UIPickerView alloc] init];
    _accountPickerView= [[UIView alloc] initWithFrame: _accountPicker.frame];
    _accountPickerView.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    
    [_accountPickerView addSubview:_accountPicker];
    _accountPicker.delegate=self;
    _accountPicker.dataSource=self;
    _accountPicker.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    
    _accountName.inputView=_accountPickerView;
    
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
    
    [_addButton setBackgroundImage:buttonImage forState:UIControlStateNormal];
    [_addButton setBackgroundImage:buttonImageHighlight forState:UIControlStateSelected];
    
    
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




@end
