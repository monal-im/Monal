//
//  MLIQProcessorTest.m
//  Monal Tests
//
//  Created by Anurodh Pokharel on 12/3/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "xmpp.h"
#import "MLIQProcessor.h"
#import "MLXMPPConnection.h"
#import "MLConstants.h"
#import "MLBasePaser.h"

@interface MLIQProcessorTest : XCTestCase

@property (nonatomic, strong) xmpp *account;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *resource;
@property (nonatomic, strong) MLXMPPConnection *connectionProperties;

//@property (nonatomic, strong) SignalContext *signalContext;
//@property (nonatomic, strong) MLSignalStore *monalSignalStore;

@end

@implementation MLIQProcessorTest

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
//}

//-(void) parseString:(NSString *) sample withDelegate:(MLBasePaser *) baseParserDelegate {
//    NSString *containerStart =@"<stream:stream from='yax.im' id='42020411-eb9f-4e68-b3f6-3c92769e6104' xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:client' xml:lang='en' version='1.0'>";
//    NSString *containerStop =@"</stream:stream>";
//
//    NSMutableData *data = [[NSMutableData alloc] init];
//    [data appendData:[containerStart dataUsingEncoding:NSUTF8StringEncoding]];
//    [data appendData:[sample dataUsingEncoding:NSUTF8StringEncoding]];
//    [data appendData:[containerStop dataUsingEncoding:NSUTF8StringEncoding]];
//
//    NSXMLParser *xmlParser = [[NSXMLParser alloc] initWithData:data];
//    [xmlParser setShouldProcessNamespaces:YES];
//    [xmlParser setShouldReportNamespacePrefixes:NO];
//    [xmlParser setShouldResolveExternalEntities:NO];
//    [xmlParser setDelegate:baseParserDelegate];
//
//    [xmlParser parse];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testResultBind {
    NSString  *sample= @"<iq id='C923CE5C-2FC6-4ADD-AEFE-0AE04A99FD00' type='result'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><jid>foo@monal.im/Monal-iOS.51</jid></bind></iq>";
        
//    MLBasePaser *baseParserDelegate = [[MLBasePaser alloc] initWithCompeltion:^(XMPPParser * _Nullable parsedStanza) {
//        MLIQProcessor *processor = [[MLIQProcessor alloc] initWithAccount:self.account connection:self.connectionProperties signalContex:self.signalContext andSignalStore:self.monalSignalStore];
//        processor.initSession = ^{ };       //dummy handler
//        [processor processIq: (ParseIq *)parsedStanza];
//        XCTAssert([self.connectionProperties.boundJid isEqualToString:@"foo@monal.im/Monal-iOS.51"]);
//    }];
//
//    [self parseString:sample withDelegate:baseParserDelegate];
//
}


- (void)testResultRoster {
    NSString  *sample= @"<iq id='E9A2584E-9FD1-47D6-82AB-F9C50571D791' to='anu@yax.im/Monal-iOS.26' type='result'><query ver='56' xmlns='jabber:iq:roster'><item jid='support@404.city' subscription='none'/><item jid='monal1@xmpp.jp' subscription='both'/></query></iq>";
    
//    XCTestExpectation *vcard= [[XCTestExpectation alloc] initWithDescription:@"vcard"];
//
//    MLBasePaser *baseParserDelegate = [[MLBasePaser alloc] initWithCompeltion:^(XMPPParser * _Nullable parsedStanza) {
//        MLIQProcessor *processor = [[MLIQProcessor alloc] initWithAccount:self.account connection:self.connectionProperties signalContex:self.signalContext andSignalStore:self.monalSignalStore];
//        processor.getVcards = ^{
//            [vcard fulfill];
//        };
//        [processor processIq: (ParseIq *)parsedStanza];
//    }];
//    [self parseString:sample withDelegate:baseParserDelegate];
//    [self waitForExpectations:@[vcard] timeout:5];

}

- (void)testRosterImpersonation {
    NSString  *sample= @"<iq type='set' to='alice@siacs.eu/Gajim' id='test'> <query xmlns='jabber:iq:roster'> item subscription='remove' jid='bob@siacs.eu'/> <item subscription='both' jid='eve@siacs.eu' name='Bob' /> </query> </iq>";
    
//    XCTestExpectation *vcard= [[XCTestExpectation alloc] initWithDescription:@"vcard"];
//
//    MLBasePaser *baseParserDelegate = [[MLBasePaser alloc] initWithCompeltion:^(XMPPParser * _Nullable parsedStanza) {
//        MLIQProcessor *processor = [[MLIQProcessor alloc] initWithAccount:self.account connection:self.connectionProperties signalContex:self.signalContext andSignalStore:self.monalSignalStore];
//        processor.getVcards = ^{
//            [vcard fulfill];
//        };
//        [processor processIq: (ParseIq *)parsedStanza];
//    }];
//    [self parseString:sample withDelegate:baseParserDelegate];

}




- (void)testResultvCard {
    NSString  *sample= @"<iq from='georg@yax.im' to='anu@yax.im/Monal-iOS.88' id='3B01AE4A-226A-409B-ABBF-F6A83904CFE5' type='result'><vCard xmlns='vcard-temp'><NICKNAME>Ge0rG</NICKNAME><URL>https://yaxim.org/</URL><N><FAMILY>Lukas</FAMILY><GIVEN>Georg</GIVEN></N><PHOTO><BINVAL>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</BINVAL><TYPE>image/jpeg</TYPE></PHOTO></vCard></iq>";
    
    XCTNSNotificationExpectation *expectation=[[XCTNSNotificationExpectation alloc] initWithName:kMonalContactRefresh object:nil];
    
//    MLBasePaser *baseParserDelegate = [[MLBasePaser alloc] initWithCompeltion:^(XMPPParser * _Nullable parsedStanza) {
//        MLIQProcessor *processor = [[MLIQProcessor alloc] initWithAccount:self.account connection:self.connectionProperties signalContex:self.signalContext andSignalStore:self.monalSignalStore];
//            [processor processIq: (ParseIq *)parsedStanza];
//    }];
//    
//    [self parseString:sample withDelegate:baseParserDelegate];
//    [self waitForExpectations:@[expectation] timeout:5];
}





@end
