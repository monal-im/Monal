//
//  ParseEnabled.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/2/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "ParseEnabled.h"

@implementation ParseEnabled

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    _messageBuffer=nil;
    
    if([attributeDict objectForKey:@"max"] )    {
        _max=[attributeDict objectForKey:@"max"];
    }
    _streamID=[attributeDict objectForKey:@"id"];
    
    if([[attributeDict objectForKey:@"resume"] isEqualToString:@"true"])
    {
        _resume=YES;
    }
}

@end
