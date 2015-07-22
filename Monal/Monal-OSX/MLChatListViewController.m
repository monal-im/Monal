//
//  MLChatListViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/28/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "MLChatListViewController.h"
#import "MLChatListCell.h"

@interface MLChatListViewController ()

@end

@implementation MLChatListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.chatListTable.backgroundColor= [NSColor clearColor];
}


#pragma mark -table view datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return 2;
}

#pragma mark - table view delegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn  row:(NSInteger)row
{

    MLChatListCell *cell = [tableView makeViewWithIdentifier:@"OnlineUser" owner:self];
    
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    return 60.0f;
}


@end
