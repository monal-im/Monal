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
    self.loginHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.loginHUD.mode = MBProgressHUDModeIndeterminate;
    self.loginHUD.removeFromSuperViewOnHide=YES;
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self registerForKeyboardNotifications];
    
    //default ibr server
    if(!self.registerServer || !self.registerServer.length)
    {
        self.registerServer = kRegServer;
        self.disclaimer.text = NSLocalizedString(@"yax.im is a public server, not affiliated with Monal. This page is provided for convenience.", @"");
        self.tos.hidden = NO;
    }
    else
    {
        self.disclaimer.text = [NSString stringWithFormat:NSLocalizedString(@"Using server '%@' that was provided by the registration link you used.", @""), self.registerServer];
        self.tos.hidden = YES;
    }

    
    if(self.registerUsername)
        self.jid.text = self.registerUsername;
    
    [self createXMPPInstance];
    
    self.loginHUD.label.text = NSLocalizedString(@"Loading registration form", @"");
    self.loginHUD.hidden = NO;
    
    weakify(self);
    [self.xmppAccount requestRegFormWithToken:self.registerToken andCompletion:^(NSData* captchaImage, NSDictionary* hiddenFields) {
        dispatch_async(dispatch_get_main_queue(), ^{
            strongify(self);
            self.loginHUD.hidden = YES;
            /*
            if(captchaImage) {
                self.hiddenFields = hiddenFields;
                self.captchaImage.image = [UIImage imageWithData:captchaImage];
                self.captcha.hidden = NO;
                self.captchaImage.hidden = NO;
            } else {
                self.captcha.hidden = YES;
                self.captchaImage.hidden = YES;
            }
            */
        });
    } andErrorCompletion:^(BOOL success, NSString* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            strongify(self);
            self.loginHUD.hidden = YES;
            NSString* displayMessage = error;
            if(!displayMessage || !displayMessage.length)
                displayMessage = NSLocalizedString(@"Could not request registration form. Please check your internet connection and try again.", @ "");
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @ "") message:displayMessage preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @ "") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
                [self dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }];
}

-(void) createXMPPInstance
{
    MLXMPPIdentity* identity = [[MLXMPPIdentity alloc] initWithJid:[NSString stringWithFormat:@"nothing@%@", self.registerServer] password:@"nothing" andResource:@"MonalReg"];
    MLXMPPServer* server = [[MLXMPPServer alloc] initWithHost:@"" andPort:[NSNumber numberWithInt:5222] andDirectTLS:NO];
    self.xmppAccount = [[xmpp alloc] initWithServer:server andIdentity:identity andAccountNo:@"-1"];
}

-(IBAction)registerAccount:(id) sender
{
    if(self.jid.text.length == 0 || self.password.text.length == 0)
        {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"No Empty Values", @"") message:NSLocalizedString(@"Please make sure you have entered a username, password.", @"") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
    
    if([self.jid.text rangeOfString:@"@"].location != NSNotFound)
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Invalid username", @"") message:NSLocalizedString(@"The username does not need to have an @ symbol. Please try again.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    self.loginHUD.label.text = NSLocalizedString(@"Signing Up", @"");
    self.loginHUD.hidden = NO;
    
    NSString* jid = [self.jid.text.lowercaseString copy];
    NSString* pass = [self.password.text copy];
    NSString* code = nil;       //[self.captcha.text copy];
    
	    [self.xmppAccount registerUser:jid withPassword:pass captcha:code andHiddenFields: self.hiddenFields withCompletion:^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loginHUD.hidden = YES;
            [self.xmppAccount disconnect:YES];
            
            if(success == NO)
            {
                NSString* displayMessage = message;
                if(displayMessage.length == 0) displayMessage = NSLocalizedString(@"Could not register your username. Please check your code or change the username and try again.", @"");
                UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"") message:displayMessage preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [alert dismissViewControllerAnimated:YES completion:nil];
                }]];
                [self presentViewController:alert animated:YES completion:nil];
            }
            else
            {
                NSMutableDictionary* dic = [[NSMutableDictionary alloc] init];
                [dic setObject:self.registerServer forKey:kDomain];
                [dic setObject:jid forKey:kUsername];
                [dic setObject:[HelperTools encodeRandomResource] forKey:kResource];
                [dic setObject:@YES forKey:kEnabled];
                [dic setObject:@NO forKey:kDirectTLS];
                
                NSString* passwordText = [self.password.text copy];
                
                NSNumber* accountID = [[DataLayer sharedInstance] addAccountWithDictionary:dic];
                if(accountID) {
                    NSString* accountno = [NSString stringWithFormat:@"%@", accountID];
                    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
                    [SAMKeychain setPassword:passwordText forService:kMonalKeychainName account:accountno];
                    [[MLXMPPManager sharedInstance] connectAccount:accountno];
                }
                [self performSegueWithIdentifier:@"showSuccess" sender:nil];
            }
        });
    }];
}

-(void) prepareForSegue:(UIStoryboardSegue*) segue sender:(id) sender
{
    if([segue.identifier isEqualToString:@"showSuccess"])
    {
        [[HelperTools defaultsDB] setBool:YES forKey:@"HasSeenLogin"];
        MLRegSuccessViewController* dest = (MLRegSuccessViewController *) segue.destinationViewController;
        dest.registeredAccount = [NSString stringWithFormat:@"%@@%@", self.jid.text, self.registerServer];
        dest.completionHandler = self.completionHandler;
    }
}

-(IBAction) useWithoutAccount:(id) sender
{
    [[HelperTools defaultsDB] setBool:YES forKey:@"HasSeenLogin"];
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction) tapAction:(id) sender
{
    [self.view endEditing:YES];
}

-(IBAction) openTos:(id) sender;
{
    [self openLink:@"https://yaxim.org/yax.im/"];
}

-(void) openLink:(NSString*) link
{
    NSURL *url= [NSURL URLWithString:link];
    
    if ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"] ) {
        SFSafariViewController *safariView = [[ SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:safariView animated:YES completion:nil];
    }
}

#pragma mark -textfield delegate

-(void) textFieldDidBeginEditing:(UITextField*) textField
{
    self.activeField = textField;
}

-(void) textFieldDidEndEditing:(UITextField*) textField
{
    self.activeField = nil;
}



#pragma mark - keyboard management

-(void) registerForKeyboardNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWasShown:)
                                                 name:UIKeyboardDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillBeHidden:)
                                                 name:UIKeyboardWillHideNotification object:nil];
}

// Called when the UIKeyboardDidShowNotification is sent.
-(void) keyboardWasShown:(NSNotification*) aNotification
{
    NSDictionary* info = [aNotification userInfo];
    CGSize kbSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height, 0.0);
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
    
    // If active text field is hidden by keyboard, scroll it so it's visible
    CGRect aRect = self.view.frame;
    aRect.size.height -= kbSize.height;
    if(!CGRectContainsPoint(aRect, self.activeField.frame.origin))
    {
        [self.scrollView scrollRectToVisible:self.activeField.frame animated:YES];
    }
}

// Called when the UIKeyboardWillHideNotification is sent
-(void) keyboardWillBeHidden:(NSNotification*) aNotification
{
    UIEdgeInsets contentInsets = UIEdgeInsetsZero;
    self.scrollView.contentInset = contentInsets;
    self.scrollView.scrollIndicatorInsets = contentInsets;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}



@end
