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
#import "MLOMEMO.h"
#import "SignalAddress.h"
#import "MLSignalStore.h"
#import "MLOmemoQrCodeView.h"

@interface MLKeysTableViewController ()

@property (nonatomic, weak) xmpp *account;
@property (nonatomic, strong) NSMutableArray<NSNumber*> * devices;
@property (nonatomic, assign) NSInteger ownKeyRow;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *qrCodeScanButton;

enum MLKeysTableViewControllerSections {
    keysSection,
    MLKeysTableViewControllerSectionCnt
};


@end

@implementation MLKeysTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if(self.ownKeys) {
        self.navigationItem.title=NSLocalizedString(@"My Encryption Keys", @"");
    } else  {
        self.navigationItem.title=NSLocalizedString(@"Encryption Keys", @"");
    }
    self.ownKeyRow = -1;
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
#ifndef DISABLE_OMEMO
    self.devices = [[NSMutableArray alloc] initWithArray:[self.account.omemo knownDevicesForAddressName:self.contact.contactJid]];
#endif
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MLKeysTableViewControllerSectionCnt;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.devices.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MLKeyCell* cell = (MLKeyCell *) [tableView dequeueReusableCellWithIdentifier:@"key" forIndexPath:indexPath];

#ifndef DISABLE_OMEMO
    NSNumber* device = [self.devices objectAtIndex:indexPath.row];
    SignalAddress* address = [[SignalAddress alloc] initWithName:self.contact.contactJid deviceId:(int) device.integerValue];

    NSData* identity = [self.account.omemo getIdentityForAddress:address];

    cell.key.text = [HelperTools signalHexKeyWithSpacesWithData:identity];
    cell.toggle.on = [self.account.omemo isTrustedIdentity:address identityKey:identity];
    cell.toggle.tag = 100 + indexPath.row;
    [cell.toggle addTarget:self action:@selector(toggleTrust:) forControlEvents:UIControlEventValueChanged];
    if(device.integerValue == self.account.omemo.monalSignalStore.deviceid)
    {
        cell.deviceid.text = [NSString stringWithFormat:NSLocalizedString(@"%ld (This device)", @""), (long)device.integerValue];
        self.ownKeyRow = indexPath.row;
    } else  {
        cell.deviceid.text = [NSString stringWithFormat:@"%ld", (long)device.integerValue];
    }
#endif
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString* toreturn = nil;
    if(section == 0)
    {
        if(self.ownKeys) {
            toreturn = NSLocalizedString(@"These are your encryption keys. Each device is a different place you have logged in. You should trust a key when you have verified it.", @"");
        } else {
            toreturn = NSLocalizedString(@"You should trust a key when you have verified it. Verify by comparing the key below to the one on your contact's screen.", @""); ///or scan their QR code
        }
    }

    return toreturn;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString* toreturn = nil;
    if(section == 0)
        toreturn = NSLocalizedString(@"Monal uses OMEMO encryption to protect your conversations", @"");

    return toreturn;
}

-(void) toggleTrust:(id) sender
{
    UISwitch* button = (UISwitch *)sender;
    NSInteger row = button.tag - 100;

#ifndef DISABLE_OMEMO
    NSNumber* device = [self.devices objectAtIndex:row];
    SignalAddress* address = [[SignalAddress alloc] initWithName:self.contact.contactJid deviceId:(int) device.integerValue];

    NSData* identity = [self.account.omemo.monalSignalStore getIdentityForAddress:address];

    BOOL newTrust;
    int internalTrustLevel = [self.account.omemo.monalSignalStore getInternalTrustLevel:address identityKey:identity];
    if(internalTrustLevel == MLOmemoInternalTrusted) {
        newTrust = NO;
    } else { // MLOmemoInternalToFU || MLOmemoInternalNotTrusted
        newTrust = YES;
    }
    [self.account.omemo updateTrust:newTrust forAddress:address];
#endif
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // We can only delete devices if we are bound or hibernated
    if(self.account.accountState < kStateBound) return NO;

    // Only allow deleting other keys from this account
    return self.ownKeys && indexPath.row != self.ownKeyRow && indexPath.section == keysSection;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if(!self.ownKeys) return; // Only allow deleting own keys

        if(indexPath.section == keysSection) {
            // get device rid
#ifndef DISABLE_OMEMO
            NSNumber* device = [self.devices objectAtIndex:indexPath.row];
            [self.account.omemo deleteDeviceForSource:self.contact.contactJid andRid:device.intValue];
            // Send own updated omemo devices
            [self.account.omemo sendOMEMODeviceWithForce:YES];
#endif // DISABLE_OMEMO
            // delete device from tableView
            [self.devices removeObjectAtIndex:indexPath.row];
            [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
        }
    }
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if([segue.identifier isEqualToString:@"showOwnQRCode"])
    {
        MLOmemoQrCodeView* oQrCodeView = segue.destinationViewController;
        MLContact* ownContact = [[MLContact alloc] init];
        ownContact.contactJid = self.account.connectionProperties.identity.jid;
        ownContact.accountId = self.account.accountNo;

        oQrCodeView.contact = ownContact;
    }
    else if([segue.identifier isEqualToString:@"showScanQRCode"])
    {
        MLQRCodeScanner* qrCodeScanner = (MLQRCodeScanner *) segue.destinationViewController;
        qrCodeScanner.contactDelegate = self;
    }
}


-(void) MLQRCodeContactScannedWithJid:(NSString *)jid fingerprints:(NSDictionary<NSNumber *,NSString *> *)fingerprints
{
    // untrust all devices from jid
    [self.account.omemo untrustAllDevicesFrom:jid];
    DDLogInfo(@"Removing trust for all devices from jid %@", jid);

    // get new list with all known devices for jid
    NSArray<NSNumber*>* knownDevices = [self.account.omemo knownDevicesForAddressName:jid];
    for(NSNumber* qrDeviceId in fingerprints)
    {
        if([knownDevices containsObject:qrDeviceId])
        {
            SignalAddress* address = [[SignalAddress alloc] initWithName:jid deviceId:(int) qrDeviceId.integerValue];
            NSData* identity = [self.account.omemo getIdentityForAddress:address];
            NSString* knownIdentity = [HelperTools signalHexKeyWithData:identity];

            // check that the fingerprint match
            if([knownIdentity.uppercaseString isEqualToString:fingerprints[qrDeviceId].uppercaseString])
            {
                // trust this device
                [self.account.omemo updateTrust:YES forAddress:address];
                DDLogInfo(@"Trusting jid: %@ with device id %@", jid, qrDeviceId);
            }
        }
        else
        {
            // TODO: save fingerprint and trust separately in another table
        }
    }
    // Close QR-Code scanner
    [self.navigationController popViewControllerAnimated:YES];
}

@end
