//
//  XMPPParser.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import <Foundation/Foundation.h>

#import "MLXMPPConstants.h"
#import "MLConstants.h"


@interface XMPPParser : NSObject 
{
    NSString* State;
    NSMutableString* _messageBuffer;
    
    NSString* _type;
    NSString* _from;
    NSString* _to;
    NSString* _user;
    NSString* _resource;
    NSString* _idval;
    
    NSString* _errorType;
    NSString* _errorReason;
	NSString* _errorText;
}

@property (nonatomic, copy) NSString* stanzaType;
@property (nonatomic, copy) NSString* stanzaNameSpace;

@property (nonatomic, copy, readonly) NSString* type;
/**
 full name as sent from server
 */
@property (nonatomic, copy, readonly) NSString* from;

/**
 full name as sent from server
 */
@property (nonatomic, copy, readonly) NSString* to;

/**
 username part of from
 */
@property (nonatomic, copy, readonly) NSString* user;

/**
 resource part of from
 */
@property (nonatomic, copy, readonly) NSString* resource;

/**
 node id
 */
@property (nonatomic, copy, readonly) NSString* idval;

/**
 if error, the type
 */
@property (nonatomic, copy, readonly) NSString* errorType;

/**
if error, the reason
*/
@property (nonatomic, copy, readonly) NSString* errorReason;

/**
if error, the human readable text
*/
@property (nonatomic, copy, readonly) NSString* errorText;


- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict;
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string;
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName ;

@end
