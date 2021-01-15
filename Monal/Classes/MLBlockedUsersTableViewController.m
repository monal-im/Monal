//
//  MLBlockedUsersTableViewController.m
//  Monal
//
//  Created by Friedrich Altheide on 10.01.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLBlockedUsersTableViewController.h"
#import "DataLayer.h"
#import "MBProgressHUD.h"
#import "MLXMPPManager.h"
#import "HelperTools.h"

@interface MLBlockedUsersTableViewController ()

@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString*, NSString*>*>* blockedJids;
@property (nonatomic, strong) MBProgressHUD* blockingHUD;

- (IBAction)addBlockButton:(id)sender;

@end

@implementation MLBlockedUsersTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

-(void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if(!self.xmppAccount) return;
    [self reloadBlocksFromDB];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshBlockState:) name:kMonalBlockListRefresh object:nil];

    self.blockingHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.blockingHUD.label.text = NSLocalizedString(@"Saving changes to server", @"");
    self.blockingHUD.mode = MBProgressHUDModeIndeterminate;
    self.blockingHUD.removeFromSuperViewOnHide = YES;
    self.blockingHUD.hidden = YES;
}

-(void) reloadBlocksFromDB
{
    self.blockedJids = [[NSMutableArray alloc] initWithArray:[[DataLayer sharedInstance] blockedJidsForAccount:self.xmppAccount.accountNo]];
}

-(void) refreshBlockState:(NSNotification*) notification
{
    if([notification.userInfo[@"accountNo"] isEqualToString:self.xmppAccount.accountNo]) {
        weakify(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            strongify(self);
            [self reloadBlocksFromDB];
            [self.tableView reloadData];
            self.blockingHUD.hidden = YES;
            [self.blockingHUD hideAnimated:YES afterDelay:30];
        });
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.blockedJids.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"blockUser" forIndexPath:indexPath];

    cell.textLabel.text = self.blockedJids[indexPath.row][@"fullBlockedJid"];

    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.xmppAccount.connectionProperties.supportsBlocking;
}


- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if(!self.xmppAccount.connectionProperties.supportsBlocking) return;
        // unblock jid
        [[MLXMPPManager sharedInstance] blocked:NO Jid:self.blockedJids[indexPath.row][@"fullBlockedJid"] Account:self.xmppAccount.accountNo];

        self.blockingHUD.hidden = NO;
    }
}


- (IBAction)addBlockButton:(id)sender {
    if(!self.xmppAccount.connectionProperties.supportsBlocking)
    {
        // show blocking is not supported alert
        UIAlertController* blockUnsuported = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Blocking is not supported by the server", @"") message:nil preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"") style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction * action) {}];
        [blockUnsuported addAction:defaultAction];
        [self presentViewController:blockUnsuported animated:YES completion:nil];
    }

    UIAlertController* blockJidForm = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Enter the jid that you want to block", @"") message:nil preferredStyle:UIAlertControllerStyleAlert];
    // add password field to alert
    [blockJidForm addTextFieldWithConfigurationHandler:^(UITextField* passwordField) {
        passwordField.secureTextEntry = NO;
        passwordField.placeholder = NSLocalizedString(@"user@example.org/resource", @"BlockUserTable - blockJidForm");
    }];

    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Block", @"") style:UIAlertActionStyleDefault
       handler:^(UIAlertAction * action) {
        NSString* jidToBlock = [blockJidForm textFields][0].text;
        // try to split the jid
        NSDictionary* splittedJid = [HelperTools splitJid: jidToBlock];
        if(splittedJid[@"host"])
        {
            self.blockingHUD.hidden = NO;

            // block the jid
            [[MLXMPPManager sharedInstance] blocked:YES Jid:jidToBlock Account:self.xmppAccount.accountNo];

            // close form
            [blockJidForm dismissViewControllerAnimated:YES completion:nil];
        }
        else
        {
            UIAlertController* invalidJid = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Input is not a valid jid", @"") message:nil preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"") style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * action) {}];
            [invalidJid addAction:defaultAction];
            [self presentViewController:invalidJid animated:YES completion:nil];
        }
    }];

    [blockJidForm addAction:defaultAction];
    [self presentViewController:blockJidForm animated:YES completion:nil];
}
@end
