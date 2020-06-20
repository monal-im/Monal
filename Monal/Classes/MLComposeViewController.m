//
//  MLComposeViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/2/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLComposeViewController.h"
#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "MLButtonCell.h"
#import "MLTextInputCell.h"
#import  "DataLayer.h"

@interface MLComposeViewController ()

@end

@implementation MLComposeViewController

- (IBAction)close:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)send:(id)sender
{
    if([[MLXMPPManager sharedInstance].connectedXMPP count]==0)
    {
        UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"No connected accounts",@"") message:NSLocalizedString(@"Please make sure at least one account has connected before trying to message someone.",@"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *closeAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            
        }];
        [messageAlert addAction:closeAction];
        
        [self presentViewController:messageAlert animated:YES completion:nil];
    }
    else  {
        
        if(self.message.text.length==0)
        {
            UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error",@"") message:NSLocalizedString(@"Message can't be empty",@"") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *closeAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                
            }];
            [messageAlert addAction:closeAction];
            
            [self presentViewController:messageAlert animated:YES completion:nil];
            return;
            
        }
        
        if(self.contactName.text.length>0)
        {
            xmpp* account;
            
            if(_selectedRow<[[MLXMPPManager sharedInstance].connectedXMPP count] && _selectedRow>=0) {
                xmpp* account = [[MLXMPPManager sharedInstance].connectedXMPP objectAtIndex:_selectedRow];

            }
            
            NSString *messageID =[[NSUUID UUID] UUIDString];
            NSString *name =[self.contactName.text copy];
            NSString *text =[self.message.text copy];
            BOOL encryptChat =[[DataLayer sharedInstance] shouldEncryptForJid:name andAccountNo:account.accountNo];

            [[DataLayer sharedInstance] addMessageHistoryFrom:account.connectionProperties.identity.jid to:name forAccount:account.accountNo withMessage:text actuallyFrom:account.connectionProperties.identity.jid  withId:messageID encrypted:encryptChat withCompletion:^(BOOL success, NSString *messageType) {
                
            }];
            
            [[MLXMPPManager sharedInstance] sendMessage:text toContact:name fromAccount:account.accountNo isEncrypted:encryptChat isMUC:NO isUpload:NO messageId:messageID  withCompletionHandler:^(BOOL success, NSString *messageId) {
                
            }];
            
            
            [[DataLayer sharedInstance] addActiveBuddies:name forAccount:account.accountNo withCompletion:nil];
            
            //dismiss and go to conversation
            [self dismissViewControllerAnimated:YES completion:^{
               //push new conversation on view conroller
            }];
            
        }
        else
        {
            UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error",@"") message:NSLocalizedString(@"Recipient name can't be empty",@"") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *closeAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                
            }];
            [messageAlert addAction:closeAction];
            
            [self presentViewController:messageAlert animated:YES completion:nil];
            
        }
        
        
    }
    
    [self close:self];
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


#pragma mark View life cycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title=NSLocalizedString(@"Send A Message",@"");
    
    _accountPicker = [[ UIPickerView alloc] init];
    _accountPickerView= [[UIView alloc] initWithFrame: _accountPicker.frame];
    _accountPickerView.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    
    
    [_accountPickerView addSubview:_accountPicker];
    _accountPicker.delegate=self;
    _accountPicker.dataSource=self;
    _accountPicker.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    
    
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
        [[MLXMPPManager sharedInstance] getServiceDetailsForAccount:0 ];
        [_accountPicker selectedRowInComponent:0];
        
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
        return NSLocalizedString(@"Recipients are usually in the format: username@domain.something",@"");
    }
    else return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger toreturn =0;
    switch (section) {
        case 0:
            toreturn =3;
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
                
                if([[MLXMPPManager sharedInstance].connectedXMPP count]==1)
                {
                    self.accountName.text=[[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:0];
                }
                
                if([[MLXMPPManager sharedInstance].connectedXMPP count]>1){
                    self.accountName =textCell.textInput;
                    self.accountName.placeholder = NSLocalizedString(@"Account",@"");
                    self.accountName.inputView=_accountPickerView;
                    self.accountName.delegate=self;
                } else  {
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"blank"];
                    cell.contentView.backgroundColor= [UIColor groupTableViewBackgroundColor];
                    break;
                }
                
            }
            else   if(indexPath.row ==1){
                self.contactName =textCell.textInput;
                self.contactName.placeholder = NSLocalizedString(@"Recipient Name",@"");
                self.contactName.delegate=self;
            }
            
            else   if(indexPath.row ==2){
                self.message =textCell.textInput;
                self.message.placeholder = NSLocalizedString(@"Message",@"");
                self.message.delegate=self;
            }
            textCell.textInput.inputAccessoryView =_keyboardToolbar;
            
            cell= textCell;
            break;
        }
        case 1: {
            
            cell =[tableView dequeueReusableCellWithIdentifier:@"addButton"];
            
            
            break;
        }
        default:
            break;
    }
    
    return cell;
    
}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    
}


#pragma mark picker view delegate
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    _selectedRow=row;
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
    return NSLocalizedString(@"Unnamed",@"");
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
