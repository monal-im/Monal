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
-(id) initWithElement:(NSString*) element;
-(id) initWithElement:(NSString*) element andNamespace:(NSString*) xmlns;
-(id) initWithElement:(NSString*) element andNamespace:(NSString*) xmlns withAttributes:(NSDictionary*) attributes andChildren:(NSArray*) children andData:(NSString*) data;
-(id) initWithElement:(NSString*) element withAttributes:(NSDictionary*) attributes andChildren:(NSArray*) children andData:(NSString*) data;

/**
 Query for text contents, elementNames, attributes or child elements
 */
-(NSArray*) find:(NSString* _Nonnull) queryString;
-(id) findFirst:(NSString* _Nonnull) queryString;

/**
 Check if the current node matches the queryString and/or its extraction command would return something
 */
-(BOOL) check:(NSString* _Nonnull) queryString;

/**
 Quickly set an XMLNS attribute
 */
-(void) setXMLNS:(NSString*) xmlns;

/**
 Generates an XML String suitable for writing based on the node
 */
@property (strong, readonly) NSString* XMLString;
-(NSString*) XMLString;
-(NSString*) description;

/**
 Adds a new child node (this creates a copy of the node and changes the copy's parent property to its new parent
 */
-(void) addChild:(MLXMLNode*) child;

/**
 The name of the element itself. 
 */
@property (atomic, strong) NSString* element;

/**
 Attributes are given keys as they will be printed in the XML
 */
@property (atomic, strong) NSMutableDictionary* attributes;

/**
 Children are XMLnodes
 */
@property (atomic, strong) NSMutableArray* children;

/**
 String to be inserted into the data field between elements. AKA inner text.
 */
@property (atomic, strong) NSString* data;

/**
 One-based depth this node was encountered at in XML stream (always 0 for locally generated nodes)
 */
@property (atomic, assign) NSInteger* depth;

/**
 Parent node of this one (if any)
 */
@property (atomic, strong) MLXMLNode* parent;

@end
