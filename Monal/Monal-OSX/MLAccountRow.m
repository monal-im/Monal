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
    self.accountName.stringValue= [NSString stringWithFormat:@"%@@%@", [self.account objectForKey:@"account_name"], [self.account objectForKey:@"domain"]];
}

-(IBAction)checkBoxAction:(id)sender;
{

    NSMutableDictionary *mutableAccount= [self.account mutableCopy];
    [mutableAccount setObject:[NSNumber numberWithBool:self.enabledCheckBox.state] forKey:kEnabled];
    
    [[DataLayer sharedInstance] updateAccounWithDictionary:mutableAccount andCompletion:nil];
    self.account= [mutableAccount copy];
     
}


@end
