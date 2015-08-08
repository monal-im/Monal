//
//  MLAccountRow.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/7/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLAccountRow.h"
#import "DataLayer.h"

@implementation MLAccountRow

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
}

-(void) updateWithAccountDictionary:(NSDictionary *)account
{
    self.account = account;
    self.enabledCheckBox.state= [[self.account objectForKey:@"enabled"] boolValue];
    self.enabledCheckBox.title= [NSString stringWithFormat:@"%@@@%@", [self.account objectForKey:@"account_name"], [self.account objectForKey:@"domain"]];
}

-(IBAction)checkBoxAction:(id)sender;
{

    [[DataLayer sharedInstance] updateAccount:
                                 [NSString stringWithFormat:@"%@@@%@", [self.account objectForKey:@"account_name"], [self.account objectForKey:@"domain"]]
                                 @"1":
                                             [self.account objectForKey:@"username"] :
                                 @"" :
                                 [self.account objectForKey:@"server"]:
                                 [self.account objectForKey:@"port"]:
                                    [self.account objectForKey:@"secure"]:
                                    [self.account objectForKey:@"resource"]:
                                               [self.account objectForKey:@"domain"]:
                                    self.enabledCheckBox.state
                                        [self.account objectForKey:@"account_is"]:
                                 self.selfSignedSSL:
                                 self.oldStyleSSL];
}


@end
