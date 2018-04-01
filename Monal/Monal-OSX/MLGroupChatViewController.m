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
    if([MLXMPPManager sharedInstance].connectedXMPP.count<=self.accounts.indexOfSelectedItem) return;
    
    NSDictionary *accountrow = [MLXMPPManager sharedInstance].connectedXMPP[self.accounts.indexOfSelectedItem];
    xmpp* account= (xmpp*)[accountrow objectForKey:kXmppAccount];
    
    if(self.favorite.state==NSControlStateValueOn){
        BOOL autoJoinValue=NO;
        if(self.autoJoin.state==NSControlStateValueOn) autoJoinValue=YES;
        
        [[DataLayer sharedInstance] addMucFavoriteForAccount:account.accountNo withRoom:self.room.stringValue nick:self.nick.stringValue autoJoin:autoJoinValue andCompletion:nil];
    }

    [[MLXMPPManager sharedInstance] joinRoom:self.room.stringValue withNick:self.nick.stringValue andPassword:self.password.stringValue forAccountRow:self.accounts.indexOfSelectedItem];
    
    [[DataLayer sharedInstance] updateOwnNickName:self.nick.stringValue forMuc:self.room.stringValue forAccount:account.accountNo];
}

@end
