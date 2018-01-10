//
//  MLGroupChatViewController.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/10/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLGroupChatViewController.h"
#import "MLXMPPManager.h"

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
    
}

@end
