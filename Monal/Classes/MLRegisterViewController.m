//
//  MLLogInViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/9/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLRegisterViewController.h"
#import "MBProgressHUD.h"
#import "DataLayer.h"
#import "MLXMPPManager.h"
#import "SAMKeychain.h"
@import QuartzCore;
@import Crashlytics;
@import SafariServices;

@interface MLRegisterViewController ()
@property (nonatomic, strong) MBProgressHUD *loginHUD;
@property (nonatomic, weak) UITextField *activeField;
@property (nonatomic, strong) xmpp* xmppAccount;
@property (nonatomic, strong) NSDictionary *hiddenFields;


@end

@implementation MLRegisterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
}

- (void) viewWillAppear:(BOOL)animated
{
    self.xmppAccount=[[xmpp alloc] init];
    self.xmppAccount.explicitLogout=NO;
    
    self.xmppAccount.username=@"nothing";
    self.xmppAccount.domain=@"blabber.im";
    
    self.xmppAccount.resource=@"MonalReg";
    self.xmppAccount.server=@"blabber.im";
    self.xmppAccount.port=5222;
    self.xmppAccount.SSL=YES;
    self.xmppAccount.selfSigned=NO;
    self.xmppAccount.oldStyleSSL=NO;
    self.xmppAccount.registration=YES;
    
    __weak MLRegisterViewController *weakself = self;
    self.xmppAccount.regFormCompletion=^(NSData *captchaImage, NSDictionary *hiddenFields) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(captchaImage) {
                weakself.captchaImage.image= [UIImage imageWithData:captchaImage];
                self.hiddenFields = hiddenFields;
            } else {
                //show error image
                //self.captchaImage.image=
            }
        });
    };
    [self.xmppAccount connect];

}

-(IBAction)registerAccount:(id)sender {
    
    if(self.jid.text.length==0 || self.password.text.length==0 || self.captcha.text.length==0)
        {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Empty Values" message:@"Please make sure you have entered a username, password and code." preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
    
    if([self.jid.text rangeOfString:@"@"].location!=NSNotFound)
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Invalid username" message:@"The username does not need to have an @ symbol. Please try again." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
        self.loginHUD= [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        self.loginHUD.label.text=@"Signing Up";
        self.loginHUD.mode=MBProgressHUDModeIndeterminate;
        self.loginHUD.removeFromSuperViewOnHide=YES;
    [self.xmppAccount registerUser:self.jid.text withPassword:self.password.text captcha:self.captcha.text andHiddenFields: self.hiddenFields withCompletion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loginHUD.hidden=YES;
            if(!success) {
                NSString *displayMessage = message;
                if(displayMessage.length==0) displayMessage = @"Could not register your username. Please check your code or change the username and try again.";
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:displayMessage preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [alert dismissViewControllerAnimated:YES completion:nil];
                }]];
                [self presentViewController:alert animated:YES completion:nil];
                
            } else {
                    [self.xmppAccount disconnect];
                    NSMutableDictionary *dic  = [[NSMutableDictionary alloc] init];
                    [dic setObject:@"blabber.im" forKey:kDomain];
                    [dic setObject:self.jid.text forKey:kUsername];
                    [dic setObject:@"blabber.im"  forKey:kServer];
                    [dic setObject:@"5222" forKey:kPort];
                    NSString *resource=[NSString stringWithFormat:@"Monal-iOS.%d",rand()%100];
                    [dic setObject:resource  forKey:kResource];
                    [dic setObject:@YES forKey:kSSL];
                    [dic setObject:@YES forKey:kEnabled];
                    [dic setObject:@NO forKey:kSelfSigned];
                    [dic setObject:@NO forKey:kOldSSL];
                    [dic setObject:@NO forKey:kOauth];
                
                    NSString *passwordText = [self.password.text copy];
                
                    [[DataLayer sharedInstance] addAccountWithDictionary:dic andCompletion:^(BOOL result) {
                        if(result) {
                            [[DataLayer sharedInstance] executeScalar:@"select max(account_id) from account" withCompletion:^(NSObject * accountid) {
                                if(accountid) {
                                    NSString *accountno=[NSString stringWithFormat:@"%@",accountid];
                                    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
                                    [SAMKeychain setPassword:passwordText forService:@"Monal" account:accountno];
                                    [[MLXMPPManager sharedInstance] connectAccount:accountno];
                                }
                            }];
                        }
                    }];
            }
        });
    }];
}

-(IBAction) useWithoutAccount:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HasSeenLogin"];
}

-(IBAction) tapAction:(id)sender
{
    [self.view endEditing:YES];
}

-(IBAction) openTos:(id)sender;
{
    [self openLink:@"https://blabber.im/en/nutzungsbedingungen/"];
}

-(void) openLink:(NSString *) link
{
    NSURL *url= [NSURL URLWithString:link];
    
    if ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"]) {
        SFSafariViewController *safariView = [[ SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:safariView animated:YES completion:nil];
    }
}

#pragma mark -textfield delegate

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    self.activeField= textField;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    self.activeField=nil;
}



#pragma mark - keyboard management

- (void)registerForKeyboardNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWasShown:)
                                                 name:UIKeyboardDidShowNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillBeHidden:)
                                                 name:UIKeyboardWillHideNotification object:nil];
    
}

// Called when the UIKeyboardDidShowNotification is sent.
- (void)keyboardWasShown:(NSNotification*)aNotification
{
    NSDictionary* info = [aNotification userInfo];
    CGSize kbSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height, 0.0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
    
    // If active text field is hidden by keyboard, scroll it so it's visible
    // Your app might not need or want this behavior.
    CGRect aRect = self.view.frame;
    aRect.size.height -= kbSize.height;
    if (!CGRectContainsPoint(aRect, self.activeField.frame.origin) ) {
        [self.scrollView scrollRectToVisible:self.activeField.frame animated:YES];
    }
}

// Called when the UIKeyboardWillHideNotification is sent
- (void)keyboardWillBeHidden:(NSNotification*)aNotification
{
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

-(void) dealloc
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];
}



@end
