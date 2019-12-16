//
//  MLKeyViewContoller.m
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 1/10/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import "MLKeyViewController.h"
#import "MLXMPPManager.h"
#import "MLKeyRow.h"

@interface MLKeyViewController ()
@property (nonatomic, weak) xmpp *account;
@property (nonatomic, strong) NSArray * devices;
@end

@implementation MLKeyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

-(void)viewWillAppear
{
    [super viewWillAppear];
    if(self.ownKeys) {
        self.view.window.title=@"My Encryption Keys";
    } else  {
        self.view.window.title=@"Encryption Keys";
    }
    
    self.account=[[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    self.devices= [self.account.monalSignalStore allDeviceIdsForAddressName:self.contact.contactJid];
    self.jid.stringValue =self.contact.contactJid;
    [self.table reloadData];
    
    if(self.ownKeys) {
        self.topText.stringValue= @"These are your encryption keys. Each device is a different place you have logged in. You should trust a key when you have verified it.";
    } else {
         self.topText.stringValue= @"You should trust a key when you have verified it. Verify by comparing the key below to the one on your contact's screen."; ///or scan their QR code
    }
        
}


#pragma mark  - tableview datasource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
{
    return self.devices.count;
}


#pragma  mark - tableview delegate
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row;
{
    MLKeyRow *cell = [tableView makeViewWithIdentifier:@"KeyRow" owner:nil];
    
    NSNumber *device =[self.devices objectAtIndex:row];
    SignalAddress *address = [[SignalAddress alloc] initWithName:self.contact.contactJid deviceId:(int) device.integerValue];
    
    NSData *identity=[self.account.monalSignalStore getIdentityForAddress:address];
    if(identity) {
    cell.key.stringValue = [EncodingTools signalHexKeyWithData:identity];
    }
    if( [self.account.monalSignalStore isTrustedIdentity:address identityKey:identity])
    {
        [cell.toggle setState:NSControlStateValueOn];
    } else  {
        [cell.toggle setState:NSControlStateValueOff];
    }
    
    if(device.integerValue == self.account.monalSignalStore.deviceid)
    {
        cell.deviceid.stringValue = [NSString stringWithFormat:@"%ld (This device)", (long)device.integerValue];
    } else  {
        cell.deviceid.stringValue = [NSString stringWithFormat:@"%ld", (long)device.integerValue];
    }
    
    [cell.toggle setTag:100+row];
    [cell.toggle setAction:@selector(toggleTrust:)];
    return cell;
}



-(void) toggleTrust:(id) sender
{
    NSButton *button =(NSButton *)sender;
    NSInteger row = button.tag-100;
    
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
}

@end
