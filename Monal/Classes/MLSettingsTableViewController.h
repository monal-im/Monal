//
//  MLSettingsTableViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/26/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
@import MessageUI;
@import StoreKit;
#import "MLConstants.h"
#import "AccountListController.h"

@interface MLSettingsTableViewController : AccountListController <MFMailComposeViewControllerDelegate, SKStoreProductViewControllerDelegate>

- (IBAction)close:(id) sender;

@end
