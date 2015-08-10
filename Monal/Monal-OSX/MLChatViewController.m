//
//  MLChatViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLChatViewController.h"

@interface MLChatViewController ()

@end

@implementation MLChatViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}



-(void) showConversationForContact:(NSDictionary *) contact
{
    
}


#pragma mark - actions 
-(IBAction)send:(id)sender
{
    
}

#pragma mark -table view datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return 0;
}

#pragma mark - table view delegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn  row:(NSInteger)row
{
    
 // MLchatViewCell *cell= [tableView makeViewWithIdentifier:cellIdentifier owner:self];
    return nil;
}


@end
