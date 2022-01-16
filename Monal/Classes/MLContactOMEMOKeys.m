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
#ifndef DISABLE_OMEMO
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:contact.accountId];
    self.devices = [[NSMutableArray alloc] initWithArray:[account.omemo knownDevicesForAddressName:contact.contactJid]];
#endif
    return self;
}

@end
