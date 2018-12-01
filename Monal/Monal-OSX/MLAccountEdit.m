//
//  MLAccountEdit.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/3/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLAccountEdit.h"
#import "MLXMPPManager.h"
#import "DataLayer.h"
#import "MLAccountSettings.h"
#import "SAMKeychain.h"

#import "NXOAuth2.h"
#import "MLOAuthViewController.h"

@interface MLAccountEdit ()
@property (nonatomic, strong) NSURL *oAuthURL;

@end

@implementation MLAccountEdit

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreAccountsDidChangeNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *aNotification){
                                                    
                                                      for (NXOAuth2Account *account in [[NXOAuth2AccountStore sharedStore] accountsWithAccountType:self.jabberID.stringValue]) {
                                                       
                                                          self.password.stringValue= account.accessToken.accessToken;
                                                          
                                                      };
                                                      
                                                  }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreDidFailToRequestAccessNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *aNotification){
                                                      NSError *error = [aNotification.userInfo objectForKey:NXOAuth2AccountStoreErrorKey];
                                                      // Do something with the error
                                                  }];
}

-(void) viewWillAppear {
    [super viewWillAppear];
    
     if([self.accountType isEqualToString:@"Gtalk"]) {
         //disable options
         [self toggleGoogleTalkDisplay];
     }
    
    if(!self.accountToEdit) {
        if([self.accountType isEqualToString:@"Gtalk"]) {
            self.server.stringValue= @"talk.google.com";
            self.jabberID.stringValue=@"@gmail.com";
        }
    } else  {
        self.jabberID.stringValue =[NSString stringWithFormat:@"%@@%@", [self.accountToEdit objectForKey:kUsername], [self.accountToEdit objectForKey:kDomain]];
        
        self.server.stringValue =[self.accountToEdit objectForKey:kServer];
        self.port.stringValue =[NSString stringWithFormat:@"%@", [self.accountToEdit objectForKey:kPort]];
       // self.resource.stringValue =[self.accountToEdit objectForKey:kResource];
        
        self.sslCheck.state =[[self.accountToEdit objectForKey:kSSL] boolValue];
        self.enabledCheck.state =[[self.accountToEdit objectForKey:kEnabled] boolValue];
        self.selfSigned.state =[[self.accountToEdit objectForKey:kSelfSigned] boolValue];
        self.oldStyleSSL.state =[[self.accountToEdit objectForKey:kOldSSL] boolValue];
        
        if([[self.accountToEdit objectForKey:kOauth] boolValue] )
        {
            [self toggleGoogleTalkDisplay];
        }
        
        NSString *pass= [SAMKeychain passwordForService:@"Monal" account:[NSString stringWithFormat:@"%@",[self.accountToEdit objectForKey:kAccountID]]];
        
        if(pass) {
            self.password.stringValue =pass;
        }
    }
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) toggleGoogleTalkDisplay
{
    self.advancedBox.hidden =YES;
    self.password.hidden =YES;
    self.oAuthTokenButton.hidden =NO; 
}

-(void) refreshPresenter
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if([self.presentingViewController respondsToSelector:@selector(refreshAccountList)])
        {
            MLAccountSettings *presenter = (MLAccountSettings *)self.presentingViewController;
            [presenter refreshAccountList];
            [[MLXMPPManager sharedInstance]  connectIfNecessary];
        }
        [self.presentingViewController dismissViewController:self];
    });
}

#pragma mark Actons

-(IBAction)authenticateWithOAuth:(id)sender;
{
    
    NSArray *accounts= [[NXOAuth2AccountStore sharedStore] accountsWithAccountType:self.jabberID.stringValue];
    NXOAuth2AccountStore *store =[NXOAuth2AccountStore sharedStore];
    
    for(NXOAuth2Account *oauthAccount in accounts ) {
        [store removeAccount:oauthAccount];
    }
    
    
    [[NXOAuth2AccountStore sharedStore] setClientID:@"472865344000-q63msgarcfs3ggiabdobkkis31ehtbug.apps.googleusercontent.com"
                                             secret:@"IGo7ocGYBYXf4znad5Qhumjt"
                                              scope:[NSSet setWithArray:@[@"https://www.googleapis.com/auth/googletalk"]]
                                   authorizationURL:[NSURL URLWithString:@"https://accounts.google.com/o/oauth2/auth"]
                                           tokenURL:[NSURL URLWithString:@"https://www.googleapis.com/oauth2/v3/token"]
                                        redirectURL:[NSURL URLWithString:@"urn:ietf:wg:oauth:2.0:oob:auto"]
                                      keyChainGroup:@"MonalGTalk"
                                     forAccountType:self.jabberID.stringValue];
    
    [[NXOAuth2AccountStore sharedStore] requestAccessToAccountWithType:self.jabberID.stringValue
                                   withPreparedAuthorizationURLHandler:^(NSURL *preparedURL){
                                   
                                       
                                       self.oAuthURL= preparedURL;
                                       [self performSegueWithIdentifier:@"showOAuth" sender:self];
                                       
                                   }];

}

-(IBAction)save:(id)sender
{
    NSString *user=@"";
    NSString *domain=@"";
    
    srand([[NSDate date] timeIntervalSince1970]);
    NSString *resource=[NSString stringWithFormat:@"Monal-OSX.%d",rand()%100];

    NSString *port=@"";
    
    NSArray *parts = [self.jabberID.stringValue componentsSeparatedByString:@"@"];
    if(parts.count > 1) {
        user =[parts objectAtIndex:0];
        domain =[parts objectAtIndex:1];
    }
    
    if(self.server.stringValue.length==0)
    {
        self.server.stringValue = domain;
    }
    
    NSMutableDictionary *dic =[self.accountToEdit mutableCopy];
    if(!self.accountToEdit) {
        dic = [[NSMutableDictionary alloc] init];
        [dic setObject:domain forKey:kDomain];
    }
    else {
        dic =[self.accountToEdit mutableCopy];
    }
    
    
    if(self.port.stringValue.length>0)
    {
        port=self.port.stringValue;
    }
    
//    if(self.resource.stringValue.length>0)
//    {
//        resource=self.resource.stringValue;
//    }
    
    [dic setObject:user forKey:kUsername];
    [dic setObject:self.server.stringValue  forKey:kServer];
    [dic setObject:port forKey:kPort];
    [dic setObject:resource  forKey:kResource];
    
    [dic setObject:[NSNumber numberWithBool:self.sslCheck.state] forKey:kSSL];
    [dic setObject:[NSNumber numberWithBool:self.enabledCheck.state] forKey:kEnabled];
    [dic setObject:[NSNumber numberWithBool:self.selfSigned.state] forKey:kSelfSigned];
    [dic setObject:[NSNumber numberWithBool:self.oldStyleSSL.state] forKey:kOldSSL];
    
    BOOL isGtalk=NO;
    if([self.accountType isEqualToString:@"Gtalk"]) {
        isGtalk=YES;
    }
    
    [dic setObject:[NSNumber numberWithBool:isGtalk] forKey:kOauth];
    
    BOOL isEnabled =self.enabledCheck.state;
    NSString *passwordText =[self.password.stringValue copy] ;
    
    if(!self.accountToEdit) {
        [[DataLayer sharedInstance] addAccountWithDictionary:dic andCompletion:^(BOOL result) {
            if(result) {
                [[DataLayer sharedInstance] executeScalar:@"select max(account_id) from account" withCompletion:^(NSObject * accountid) {
                    if(accountid) {
                        [SAMKeychain setPassword:passwordText forService:@"Monal" account:[NSString stringWithFormat:@"%@", accountid]];
                        
                        [self refreshPresenter];
                        
                        if(isEnabled)
                        {
                            [[MLXMPPManager sharedInstance] connectAccount:[NSString stringWithFormat:@"%@", accountid]];
                        }
                        else
                        {
                            [[MLXMPPManager sharedInstance] disconnectAccount:[NSString stringWithFormat:@"%@", accountid]];
                        }
                        
                    }
                }];
            }
        }];
        
    }
    else
    {
        [[DataLayer sharedInstance] updateAccounWithDictionary:dic andCompletion:^(BOOL result) {
            [self refreshPresenter];
            [SAMKeychain setPassword:passwordText forService:@"Monal" account:[NSString stringWithFormat:@"%@", [self.accountToEdit objectForKey:kAccountID]]];
            
            if(isEnabled)
            {
                [[MLXMPPManager sharedInstance] connectAccount:[NSString stringWithFormat:@"%@",[self.accountToEdit objectForKey:kAccountID]]];
            }
            else
            {
                [[MLXMPPManager sharedInstance] disconnectAccount:[NSString stringWithFormat:@"%@",[self.accountToEdit objectForKey:kAccountID]]];
            }
        }];
        
        //out here to prevent a deadlocak on db queue
        if (!isEnabled)
        {
               [[DataLayer sharedInstance] resetContactsForAccount:[NSString stringWithFormat:@"%@",[self.accountToEdit objectForKey:kAccountID]]];
        }
        
    }

}


- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(nullable id)sender
{
     if([segue.identifier isEqualToString:@"showOAuth"]) {
         MLOAuthViewController *oauthVC = (MLOAuthViewController *)segue.destinationController;
       
         oauthVC.oAuthURL= self.oAuthURL;
         oauthVC.completionHandler=^(NSString *token) {
           //  self.password.stringValue = token;
             NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"urn:ietf:wg:oauth:2.0:oob:auto?code=%@", token]];
             [[NXOAuth2AccountStore sharedStore] handleRedirectURL:url];
             
         };
         
         
     }
}
@end
