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
#import "xmpp.h"
#import "MLRegSuccessViewController.h"

@import QuartzCore;
@import SafariServices;
@import SAMKeychain;

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
    [super viewWillAppear:animated];
    [self registerForKeyboardNotifications];
    
    [self createXMPPInstance];
    
    __weak MLRegisterViewController *weakself = self;
    [self.xmppAccount requestRegFormWithCompletion:^(NSData *captchaImage, NSDictionary *hiddenFields) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if(captchaImage) {
                weakself.captchaImage.image= [UIImage imageWithData:captchaImage];
                weakself.hiddenFields = hiddenFields;
            } else {
                //show error image
                //self.captchaImage.image=
            }
            [weakself.xmppAccount disconnect:YES];  //we dont want to see any time out errors
        });
    } andErrorCompletion:^(BOOL success, NSString* error) {
        NSString *displayMessage = error;
        if(displayMessage.length==0) displayMessage = NSLocalizedString(@"Could not request registration form. Please check your internet connection and try again.", @ "");
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @ "") message:displayMessage preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

-(void) createXMPPInstance
{
    MLXMPPIdentity* identity = [[MLXMPPIdentity alloc] initWithJid:@"nothing@yax.im" password:@"nothing" andResource:@"MonalReg"];
    MLXMPPServer* server = [[MLXMPPServer alloc] initWithHost:@"" andPort:[NSNumber numberWithInt:5222] andDirectTLS:NO];
    server.selfSignedCert = NO;
    self.xmppAccount = [[xmpp alloc] initWithServer:server andIdentity:identity andAccountNo:@"-1"];
}

-(IBAction)registerAccount:(id) sender
{
    if(self.jid.text.length==0 || self.password.text.length==0)
        {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No Empty Values", @"") message:NSLocalizedString(@"Please make sure you have entered a username, password.", @"") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
    
    if([self.jid.text rangeOfString:@"@"].location!=NSNotFound)
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Invalid username", @"") message:NSLocalizedString(@"The username does not need to have an @ symbol. Please try again.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    self.loginHUD= [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.loginHUD.label.text=NSLocalizedString(@"Signing Up", @"");
    self.loginHUD.mode=MBProgressHUDModeIndeterminate;
    self.loginHUD.removeFromSuperViewOnHide=YES;
    
    NSString *jid = [self.jid.text copy];
    NSString *pass =[self.password.text copy];
    NSString *code =[self.captcha.text copy];
    [self createXMPPInstance];

    self.loginHUD.hidden=NO;
    
    [self.xmppAccount registerUser:jid withPassword:pass captcha:code andHiddenFields: self.hiddenFields withCompletion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loginHUD.hidden=YES;
            [self.xmppAccount disconnect:YES];
            
            if(!success)
            {
                NSString *displayMessage = message;
                if(displayMessage.length==0) displayMessage = NSLocalizedString(@"Could not register your username. Please check your code or change the username and try again.", @"");
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"") message:displayMessage preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [alert dismissViewControllerAnimated:YES completion:nil];
                }]];
                [self presentViewController:alert animated:YES completion:nil];
            }
            else
            {
                NSMutableDictionary *dic  = [[NSMutableDictionary alloc] init];
                [dic setObject:kRegServer forKey:kDomain];
                [dic setObject:self.jid.text forKey:kUsername];
                [dic setObject:[HelperTools encodeRandomResource] forKey:kResource];
                [dic setObject:@YES forKey:kEnabled];
                [dic setObject:@NO forKey:kSelfSigned];
                [dic setObject:@NO forKey:kDirectTLS];
                
                NSString *passwordText = [self.password.text copy];
                
                NSNumber* accountID = [[DataLayer sharedInstance] addAccountWithDictionary:dic];
                if(accountID) {
                    NSString* accountno = [NSString stringWithFormat:@"%@", accountID];
                    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
                    [SAMKeychain setPassword:passwordText forService:@"Monal" account:accountno];
                    [[MLXMPPManager sharedInstance] connectAccount:accountno];
                }
                [self performSegueWithIdentifier:@"showSuccess" sender:nil];
            }
        });
    }];
}

-(void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showSuccess"])
    {
        MLRegSuccessViewController *dest = (MLRegSuccessViewController *) segue.destinationViewController;
        dest.registeredAccount = [NSString stringWithFormat:@"%@@%@",self.jid.text,kRegServer];
    }
}

-(IBAction) useWithoutAccount:(id)sender
{
    [[HelperTools defaultsDB] setBool:YES forKey:@"HasSeenLogin"];
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction) tapAction:(id)sender
{
    [self.view endEditing:YES];
}

-(IBAction) openTos:(id)sender;
{
   // [self openLink:@"https://blabber.im/en/nutzungsbedingungen/"];
    [self openLink:@"https://yaxim.org/yax.im/"];
}

-(void) openLink:(NSString *) link
{
    NSURL *url= [NSURL URLWithString:link];
    
    if ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"] ) {
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
