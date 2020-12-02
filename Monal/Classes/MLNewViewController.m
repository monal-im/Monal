//
//  MLNewViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/28/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLNewViewController.h"
#import "MLEditGroupViewController.h"
#import "MLSubscriptionTableViewController.h"
#import "addContact.h"

@interface MLNewViewController ()

@end

@implementation MLNewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

-(IBAction) close:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"newContact"])
    {
       addContact* newScreen = (addContact *)segue.destinationViewController;
       newScreen.completion = ^(MLContact *selectedContact) {
           if(self.selectContact) self.selectContact(selectedContact);
       };
    }
    else if([segue.identifier isEqualToString:@"newGroup"])
    {
        MLEditGroupViewController* newScreen = (MLEditGroupViewController *)segue.destinationViewController;
        newScreen.completion = ^(MLContact *selectedContact) {
            if(self.selectContact) self.selectContact(selectedContact);
        };
    }
    else if([segue.identifier isEqualToString:@"acceptContact"]) {
        //MLSubscriptionTableViewController* newScreen = (MLSubscriptionTableViewController *)segue.destinationViewController;
    }
}

@end
