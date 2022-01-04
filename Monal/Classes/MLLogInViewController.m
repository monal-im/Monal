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
#import "xmpp.h"
#import "MLNotificationQueue.h"
#import "MLRegisterViewController.h"

@import SAMKeychain;
@import QuartzCore;
@import SafariServices;

@class MLQRCodeScanner;

#define FIRST_LOGIN_TIMEOUT 30.0

@interface MLLogInViewController ()

@property (nonatomic, strong) MBProgressHUD* loginHUD;
@property (nonatomic, weak) UITextField* activeField;
@property (nonatomic, strong) NSString* accountNo;
@property (nonatomic, strong) monal_void_block_t cancelFirstLoginTimer;

@end

@implementation MLLogInViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    self.topImage.layer.cornerRadius = 5.0;
    self.topImage.clipsToBounds = YES;
}

-(void) viewWillAppear:(BOOL) animated
{
    [super viewWillAppear:animated];
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(connected:) name:kMLHasConnectedNotice object:nil];
    [nc addObserver:self selector:@selector(catchedup:) name:kMonalFinishedCatchup object:nil];
#ifndef DISABLE_OMEMO
    [nc addObserver:self selector:@selector(omemoBundleFetchFinished:) name:kMonalFinishedOmemoBundleFetch object:nil];
#endif
    [self registerForKeyboardNotifications];
}


-(void) openLink:(NSString *) link
{
    NSURL* url = [NSURL URLWithString:link];
    
    if([url.scheme isEqualToString:@"http"] || [url.scheme isEqualToString:@"https"])
    {
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
    [self login];
}

-(void) login
{
    self.loginHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.loginHUD.label.text = NSLocalizedString(@"Logging in", @"");
    self.loginHUD.mode=MBProgressHUDModeIndeterminate;
    self.loginHUD.removeFromSuperViewOnHide=YES;

    NSString* jid = self.jid.text;
    NSString* password = self.password.text;
    
    NSArray* elements = [jid componentsSeparatedByString:@"@"];

    NSString* domain;
    NSString* user;
    //if it is a JID
    if([elements count] > 1)
    {
        user = [elements objectAtIndex:0];
        domain = [elements objectAtIndex:1];
    }
   
    if(!user || !domain)
    {
        self.loginHUD.hidden = YES;
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Invalid Credentials", @"") message:NSLocalizedString(@"Your XMPP account should be in in the format user@domain. For special configurations, use manual setup.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    if(password.length == 0)
    {
        self.loginHUD.hidden = YES;
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Invalid Credentials", @"") message:NSLocalizedString(@"Please enter a password.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    if([[DataLayer sharedInstance] doesAccountExistUser:user.lowercaseString andDomain:domain.lowercaseString]) {
        self.loginHUD.hidden = YES;
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Duplicate Account", @"") message:NSLocalizedString(@"This account already exists on this instance", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSMutableDictionary* dic  = [[NSMutableDictionary alloc] init];
    [dic setObject:domain.lowercaseString forKey:kDomain];
    [dic setObject:user.lowercaseString forKey:kUsername];
    [dic setObject:[HelperTools encodeRandomResource]  forKey:kResource];
    [dic setObject:@YES forKey:kEnabled];
    [dic setObject:@NO forKey:kDirectTLS];
    
    NSNumber* accountID = [[DataLayer sharedInstance] addAccountWithDictionary:dic];
    if(accountID)
    {
        //make sure we observer new connection errors (the observer will be removed in connected: to make sure we don't catch
        //non-fatal errors like muc join failures etc. (or any other errors after we successfully connected and logged in for that matter)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(error:) name:kXMPPError object:nil];
        self.accountNo = [NSString stringWithFormat:@"%@", accountID];
        [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
        [SAMKeychain setPassword:password forService:kMonalKeychainName account:self.accountNo];
        [[MLXMPPManager sharedInstance] connectAccount:self.accountNo];
        
        self.cancelFirstLoginTimer = createQueuedTimer(FIRST_LOGIN_TIMEOUT, dispatch_get_main_queue(), (^{
            DDLogError(@"First login took too long, cancelling and displaying error message to user");
            self.cancelFirstLoginTimer = nil;
            self.loginHUD.hidden=YES;
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Timeout Error", @"") message:NSLocalizedString(@"We were not able to connect your account. Please check your credentials and make sure you are connected to the internet.", @"") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            
            if(self.accountNo)
            {
                [[MLXMPPManager sharedInstance] disconnectAccount:self.accountNo];
                [[DataLayer sharedInstance] removeAccount:self.accountNo];
                // trigger UI removal
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
            }
        }));
    }
}

-(void) connected:(NSNotification*) notification
{
    xmpp* xmppAccount = notification.object;
    if(xmppAccount != nil && [xmppAccount.accountNo isEqualToString:self.accountNo])
    {
        if(self.cancelFirstLoginTimer != nil)
        {
            self.cancelFirstLoginTimer();
            self.cancelFirstLoginTimer = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kXMPPError object:nil];
        [[HelperTools defaultsDB] setBool:YES forKey:@"HasSeenLogin"];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loginHUD.label.text = NSLocalizedString(@"Loading contact list", @"");
        });
    }
}

-(void) catchedup:(NSNotification*) notification
{
    xmpp* xmppAccount = notification.object;
    if(xmppAccount != nil && [xmppAccount.accountNo isEqualToString:self.accountNo])
    {
#ifndef DISABLE_OMEMO
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loginHUD.label.text = NSLocalizedString(@"Loading omemo bundles", @"");
        });
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateBundleFetchStatus:) name:kMonalUpdateBundleFetchStatus object:nil];
#else
        [self omemoBundleFetchFinished:nil];
#endif
    }
}

#ifndef DISABLE_OMEMO
-(void) updateBundleFetchStatus:(NSNotification*) notification
{
    if([notification.userInfo[@"accountNo"] isEqualToString:self.accountNo])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loginHUD.label.text = [NSString stringWithFormat:NSLocalizedString(@"Loading omemo bundles: %@ / %@", @""), notification.userInfo[@"completed"], notification.userInfo[@"all"]];
        });
    }
}
#endif

-(void) omemoBundleFetchFinished:(NSNotification*) notification
{
    if(notification == nil || [notification.userInfo[@"accountNo"] isEqualToString:self.accountNo])
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kMonalUpdateBundleFetchStatus object:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loginHUD.hidden = YES;
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Success!", @"") message:NSLocalizedString(@"You are set up and connected.", @"") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Start Using Monal", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }
}

-(void) error:(NSNotification*) notification
{
    xmpp* xmppAccount = notification.object;
    if(xmppAccount != nil && [xmppAccount.accountNo isEqualToString:self.accountNo])
    {
        if(self.cancelFirstLoginTimer != nil)
        {
            self.cancelFirstLoginTimer();
            self.cancelFirstLoginTimer = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loginHUD.hidden=YES;
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"") message:NSLocalizedString(@"We were not able to connect your account. Please check your credentials and make sure you are connected to the internet.", @"") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            
            if(self.accountNo)
            {
                [[MLXMPPManager sharedInstance] disconnectAccount:self.accountNo];
                [[DataLayer sharedInstance] removeAccount:self.accountNo];
                // trigger UI removal
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
            }
        });
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



#pragma mark -textfield delegate

-(void) textFieldDidBeginEditing:(UITextField*) textField
{
    self.activeField = textField;
}

- (void) textFieldDidEndEditing:(UITextField*) textField
{
    self.activeField = nil;
}

#pragma mark - key commands

-(BOOL) canBecomeFirstResponder
{
    return YES;
}


// login on enter
-(void) enterPressed:(UIKeyCommand*)keyCommand
{
    [self login];
}

// List of custom hardware key commands
-(NSArray<UIKeyCommand *> *) keyCommands
{
    return @[
        // enter
        [UIKeyCommand keyCommandWithInput:@"\r" modifierFlags:0 action:@selector(enterPressed:)],
    ];
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
    // Your app might not need or want this behavior.
    CGRect aRect = self.view.frame;
    aRect.size.height -= kbSize.height;
    if (!CGRectContainsPoint(aRect, self.activeField.frame.origin) ) {
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
    [self removeObservers];
}


-(void) removeObservers
{
    DDLogVerbose(@"removing all observers");
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];
}

-(void) prepareForSegue:(UIStoryboardSegue*) segue sender:(id) sender
{
    if([segue.identifier isEqualToString:@"scanQRCode"])
    {
        MLQRCodeScanner* qrCodeScanner = (MLQRCodeScanner*)segue.destinationViewController;
        qrCodeScanner.loginDelegate = self;
        return;     //do not remove observers
    }
    
    [self removeObservers];
    
    if([segue.identifier isEqualToString:@"register"])
    {
        MLRegisterViewController* dest = (MLRegisterViewController*) segue.destinationViewController;
        dest.registerServer = kRegServer;
    }
}

-(void) MLQRCodeAccountLoginScannedWithJid:(NSString*) jid password:(NSString*) password
{
    // Insert jid and password into text fields
    self.jid.text = jid;
    self.password.text = password;
    // Close QR-Code scanner
    [self.navigationController popViewControllerAnimated:YES];
}


@end
