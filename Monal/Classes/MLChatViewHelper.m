//
//  MLChatViewHelper.m
//  Monal
//
//  Created by Friedrich Altheide on 04.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLChatViewHelper.h"
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLContact.h>

@import UIKit.UIAlertController;

@implementation MLChatViewHelper

+(void) toggleEncryptionForContact:(MLContact*) contact withSelf:(id) andSelf afterToggle:(void (^)(void)) afterToggle
{
    // Update the encryption value in the caller class
    if(![contact toggleEncryption:!contact.isEncrypted])
    {
        // Show a warning when no device keys could be found and the user tries to enable encryption -> encryption is not possible
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Encryption Not Supported", @"") message:NSLocalizedString(@"This contact does not appear to have any devices that support encryption, please try again later if you think this is wrong.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action __unused) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];

        // open the alert msg in the calling view controller
        [andSelf presentViewController:alert animated:YES completion:nil];
    }

    // Call the code that should update the UI elements
    afterToggle();
}

@end
