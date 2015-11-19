//
//  MLAddContact.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/18/15.
//  Copyright © 2015 Monal.im. All rights reserved.
//

#import "MLAddContact.h"
#import "MLXMPPManager.h"
#import "DataLayer.h"

@interface MLAddContact ()
@property (nonatomic, strong) NSMutableArray *displyedAccounts;

@end

@implementation MLAddContact

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}


-(void) viewWillAppear
{
    NSArray *accountsArray = [[DataLayer sharedInstance] accountList];
    self.displyedAccounts= [[NSMutableArray alloc] init];
    
    for (NSDictionary *account in accountsArray)
    {
        if([[MLXMPPManager sharedInstance] isAccountForIdConnected:[NSString stringWithFormat:@"%@", [account objectForKey:@"account_id"]]])
        {
            [self.accounts addItemWithObjectValue:[NSString stringWithFormat:@"%@@%@", [account objectForKey:@"account_name"], [account objectForKey:@"domain"]]];
            [self.displyedAccounts addObject:account];
        }
    }
    
}

-(IBAction)add:(id)sender
{
    
}

@end
