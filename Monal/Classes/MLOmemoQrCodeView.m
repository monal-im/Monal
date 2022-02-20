//
//  MLOmemoQrCodeView.m
//  Monal
//
//  Created by Friedrich Altheide on 05.02.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLOmemoQrCodeView.h"
#import "MLXMPPManager.h"
#import "SignalAddress.h"
#import "MLSignalStore.h"
#import "MLOMEMO.h"
#import "HelperTools.h"
#import "xmpp.h"

@interface MLOmemoQrCodeView ()

@property (nonatomic, weak) xmpp* account;
@property (weak, nonatomic) IBOutlet UIImageView* qrCodeView;

@end

@implementation MLOmemoQrCodeView

- (void)viewDidLoad {
    [super viewDidLoad];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
    [self loadKeysAndDisplayQRCode];
}

-(void) loadKeysAndDisplayQRCode
{
    NSMutableString* keyList = [[NSMutableString alloc] init];
    BOOL firstKey = YES;
    NSArray<NSNumber*>* devices = [self.account.omemo knownDevicesForAddressName:self.contact.contactJid];
    for(NSNumber* device in devices) {
        SignalAddress* address = [[SignalAddress alloc] initWithName:self.contact.contactJid deviceId:(int) device.integerValue];
        NSData* identity = [self.account.omemo getIdentityForAddress:address];

        // Only add trusted keys to the list
        if([self.account.omemo isTrustedIdentity:address identityKey:identity])
        {
            NSString* hexIdentity = [HelperTools signalHexKeyWithData:identity];
            NSString* keyString = [NSString stringWithFormat:@"%@omemo-sid-%@=%@", firstKey ? @"?" : @";", device, hexIdentity];
            [keyList appendString:keyString];
            firstKey = NO;
        }
    }
    NSString* contactString = [NSString stringWithFormat:@"xmpp:%@%@", self.contact.contactJid, keyList];

    CIImage* qrImage = [HelperTools createQRCodeFromString:contactString];

    if(qrImage) {
        self.qrCodeView.layer.magnificationFilter = kCAFilterNearest; // reduce blur
        self.qrCodeView.image = [[UIImage alloc] initWithCIImage:qrImage];
    } else {
        // to many device keys -> show error msg
        self.qrCodeView.image = nil;
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"To many device keys", @"OmemoQrCodeView") message:NSLocalizedString(@"You have to many enabled devices on this account. You need to remove some devices", @"OmemoQrCodeView") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action __unused) {
            // close alert and segue to previous view controller
            [alert dismissViewControllerAnimated:YES completion:nil];
            [self.navigationController popViewControllerAnimated:YES];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
