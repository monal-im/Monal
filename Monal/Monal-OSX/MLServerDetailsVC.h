//
//  MLServerDetailsVC.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 12/21/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "xmpp.h"

@interface MLServerDetailsVC : NSViewController  <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) IBOutlet NSTableView *detailsTable;
@property (nonatomic, weak) xmpp *xmppAccount;

@end
