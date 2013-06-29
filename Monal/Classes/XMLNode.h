//
//  XMLNode.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <Foundation/Foundation.h>

@interface XMLNode : NSObject
{
    
}

/**
 Generates an XML String suitable for writing based on the node
 */
-(NSString*) XMLString;

/**
 Generates a node object after parsing a string.
 */
+(XMLNode*) nodeFromDictionary:(NSDictionary*) dictionary;

@property (nonatomic,strong) NSString* element;
@property (nonatomic,strong) NSMutableDictionary* attributes;
@property (nonatomic,strong) NSMutableDictionary* children;
@property (nonatomic,strong) NSString* data;

@end
