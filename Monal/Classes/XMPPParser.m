//
//  XMPPParser.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMPPParser.h"


static const int ddLogLevel = LOG_LEVEL_INFO;

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
	DDLogVerbose(@"parsing start");
  
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    _messageBuffer=nil;
    _type=[attributeDict objectForKey:@"type"];
    
    if([attributeDict objectForKey:@"from"])
    {
    _user =[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
    if([[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] count]>1)
        _resource=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:1];
    _from =[attributeDict objectForKey:@"from"] ;
    _from=[_from lowercaseString];
    }
    
    _idval =[attributeDict objectForKey:@"id"] ;
   
    if([attributeDict objectForKey:@"to"])
    {
        _to =[[(NSString*)[attributeDict objectForKey:@"to"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
        _to=[_to lowercaseString];
    }
    
    //remove any  resource markers and get user
    _user=[_user lowercaseString];
    

}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if(!_messageBuffer)
    {
           _messageBuffer=[[NSMutableString alloc] init];
    }
    
    [_messageBuffer appendString:string];
}


- (void)parser:(NSXMLParser *)parser foundIgnorableWhitespace:(NSString *)whitespaceString
{
	DDLogVerbose(@"found ignorable whitespace: %@", whitespaceString);
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	DDLogVerbose(@"Error: line: %d , col: %d desc: %@ ",[parser lineNumber],
                [parser columnNumber], [parseError localizedDescription]);
	
    
}

@end
