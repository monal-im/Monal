//
//  XMLNode.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import "XMLNode.h"

@implementation XMLNode

-(id) init
{
    self=[super init];
    _attributes=[[NSMutableDictionary alloc] init];
    _children=[[NSMutableArray alloc] init];
    _data=nil; 
    return self; 
}

-(id) initWithElement:(NSString*)element
{
    self=[self init];
    self.element=element;
    return self;
    
}

-(void) setXMLNS:(NSString*) xmlns
{
    [self.attributes setObject:xmlns forKey:@"xmlns"];
}

-(NSString*) XMLString
{
    if(!_element) return nil; // sanity check
 
    if([_element isEqualToString:@"whitePing"]) return @" ";
    
    NSMutableString* outputString=[[NSMutableString alloc] init];
    
    if([_element isEqualToString:@"stream:stream"])
        [outputString appendString:[NSString stringWithFormat:@"<?xml version='1.0'?>"]];
    
    
    [outputString appendString:[NSString stringWithFormat:@"<%@",_element]];
    
    //set attributes
    for(NSString* key in [_attributes allKeys])
    {
        [outputString appendString:[NSString stringWithFormat:@" %@='%@' ",key, [_attributes objectForKey:key]]];
    }
    
    if ([_element isEqualToString:@"starttls"])
        [outputString appendString:[NSString stringWithFormat:@"/>"]];
    else
    {
        [outputString appendString:[NSString stringWithFormat:@">"]];
        
        //set children here
        for(XMLNode* child in _children)
        {
            [outputString appendString:[child XMLString]];
        }
        
        
        if(_data)
            [outputString appendString:_data];
        
        //dont close stream
        if((![_element isEqualToString:@"stream:stream"]) )
            [outputString appendString:[NSString stringWithFormat:@"</%@>", _element]];
    }
    
    return (NSString*)outputString ;
}


@end
