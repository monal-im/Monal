//
//  MLKeysTableViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/30/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//
#import <UIKit/UIKit.h>
#import "xmpp.h"
#import "MLContact.h"
#import <Monal-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLKeysTableViewController : UITableViewController<MLLQRCodeScannerContactDelegate>
@property (nonatomic, assign) BOOL ownKeys;
@property (nonatomic, strong) MLContact *contact;

@end

NS_ASSUME_NONNULL_END
