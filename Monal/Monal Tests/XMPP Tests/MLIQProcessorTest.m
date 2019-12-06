//
//  MLIQProcessorTest.m
//  Monal Tests
//
//  Created by Anurodh Pokharel on 12/3/19.
//  Copyright © 2019 Monal.im. All rights reserved.
//

#import <XCTest/XCTest.h>
//#import "ParseIQ.h"
//#import "MLIQProcessor.h"

@interface MLIQProcessorTest : XCTestCase

@property (nonatomic, strong) NSString *accountNo;
@property (nonatomic, strong) NSString *jid;
@property (nonatomic, strong) NSString *resource;

@end

@implementation MLIQProcessorTest

- (void)setUp {
    self.accountNo=@"1";
    self.jid=@"foo@monal.im";
    self.resource=@"Monal-iOS.51";
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testResultBind {
    NSString  *sample= @"<iq id='C923CE5C-2FC6-4ADD-AEFE-0AE04A99FD00' type='result'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><jid>foo@monal.im/Monal-iOS.51</jid></bind></iq>";
    
    NSDictionary *stanzaToParse =@{@"stanzaType":@"iq", @"stanzaString":sample};
    
//     ParseIq* iqNode= [[ParseIq alloc]  initWithDictionary:stanzaToParse];
//    MLIQProcessor *processor = [[MLIQProcessor alloc] initWithAccount:self.accountNo jid:self.jid signalContex:nil andSignalStore:nil];
//
//    [processor processIq:iqNode];
//
    
}


- (void)testResultRoster {
    NSString  *sample= @"<iq id='cXCMufBA' type='set'><query ver='56' xmlns='jabber:iq:roster'><item jid='foo@monal.im' ask='subscribe' subscription='none'/></query></iq>";
    
    NSDictionary *stanzaToParse =@{@"stanzaType":@"iq", @"stanzaString":sample};
    
//     ParseIq* iqNode= [[ParseIq alloc]  initWithDictionary:stanzaToParse];
//    MLIQProcessor *processor = [[MLIQProcessor alloc] initWithAccount:self.accountNo jid:self.jid signalContex:nil andSignalStore:nil];
//
//    [processor processIq:iqNode];
//
    
}



@end
