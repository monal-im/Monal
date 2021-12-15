//
//  MLContactOMEMOKeys.m
//  monalxmpp
//
//  Created by ich on 12.12.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLXMPPManager.h"
#import "xmpp.h"
#import "MLOMEMO.h"
#import "MLContact.h"
#import "MLContactOMEMOKeys.h"

@implementation MLContactOMEMOKeys

-(instancetype) initWithContact:(MLContact*) contact
{
    self = [super init];
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:contact.accountId];
#ifndef DISABLE_OMEMO
    self.devices = [[NSMutableArray alloc] initWithArray:[account.omemo knownDevicesForAddressName:contact.contactJid]];
#endif
    return self;
}

@end
