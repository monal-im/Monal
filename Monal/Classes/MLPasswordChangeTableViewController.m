//
//  MLPasswordChangeTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 5/22/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLPasswordChangeTableViewController.h"


#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "MLButtonCell.h"
#import "MLTextInputCell.h"


@interface MLPasswordChangeTableViewController ()
@property (nonatomic, weak)  UITextField* password;
@end

@implementation MLPasswordChangeTableViewController

-(void) closeView
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction) addPress:(id)sender
{
    if([[MLXMPPManager sharedInstance].connectedXMPP count]==0)
    {
        UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:@"No connected accounts" message:@"Please make sure you are connected before chaning your password." preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *closeAction =[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            
        }];
        [messageAlert addAction:closeAction];
        
        [self presentViewController:messageAlert animated:YES completion:nil];
    }
    else  {
        
        if(self.password.text.length>0)
        {
//            NSDictionary* contact =@{@"row":[NSNumber numberWithInteger:_selectedRow],@"buddy_name":self.contactName.text};
//            [[MLXMPPManager sharedInstance] addContact:contact];
//
//            UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:@"Permission Requested" message:@"The new contact will be added to your contacts list when the person you've added has approved your request." preferredStyle:UIAlertControllerStyleAlert];
//            UIAlertAction *closeAction =[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
//                [self dismissViewControllerAnimated:YES completion:nil];
//            }];
//            [messageAlert addAction:closeAction];
//
//            [self presentViewController:messageAlert animated:YES completion:nil];
//
        }
        else
        {
            UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:@"Error" message:@"Password can't be empty" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *closeAction =[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                
            }];
            [messageAlert addAction:closeAction];
            
            [self presentViewController:messageAlert animated:YES completion:nil];
            
        }
        
    }
}

#pragma mark - textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    
    return YES;
}


- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    
    return YES;
}


#pragma mark View life cycle

-(void) viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title=@"Change Password";
    [self.tableView registerNib:[UINib nibWithNibName:@"MLTextInputCell"
                                               bundle:[NSBundle mainBundle]]
         forCellReuseIdentifier:@"TextCell"];
    
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
  
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
        return @"Enter your new password. Passwords may not be empty. They may also be governed by server or company policies.";
    }
    else return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger toreturn =0;
    switch (section) {
        case 0:
            toreturn =1;
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
                self.password =textCell.textInput;
                self.password.placeholder = @"New Password";
                self.password.delegate=self;
            }
           
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
