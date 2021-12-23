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

+(void) toggleEncryptionForContact:(MLContact*) contact withSelf:(id) andSelf afterToggle:(void (^)(void)) afterToggle
{
    // Update the encryption value in the caller class
    if(![contact toggleEncryption:!contact.isEncrypted])
    {
        // Show a warning when no device keys could be found and the user tries to enable encryption -> encryption is not possible
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Encryption Not Supported", @"") message:NSLocalizedString(@"This contact does not appear to have any devices that support encryption.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }]];

        // open the alert msg in the calling view controller
        [andSelf presentViewController:alert animated:YES completion:nil];
    }

    // Call the code that should update the UI elements
    afterToggle();
}

@end
