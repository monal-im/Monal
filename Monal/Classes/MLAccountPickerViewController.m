//
//  MLAccountPickerViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/10/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLAccountPickerViewController.h"
#import <monalxmpp/MLXMPPManager.h>
#import <monalxmpp/xmpp.h>

@interface MLAccountPickerViewController ()

@end

@implementation MLAccountPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
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
    xmpp* xmppAccount = [MLXMPPManager sharedInstance].connectedXMPP[indexPath.row];
    cell.textLabel.text=xmppAccount.connectionProperties.identity.jid;
    return cell;
}


-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if(self.completion) self.completion(indexPath.row);
    [self.navigationController popViewControllerAnimated:YES];
}


@end
