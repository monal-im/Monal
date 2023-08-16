//
//  MLBasePaser.m
//  monalxmpp
//
//  Created by Anurodh Pokharel on 4/11/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLConstants.h"
#import "MLBasePaser.h"

//#define DebugParser(...)    DDLogDebug(__VA_ARGS__)
#define DebugParser(...)

@interface MLXMLNode()
@property (atomic, readwrite) MLXMLNode* parent;
-(MLXMLNode*) addChildNodeWithoutCopy:(MLXMLNode*) child;
@end

@interface MLBasePaser ()
{
    //this stak is needed to hold strong references to all nodes until they are dispatched to our _completion callback
    //(the parent references of the MLXMLNodes are weak and don't hold the parents alive)
    NSMutableArray* _currentStack;
    stanza_completion_t _completion;
    NSMutableArray* _namespacePrefixes;
}
@end

@implementation MLBasePaser

-(id) initWithCompletion:(stanza_completion_t) completion
{
    self = [super init];
    _completion = completion;
    return self;
}

-(void) reset
{
    _currentStack = [NSMutableArray new];
}

-(void) parserDidStartDocument:(NSXMLParser*) parser
{
    DDLogInfo(@"Document start");
    [self reset];
}

-(void) parser:(NSXMLParser*) parser didStartMappingPrefix:(NSString*) prefix toURI:(NSString*) namespaceURI
{
    DebugParser(@"Got new namespace prefix mapping for '%@' to '%@'...", prefix, namespaceURI);
}

-(void) parser:(NSXMLParser*) parser didEndMappingPrefix:(NSString*) prefix
{
    DebugParser(@"Namespace prefix '%@' now out of scope again...", prefix);
}

-(void) parser:(NSXMLParser*) parser didStartElement:(NSString*) elementName namespaceURI:(NSString*) namespaceURI qualifiedName:(NSString*) qName attributes:(NSDictionary*) attributeDict
{
    NSInteger depth = [_currentStack count] + 1;        //this makes the depth in here equal to the depth in didEndElement:
    DebugParser(@"Started element: %@ :: %@ (%@) depth %ld", elementName, namespaceURI, qName, depth);
    
    //use appropriate MLXMLNode child classes for iq, message and presence stanzas
    MLXMLNode* newNode;
    if(depth == 2 && [elementName isEqualToString:@"iq"] && [namespaceURI isEqualToString:@"jabber:client"])
        newNode = [XMPPIQ alloc];
    else if(depth == 2 && [elementName isEqualToString:@"message"] && [namespaceURI isEqualToString:@"jabber:client"])
        newNode = [XMPPMessage alloc];
    else if(depth == 2 && [elementName isEqualToString:@"presence"] && [namespaceURI isEqualToString:@"jabber:client"])
        newNode = [XMPPPresence alloc];
    else if(depth >= 3 && [elementName isEqualToString:@"x"] && [namespaceURI isEqualToString:@"jabber:x:data"])
        newNode = [XMPPDataForm alloc];
    else
        newNode = [MLXMLNode alloc];
    newNode = [newNode initWithElement:elementName andNamespace:namespaceURI withAttributes:attributeDict andChildren:@[] andData:nil];
    
    DebugParser(@"Current stack: %@", _currentStack);
    //add new node to tree (each node needs a prototype MLXMLNode element and a mutable string to hold its future
    //char data added to the MLXMLNode when the xml element is closed
    newNode.parent = [_currentStack lastObject][@"node"];
    [_currentStack addObject:@{@"node": newNode, @"charData": [NSMutableString new]}];
}

-(void) parser:(NSXMLParser*) parser foundCharacters:(NSString*) string
{
    DebugParser(@"Got new xml character data: '%@'", string);
    NSInteger depth = [_currentStack count];
    if(depth == 0)
    {
        DDLogError(@"Got xml character data outside of any element!");
        [self fakeStreamError];
        return;
    }
    
    [[_currentStack lastObject][@"charData"] appendString:string];
    DebugParser(@"_currentCharData is now: '%@'", [_currentStack lastObject][@"charData"]);
}

-(void) parser:(NSXMLParser*) parser didEndElement:(NSString*) elementName namespaceURI:(NSString*) namespaceURI qualifiedName:(NSString*) qName
{
    NSInteger depth = [_currentStack count];
    NSDictionary* topmostStackElement = [_currentStack lastObject];
    MLXMLNode* currentNode = ((MLXMLNode*)topmostStackElement[@"node"]);
    
    if([topmostStackElement[@"charData"] length])
        currentNode.data = [topmostStackElement[@"charData"] copy];
    
    DebugParser(@"Ended element: %@ :: %@ (%@) depth %ld", elementName, namespaceURI, qName, depth);
    
    MLXMLNode* parent = currentNode.parent;
    if(parent)
    {
        DebugParser(@"Ascending from child %@ to parent %@", currentNode.element, parent.element);
        if(depth > 2)      //don't add all received stanzas/nonzas as childs to our stream header (that would create a memory leak!)
        {
            DebugParser(@"Adding %@ to parent %@", currentNode.element, parent.element);
            [parent addChildNodeWithoutCopy:currentNode];
        }
    }
    [_currentStack removeLastObject];
    
    //only call completion for stanzas, not for inner elements inside stanzas and not for our outermost stream start element
    if(depth == 2)
        _completion(currentNode);
}

-(void) parserDidEndDocument:(NSXMLParser*) parser
{
    DDLogInfo(@"Document end");
}

-(void) parser:(NSXMLParser*) parser foundIgnorableWhitespace:(NSString*) whitespaceString
{
    DebugParser(@"Found ignorable whitespace: '%@'", whitespaceString);
}

-(void) parser:(NSXMLParser*) parser parseErrorOccurred:(NSError*) parseError
{
    DDLogError(@"XML parse error occurred: line: %ld , col: %ld desc: %@ ",(long)[parser lineNumber],
               (long)[parser columnNumber], [parseError localizedDescription]);
    [self fakeStreamError];
}

-(void) fakeStreamError
{
    //fake stream error and let xmpp.m handle it
    _completion([[MLXMLNode alloc] initWithElement:@"error" andNamespace:@"http://etherx.jabber.org/streams" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"bad-format" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[] andData:@"Could not parse XML coming from server"]
        ] andData:nil]
    ] andData:nil]);
}

@end
