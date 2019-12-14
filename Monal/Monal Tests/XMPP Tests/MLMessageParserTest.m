//
//  MLMessageParserTest.m
//  Monal Tests
//
//  Created by Anurodh Pokharel on 12/14/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "ParseMessage.h"
#import "MLXMPPConnection.h"
#import "MLConstants.h"
#import "MLMessage.h"
#import "xmpp.h"
@import SignalProtocolC;


@interface MLMessageParserTest : XCTestCase

@property (nonatomic, strong) NSString *accountNo;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *resource;
@property (nonatomic, strong) MLXMPPConnection *connectionProperties;

@property (nonatomic, strong) SignalContext *signalContext;
@property (nonatomic, strong) MLSignalStore *monalSignalStore;

@end


@implementation MLMessageParserTest

- (void)setUp {
    self.accountNo=@"1";
    self.jid=@"foo@monal.im";
    self.resource=@"Monal-iOS.51";
    
    MLXMPPIdentity *identity = [[MLXMPPIdentity alloc] initWithJid:self.jid  password:@"" andResource:self.resource];

    MLXMPPServer *server = [[MLXMPPServer alloc] initWithHost:@"monal.im" andPort:@5222];
    server.SSL=YES;
 
    self.connectionProperties = [[MLXMPPConnection alloc] initWithServer:server andIdentity:identity];
    
    self.monalSignalStore = [[MLSignalStore alloc] initWithAccountId:_accountNo];
    
    //signal store
    SignalStorage *signalStorage = [[SignalStorage alloc] initWithSignalStore:self.monalSignalStore];
    //signal context
    self.signalContext= [[SignalContext alloc] initWithStorage:signalStorage];
}

-(void) testMessageValid {
    NSString  *sample= @"<message xmlns='jabber:client' from='juliet@capulet.example/balcony' to='romeo@montague.example/garden' type='chat'><body>Hello</body><thread>0e3141cd80894871a68e6fe6b1ec56fa</thread></message>";
    
    NSDictionary *stanzaToParse =@{@"stanzaType":@"message", @"stanzaString":sample};
    ParseMessage* messageNode= [[ParseMessage alloc]  initWithDictionary:stanzaToParse];
    XCTAssert([messageNode.messageText isEqualToString:@"Hello"], @"message body wrong");
    XCTAssert([messageNode.from isEqualToString:@"juliet@capulet.example"], @"sender not parsed");
    XCTAssert([messageNode.to isEqualToString:@"romeo@montague.example"], @"recipient not parsed");
    
}


-(void) testCarbonValid {
     NSString  *sample= @"<message xmlns='jabber:client' from='romeo@montague.example' to='romeo@montague.example/home' type='chat'>  <received xmlns='urn:xmpp:carbons:2'><forwarded xmlns='urn:xmpp:forward:0'><message xmlns='jabber:client' from='juliet@capulet.example/balcony' to='romeo@montague.example/garden' type='chat'><body>Thou shall meet me tonite, at our house's hall!</body></message></forwarded></received></message>";
      
      NSDictionary *stanzaToParse =@{@"stanzaType":@"message", @"stanzaString":sample};
      ParseMessage* messageNode= [[ParseMessage alloc]  initWithDictionary:stanzaToParse];
    XCTAssert([messageNode.from isEqualToString:@"juliet@capulet.example"], @"Valid Carbon not processed");
      
}


-(void) testCarbonImpersonation {
     NSString  *sample= @"<message xmlns='jabber:client' from='tybalt@capulet.example/home' to='romeo@montague.example' type='chat'>  <received xmlns='urn:xmpp:carbons:2'><forwarded xmlns='urn:xmpp:forward:0'><message xmlns='jabber:client' from='juliet@capulet.example/balcony' to='romeo@montague.example/garden' type='chat'><body>Thou shall meet me tonite, at our house's hall!</body></message></forwarded></received></message>";
      
      NSDictionary *stanzaToParse =@{@"stanzaType":@"message", @"stanzaString":sample};
      ParseMessage* messageNode= [[ParseMessage alloc]  initWithDictionary:stanzaToParse];
    XCTAssert([messageNode.from isEqualToString:@"tybalt@capulet.example"], @"Carbon impersonation");

    //  [self waitForExpectations:@[expectation] timeout:5];
      
}


@end
