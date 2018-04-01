//
//  MLEditGroupViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 4/1/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLEditGroupViewController.h"
#import "DataLayer.h"
#import "SAMKeychain.h"
#import "MLSwitchCell.h"
#import "MLTextInputCell.h"
#import "UIColor+Theme.h"
#import "MLButtonCell.h"
#import "MLXMPPManager.h"

@interface MLEditGroupViewController ()
@property (nonatomic, weak)  UITextField* accountName;
@property (nonatomic, weak) IBOutlet UIToolbar* keyboardToolbar;

@property (nonatomic, weak) UITextField* currentTextField;
@property (nonatomic, strong) UIPickerView* accountPicker;
@property (nonatomic, strong) UIView* accountPickerView;
@property (nonatomic, assign) NSInteger selectedRow;
@property (nonatomic, strong) UIBarButtonItem* closeButton;

-(IBAction) addPress:(id)sender;
-(void) closeView;


- (IBAction)toolbarDone:(id)sender;
- (IBAction)toolbarPrevious:(id)sender;
- (IBAction)toolbarNext:(id)sender;
@end

@implementation MLEditGroupViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    

    self.closeButton =[[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(closeView)];
    self.navigationItem.rightBarButtonItem=_closeButton;
    
    self.accountPicker = [[ UIPickerView alloc] init];
    self.accountPickerView= [[UIView alloc] initWithFrame: _accountPicker.frame];
    self.accountPickerView.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    
    [self.accountPickerView addSubview:_accountPicker];
    self.accountPicker.delegate=self;
    self.accountPicker.dataSource=self;
    self.accountPicker.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;

    [self.tableView registerNib:[UINib nibWithNibName:@"MLSwitchCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"AccountCell"];
    
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLTextInputCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"TextCell"];
    
    [self.tableView registerNib:[UINib nibWithNibName:@"MLButtonCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"ButtonCell"];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger toreturn=0;
    
    switch (section)
    {
        case 0:
        {
            toreturn=1;
            break;
        }
            
        case 1:
        {
            toreturn=5;
            break;
        }
            
        case 2:
        {
            toreturn=1;
            break;
        }
            
    }
    return toreturn;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn=0;
    
    switch (section)
    {
        case 0:
        {
            toreturn=@"Account To Use";
            break;
        }
            
        case 1:
        {
            toreturn=@"Group Information";
            break;
        }
            
        default:
        {
            toreturn=@"";
            break;
        }
            
    }
    return toreturn;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *toreturn ;
    
    switch (indexPath.section)
    {
        case 0:
        {
            MLTextInputCell *textCell =[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
            
                self.accountName =textCell.textInput;
                self.accountName.placeholder = @"Account";
                self.accountName.inputView=_accountPickerView;
                self.accountName.delegate=self;
                
                if([[MLXMPPManager sharedInstance].connectedXMPP count]==1)
                {
                    self.accountName.text=[[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:0];
                }
                toreturn=textCell;
                break;
        }
            
        case 1:
        {
            
            
            switch (indexPath.row)
            {
                case 0:{
                      MLTextInputCell* thecell=(MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                    thecell.textInput.placeholder=@"Room";
                    thecell.textInput.tag=1;
                    thecell.textInput.keyboardType = UIKeyboardTypeEmailAddress;
                    toreturn=thecell;
                    break;
                }
                case 1:{
                     MLTextInputCell* thecell=(MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
              
                    thecell.textInput.placeholder=@"NickNnme";
                    thecell.textInput.tag=2;
                
                    toreturn=thecell;
                    break;
                }
                case 2:{
                    MLTextInputCell* thecell=(MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                   // thecell.textInputField.text=self.password;
                    thecell.textInput.placeholder=@"Password";
                    thecell.textInput.tag=3;
                    thecell.textInput.secureTextEntry=YES;
                    toreturn=thecell;
                    break;
                }
                case 3:{
                    MLSwitchCell* thecell=(MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
                    
                    thecell.cellLabel.text=@"Favorite";
                    thecell.textInputField.hidden=YES;
                    thecell.toggleSwitch.tag=4;
                  //  thecell.toggleSwitch.on=self.enabled;
                    toreturn=thecell;
                    break;
                }
                case 4:{
                    MLSwitchCell* thecell=(MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
                    
                    thecell.cellLabel.text=@"Auto Join";
                    thecell.textInputField.hidden=YES;
                    thecell.toggleSwitch.tag=2;
                   // thecell.toggleSwitch.on=self.enabled;
                    toreturn=thecell;
                    break;
                }
                    
            }
            
            break;
        }
            
        case 2:
        {
            //save button
            MLButtonCell *buttonCell =(MLButtonCell*)[tableView dequeueReusableCellWithIdentifier:@"ButtonCell"];
            buttonCell.buttonText.text=@"Save";
            buttonCell.buttonText.textColor= [UIColor monalGreen];
            buttonCell.selectionStyle= UITableViewCellSelectionStyleNone;
            toreturn= buttonCell;
            break;
        }
            
    }
    

    return toreturn;
}

-(void) closeView
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction) addPress:(id)sender
{
    if([[MLXMPPManager sharedInstance].connectedXMPP count]==0)
    {
        UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:@"No connected accounts" message:@"Please make sure at least one account has connected before trying to add a contact." preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *closeAction =[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            
        }];
        [messageAlert addAction:closeAction];
        
        [self presentViewController:messageAlert animated:YES completion:nil];
    }
    else  {
    }
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

#pragma mark - textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    
    return YES;
}


- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    
    _currentTextField=textField;
    return YES;
}


#pragma mark - toolbar

-(IBAction)toolbarDone:(id)sender
{
//    if(_currentTextField ==self.contactName)
//    {
//        [self.contactName resignFirstResponder];
//    }
//    else {
//        [self.accountName resignFirstResponder];
//    }
    
}

- (IBAction)toolbarPrevious:(id)sender
{
//    if(_currentTextField ==self.contactName)
//    {
//        [self.accountName becomeFirstResponder];
//    }
//    else {
//        [self.contactName becomeFirstResponder];
//    }
}

- (IBAction)toolbarNext:(id)sender
{
//    if(_currentTextField ==self.contactName)
//    {
//        [self.accountName becomeFirstResponder];
//    }
//    else {
//        [self.contactName becomeFirstResponder];
//    }
}

@end
