//
//  XMPPParser.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import <Foundation/Foundation.h>

@interface XMPPParser : NSObject <NSXMLParserDelegate>
{
    NSString* State;
    NSString* _messageBuffer;
}

- (id) initWithDictionary:(NSDictionary*) dictionary;


@end
