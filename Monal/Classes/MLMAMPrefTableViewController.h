//
//  MLMAMPrefTableViewController.h
//  Monal
//
//  Created by Anurodh Pokharel on 5/17/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <monalxmpp/xmpp.h>

@interface MLMAMPrefTableViewController : UITableViewController

@property (nonatomic, weak) xmpp *xmppAccount;

@end
