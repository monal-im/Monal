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

static NSMutableArray<MLXMLNode*>* _parsedStanzas;
static NSString* _rawXML = @"<?xml version='1.0'?>\n\
        <stream:stream xmlns:stream='http://etherx.jabber.org/streams' version='1.0' xmlns='jabber:client' xml:lang='en' from='example.org' id='a344b8bb-518e-4456-9140-d15f66c1d2db'>\n\
\
        <stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl' someEmptyAttribute=''><mechanism>SCRAM-SHA-1</mechanism><mechanism>PLAIN</mechanism></mechanisms></stream:features>\n\
\
        <message from='test@example.org' id='some_id' xmlns='jabber:client'>\n\
            <body>Message text</body>\n\
            <body xmlns='urn:some:different:namespace'>This will NOT be used</body>\n\
            <some xmlns='urn:some:different:namespace' fin='true' hello='0' world='1' number='42' uuid='18382ACA-EF9D-4BC9-8779-7901C63B6631' id='18382ACA' when='2002-09-10T23:08:25Z'>aGVsbG8gd29ybGQh</some>\n\
            <attr-presence xmlns='urn:checker:0' test1='yellow'/>\n\
            <attr-presence xmlns='urn:checker:1' test2='green'/>\n\
            <attr-presence xmlns='urn:checker:2' test1='blue' test2='red'/>\n\
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

//parse complete xml document once and collect parsed stanzas in _parsedStanzas to be processed by our individual tests later on
+(void) setUp
{
//yes, but this is not insecure because these are string literals boxed into an NSArray below rather than containing unchecked user input
//see here: https://releases.llvm.org/13.0.0/tools/clang/docs/DiagnosticsReference.html#wformat-security
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
    _parsedStanzas = [NSMutableArray new];
    MLBasePaser* delegate = [[MLBasePaser alloc] initWithCompletion:^(MLXMLNode* _Nullable parsedStanza) {
        if(parsedStanza != nil)
        {
            DDLogInfo(@"Got new parsed stanza: %@", parsedStanza);
            [_parsedStanzas addObject:parsedStanza];
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

-(void) setUp
{
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

-(void) tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

-(void) testParseConversionBase64
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some#|base64"];
        if(i == 1)
            XCTAssertEqualObjects(result, [@"hello world!" dataUsingEncoding:NSUTF8StringEncoding], "stanza 1 should match and convert 'some' element text from base64 to @'hello world!'");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseConversionBoolean01
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some@fin|bool"];
        if(i == 1)
            XCTAssertEqualObjects(result, @YES, "stanza 1 should match and convert 'fin' attr to bool @YES");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseConversionBoolean02
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some@hello|bool"];
        if(i == 1)
            XCTAssertEqualObjects(result, @NO, "stanza 1 should match and convert 'hello' attr to bool @NO");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseConversionBoolean03
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some@world|bool"];
        if(i == 1)
            XCTAssertEqualObjects(result, @YES, "stanza 1 should match and convert 'wold' attr to bool @YES");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}


-(void) testParseConversionInt
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some@number|int"];
        if(i == 1)
            XCTAssertEqualObjects(result, @42, "stanza 1 should match and convert 'number' attr to int @42");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseConversionUUID
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some@uuid|uuid"];
        if(i == 1)
            XCTAssertEqualObjects([result UUIDString], @"18382ACA-EF9D-4BC9-8779-7901C63B6631", "stanza 1 should match and convert 'uuid' attr to uuid 18382ACA-EF9D-4BC9-8779-7901C63B6631");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseConversionUUIDCast01
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some@uuid|uuidcast"];
        if(i == 1)
            XCTAssertEqualObjects([result UUIDString], @"18382ACA-EF9D-4BC9-8779-7901C63B6631", "stanza 1 should match and identity-cast 'uuid' attr to uuid 18382ACA-EF9D-4BC9-8779-7901C63B6631");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseConversionUUIDCast02
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some@id|uuidcast"];
        if(i == 1)
            XCTAssertEqualObjects([result UUIDString], @"43363852-14A2-D540-E8CE-6BEA040CD228", "stanza 1 should match and cast 'id' attr to uuid 43363852-14A2-D540-E8CE-6BEA040CD228");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseConversionDatetime
{
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyyMMddHHmmss"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDate* expectedDate = [formatter dateFromString:@"20020910230825"];

    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some@when|datetime"];
        if(i == 1)
            XCTAssertEqualObjects(result, expectedDate, "stanza 1 should match and convert 'when' attr to datetime %@", expectedDate);
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseAttributeRegexNoMatch01
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //no stanza should match
        id result = [_parsedStanzas[i] find:@"/{jabber:client}iq/{http://jabber.org/protocol/pubsub}pubsub/items<node~eu\\.siacs\\.conversations\\.axolotl\\.bundles:[0-9]+>@node"];
        XCTAssertEqualObjects(result, @[], "no stanzas should match this");
    }
}

-(void) testParseAttributeRegexNoMatch02
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        BOOL result = [_parsedStanzas[i] check:@"{urn:some:different:namespace}some<number~^4[^2]$>@number|int"];
        if(i == 1)
            XCTAssertFalse(result, "stanza 1 should not match 'number' attr regex '^4[^2]$'");
        else
            XCTAssertFalse(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseAttributeRegexMatch
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"{urn:some:different:namespace}some<number~^4[0-9]$>@number|int"];
        if(i == 1)
            XCTAssertEqualObjects(result, @42, "stanza 1 should match 'number' attr regex ^4[0-9]$");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseBrokenQueryAttributeFilterRegexBroken
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"/<someUnknownAttribute~[]bro[ken[^regex$>"], XMLQueryBrokenException, @"AttributeFilterRegexException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryAttributeFilterEmptyRegexValue
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"/<someUnknownAttribute~>"], XMLQueryBrokenException, @"AttributeFilterRegexException", "all stanzas should throw an exception");
    }
}

-(void) testParseAttributeFilterEmptyVerbatimValue
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        BOOL result = [_parsedStanzas[i] check:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms<someEmptyAttribute=>"];
        if(i == 0)
            XCTAssertTrue(result, "stanza 0 should match the empty but present attribute");
        else
            XCTAssertFalse(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseBrokenQueryGarbageInputUsingMultipleConversionCommandSeparators
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"|||"], XMLQueryBrokenException, @"SyntaxErrorException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryMissingNodeSelectionBeforeConversionCommand
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"|base64"], XMLQueryBrokenException, @"SyntaxErrorException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryDoubleConversionCommand
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"#|base64|base64"], XMLQueryBrokenException, @"SyntaxErrorException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryNeitherElementNorNamespace
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"@@|bool"], XMLQueryBrokenException, @"NeitherElementNorNamespaceException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenConversionQuery
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"/@@|bool"], XMLQueryBrokenException, @"ConversionCommandOnNonStringResultException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryPathComponent01
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"//#|bool"], XMLQueryBrokenException, @"PathComponentBrokenException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryPathComponent02
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"//#|bool"], XMLQueryBrokenException, @"PathComponentBrokenException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryConversionNotAtTerminalNode01
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"/#|bool/{hello}world"], XMLQueryBrokenException, @"SyntaxErrorException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryConversionNotAtTerminalNode02
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"{hello}world|bool/{some}element"], XMLQueryBrokenException, @"SyntaxErrorException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryConversionForFullNode
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"{*}*|bool"], XMLQueryBrokenException, @"SyntaxErrorException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryFormsQueryOnNonDataForm
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should give that error
        XCTAssertThrowsSpecificNamed([_parsedStanzas[i] find:@"/{*}*\\{some}result@here\\"], XMLQueryBrokenException, @"DataFormsQueryOnNonDataFormsNodeException", "all stanzas should throw an exception");
    }
}

-(void) testParseBrokenQueryDataFormsSubqueryUnallowedConversionCommandAfterFullDataFormExtraction
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
        if(i == 2)
            XCTAssertThrowsSpecificNamed([_parsedStanzas[i] findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/protocol/muc#roominfo}result\\|base64"], XMLQueryBrokenException, @"DataFormsConversionException", "all stanzas should throw an exception");
}

-(void) testParseBrokenQueryDataFormsSubqueryUnallowedConversionCommandAfterFullFieldExtraction
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
        if(i == 2)
            XCTAssertThrowsSpecificNamed([_parsedStanzas[i] findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/protocol/muc#roominfo}result&muc#roomconfig_roomname\\|uuidcast"], XMLQueryBrokenException, @"DataFormsConversionException", "all stanzas should throw an exception");
}

-(void) testParseBrokenQueryDataFormsSubqueryEmpty
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
        if(i == 2)
            XCTAssertThrowsSpecificNamed([_parsedStanzas[i] findFirst:@"{http://jabber.org/protocol/disco#info}query/\\\\"], XMLQueryBrokenException, @"SyntaxErrorException", "all stanzas should throw an exception");
}

-(void) testParseBrokenQueryDataFormsSubqueryGarbage
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
        if(i == 2)
        {
            XCTAssertThrowsSpecificNamed([_parsedStanzas[i] findFirst:@"{http://jabber.org/protocol/disco#info}query/\\***{***}\\"], XMLQueryBrokenException, @"DataFormSyntaxErrorException", "all stanzas should throw an exception");
        }
}

-(void) testParseBrokenQueryDoubleConversionCommandAfterDataFormSubquery
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
        if(i == 2)
            XCTAssertThrowsSpecificNamed([_parsedStanzas[i] findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/protocol/muc#roominfo}result@muc#roomconfig_roomname\\|datetime|uuidcast"], XMLQueryBrokenException, @"SyntaxErrorException", "all stanzas should throw an exception");
}

-(void) testParseDataFormSubqueryImplicitNamespaceAndElementName
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //all stanzas should be filtered by the implicit '{jabber:x:data}x' query, thus don't match
        id result = [_parsedStanzas[i] find:@"/\\{some}result@here\\"];
        XCTAssertEqualObjects(result, @[], "all stanzas should be filtered by the implicit '{jabber:x:data}x' query, thus don't match");
    }
}

-(void) testParseDataFormsSubquery
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 2 should match
        id result = [_parsedStanzas[i] findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/protocol/muc#roominfo}result@muc#roomconfig_roomname\\"];
        if(i == 2)
            XCTAssertEqualObjects(result, @"testchat gruppe");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseDataFormsSubqueryWithConversion
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
        if(i == 2)
            XCTAssertNoThrow([_parsedStanzas[i] findFirst:@"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/protocol/muc#roominfo}result@muc#roomconfig_roomname\\|uuidcast"], "dataform subqueries should not throw when using conversion commands for field extractions");
}

-(void) testParseAttributePresence
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //only stanza 1 should match
        NSArray<MLXMLNode*>* result = [_parsedStanzas[i] find:@"/{jabber:client}message<id=some_id>/{*}attr-presence<xmlns~^urn:checker:[0-9]$>"];
        if(i == 1)
        {
            XCTAssertNotEqualObjects(result, @[], "stanza 1 should match id=some_id attr equality and all attr-presence elements matching the xmlns regex pattern: %@", result);
            XCTAssertEqual(result.count, 3, "stanza 1 should exactly match 3 attr-presence elements: %@", result);
            
            for(unsigned long j=0; j<result.count; j++)
            {
                id innerResult1 = [result[j] findFirst:@"/{*}attr-presence@test1"];
                id innerResult2 = [result[j] findFirst:@"/{*}attr-presence@test2"];
                
                if(j == 0)
                {
                    XCTAssertTrue([result[j] check:@"/{urn:checker:0}attr-presence"], "attr-presence element 0 should have namespace urn:checker:0");
                    XCTAssertFalse([result[j] check:@"/{urn:checker:0}attr-presence<test1!~.*>"], "attr-presence element 0 should not match 'test1!~.*' attr check");
                    XCTAssertTrue([result[j] check:@"/{urn:checker:0}attr-presence<test2!~.*>"], "attr-presence element 0 should match 'test2!~.*' attr check");
                    
                    id innerResult0 = [result[j] findFirst:@"/{urn:checker:0}attr-presence<test1~.*>"];
                    XCTAssertEqualObjects(result[j], innerResult0, "attr-presence element 0 should match 'test1~.*' attr check and be an idempotent match");
                    
                    XCTAssertEqualObjects(innerResult1, @"yellow", "attr-presence element 0 should have 'test1' attr with value 'yellow': %@", innerResult1);
                    XCTAssertNil(innerResult2, "attr-presence element 0 should not have 'test2' attr: %@", innerResult2);
                }
                else if(j == 1)
                {
                    XCTAssertTrue([result[j] check:@"/{urn:checker:1}attr-presence"], "attr-presence element 1 should have namespace urn:checker:1: %@", result[j]);
                    XCTAssertTrue([result[j] check:@"/{urn:checker:1}attr-presence<test1!~.*>"], "attr-presence element 1 should match 'test1!~.*' attr check: %@", result[j]);
                    XCTAssertFalse([result[j] check:@"/{urn:checker:1}attr-presence<test2!~.*>"], "attr-presence element 1 should not match 'test2!~.*' attr check: %@", result[j]);
                    
                    id innerResult0 = [result[j] findFirst:@"/{urn:checker:1}attr-presence<test2~.*>"];
                    XCTAssertEqualObjects(result[j], innerResult0, "attr-presence element 1 should match 'test2~.*' attr check and be an idempotent match");
                    
                    XCTAssertNil(innerResult1, "attr-presence element 1 should not have 'test1' attr: %@", innerResult1);
                    XCTAssertEqualObjects(innerResult2, @"green", "attr-presence element 1 should have 'test2' attr with value 'green': %@", innerResult2);
                }
                else if(j == 2)
                {
                    XCTAssertTrue([result[j] check:@"/{urn:checker:2}attr-presence"], "attr-presence element 0 should have namespace urn:checker:2: %@", result[j]);
                    XCTAssertFalse([result[j] check:@"/{urn:checker:2}attr-presence<test1!~.*>"], "attr-presence element 2 should not match 'test1!~.*' attr check: %@", result[j]);
                    XCTAssertFalse([result[j] check:@"/{urn:checker:2}attr-presence<test2!~.*>"], "attr-presence element 2 should not match 'test2!~.*' attr check: %@", result[j]);
                    
                    XCTAssertTrue([result[j] check:@"/{urn:checker:2}attr-presence<test1~.*>"], "attr-presence element 2 should match 'test1~.*' attr check: %@", result[j]);
                    XCTAssertTrue([result[j] check:@"/{urn:checker:2}attr-presence<test2~.*>"], "attr-presence element 2 should match 'test2~.*' attr check: %@", result[j]);
                    
                    id innerResult0 = [result[j] findFirst:@"/{urn:checker:2}attr-presence<test1~.*><test2~.*>"];
                    XCTAssertEqualObjects(result[j], innerResult0, "attr-presence element 2 should match 'test1~.*' and 'test2~.*' attr checks and be an idempotent match");
                    
                    XCTAssertEqualObjects(innerResult1, @"blue", "attr-presence element 2 should have 'test1' attr with value 'blue': %@", innerResult1);
                    XCTAssertEqualObjects(innerResult2, @"red", "attr-presence element 2 should have 'test2' attr with value 'red': %@", innerResult2);
                }
            }
        }
        else
            XCTAssertEqualObjects(result, @[], "all other stanzas should not match: %lu: %@", i, result);
    }
}

-(void) testParseSaslMechanisms
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 0 should match
        NSSet* result = [NSSet setWithArray:[_parsedStanzas[i] find:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms/mechanism#"]];
        if(i == 0)
            XCTAssertEqualObjects(result, ([NSSet setWithArray:@[@"SCRAM-SHA-1", @"PLAIN"]]), "wrong mechanisms extracted");
        else
            XCTAssertEqualObjects(result, [NSSet new], "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseMessageBody
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 1 should match
        id result = [_parsedStanzas[i] findFirst:@"body#"];
        if(i == 1)
            XCTAssertEqualObjects(result, @"Message text");
        else
            XCTAssertNil(result, "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseWithFormatParameters
{
    for(unsigned long i=0; i<_parsedStanzas.count; i++)
    {
        //stanza 3 should match
        NSArray* result = [_parsedStanzas[i] find:@"/<type=%@>/{http://jabber.org/protocol/pubsub}pubsub/subscription<node=eu.siacs.conversations.axolotl.%@><subscription=%s><jid=user@%@.com>", @"result", @"devicelist", "subscribed", @"example"];
        if(i == 3)
        {
            XCTAssertEqual(result.count, 1, "we expect exactly one match");
            XCTAssertEqualObjects([result[0] XMLString], @"<subscription jid='user@example.com' node='eu.siacs.conversations.axolotl.devicelist' subid='6795F13596465' subscription='subscribed'/>", "failed to properly extract and stringify MLXMLNode");
        }
        else
            XCTAssertEqualObjects(result, @[], "all other stanzas should not match: %lu", i);
    }
}

-(void) testParseCapsHash
{
    //stanza 4 should match, no non-match handling here
    unsigned long i = 4;
    
    //gajim disco hash testcase
    XCTAssertTrue([_parsedStanzas[i] check:@"/<id=disco1>"], "expected iq response having id 'disco1'");
    
    //the the original implementation is in MLIQProcessor $$class_handler(handleEntityCapsDisco)
    NSMutableArray* identities = [NSMutableArray new];
    for(MLXMLNode* identity in [_parsedStanzas[i] find:@"{http://jabber.org/protocol/disco#info}query/identity"])
        [identities addObject:[NSString stringWithFormat:@"%@/%@/%@/%@", [identity findFirst:@"/@category"], [identity findFirst:@"/@type"], ([identity check:@"/@xml:lang"] ? [identity findFirst:@"/@xml:lang"] : @""), ([identity check:@"/@name"] ? [identity findFirst:@"/@name"] : @"")]];
    NSSet* features = [NSSet setWithArray:[_parsedStanzas[i] find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
    NSArray* forms = [_parsedStanzas[i] find:@"{http://jabber.org/protocol/disco#info}query/{jabber:x:data}x"];
    NSString* ver = [HelperTools getEntityCapsHashForIdentities:identities andFeatures:features andForms:forms];
    DDLogDebug(@"Caps hash calculated: %@", ver);
    XCTAssertEqualObjects(ver, @"q07IKJEyjvHSyhy//CH0CxmKi8w=", "Caps hash NOT equal to testcase hash 'q07IKJEyjvHSyhy//CH0CxmKi8w='!");
}

@end
