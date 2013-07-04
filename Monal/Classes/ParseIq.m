//
//  ParseIq.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "ParseIq.h"

@implementation ParseIq


#pragma mark NSXMLParser delegate

- (void)parserDidStartDocument:(NSXMLParser *)parser{
	debug_NSLog(@"parsing");
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{

}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
   
    
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    _messageBuffer=string;
}


- (void)parser:(NSXMLParser *)parser foundIgnorableWhitespace:(NSString *)whitespaceString
{
	debug_NSLog(@"foudn ignorable whitespace: %@", whitespaceString);
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	debug_NSLog(@"Error: line: %d , col: %d desc: %@ ",[parser lineNumber],
                [parser columnNumber], [parseError localizedDescription]);
	
    
}

@end
