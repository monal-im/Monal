//
//  MLAccountPickerViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/10/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLAccountPickerViewController.h"
#import "MLXMPPManager.h"

@interface MLAccountPickerViewController ()

@end

@implementation MLAccountPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[MLXMPPManager sharedInstance].connectedXMPP count];
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AccountCell" forIndexPath:indexPath];
    NSDictionary *row=[MLXMPPManager sharedInstance].connectedXMPP[indexPath.row];
    xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
    cell.textLabel.text=xmppAccount.connectionProperties.identity.jid;
    
    return cell;
}





@end
