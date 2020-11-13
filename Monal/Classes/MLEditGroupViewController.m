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
#import "xmpp.h"
#import "MLAccountPickerViewController.h"

@interface MLEditGroupViewController ()
@property (nonatomic, weak)  UITextField* accountName;
@property (nonatomic, weak) IBOutlet UIToolbar* keyboardToolbar;

@property (nonatomic, weak) UITextField* currentTextField;

@property (nonatomic, weak) UITextField* roomField;
@property (nonatomic, weak) UITextField* nickField;
@property (nonatomic, weak) UITextField* passField;

@property (nonatomic, weak) UISwitch* favSwitch;
@property (nonatomic, weak) UISwitch* autoSwitch;

@property (nonatomic, strong) UIBarButtonItem* closeButton;

-(IBAction) addPress:(id)sender;

- (IBAction)toolbarDone:(id)sender;
- (IBAction)toolbarPrevious:(id)sender;
- (IBAction)toolbarNext:(id)sender;
@end

@implementation MLEditGroupViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
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
                toreturn=NSLocalizedString(@"Account To Use",@"");
            }
            break;
        }
            
        case 1:
        {
            toreturn=NSLocalizedString(@"Group Information",@"");
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
            UITableViewCell *accountCell =[tableView dequeueReusableCellWithIdentifier:@"AccountPickerCell"];
            accountCell.textLabel.text=[NSString stringWithFormat:NSLocalizedString(@"Using Account: %@",@""), [[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:_selectedRow]];
            accountCell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
            toreturn=accountCell;
            break;
        }
            
        case 1:
        {

            switch (indexPath.row)
            {
                case 0:{
                      MLTextInputCell* thecell=(MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                    thecell.textInput.placeholder=NSLocalizedString(@"Room",@"");
                    
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
                    thecell.textInput.placeholder=NSLocalizedString(@"Nickname",@"");
                    thecell.textInput.inputAccessoryView =self.keyboardToolbar;
                     self.nickField= thecell.textInput;
                    thecell.textInput.delegate=self;
                      self.nickField.text=[_groupData objectForKey:@"nick"];
                    toreturn=thecell;
                    break;
                }
                case 2:{
                    MLTextInputCell* thecell=(MLTextInputCell *)[tableView dequeueReusableCellWithIdentifier:@"TextCell"];
                   thecell.textInput.placeholder=NSLocalizedString(@"Password",@"");
                    thecell.textInput.inputAccessoryView =self.keyboardToolbar;
                    thecell.textInput.secureTextEntry=YES;
                    
                     self.passField= thecell.textInput;
                     // self.roomField.text=[_groupData objectForKey:@"room"];
                    toreturn=thecell;
                    break;
                }
                case 3:{
                    MLSwitchCell* thecell=(MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
                    
                    thecell.cellLabel.text=NSLocalizedString(@"Favorite",@"");
                    thecell.textInputField.hidden=YES;
                     self.favSwitch= thecell.toggleSwitch;
                    [self.favSwitch addTarget:self action:@selector(toggleFav) forControlEvents:UIControlEventTouchUpInside];
                    if(self.groupData) self.favSwitch.on=YES;
                    toreturn=thecell;
                    break;
                }
                case 4:{
                    MLSwitchCell* thecell=(MLSwitchCell *)[tableView dequeueReusableCellWithIdentifier:@"AccountCell"];
                    
                    thecell.cellLabel.text=NSLocalizedString(@"Auto Join",@"");
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0: {
            if(indexPath.row ==0){
                [self performSegueWithIdentifier:@"showAccountPicker" sender:self];
            }
        }
    }
}


#pragma  mark - toggle

-(void) toggleFav {
    if(self.groupData) {
        NSNumber *account=[self.groupData objectForKey:@"account_id"];
        
        [[DataLayer sharedInstance] deleteMucFavorite:[self.groupData objectForKey:@"mucid"] forAccountId:account.integerValue];
    }
}

-(void) toggleJoin {
    if(self.groupData) {
        NSNumber *account=[self.groupData objectForKey:@"account_id"];

        [[DataLayer sharedInstance] updateMucFavorite:[self.groupData objectForKey:@"mucid"] forAccountId:account.integerValue autoJoin:self.autoSwitch.on];
    }
}

#pragma mark actions

-(IBAction) addPress:(id)sender
{
    if([[MLXMPPManager sharedInstance].connectedXMPP count]==0)
    {
        UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"No connected accounts",@"") message:NSLocalizedString(@"Please make sure at least one account has connected before trying to add a contact.",@"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *closeAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            
        }];
        [messageAlert addAction:closeAction];
        
        [self presentViewController:messageAlert animated:YES completion:nil];
    }
    else  {
        xmpp* account = [MLXMPPManager sharedInstance].connectedXMPP[_selectedRow];
        
        if(self.favSwitch.on && !self.groupData){
            BOOL autoJoinValue=NO;
            if(self.autoSwitch.on) autoJoinValue=YES;

            [[DataLayer sharedInstance] addMucFavoriteForAccount:account.accountNo withRoom:self.roomField.text nick:self.nickField.text autoJoin:autoJoinValue];
        }

        NSString *nick=[self.nickField.text copy];
        NSString *room =[self.roomField.text copy];
        NSString *pass=[self.passField.text copy];
        
        NSString *combinedRoom = room;
         if([combinedRoom componentsSeparatedByString:@"@"].count==1) {
             combinedRoom = [NSString stringWithFormat:@"%@@%@", room, account.connectionProperties.conferenceServer];
         }
         
        MLContact *group = [[MLContact alloc] init];
        group.isGroup=YES;
        group.accountId=account.accountNo;
        group.accountNickInGroup=nick;
        group.contactJid=room;
        
        [[DataLayer sharedInstance] addContact:combinedRoom forAccount:account.accountNo nickname:@"" andMucNick:nick];
        //race condition on creation otherwise
        [[MLXMPPManager sharedInstance] joinRoom:combinedRoom withNick:nick andPassword:pass forAccountRow:self->_selectedRow];

        dispatch_async(dispatch_get_main_queue(), ^{
            if(self.completion) self.completion(group);
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }
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
     if(_currentTextField ==self.roomField)
    {
        [self.passField becomeFirstResponder];
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
     if(_currentTextField ==self.roomField)
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




- (void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if([segue.identifier isEqualToString:@"showAccountPicker"])
    {
        MLAccountPickerViewController *accountPicker = (MLAccountPickerViewController *) segue.destinationViewController;
        accountPicker.completion = ^(NSInteger accountRow) {
            self->_selectedRow=accountRow;
            NSIndexPath *indexpath = [NSIndexPath indexPathForRow:0 inSection:0];
            [self.tableView reloadRowsAtIndexPaths:@[indexpath] withRowAnimation:UITableViewRowAnimationNone];
        };
    }
    
}

@end
