//
//  ParsePresence.m
//  Monal
//
//  Created by Anurodh Pokharel on 7/6/13.
//
//

#import "ParsePresence.h"

@implementation ParsePresence


- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if([elementName isEqualToString:@"presence"])
    {
         [super parser:parser didStartElement:elementName namespaceURI:namespaceURI qualifiedName:qName attributes:attributeDict];
        debug_NSLog(@"Presence from %@", _user);
		debug_NSLog(@"Presence type %@", _type);
        
        if([_type isEqualToString:@"error"])
		{
            //we are done, parse next element
            return;
			
		}
    }
    
    if([elementName isEqualToString:@"show"])
    {
        _messageBuffer=nil;
    }
    
    if([elementName isEqualToString:@"status"])
    {
        _messageBuffer=nil;
    }
    
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if(_messageBuffer)
    {
        if([elementName isEqualToString:@"show"])
        {
            _show=_messageBuffer;
            if(_show==nil)
                _show=@"";
            
        }
        
        if([elementName isEqualToString:@"status"])
        {
            _status=_messageBuffer;
            if(_status==nil)
                _status=@"";
            
            
        }
        
        if([elementName isEqualToString:@"photo"])
        {
            _photoHash=_messageBuffer;
            
        }
    }
}

@end
