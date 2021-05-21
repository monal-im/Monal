//
//  MLSubscriptionTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/24/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLSubscriptionTableViewController.h"
#import "DataLayer.h"
#import "MLXMPPManager.h"
#import "xmpp.h"

@interface MLSubscriptionTableViewController ()
@property (nonatomic, strong) NSMutableArray *requests;
@end

@implementation MLSubscriptionTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}


-(void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSMutableArray* result = [[DataLayer sharedInstance] contactRequestsForAccount];
    self.requests = result;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
   return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.requests.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"subCell" forIndexPath:indexPath];
    
    MLContact *contact = self.requests[indexPath.row];
    cell.textLabel.text= contact.contactJid;
    xmpp* account =[[MLXMPPManager sharedInstance] getConnectedAccountForID:contact.accountId];
    cell.detailTextLabel.text=[NSString stringWithFormat:NSLocalizedString(@"Account: %@",@ ""),account.connectionProperties.identity.jid];
    
    return cell;
}


- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}



-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return NSLocalizedString(@"Allowing someone to add you as a contact lets them see when you are online. It also allows you to send encrypted messages.  Tap to approve. Swipe to reject.",@ "");
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        MLContact *contact = self.requests[indexPath.row];
        [[MLXMPPManager sharedInstance] rejectContact:contact];
        [[DataLayer sharedInstance] deleteContactRequest:contact];
        [self.requests removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    MLContact *contact = self.requests[indexPath.row];
    [[MLXMPPManager sharedInstance] addContact:contact];
    [self.requests removeObjectAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
}


@end
