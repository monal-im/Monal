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
    
    MLXMPPServer *server = [[MLXMPPServer alloc] initWithHost:@"monal.im" andPort:@5222 andOldStyleSSL:NO];
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
    
}

-(void) testDelay {
    NSString  *sample= @"<message type='chat' from='anu@yax.im' to='anu@yax.im/Monal-iOS.78'><sent xmlns='urn:xmpp:carbons:2'><forwarded xmlns='urn:xmpp:forward:0'><message xmlns='jabber:client' type='chat' from='anu@yax.im/Monal-iOS.51' to='anurodhp@jabb3r.org' id='5F246FD4-8A5C-414C-BAD4-CDCD4F0B825C'><body>Culprit</body><request xmlns='urn:xmpp:receipts'/><store xmlns='urn:xmpp:hints'/><stanza-id by='anu@yax.im' xmlns='urn:xmpp:sid:0' id='b9a2a83b-ea6a-4763-9ace-c6adf6b2b47d'/></message></forwarded></sent><delay from='anu@yax.im' stamp='2020-01-01T18:16:32Z' xmlns='urn:xmpp:delay'/></message>";
    
    NSDictionary *stanzaToParse =@{@"stanzaType":@"message", @"stanzaString":sample};
    ParseMessage* messageNode= [[ParseMessage alloc]  initWithDictionary:stanzaToParse];
    XCTAssert([messageNode.delayTimeStamp isEqualToDate:[NSDate dateWithTimeIntervalSince1970:1577902592]], @"Delay time stamp ok");
    
}


-(void) testMucMessage {
    NSString  *sample= @"<message id='B3AF01E4-026A-4C0E-B183-A1273B585C07' to='anu@yax.im/Monal-iOS.51' from='monal_muc2@chat.yax.im/sim' type='groupchat'><body>Ok</body><store xmlns='urn:xmpp:hints'/><stanza-id id='LvW2gRGIhjrL_OTD' by='monal_muc2@chat.yax.im' xmlns='urn:xmpp:sid:0'/></message>";
    
    NSDictionary *stanzaToParse =@{@"stanzaType":@"message", @"stanzaString":sample};
    ParseMessage* messageNode= [[ParseMessage alloc]  initWithDictionary:stanzaToParse];
    XCTAssert([messageNode.type isEqualToString:kMessageGroupChatType], @"did not identify group chat");
    XCTAssert([messageNode.from isEqualToString:@"monal_muc2@chat.yax.im"], @"did not identify room");
    XCTAssert([messageNode.actualFrom isEqualToString:@"sim"], @"did not identify sender nick");

}







@end
