//
//  ParseFailure.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/22/13.
//
//

#import "ParseFailure.h"

@interface  ParseFailure()
@property (nonatomic, strong) NSString *text;

@end

@implementation ParseFailure

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
     _messageBuffer=nil;
    
    if([[attributeDict objectForKey:kXMLNS] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
    {
        _saslError=YES;
        return;
    }
    
    if([elementName isEqualToString:@"not-authorized"])
    {
        _notAuthorized=YES;
    }
    

}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if([elementName isEqualToString:@"text"])
    {
        self.text= _messageBuffer; 
    }
    
}

@end
