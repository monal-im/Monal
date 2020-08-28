//
//  MLLogInViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/9/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLLogInViewController.h"
#import "MBProgressHUD.h"
#import "DataLayer.h"
#import "MLXMPPManager.h"
@import SAMKeychain;
@import QuartzCore;
@import SafariServices;

@interface MLLogInViewController ()
@property (nonatomic, strong) MBProgressHUD *loginHUD;
@property (nonatomic, weak) UITextField *activeField;
@property (nonatomic, strong) NSString *accountno;

@end

@implementation MLLogInViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.topImage.layer.cornerRadius=5.0;
    self.topImage.clipsToBounds=YES;
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(connected) name:kMonalAccountStatusChanged object:nil];
    [nc addObserver:self selector:@selector(error) name:kXMPPError object:nil];
    [self registerForKeyboardNotifications];
}

-(void) openLink:(NSString *) link
{
    NSURL *url= [NSURL URLWithString:link];
    
    if ([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"] ) {
        SFSafariViewController *safariView = [[ SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:safariView animated:YES completion:nil];
    }
}

-(IBAction) registerAccount:(id)sender;
{
    [self openLink:@"https://monal.im/welcome-to-xmpp/"];
}

-(IBAction) login:(id)sender
{
    self.loginHUD= [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.loginHUD.label.text=NSLocalizedString(@"Logging in",@"");
    self.loginHUD.mode=MBProgressHUDModeIndeterminate;
    self.loginHUD.removeFromSuperViewOnHide=YES;

    NSString *jid= self.jid.text;
    NSString *password = self.password.text;
    
    NSArray* elements=[jid componentsSeparatedByString:@"@"];

    NSString *domain;
    NSString *user;
    //if it is a JID
    if([elements count]>1)
    {
        user= [elements objectAtIndex:0];
        domain = [elements objectAtIndex:1];
    }
   
    if(!user || !domain)
    {
        self.loginHUD.hidden=YES;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Invalid Credentials",@"") message:NSLocalizedString(@"Your XMPP account should be in in the format user@domain. For special configurations, use manual setup.",@"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    if(password.length==0)
    {
        self.loginHUD.hidden=YES;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Invalid Credentials",@"") message:NSLocalizedString(@"Please enter a password.",@"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSMutableDictionary *dic  = [[NSMutableDictionary alloc] init];
    [dic setObject:domain forKey:kDomain];
    [dic setObject:user forKey:kUsername];
    [dic setObject:[HelperTools encodeRandomResource]  forKey:kResource];
    [dic setObject:@YES forKey:kEnabled];
    [dic setObject:@NO forKey:kSelfSigned];
    [dic setObject:@NO forKey:kDirectTLS];
    
    NSNumber* accountID = [[DataLayer sharedInstance] addAccountWithDictionary:dic];
    if(accountID) {
        self.accountno=[NSString stringWithFormat:@"%@", accountID];
        [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
        [SAMKeychain setPassword:password forService:@"Monal" account:self.accountno];
        [[MLXMPPManager sharedInstance] connectAccount:self.accountno];
    }
}

-(void) connected
{
     dispatch_async(dispatch_get_main_queue(), ^{
    self.loginHUD.hidden=YES;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Success!",@"") message:NSLocalizedString(@"You are set up and connected.",@"") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Start Using Monal",@"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
     });
}


-(void) error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.loginHUD.hidden=YES;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error",@"") message:NSLocalizedString(@"We were not able to connect your account. Please check your credentials and make sure you are connected to the internet.",@"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close",@"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        
        [[DataLayer sharedInstance] removeAccount:self.accountno];
    });
}

-(IBAction) useWithoutAccount:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
    [[HelperTools defaultsDB] setBool:YES forKey:@"HasSeenLogin"];
}

-(IBAction) tapAction:(id)sender
{
    [self.view endEditing:YES];
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
    [self removeObservers];
}


-(void) removeObservers {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
     [self removeObservers];
}


@end
