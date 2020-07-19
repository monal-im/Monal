//
//  ParseFailed.m
//  Monal
//
//  Created by Thilo Molitor on 4/19/17.
//  Copyright (c) 2017 Monal.im. All rights reserved.
//

#import "ParseFailed.h"

@implementation ParseFailed

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    _messageBuffer=nil;
    _h=0;
    if([attributeDict objectForKey:@"h"])
        _h=[NSNumber numberWithInteger:[(NSString*)[attributeDict objectForKey:@"h"] integerValue]];
}

@end
