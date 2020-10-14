//
//  MLBasePaser.m
//  monalxmpp
//
//  Created by Anurodh Pokharel on 4/11/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLBasePaser.h"

@interface MLXMLNode()
@property (atomic, readwrite) MLXMLNode* parent;
@end

@interface MLBasePaser ()
{
    MLXMLNode* _currentNode;
    NSMutableString* _currentCharData;
    NSInteger _depth;
    stanzaCompletion _completion;
}
@end

@implementation MLBasePaser

-(id) initWithCompletion:(stanzaCompletion) completion
{
    self = [super init];
    _completion = completion;
    return self;
}

-(void) reset
{
    _currentNode = nil;
    _depth = 0; 
}

-(void) parserDidStartDocument:(NSXMLParser*) parser
{
    DDLogInfo(@"Document start");
    [self reset];
}

-(void) parser:(NSXMLParser*) parser didStartElement:(NSString*) elementName namespaceURI:(NSString*) namespaceURI qualifiedName:(NSString*) qName attributes:(NSDictionary*) attributeDict
{
    _depth++;
//     DDLogDebug(@"Started element: %@ :: %@ (%@) depth %ld", elementName, namespaceURI, qName, _depth);
    
    //use appropriate MLXMLNode child classes for iq, message and presence stanzas
    MLXMLNode* newNode;
    if(_depth == 2 && [elementName isEqualToString:@"iq"] && [namespaceURI isEqualToString:@"jabber:client"])
        newNode = [XMPPIQ alloc];
    else if(_depth == 2 && [elementName isEqualToString:@"message"] && [namespaceURI isEqualToString:@"jabber:client"])
        newNode = [XMPPMessage alloc];
    else if(_depth == 2 && [elementName isEqualToString:@"presence"] && [namespaceURI isEqualToString:@"jabber:client"])
        newNode = [XMPPPresence alloc];
    else if([elementName isEqualToString:@"x"] && [namespaceURI isEqualToString:@"jabber:x:data"])
        newNode = [XMPPDataForm alloc];
    else
        newNode = [MLXMLNode alloc];
    newNode = [newNode initWithElement:elementName andNamespace:namespaceURI withAttributes:attributeDict andChildren:@[] andData:nil];
    
    //add new node to tree
    if(_currentNode)
        newNode.parent = _currentNode;
    _currentNode = newNode;
}

-(void) parser:(NSXMLParser*) parser foundCharacters:(NSString*) string
{
    if(!_currentNode)
    {
        DDLogError(@"Got xml character data outside of any element!");
        return;
    }
    if(!_currentCharData)
        _currentCharData = [[NSMutableString alloc] init];
    [_currentCharData appendString:string];
}

-(void) parser:(NSXMLParser*) parser didEndElement:(NSString*) elementName namespaceURI:(NSString*) namespaceURI qualifiedName:(NSString*) qName
{
    if(_currentCharData)
        _currentNode.data = [_currentCharData copy];
    _currentCharData = nil;
    
//     DDLogDebug(@"Ended element: %@ :: %@ (%@) depth %ld", elementName, namespaceURI, qName, _depth);
    
    //only call completion for stanzas and stream start, not for inner elements inside stanzas
    if(_depth <= 2)
        _completion(_currentNode);
    if(_currentNode.parent)
    {
//         DDLogDebug(@"Ascending from child %@ to parent %@", _currentNode.element, _currentNode.parent.element);
        if(_depth > 2)      //don't add all received stanzas/nonzas as childs to our stream header (that would create a memory leak!)
        {
//             DDLogDebug(@"Adding %@ to parent %@", _currentNode.element, _currentNode.parent.element);
            [_currentNode.parent addChild:_currentNode];
        }
        _currentNode = _currentNode.parent;
    }
    _depth--;
}

-(void) parserDidEndDocument:(NSXMLParser*) parser
{
    DDLogInfo(@"Document end");
}

-(void) parser:(NSXMLParser*) parser foundIgnorableWhitespace:(NSString*) whitespaceString
{
    DDLogVerbose(@"Found ignorable whitespace: '%@'", whitespaceString);
}

-(void) parser:(NSXMLParser*) parser parseErrorOccurred:(NSError*) parseError
{
    DDLogError(@"XML parse error occurred: line: %ld , col: %ld desc: %@ ",(long)[parser lineNumber],
               (long)[parser columnNumber], [parseError localizedDescription]);
}

@end
