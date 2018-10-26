//
//  MLSelectionController.m
//  Monal
//
//  Created by Anurodh Pokharel on 10/26/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLSelectionController.h"

@interface MLSelectionController ()

@end

@implementation MLSelectionController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

-(void) viewWillDisappear:(BOOL)animated {
    if(self.completion) {
        self.completion(self.selection);
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.options.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option" forIndexPath:indexPath];
    cell.textLabel.text = self.options[indexPath.row];
    if([self.selection isEqualToString: cell.textLabel.text]) {
        cell.accessoryType=UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType= UITableViewCellAccessoryNone;
    }
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    self.selection= self.options[indexPath.row];
    [tableView reloadData];
}


@end
