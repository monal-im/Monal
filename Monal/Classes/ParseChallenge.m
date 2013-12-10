//
//  ParseChallenge.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/20/13.
//
//

#import "ParseChallenge.h"

@implementation ParseChallenge

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
     _messageBuffer=nil;
    
    if([elementName isEqualToString:@"challenge"])
    {
        if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
           {
               _saslChallenge=YES; 
           }
        return;
    }

}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if([elementName isEqualToString:@"challenge"])
    {
        _challengeText=_messageBuffer; 
    }
    
}

@end
