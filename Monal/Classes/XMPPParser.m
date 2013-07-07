//
//  XMPPParser.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMPPParser.h"

@implementation XMPPParser

- (id) initWithDictionary:(NSDictionary*) dictionary
{
    self=[super init];
    
    NSData* stanzaData= [[dictionary objectForKey:@"stanzaString"] dataUsingEncoding:NSUTF8StringEncoding];
	
    //xml parsing
	NSXMLParser* parser = [[NSXMLParser alloc] initWithData:stanzaData];
	[parser setShouldProcessNamespaces:NO];
    [parser setShouldReportNamespacePrefixes:NO];
    [parser setShouldResolveExternalEntities:NO];
	[parser setDelegate:self];
	
	[parser parse];
    
    return  self;
    
}


#pragma mark common parser delegate functions
- (void)parserDidStartDocument:(NSXMLParser *)parser{
	debug_NSLog(@"parsing iq");
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    _messageBuffer=string;
}


- (void)parser:(NSXMLParser *)parser foundIgnorableWhitespace:(NSString *)whitespaceString
{
	debug_NSLog(@"found ignorable whitespace: %@", whitespaceString);
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	debug_NSLog(@"Error: line: %d , col: %d desc: %@ ",[parser lineNumber],
                [parser columnNumber], [parseError localizedDescription]);
	
    
}

@end
