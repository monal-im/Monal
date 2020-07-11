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
    if(self.ownKeys) {
        self.navigationItem.title=NSLocalizedString(@"My Encryption Keys",@"");
    } else  {
        self.navigationItem.title=NSLocalizedString(@"Encryption Keys",@"");
    }
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
#ifndef DISABLE_OMEMO
    self.devices= [self.account.monalSignalStore knownDevicesForAddressName:self.contact.contactJid];
#endif
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
    SignalAddress *address = [[SignalAddress alloc] initWithName:self.contact.contactJid deviceId:(int) device.integerValue];
    
#ifndef DISABLE_OMEMO
    NSData *identity=[self.account.monalSignalStore getIdentityForAddress:address];
    
    cell.key.text = [HelperTools signalHexKeyWithData:identity];
    cell.toggle.on = [self.account.monalSignalStore isTrustedIdentity:address identityKey:identity];
    cell.toggle.tag= 100+indexPath.row;
    [cell.toggle addTarget:self action:@selector(toggleTrust:) forControlEvents:UIControlEventValueChanged];
    if(device.integerValue == self.account.monalSignalStore.deviceid)
    {
        cell.deviceid.text = [NSString stringWithFormat:NSLocalizedString(@"%ld (This device)",@""), (long)device.integerValue];
    } else  {
        cell.deviceid.text = [NSString stringWithFormat:@"%ld", (long)device.integerValue];
    }
#endif
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn=nil;
    if(section==0)
    {
        if(self.ownKeys) {
            toreturn= NSLocalizedString(@"These are your encryption keys. Each device is a different place you have logged in. You should trust a key when you have verified it.",@"");
        } else {
            toreturn= NSLocalizedString(@"You should trust a key when you have verified it. Verify by comparing the key below to the one on your contact's screen.",@""); ///or scan their QR code
        }
    }
    
    return toreturn;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString* toreturn=nil;
    if(section==0)
        toreturn= NSLocalizedString(@"Monal uses OMEMO encryption to protect your conversations",@"");
    
    return toreturn;
}

-(void) toggleTrust:(id) sender
{
    UISwitch *button =(UISwitch *)sender;
    NSInteger row = button.tag-100;
    
#ifndef DISABLE_OMEMO
    NSNumber *device =[self.devices objectAtIndex:row];
    SignalAddress *address = [[SignalAddress alloc] initWithName:self.contact.contactJid deviceId:(int) device.integerValue];
    
    NSData *identity=[self.account.monalSignalStore getIdentityForAddress:address];
    
    BOOL newTrust;
    if( [self.account.monalSignalStore isTrustedIdentity:address identityKey:identity]) {
        newTrust=NO;
    } else  {
        newTrust=YES;
    }
    
    [self.account.monalSignalStore updateTrust:newTrust forAddress:address];
#endif
}

@end
