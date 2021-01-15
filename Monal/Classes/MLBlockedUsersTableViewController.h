//
//  MLBlockedUsersTableViewController.h
//  Monal
//
//  Created by Friedrich Altheide on 10.01.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "xmpp.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLBlockedUsersTableViewController : UITableViewController

@property (nonatomic, weak) xmpp* xmppAccount;

@end

NS_ASSUME_NONNULL_END
