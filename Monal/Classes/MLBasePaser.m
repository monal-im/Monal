//
//  MLBasePaser.m
//  monalxmpp
//
//  Created by Anurodh Pokharel on 4/11/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLBasePaser.h"

@interface MLBasePaser ()

@property (nonatomic, strong) XMPPParser *currentStanzaParser;
@property (nonatomic, assign) NSInteger depth;
@property (nonatomic, strong) stanzaCompletion completion;

@end

@implementation MLBasePaser

-(id) initWithCompeltion:(stanzaCompletion) completion
{
    self = [super init];
    self.completion = completion;
    return self;
}

-(void) reset
{
    self.currentStanzaParser=nil;
    self.depth=0; 
}

#pragma mark common parser delegate functions
- (void)parserDidStartDocument:(NSXMLParser *)parser{
    DDLogVerbose(@"Document start");
    self.currentStanzaParser=nil;
    self.depth=0;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    self.depth++;
    DDLogDebug(@"Started element: %@ with depth: %ld and namespaceURI: %@", elementName, self.depth, namespaceURI);
    
    if(self.depth <= 2) // stream:stream is 1
    {
        DDLogDebug(@"Creating new stanza parser for element: %@", elementName);
        [self makeStanzaParser:elementName andNamespaceURI:namespaceURI];
        self.currentStanzaParser.stanzaType=elementName;
        self.currentStanzaParser.stanzaNameSpace=namespaceURI;
    }
    
    if(!self.currentStanzaParser)
    {
        DDLogError(@"no parser!");
        return;
    }
    
    [self.currentStanzaParser parser:parser didStartElement:elementName namespaceURI:namespaceURI qualifiedName:qName attributes:attributeDict];
}

-(void) makeStanzaParser:(NSString *) elementName andNamespaceURI:(NSString *)namespaceURI
{
    //http://etherx.jabber.org/streams
    if(([elementName isEqualToString:@"stream"] && [namespaceURI isEqualToString:@"http://etherx.jabber.org/streams"]) ||
        ([elementName isEqualToString:@"proceed"] && [namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-tls"]) ||
        ([elementName isEqualToString:@"success"] && [namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"]) ||
        ([elementName isEqualToString:@"features"] && [namespaceURI isEqualToString:@"http://etherx.jabber.org/streams"]) ||
        ([elementName isEqualToString:@"error"] && [namespaceURI isEqualToString:@"http://etherx.jabber.org/streams"])
    )
    {
        DDLogDebug(@"Creating ParseStream for %@", elementName);
        self.currentStanzaParser=[[ParseStream alloc] init];
    }
    
    if([elementName isEqualToString:@"iq"] && [namespaceURI isEqualToString:@"jabber:client"])
    {
        DDLogDebug(@"Creating ParseIq for %@", elementName);
        self.currentStanzaParser=[[ParseIq alloc] init];
    }
    if([elementName isEqualToString:@"message"] && [namespaceURI isEqualToString:@"jabber:client"])
    {
        DDLogDebug(@"Creating ParseMessage for %@", elementName);
        self.currentStanzaParser=[[ParseMessage alloc] init];
    }
    if([elementName isEqualToString:@"presence"] && [namespaceURI isEqualToString:@"jabber:client"])
    {
        DDLogDebug(@"Creating ParsePresence for %@", elementName);
        self.currentStanzaParser=[[ParsePresence alloc] init];
    }
    
    if([elementName isEqualToString:@"enabled"] && [namespaceURI isEqualToString:@"urn:xmpp:sm:3"])
    {
        DDLogDebug(@"Creating ParseEnabled for %@", elementName);
        self.currentStanzaParser=[[ParseEnabled alloc] init];
    }
    if([elementName isEqualToString:@"failed"] && [namespaceURI isEqualToString:@"urn:xmpp:sm:3"])
    {
        DDLogDebug(@"Creating ParseFailed for %@", elementName);
        self.currentStanzaParser=[[ParseFailed alloc] init];
    }
    if([elementName isEqualToString:@"resumed"] && [namespaceURI isEqualToString:@"urn:xmpp:sm:3"])
    {
        DDLogDebug(@"Creating ParseResumed for %@", elementName);
        self.currentStanzaParser=[[ParseResumed alloc] init];
    }
    if([elementName isEqualToString:@"a"] && [namespaceURI isEqualToString:@"urn:xmpp:sm:3"])
    {
        DDLogDebug(@"Creating ParseA for %@", elementName);
        self.currentStanzaParser=[[ParseA alloc] init];
    }
    if([elementName isEqualToString:@"r"] && [namespaceURI isEqualToString:@"urn:xmpp:sm:3"])
    {
        DDLogDebug(@"Creating ParseR for %@", elementName);
        self.currentStanzaParser=[[ParseR alloc] init];
    }

    if([elementName isEqualToString:@"failure"] && [namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
    {
        DDLogDebug(@"Creating ParseFailure for %@", elementName);
        self.currentStanzaParser=[[ParseFailure alloc] init];
    }
    if([elementName isEqualToString:@"challenge"] && [namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
    {
        DDLogDebug(@"Creating ParseChallenge for %@", elementName);
        self.currentStanzaParser=[[ParseChallenge alloc] init];
    }
    
    if(!self.currentStanzaParser) {
        DDLogDebug(@"Creating GENERIC XMPPParser for %@", elementName);
        self.currentStanzaParser =[[XMPPParser alloc] init];
    }
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.currentStanzaParser parser:parser foundCharacters:string];
}


-(void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    DDLogDebug(@"Ended element: %@ depth %ld", elementName, self.depth);
    [self.currentStanzaParser parser:parser didEndElement:elementName namespaceURI:namespaceURI qualifiedName:qName];
    
    if(self.depth <=2) {
        if(self.completion) {
            if(!self.currentStanzaParser) {
                DDLogError(@"No stanza parser. not calling completion");
            } else {
                self.completion(self.currentStanzaParser);
            }
        } else  {
            DDLogError(@"no completion handler for stanza!");
        }
        self.currentStanzaParser=nil;
    }
    self.depth--;
}


-(void)parserDidEndDocument:(NSXMLParser *)parser {
    DDLogVerbose(@"Document end");
}

- (void)parser:(NSXMLParser *)parser foundIgnorableWhitespace:(NSString *)whitespaceString
{
    DDLogVerbose(@"found ignorable whitespace: %@", whitespaceString);
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    DDLogError(@"parseErrorOccurred: line: %ld , col: %ld desc: %@ ",(long)[parser lineNumber],
               (long)[parser columnNumber], [parseError localizedDescription]);
}


@end
