//
//  ParseResumed.m
//  Monal
//
//  Created by Anurodh Pokharel on 2/3/15.
//  Copyright (c) 2015 Monal.im. All rights reserved.
//

#import "ParseResumed.h"

@implementation ParseResumed

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    _messageBuffer=nil;
    
    //    if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:sm:3"])
    //    {
    //
    //    }
    
    _h=[NSNumber numberWithInteger:[(NSString*)[attributeDict objectForKey:@"h"] integerValue]];
    
}

@end
