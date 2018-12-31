//
//  MLKeysTableViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/30/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLKeysTableViewController.h"
#import "MLXMPPManager.h"
#import "MLKeyCell.h"

@interface MLKeysTableViewController ()
@property (nonatomic, weak) xmpp *account;
@property (nonatomic, strong) NSArray * devices;
@end

@implementation MLKeysTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title=@"Encryption Keys";
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:[NSString stringWithFormat:@"%@",[self.contact objectForKey:@"account_id"]]];
    self.devices= [self.account.monalSignalStore allDeviceIdsForAddressName:[self.contact objectForKey:@"buddy_name"]];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.devices.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MLKeyCell *cell = (MLKeyCell *) [tableView dequeueReusableCellWithIdentifier:@"key" forIndexPath:indexPath];
    
    NSNumber *device =[self.devices objectAtIndex:indexPath.row];
    SignalAddress *address = [[SignalAddress alloc] initWithName:[self.contact objectForKey:@"buddy_name"] deviceId:device.integerValue];
    
    NSData *identity=[self.account.monalSignalStore getIdentityForAddress:address];
    
    cell.key.text = [EncodingTools hexadecimalString:identity];
    cell.toggle.on = [self.account.monalSignalStore isTrustedIdentity:address identityKey:identity];
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn=nil;
    if(section==0)
        toreturn= @"You should trust a key when you have verified it. Verify by comparing the key below to the one on your contact's screen or scan their QR code.";
    
    return toreturn;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString* toreturn=nil;
    if(section==0)
        toreturn= @"Monal uses OMEMO encryption to protect your conversations";
    
    return toreturn;
}

@end
