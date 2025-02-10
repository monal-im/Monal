//
//  ParserTest.m
//  MonalXMPPUnitTests
//
//  Created by admin on 10.02.25.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/HelperTools.h>
#import "MLBasePaser.h"

NSString* _rawXML = @"<?xml version='1.0'?>\n\
        <stream:stream xmlns:stream='http://etherx.jabber.org/streams' version='1.0' xmlns='jabber:client' xml:lang='en' from='example.org' id='a344b8bb-518e-4456-9140-d15f66c1d2db'>\n\
\
        <stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>SCRAM-SHA-1</mechanism><mechanism>PLAIN</mechanism></mechanisms></stream:features>\n\
\
        <message from='test@example.org' id='some_id' xmlns='jabber:client'>\n\
            <body>Message text</body>\n\
            <body xmlns='urn:some:different:namespace'>This will NOT be used</body>\n\
        </message>\n\
\
        <iq id='18382ACA-EF9D-4BC9-8779-7901C63B6631' to='user1@example.org/Monal-iOS.ef313600' xmlns='jabber:client' type='result' from='luloku@conference.example.org'><query xmlns='http://jabber.org/protocol/disco#info'><feature var='http://jabber.org/protocol/muc#request'/><feature var='muc_hidden'/><feature var='muc_unsecured'/><feature var='muc_membersonly'/><feature var='muc_unmoderated'/><feature var='muc_persistent'/><identity type='text' name='testchat gruppe' category='conference'/><feature var='urn:xmpp:mam:2'/><feature var='urn:xmpp:sid:0'/><feature var='muc_nonanonymous'/><feature var='http://jabber.org/protocol/muc'/><feature var='http://jabber.org/protocol/muc#stable_id'/><feature var='http://jabber.org/protocol/muc#self-ping-optimization'/><feature var='jabber:iq:register'/><feature var='vcard-temp'/><x type='result' xmlns='jabber:x:data'><field type='hidden' var='FORM_TYPE'><value>http://jabber.org/protocol/muc#roominfo</value></field><field label='Description' var='muc#roominfo_description' type='text-single'><value/></field><field label='Number of occupants' var='muc#roominfo_occupants' type='text-single'><value>2</value></field><field label='Allow members to invite new members' var='{http://prosody.im/protocol/muc}roomconfig_allowmemberinvites' type='boolean'><value>0</value></field><field label='Allow users to invite other users' var='muc#roomconfig_allowinvites' type='boolean'><value>0</value></field><field label='Title' var='muc#roomconfig_roomname' type='text-single'><value>testchat gruppe</value></field><field type='boolean' var='muc#roomconfig_changesubject'/><field type='text-single' var='{http://modules.prosody.im/mod_vcard_muc}avatar#sha1'/><field type='text-single' var='muc#roominfo_lang'><value/></field></x></query></iq>\n\
\
        <iq id='605818D4-4D16-4ACC-B003-BFA3E11849E1' to='user@example.com/Monal-iOS.15e153a8' xmlns='jabber:client' type='result' from='asdkjfhskdf@messaging.one'><pubsub xmlns='http://jabber.org/protocol/pubsub'><subscription node='eu.siacs.conversations.axolotl.devicelist' subid='6795F13596465' subscription='subscribed' jid='user@example.com'/></pubsub></iq>\n\
\
        <iq from='benvolio@capulet.lit/230193' id='disco1' to='juliet@capulet.lit/chamber' type='result'>\n\
          <query xmlns='http://jabber.org/protocol/disco#info' node='http://psi-im.org#q07IKJEyjvHSyhy//CH0CxmKi8w='>\n\
            <identity xml:lang='en' category='client' name='Psi 0.11' type='pc'/>\n\
            <identity xml:lang='el' category='client' name='Ψ 0.11' type='pc'/>\n\
            <feature var='http://jabber.org/protocol/caps'/>\n\
            <feature var='http://jabber.org/protocol/disco#info'/>\n\
            <feature var='http://jabber.org/protocol/disco#items'/>\n\
            <feature var='http://jabber.org/protocol/muc'/>\n\
            <x xmlns='jabber:x:data' type='result'>\n\
              <field var='FORM_TYPE' type='hidden'>\n\
                <value>urn:xmpp:dataforms:softwareinfo</value>\n\
              </field>\n\
              <field var='ip_version'>\n\
                <value>ipv4</value>\n\
                <value>ipv6</value>\n\
              </field>\n\
              <field var='os'>\n\
                <value>Mac</value>\n\
              </field>\n\
              <field var='os_version'>\n\
                <value>10.5.1</value>\n\
              </field>\n\
              <field var='software'>\n\
                <value>Psi</value>\n\
              </field>\n\
              <field var='software_version'>\n\
                <value>0.11</value>\n\
              </field>\n\
            </x>\n\
          </query>\n\
        </iq>\n\
\
</stream:stream>";

@interface ParserTest : XCTestCase
@end

@implementation ParserTest

-(void) setUp
{
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

-(void) tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}


-(void) testParseXML
{
//yes, but this is not insecure because these are string literals boxed into an NSArray below rather than containing unchecked user input
//see here: https://releases.llvm.org/13.0.0/tools/clang/docs/DiagnosticsReference.html#wformat-security
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
    __block int stanzaCounter = 0;
    MLBasePaser* delegate = [[MLBasePaser alloc] initWithCompletion:^(MLXMLNode* _Nullable parsedStanza) {
        if(parsedStanza != nil)
        {
            DDLogInfo(@"Got new parsed stanza: %@", parsedStanza);
            stanzaCounter++;
            
            //no stanza, should never match
            id result00 = [parsedStanza find:@"/{jabber:client}iq/{http://jabber.org/protocol/pubsub}pubsub/items<node~eu\\.siacs\\.conversations\\.axolotl\\.bundles:[0-9]+>@node"];
            XCTAssertEqualObjects(result00, @[], "no stanzas should match this");
            
            /*
            //stanza 1
            NSSet* result01 = [NSSet setWithArray:[parsedStanza find:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms/mechanism#"]];
            if(stanzaCounter == 1)
                XCTAssertEqualObjects(result01, [NSSet setWithArray:@[@"SCRAM-SHA-1", @"PLAIN"]], "wrong mechanisms extracted");
            else
                XCTAssertEqualObjects(result01, [NSSet new], "all other stanzas should not match: %d", stanzaCounter);
            */
            
            //stanza 2
            id result02 = [parsedStanza findFirst:@"body#"];
            if(stanzaCounter == 2)
                XCTAssertEqualObjects(result02, @"Message text");
            else
                XCTAssertNil(result02, "all other stanzas should not match: %d", stanzaCounter);
            
            //stanza 3
            id result03 = [parsedStanza findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/protocol/muc#roominfo}result@muc#roomconfig_roomname\\"];
            if(stanzaCounter == 3)
                XCTAssertEqualObjects(result03, @"testchat gruppe");
            else
                XCTAssertNil(result03, "all other stanzas should not match: %d", stanzaCounter);
            
            //stanza 4
            NSArray* result04 = [parsedStanza find:@"/<type=%@>/{http://jabber.org/protocol/pubsub}pubsub/subscription<node=%@><subscription=%s><jid=%@>", @"result", @"eu.siacs.conversations.axolotl.devicelist", "subscribed", @"user@example.com"];
            if(stanzaCounter == 4)
            {
                XCTAssertEqual(result04.count, 1, "we expect exactly one match");
                XCTAssertEqualObjects([result04[0] XMLString], @"<subscription node='eu.siacs.conversations.axolotl.devicelist' subid='6795F13596465' subscription='subscribed' jid='user@example.com'/>", "failed to properly extract and stringify MLXMLNode");
            }
            else
                XCTAssertEqualObjects(result04, @[], "all other stanzas should not match: %d", stanzaCounter);
            
            //stanza 5 (no non-match handling here)
            if(stanzaCounter == 5)
            {
                //gajim disco hash testcase
                XCTAssertTrue([parsedStanza check:@"/<id=disco1>"], "expected iq response having id 'disco1'");
                
                //the the original implementation is in MLIQProcessor $$class_handler(handleEntityCapsDisco)
                NSMutableArray* identities = [NSMutableArray new];
                for(MLXMLNode* identity in [parsedStanza find:@"{http://jabber.org/protocol/disco#info}query/identity"])
                    [identities addObject:[NSString stringWithFormat:@"%@/%@/%@/%@", [identity findFirst:@"/@category"], [identity findFirst:@"/@type"], ([identity check:@"/@xml:lang"] ? [identity findFirst:@"/@xml:lang"] : @""), ([identity check:@"/@name"] ? [identity findFirst:@"/@name"] : @"")]];
                NSSet* features = [NSSet setWithArray:[parsedStanza find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
                NSArray* forms = [parsedStanza find:@"{http://jabber.org/protocol/disco#info}query/{jabber:x:data}x"];
                NSString* ver = [HelperTools getEntityCapsHashForIdentities:identities andFeatures:features andForms:forms];
                DDLogDebug(@"Caps hash calculated: %@", ver);
                XCTAssertEqualObjects(ver, @"q07IKJEyjvHSyhy//CH0CxmKi8w=", "Caps hash NOT equal to testcase hash 'q07IKJEyjvHSyhy//CH0CxmKi8w='!");
            }
        }
    }];
#pragma clang diagnostic pop
    
    //create xml parser, configure our delegate and feed it with data
    NSXMLParser* xmlParser = [[NSXMLParser alloc] initWithData:[_rawXML dataUsingEncoding:NSUTF8StringEncoding]];
    [xmlParser setShouldProcessNamespaces:YES];
    [xmlParser setShouldReportNamespacePrefixes:YES];       //for debugging only
    [xmlParser setShouldResolveExternalEntities:NO];
    [xmlParser setDelegate:delegate];
    [xmlParser parse];     //blocking operation
}

@end
