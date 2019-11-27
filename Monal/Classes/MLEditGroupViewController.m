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

@property (nonatomic, weak) UITextField* accountsField;
@property (nonatomic, weak) UITextField* roomField;
@property (nonatomic, weak) UITextField* nickField;
@property (nonatomic, weak) UITextField* passField;

@property (nonatomic, weak) UISwitch* favSwitch;
@property (nonatomic, weak) UISwitch* autoSwitch;

@property (nonatomic, strong) UIPickerView* accountPicker;
@property (nonatomic, strong) UIView* accountPickerView;
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
    
    if(!self.groupData) {
    self.closeButton =[[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(closeView)];
    self.navigationItem.rightBarButtonItem=_closeButton;
    }

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
    
      self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [_accountPicker reloadAllComponents];
    
    [[MLXMPPManager sharedInstance] getServiceDetailsForAccount:0 ];
    [_accountPicker selectedRowInComponent:0];
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
            if([[MLXMPPManager sharedInstance].connectedXMPP count]==1){
                toreturn=@"";
            } else  {
                toreturn=@"Account To Use";
            }
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
            if([[MLXMPPManager sharedInstance].connectedXMPP count]>1){
                MLTextInputCell *textCell =[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                
                self.accountName =textCell.textInput;
                self.accountName.placeholder = @"Account";
                self.accountName.inputView=_accountPickerView;
                self.accountName.delegate=self;
                textCell.textInput.tag=10;
                
                if([[MLXMPPManager sharedInstance].connectedXMPP count]==1)
                {
                    self.accountName.text=[[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:0];
                }
                textCell.textInput.inputAccessoryView =self.keyboardToolbar;
                self.accountsField= textCell.textInput;
                toreturn=textCell;
            } else  {
                toreturn = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"blank"];
                toreturn.contentView.backgroundColor= [UIColor groupTableViewBackgroundColor];
            }
            break;
        }
            
        case 1:
        {
            
            
            switch (indexPath.row)
            {
                case 0:{
                      MLTextInputCell* thecell=(MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                    thecell.textInput.placeholder=@"Room";
                    
                    thecell.textInput.keyboardType = UIKeyboardTypeEmailAddress;
                    thecell.textInput.inputAccessoryView =self.keyboardToolbar;
                    thecell.textInput.delegate=self;
                    self.roomField= thecell.textInput;
                    self.roomField.text=[_groupData objectForKey:@"room"];
                    toreturn=thecell;
                    break;
                }
                case 1:{
                     MLTextInputCell* thecell=(MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                    thecell.textInput.placeholder=@"Nickname";
                    thecell.textInput.inputAccessoryView =self.keyboardToolbar;
                     self.nickField= thecell.textInput;
                    thecell.textInput.delegate=self;
                      self.nickField.text=[_groupData objectForKey:@"nick"];
                    toreturn=thecell;
                    break;
                }
                case 2:{
                    MLTextInputCell* thecell=(MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                   thecell.textInput.placeholder=@"Password";
                    thecell.textInput.inputAccessoryView =self.keyboardToolbar;
                    thecell.textInput.secureTextEntry=YES;
                    
                     self.passField= thecell.textInput;
                     // self.roomField.text=[_groupData objectForKey:@"room"];
                    toreturn=thecell;
                    break;
                }
                case 3:{
                    MLSwitchCell* thecell=(MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
                    
                    thecell.cellLabel.text=@"Favorite";
                    thecell.textInputField.hidden=YES;
                     self.favSwitch= thecell.toggleSwitch;
                    [self.favSwitch addTarget:self action:@selector(toggleFav) forControlEvents:UIControlEventTouchUpInside];
                    if(self.groupData) self.favSwitch.on=YES;
                    toreturn=thecell;
                    break;
                }
                case 4:{
                    MLSwitchCell* thecell=(MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
                    
                    thecell.cellLabel.text=@"Auto Join";
                    thecell.textInputField.hidden=YES;
                    self.autoSwitch= thecell.toggleSwitch;
                     [self.autoSwitch addTarget:self action:@selector(toggleJoin) forControlEvents:UIControlEventTouchUpInside];
                    NSNumber *on=[_groupData objectForKey:@"autojoin"];
                    
                    if(on.intValue==1)
                    {
                        self.autoSwitch.on=YES;
                    }
                    
                    toreturn=thecell;
                    break;
                }
                    
            }
            
            break;
        }
            
        case 2:
        {
            //save button
            UITableViewCell *buttonCell =[tableView dequeueReusableCellWithIdentifier:@"addButton"];
            toreturn= buttonCell;
            break;
        }
            
    }
    
    return toreturn;
}

-(void) toggleFav {
    if(self.groupData) {
        NSNumber *account=[self.groupData objectForKey:@"account_id"];
        
        [[DataLayer sharedInstance] deleteMucFavorite:[self.groupData objectForKey:@"mucid"] forAccountId:account.integerValue withCompletion:^(BOOL success) {
            
        }];
    }
}

-(void) toggleJoin {
    if(self.groupData) {
        NSNumber *account=[self.groupData objectForKey:@"account_id"];

        [[DataLayer sharedInstance] updateMucFavorite:[self.groupData objectForKey:@"mucid"] forAccountId:account.integerValue autoJoin:self.autoSwitch.on andCompletion:^(BOOL success) {
            
        }];
    }
}

#pragma mark actions

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
        if([MLXMPPManager sharedInstance].connectedXMPP.count<=[self.accountPicker selectedRowInComponent:0]) return;
        
        NSDictionary *accountrow = [MLXMPPManager sharedInstance].connectedXMPP[[self.accountPicker selectedRowInComponent:0]];
        xmpp* account= (xmpp*)[accountrow objectForKey:kXmppAccount];
        
        if(self.favSwitch.on && !self.groupData){
            BOOL autoJoinValue=NO;
            if(self.autoSwitch.on) autoJoinValue=YES;

            [[DataLayer sharedInstance] addMucFavoriteForAccount:account.accountNo withRoom:self.roomField.text nick:self.nickField.text autoJoin:autoJoinValue andCompletion:nil];
        }

        [[MLXMPPManager sharedInstance] joinRoom:self.roomField.text withNick:self.nickField.text andPassword:self.passField.text forAccountRow:[self.accountPicker selectedRowInComponent:0]];

        NSString *nick=self.nickField.text;
        NSString *room =self.roomField.text;
        
        
        [[DataLayer sharedInstance] addContact:self.roomField.text forAccount:account.accountNo fullname:@"" nickname:self.nickField.text  withCompletion:^(BOOL success) {
            
                [[DataLayer sharedInstance] updateOwnNickName:nick forMuc:room forAccount:account.accountNo];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dismissViewControllerAnimated:YES completion:nil];
            });
            
        }];
        
        
    }
}


#pragma mark picker view delegate
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
   // _selectedRow=row;
    _accountName.text=[[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:row];
    
    [[MLXMPPManager sharedInstance] getServiceDetailsForAccount:row ];
    
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    if(row< [[MLXMPPManager sharedInstance].connectedXMPP count])
    {
        NSString* name =[[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:row];
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

#pragma mark - textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}


- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    self.currentTextField=textField;
    return YES;
}


#pragma mark - toolbar

-(IBAction)toolbarDone:(id)sender
{
    
    [self.currentTextField resignFirstResponder];
}

- (IBAction)toolbarPrevious:(id)sender
{
    if(_currentTextField ==self.accountsField)
    {
         [self.currentTextField resignFirstResponder];
    }
    else  if(_currentTextField ==self.roomField)
    {
        [self.accountsField becomeFirstResponder];
    }
    else if(_currentTextField ==self.passField)
    {
        [self.nickField becomeFirstResponder];
    }
    else  if(_currentTextField ==self.nickField)
    {
        [self.roomField becomeFirstResponder];
    }
   
    
}

- (IBAction)toolbarNext:(id)sender
{
    if(_currentTextField ==self.accountsField)
    {
        [self.roomField becomeFirstResponder];
    }
    else  if(_currentTextField ==self.roomField)
    {
        [self.nickField becomeFirstResponder];
    }
    else  if(_currentTextField ==self.nickField)
    {
        [self.passField becomeFirstResponder];
    }
    else if(_currentTextField ==self.passField)
    {
        [self.currentTextField resignFirstResponder];
    }
}

@end
