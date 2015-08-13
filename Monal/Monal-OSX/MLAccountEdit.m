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

@interface MLAccountEdit ()

@end

@implementation MLAccountEdit

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

-(void) viewWillAppear {
    [super viewWillAppear];
    if(!self.accountToEdit) {
        if([self.accountType isEqualToString:@"Gtalk"]) {
            self.server.stringValue= @"talk.google.com";
            self.jabberID.stringValue=@"@gmail.com";
        }
    } else  {
        self.jabberID.stringValue =[NSString stringWithFormat:@"%@@%@", [self.accountToEdit objectForKey:kUsername], [self.accountToEdit objectForKey:kDomain]];
        
        self.server.stringValue =[self.accountToEdit objectForKey:kServer];
        self.port.stringValue =[NSString stringWithFormat:@"%@", [self.accountToEdit objectForKey:kPort]];
        self.resource.stringValue =[self.accountToEdit objectForKey:kResource];
        
        self.sslCheck.state =[[self.accountToEdit objectForKey:kSSL] boolValue];
        self.enabledCheck.state =[[self.accountToEdit objectForKey:kEnabled] boolValue];
        self.selfSigned.state =[[self.accountToEdit objectForKey:kSelfSigned] boolValue];
        self.oldStyleSSL.state =[[self.accountToEdit objectForKey:kOldSSL] boolValue];
    }
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
-(IBAction)save:(id)sender
{
    NSString *user=@"";
    NSString *domain=@"";
    
    NSArray *parts = [self.jabberID.stringValue componentsSeparatedByString:@"@"];
    if(parts.count > 1) {
        user =[parts objectAtIndex:0];
        domain =[parts objectAtIndex:1];
    }
    
    BOOL enabled =self.enabledCheck.state;
    
    BOOL useSSL =self.sslCheck.state;
    BOOL selfSignedSSL = self.selfSigned.state;
    BOOL oldStyleSSL=self.oldStyleSSL.state;
    
    if(!self.accountToEdit) {
    [[DataLayer sharedInstance] addAccount:
     self.jabberID.stringValue  :
     @"1":
    user:
     @"":
     self.server.stringValue :
     self.port.stringValue :
     useSSL:
     self.resource.stringValue:
             domain:
     enabled:
     selfSignedSSL:
     oldStyleSSL
     ];
    
    
    [[DataLayer sharedInstance] executeScalar:@"select max(account_id) from account" withCompletion:^(NSObject * accountid) {
        if(accountid) {
        // save password
        NSString* val = [NSString stringWithFormat:@"%@", (NSString *) accountid ];
        PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",val]];
        [pass setPassword:self.password.stringValue] ;
            [self refreshPresenter];
        }
       
    }];
   
    }
    else
    {
        
        NSMutableDictionary *dic =[self.accountToEdit mutableCopy];
        [dic setObject:user forKey:kUsername];
        [dic setObject:self.server.stringValue  forKey:kServer];
        [dic setObject:self.port.stringValue forKey:kPort];
        [dic setObject:self.resource.stringValue  forKey:kResource];
        
        [dic setObject:[NSNumber numberWithBool:self.sslCheck.state] forKey:kSSL];
        [dic setObject:[NSNumber numberWithBool:self.enabledCheck.state] forKey:kEnabled];
        [dic setObject:[NSNumber numberWithBool:self.selfSigned.state] forKey:kSelfSigned];
        [dic setObject:[NSNumber numberWithBool:self.oldStyleSSL.state] forKey:kOldSSL];
        
        [[DataLayer sharedInstance] updateAccounWithDictionary:dic andCompletion:^(BOOL result) {
            [self refreshPresenter];
            
            if(self.password.stringValue.length>0) {
                PasswordManager* pass= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",[self.accountToEdit objectForKey:kAccountID]]];
                [pass setPassword:self.password] ;
            }
            
        }];
        
    }
    
    if(enabled)
    {
        [[MLXMPPManager sharedInstance] connectAccount:[NSString stringWithFormat:@"%@",[self.accountToEdit objectForKey:kAccountID]]];
    }
    else
    {
        [[MLXMPPManager sharedInstance] disconnectAccount:[NSString stringWithFormat:@"%@",[self.accountToEdit objectForKey:kAccountID]]];
    }
    
    
}

@end
