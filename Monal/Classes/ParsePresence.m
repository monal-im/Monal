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
        _type=[attributeDict objectForKey:@"type"];
        _user =[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
        if([[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] count]>1)
            _resource=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:1];
		_from =[attributeDict objectForKey:@"from"] ;
        _idval =[attributeDict objectForKey:@"id"] ;
        
		//remove any  resource markers and get user
		_user=[_user lowercaseString]; 
        debug_NSLog(@"Presence from %@", _user);
		
        
		
		//get photo hash
		
		//what type?
		debug_NSLog(@" presence notice %@", _type);
        
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
    }
    
    if([elementName isEqualToString:@"status"])
    {
        _status=_messageBuffer; 
    }
    }
}

@end
