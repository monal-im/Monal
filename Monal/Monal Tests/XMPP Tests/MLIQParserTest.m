//
//  MLIQParserTest.m
//  Monal Tests
//
//  Created by Anurodh Pokharel on 12/14/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "xmpp.h"
#import "MLXMPPConnection.h"
#import "MLConstants.h"

@interface MLIQParserTest : XCTestCase

@property (nonatomic, strong) NSString *accountNo;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *resource;
@property (nonatomic, strong) MLXMPPConnection *connectionProperties;

//@property (nonatomic, strong) SignalContext *signalContext;
//@property (nonatomic, strong) MLSignalStore *monalSignalStore;
@end

@implementation MLIQParserTest

- (void)setUp {
    self.accountNo=@"1";
    self.jid=@"foo@monal.im";
    self.resource=@"Monal-iOS.51";
    
    MLXMPPIdentity *identity = [[MLXMPPIdentity alloc] initWithJid:self.jid  password:@"" andResource:self.resource];

    MLXMPPServer *server = [[MLXMPPServer alloc] initWithHost:@"monal.im" andPort:@5222 andDirectTLS:NO];
 
    self.connectionProperties = [[MLXMPPConnection alloc] initWithServer:server andIdentity:identity];
    
//    self.monalSignalStore = [[MLSignalStore alloc] initWithAccountId:_accountNo];
//    
//    //signal store
//    SignalStorage *signalStorage = [[SignalStorage alloc] initWithSignalStore:self.monalSignalStore];
//    //signal context
//    self.signalContext= [[SignalContext alloc] initWithStorage:signalStorage];
}



@end
