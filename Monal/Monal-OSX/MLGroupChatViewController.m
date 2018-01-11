//
//  MLGroupChatViewController.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/10/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLGroupChatViewController.h"
#import "MLXMPPManager.h"
#import "DataLayer.h"

@interface MLGroupChatViewController ()

@end

@implementation MLGroupChatViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

-(void) viewWillAppear
{
    NSInteger pos=0;
    while (pos<[MLXMPPManager sharedInstance].connectedXMPP.count)
    {
        [self.accounts addItemWithObjectValue:[[MLXMPPManager sharedInstance] getAccountNameForConnectedRow:pos]];
        pos++;
    }
    
}

-(IBAction)join:(id)sender
{
    NSDictionary *accountrow = [MLXMPPManager sharedInstance].connectedXMPP[self.accounts.indexOfSelectedItem];
    xmpp* account= (xmpp*)[accountrow objectForKey:@"xmppAccount"];
    
    [[DataLayer sharedInstance] addMucFavoriteForAccount:account.accountNo withRoom:self.room.stringValue nick:self.nick.stringValue autoJoin:0 andCompletion:nil];
    [[MLXMPPManager sharedInstance] joinRoom:self.room.stringValue withPassword:self.password.stringValue forAccountRow:self.accounts.indexOfSelectedItem];
}

@end
