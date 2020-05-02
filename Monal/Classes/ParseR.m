//
//  ParseR.m
//  monalxmpp
//
//  Created by Thilo Molitor on 04.05.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "ParseR.h"

@implementation ParseR

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    _messageBuffer=nil;
}

@end
