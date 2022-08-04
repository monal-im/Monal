//
//  MLServerDetails.h
//  Monal
//
//  Created by Anurodh Pokharel on 12/21/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "xmpp.h"

@interface MLServerDetails : UITableViewController

@property (nonatomic, weak) xmpp* xmppAccount;

@end
