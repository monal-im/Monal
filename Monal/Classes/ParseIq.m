//
//  ParseIq.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "ParseIq.h"

@implementation ParseIq

-(id) init{
    self=[super init];
    _features=[[NSMutableArray alloc] init];

    return self;
}


#pragma mark NSXMLParser delegate

- (void)parserDidStartDocument:(NSXMLParser *)parser{
	debug_NSLog(@"parsing iq");
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{

	//start sessionafter bind reply
	if([elementName isEqualToString:@"bind"])
	{
        _shouldSetBind=YES;
		State=@"Bind";
		return; 
	}
	

    if([elementName isEqualToString:@"query"])
    {
        _queryXMLNS=[attributeDict objectForKey:@"xmlns"];
        return;
    }

     if([elementName isEqualToString:@"query"])
     {
         [_features addObject:[attributeDict objectForKey:@"val"]];
         return; 
     }
    
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if(([elementName isEqualToString:@"jid"]) && [State isEqualToString:@"Bind"]
	   )
    {
        _jid=_messageBuffer;
        return; 
    }
   
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
