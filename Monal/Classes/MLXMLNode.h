//
//  XMLNode.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

@interface MLXMLNode : NSObject <NSSecureCoding>
{
    
}

+(BOOL) supportsSecureCoding;

/**
 Initilizes with an element type
 */
-(id) initWithElement:(NSString*)element;
-(id) initWithElement:(NSString*)element andNamespace:(NSString*)xmlns;
-(id) initWithElement:(NSString*) element andNamespace:(NSString*) xmlns withAttributes:(NSDictionary*) attributes andChildren:(NSArray*) children andData:(NSString*) data;
-(id) initWithElement:(NSString*) element withAttributes:(NSDictionary*) attributes andChildren:(NSArray*) children andData:(NSString*) data;

/**
 Quickly set an XMLNS attribute
 */
-(void) setXMLNS:(NSString*) xmlns;

/**
 Generates an XML String suitable for writing based on the node
 */
-(NSString*) XMLString;

/**
 Adds a delayed delivery tag to the stanza, see XEP 0203
 */
-(void) addDelayTagFrom:(NSString *) from;

/**
 The name of the element itself. 
 */
@property (nonatomic,strong) NSString* element;

/**
 Attributes are given keys as they will be printed in the XML
 */
@property (nonatomic,strong) NSMutableDictionary* attributes;

/**
 Children are XMLnodes
 */
@property (nonatomic,strong) NSMutableArray* children;

/**
 String to be inserted into the data field between elements. AKA inner text.
 */
@property (nonatomic,strong) NSString* data;

@end
