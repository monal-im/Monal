//
//  MLMessageProcessorTest.m
//  Monal Tests
//
//  Created by Anurodh Pokharel on 12/11/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MLMessageProcessor.h"
#import "MLXMPPConnection.h"
#import "MLConstants.h"
#import "MLMessage.h"
#import "MLBasePaser.h"

@interface MLMessageProcessorTest : XCTestCase
@property (nonatomic, strong) xmpp *account;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *resource;
@property (nonatomic, strong) MLXMPPConnection *connectionProperties;

//@property (nonatomic, strong) SignalContext *signalContext;
//@property (nonatomic, strong) MLSignalStore *monalSignalStore;
@end

@implementation MLMessageProcessorTest

- (void)setUp {
    self.jid=@"foo@monal.im";
    self.resource=@"Monal-iOS.51";
    self.account = [[xmpp alloc] init];
    self.account.accountNo = @"1";
    
    MLXMPPIdentity *identity = [[MLXMPPIdentity alloc] initWithJid:self.jid  password:@"" andResource:self.resource];

    MLXMPPServer *server = [[MLXMPPServer alloc] initWithHost:@"monal.im" andPort:@5222 andDirectTLS:NO];
 
    self.connectionProperties = [[MLXMPPConnection alloc] initWithServer:server andIdentity:identity];
    
//    self.monalSignalStore = [[MLSignalStore alloc] initWithAccountId:self.account.accountNo];
//    
//    //signal store
//    SignalStorage *signalStorage = [[SignalStorage alloc] initWithSignalStore:self.monalSignalStore];
//    //signal context
//    self.signalContext= [[SignalContext alloc] initWithStorage:signalStorage];
}


-(void) parseString:(NSString *) sample withDelegate:(MLBasePaser *) baseParserDelegate {
    NSString *containerStart =@"<stream:stream from='yax.im' id='42020411-eb9f-4e68-b3f6-3c92769e6104' xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:client' xml:lang='en' version='1.0'>";
    NSString *containerStop =@"</stream:stream>";
    
    NSMutableData *data = [[NSMutableData alloc] init];
    [data appendData:[containerStart dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:[sample dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:[containerStop dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSXMLParser *xmlParser = [[NSXMLParser alloc] initWithData:data];
    [xmlParser setShouldProcessNamespaces:YES];
    [xmlParser setShouldReportNamespacePrefixes:NO];
    [xmlParser setShouldResolveExternalEntities:NO];
    [xmlParser setDelegate:baseParserDelegate];
    
    [xmlParser parse];
}

- (void)testmucMessage {
//    NSString  *sample= @"<message from='monal@chat.yax.im/Anu' to='anu@yax.im/Monal-iOS.31' type='groupchat'><subject>Monal IM - Official Support - XMPP client for iOS and macOS - https://monal.im/</subject></message>";
//    
//    XCTNSNotificationExpectation *expectation=[[XCTNSNotificationExpectation alloc] initWithName:kMonalNewMessageNotice object:nil];
//    expectation.handler = ^BOOL(NSNotification * _Nonnull notification) {
//        MLMessage *message = [[notification userInfo] objectForKey:@"message"];
//        
//        return YES;
//    };
//    
//    MLBasePaser *baseParserDelegate = [[MLBasePaser alloc] initWithCompeltion:^(XMPPParser * _Nullable parsedStanza) {
//        MLMessageProcessor *processor = [[MLMessageProcessor alloc] initWithAccount:self.account.accountNo jid:self.jid connection:nil signalContex:self.signalContext andSignalStore:self.monalSignalStore];
//        [processor processMessage:parsedStanza];
//    }];
//    
//    [self parseString:sample withDelegate:baseParserDelegate];
//  
    
  //  [self waitForExpectations:@[expectation] timeout:5];
    
}

- (void)testerrorMessage {
    NSString  *sample= @"<message type='error' from='reject@yax.im' to='anu@yax.im/Monal-iOS.78' id='A2481A6F-8CD8-444F-8190-1BFE312938AE'><error type='cancel'><not-allowed xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/><text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'>Error handling test</text></error></message>";
    
    NSDictionary *stanzaToParse =@{@"stanzaType":@"message", @"stanzaString":sample};
    XCTNSNotificationExpectation *expectation=[[XCTNSNotificationExpectation alloc] initWithName:kMonalNewMessageNotice object:nil];
    expectation.handler = ^BOOL(NSNotification * _Nonnull notification) {
        MLMessage *message = [[notification userInfo] objectForKey:@"message"];
        
        return YES;
    };
    
//
//      MLBasePaser *baseParserDelegate = [[MLBasePaser alloc] initWithCompeltion:^(XMPPParser * _Nullable parsedStanza) {
//          MLMessageProcessor *processor = [[MLMessageProcessor alloc] initWithAccount:self.account.accountNo jid:self.jid connection:nil signalContex:self.signalContext andSignalStore:self.monalSignalStore];
//          [processor processMessage:parsedStanza];
//      }];
//      
//      [self parseString:sample withDelegate:baseParserDelegate];
//    
      // [self waitForExpectations:@[expectation] timeout:5];
}


/*
 <message from='monal_muc@chat.yax.im/sim' to='anu@yax.im/Monal-iOS.31' id='4A2BAC34-EF67-4E73-960C-433B3D9E21C6' type='groupchat'><body>Odd</body><store xmlns='urn:xmpp:hints'/><stanza-id id='3j1b3NLEdPyOZDSs' by='monal_muc@chat.yax.im' xmlns='urn:xmpp:sid:0'/></message>
 */


@end
