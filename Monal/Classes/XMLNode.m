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
    _children=[[NSMutableDictionary alloc] init];
    _data=nil; 
    
    return self; 
}

-(NSString*) XMLString
{
    if(!_element) return nil; // sanity check 
    
    NSMutableString* outputString=[[NSMutableString alloc] init];
    
    if([_element isEqualToString:@"stream:stream"])
        [outputString appendString:[NSString stringWithFormat:@"<?xml version='1.0'?>"]];

    
    [outputString appendString:[NSString stringWithFormat:@"<%@",_element]];
    
    //set attributes
    for(NSString* key in [_attributes allKeys])
    {
        [outputString appendString:[NSString stringWithFormat:@" %@='%@' ",key, [_attributes objectForKey:key]]];
    }
    
    if (![_element isEqualToString:@"starttls"])
    [outputString appendString:[NSString stringWithFormat:@">"]];
    else
    [outputString appendString:[NSString stringWithFormat:@"/>"]];
        
    //set children here
    
    //dont close stream
    if((![_element isEqualToString:@"stream:stream"]) ) 
        [outputString appendString:[NSString stringWithFormat:@"</%@>", _element]];
    
    return (NSString*)outputString ;
}


@end
