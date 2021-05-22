//
//  MLPasswordChangeTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 5/22/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLPasswordChangeTableViewController.h"
#import "MBProgressHUD.h"
#import "MLXMPPManager.h"


@interface MLPasswordChangeTableViewController ()
@property (nonatomic, weak) MLTextInputCell* passwordOld;
@property (nonatomic, weak) MLTextInputCell* passwordNew;
@property (nonatomic, strong) MBProgressHUD* progress;
@end

@implementation MLPasswordChangeTableViewController

-(void) closeView
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction) changePress:(id)sender
{
    if(!self.xmppAccount)
    {
        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No connected accounts", @"") message:NSLocalizedString(@"Please make sure you are connected before changing your password.", @"") preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@ "") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {}];
        [messageAlert addAction:closeAction];

        [self presentViewController:messageAlert animated:YES completion:nil];
    }
    else
    {
        if([self.passwordNew getText].length > 0 && [self.passwordOld getText] > 0)
        {
            if([[MLXMPPManager sharedInstance] isValidPassword:[self.passwordOld getText] forAccount:self.xmppAccount.accountNo] == NO)
            {
                UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Invalid Password!", @"") message:NSLocalizedString(@"The current password is not correct.", @"") preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *closeAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {}];
                [messageAlert addAction:closeAction];

                [self presentViewController:messageAlert animated:YES completion:nil];
                return;
            }

            self.progress = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
            self.progress.label.text = NSLocalizedString(@"Changing Password", @"");
            self.progress.mode = MBProgressHUDModeIndeterminate;
            self.progress.removeFromSuperViewOnHide = YES;
            self.progress.hidden = NO;
            
            [self.xmppAccount changePassword:[self.passwordNew getText] withCompletion:^(BOOL success, NSString* message) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progress.hidden = YES;
                    NSString* title = NSLocalizedString(@"Error", @"");
                    NSString* displayMessage = message;
                    if(success == YES) {
                        title = NSLocalizedString(@"Success", @"");
                        displayMessage = NSLocalizedString(@"The password has been changed", @"");
               
                       [[MLXMPPManager sharedInstance] updatePassword:[self.passwordNew getText] forAccount:self.xmppAccount.accountNo];
                    } else  {
                        if(displayMessage.length == 0) displayMessage = NSLocalizedString(@"Could not change the password", @"");
                    }
                    
                    UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:title message:displayMessage preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *closeAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                        
                    }];
                    [messageAlert addAction:closeAction];
                    
                    [self presentViewController:messageAlert animated:YES completion:nil];
                });
            }];
        }
        else
        {
            UIAlertController *messageAlert =[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error",@ "") message:NSLocalizedString(@"Password cannot be empty",@ "") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *closeAction =[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@ "") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                
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
    self.navigationItem.title=NSLocalizedString(@"Change Password", @"");
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
    if(section == 0)
        return NSLocalizedString(@"Enter your new password. Passwords may not be empty. They may also be governed by server or company policies.",@ "");
    else
        return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger toreturn = 0;
    switch (section) {
        case 0:
            toreturn = 2;
            break;
        case 1:
            toreturn = 1;
            break;
            
        default:
            break;
    }
    
    return toreturn;
}

- (UITableViewCell*) tableView:(UITableView*) tableView cellForRowAtIndexPath:(NSIndexPath*) indexPath
{
    if(indexPath.section == 0)
    {
        MLTextInputCell* textCell = [tableView dequeueReusableCellWithIdentifier:@"TextCell"];
        if(indexPath.row == 0)
        {
            [textCell initPasswordCell:nil andPlaceholder:NSLocalizedString(@"Current Password", @"") andDelegate:self];
            self.passwordOld = textCell;
        }
        else if(indexPath.row == 1)
        {
            [textCell initPasswordCell:nil andPlaceholder:NSLocalizedString(@"New Password", @"") andDelegate:self];
            self.passwordNew = textCell;
        }
        else
        {
            unreachable();
        }
        return textCell;
    }
    else
        return [tableView dequeueReusableCellWithIdentifier:@"addButton"];
}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    
}




@end
