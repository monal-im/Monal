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
    }
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
    
    BOOL enabled =YES;
    
    BOOL useSSL =YES;
    BOOL selfSignedSSL = YES;
    BOOL oldStyleSSL=NO;
    
    
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
    
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if([self.presentingViewController respondsToSelector:@selector(refreshAccountList)])
            {
                MLAccountSettings *presenter = (MLAccountSettings *)self.presentingViewController;
                [presenter refreshAccountList];
                [[MLXMPPManager sharedInstance]  connectIfNecessary];
            }
            [self.presentingViewController dismissViewController:self];
        });
    }];
   
    
}

@end
