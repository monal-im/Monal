//
//  XMLNode.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLXMLNode : NSObject <NSSecureCoding>
{
    
}

+(BOOL) supportsSecureCoding;

/**
 Initilizes with an element type
 */
-(id) initWithElement:(NSString*) element;
-(id) initWithElement:(NSString*) element andNamespace:(NSString*) xmlns;
-(id) initWithElement:(NSString*) element andNamespace:(NSString*) xmlns withAttributes:(NSDictionary*) attributes andChildren:(NSArray*) children andData:(NSString* _Nullable) data;
-(id) initWithElement:(NSString*) element withAttributes:(NSDictionary*) attributes andChildren:(NSArray*) children andData:(NSString* _Nullable) data;
-(id) initWithElement:(NSString*) element andData:(NSString* _Nullable) data;

/**
 Query for text contents, elementNames, attributes or child elements
 */
-(NSArray*) find:(NSString* _Nonnull) queryString, ... NS_FORMAT_FUNCTION(1, 2);
-(id _Nullable) findFirst:(NSString* _Nonnull) queryString, ... NS_FORMAT_FUNCTION(1, 2);

/**
 Check if the current node matches the queryString and/or its extraction command would return something
 */
-(BOOL) check:(NSString* _Nonnull) queryString, ... NS_FORMAT_FUNCTION(1, 2);

/**
 Quickly set an XMLNS attribute
 */
-(void) setXMLNS:(NSString*) xmlns;

/**
 Generates an XML String suitable for writing based on the node
 */
@property (strong, readonly) NSString* XMLString;
@property (strong, readonly) NSString* description;

/**
 Adds a new child node (this creates a copy of the node and changes the copy's parent property to its new parent
 */
-(MLXMLNode* _Nullable) addChildNode:(MLXMLNode*) child;

/**
 Removes child by reference
 */
-(MLXMLNode* _Nullable) removeChildNode:(MLXMLNode*) child;

/**
 The name of the element itself. 
 */
@property (atomic, strong, readonly) NSString* element;

/**
 Attributes are given keys as they will be printed in the XML
 */
@property (atomic, readonly) NSMutableDictionary* attributes;

/**
 Children are XMLnodes
 */
@property (atomic, readonly) NSArray* children;

/**
 String to be inserted into the data field between elements. AKA inner text.
 */
@property (atomic, strong) NSString* _Nullable data;

/**
 Parent node of this one (if any)
 */
@property (atomic, weak, readonly) MLXMLNode* _Nullable parent;

@end

NS_ASSUME_NONNULL_END
