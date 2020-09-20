//
//  XMPPParser.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMPPParser.h"


@implementation XMPPParser

#pragma mark common parser delegate functions

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    _messageBuffer=nil;
    if(!_type) _type=[attributeDict objectForKey:@"type"];
    
    if([attributeDict objectForKey:@"from"])
    {
        if(!_from) {
            _from = [attributeDict objectForKey:@"from"];
            NSArray *parts = [_from componentsSeparatedByString:@"/"];
            _user = [[parts objectAtIndex:0] lowercaseString];      // intended to not break code that expects lowercase
            
            _resource = nil;
            if([parts count]>1) {
                _resource = [parts objectAtIndex:1];     // resources are case sensitive
            }
            
            // concat lowercased user part and kept-as-is resource part
            _from = [NSString stringWithFormat:@"%@%@", _user, _resource ? [NSString stringWithFormat:@"%@%@", @"/", _resource] : @""];
            
        } else {
            //DDLogError(@"Attempt to overwrite from");
        }
    }
    
    if(!_idval) _idval = [attributeDict objectForKey:@"id"] ;
    DDLogWarn(@"idval id: %@", _idval);
    
    if([attributeDict objectForKey:@"to"])
    {
        if(!_to) {
            _to = [[[(NSString*)[attributeDict objectForKey:@"to"] componentsSeparatedByString:@"/" ] objectAtIndex:0] lowercaseString];
        }
        else  {
           //DDLogError(@"Attempt to overwrite to");
        }
    }
    
    //remove any resource markers and get user
    _user = [_user stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if([elementName isEqualToString:@"error"])
    {
        _errorType=[attributeDict objectForKey:@"type"];
        return;
    }
    
    if([namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-stanzas"] ||
        [namespaceURI isEqualToString:@"urn:ietf:params:xml:ns:xmpp-streams"])
    {
        if(!_errorReason) _errorReason=elementName;
        return;
    }
    
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if(!_messageBuffer)
    {
       _messageBuffer=[[NSMutableString alloc] init];
    }
    
    [_messageBuffer appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if(_errorReason && [elementName isEqualToString:@"text"])
    {
        _errorText=_messageBuffer;
    }
}

@end
