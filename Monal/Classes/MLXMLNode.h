//
//  XMLNode.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <Foundation/Foundation.h>

@interface MLXMLNode : NSObject 
{
    
}

/**
 Initilizes with an element type
 */
-(id) initWithElement:(NSString*)element;

/**
 Quickly set an XMLNS attribute
 */
-(void) setXMLNS:(NSString*) xmlns;

/**
 Generates an XML String suitable for writing based on the node
 */
-(NSString*) XMLString;

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
