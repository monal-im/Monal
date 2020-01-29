//
//  MLNewViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/28/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLNewViewController.h"

@interface MLNewViewController ()

@end

@implementation MLNewViewController

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
    return 2;
}

-(IBAction) close:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
