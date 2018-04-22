//
//  MLMAMPref.h
//  Monal-OSX
//
//  Created by Anurodh Pokharel on 4/22/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "xmpp.h"

@interface MLMAMPref : NSViewController

@property (nonatomic, weak) xmpp *xmppAccount;
@end
