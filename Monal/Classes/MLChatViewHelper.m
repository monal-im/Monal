//
//  MLChatViewHelper.m
//  Monal
//
//  Created by Friedrich Altheide on 04.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLChatViewHelper.h"
#import "DataLayer.h"
#import "MLContact.h"

@implementation MLChatViewHelper

+(void) toggleEncryptionForContact:(MLContact*) contact withKnownDevices:(NSArray*) knownDevices withSelf:(id) andSelf afterToggle:(void (^)(void)) afterToggle {
    if(knownDevices.count == 0 && contact.isEncrypted == NO) {
        // Show a warning when no device keys could be found and the user tries to enable encryption -> encryption is not possible
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Encryption Not Supported", @"") message:NSLocalizedString(@"This contact does not appear to have any devices that support encryption.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];

        // open the alert msg in the calling view controller
        [andSelf presentViewController:alert animated:YES completion:nil];
    }
    else
    {
        if(contact.isEncrypted == YES)
        {
            [[DataLayer sharedInstance] disableEncryptForJid:contact.contactJid andAccountNo:contact.accountId];
        }
        else
        {
            [[DataLayer sharedInstance] encryptForJid:contact.contactJid andAccountNo:contact.accountId];
        }
        // Update the encryption value in the caller class
        contact.isEncrypted = !(contact.isEncrypted);
        // Call the code that should update the UI elements
        afterToggle();
    }
}

@end
