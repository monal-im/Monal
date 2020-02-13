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

@interface MLSubscriptionTableViewController ()
@property (nonatomic, strong) NSMutableArray *requests;
@end

@implementation MLSubscriptionTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}


-(void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[DataLayer sharedInstance] contactRequestsForAccountWithCompletion:^(NSMutableArray *result) {
        self.requests=result;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    }];

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
    
    return cell;
}


/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

@end
