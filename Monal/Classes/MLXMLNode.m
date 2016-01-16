//
//  XMLNode.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import "MLXMLNode.h"

@implementation MLXMLNode

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


+(NSString *) escapeForXMPPSingleQuote:(NSString *) targetString
{
    NSMutableString *mutable=[targetString mutableCopy];
    [mutable replaceOccurrencesOfString:@"'" withString:@"&apos;" options:NSLiteralSearch range:NSMakeRange(0, mutable.length)];
    return [mutable copy];
}

+(NSString *) escapeForXMPP:(NSString *) targetString
{
    NSMutableString *mutable=[targetString mutableCopy];
    [mutable replaceOccurrencesOfString:@"&" withString:@"&amp;" options:NSLiteralSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@"<" withString:@"&lt;" options:NSLiteralSearch range:NSMakeRange(0, mutable.length)];
    [mutable replaceOccurrencesOfString:@">" withString:@"&gt;" options:NSLiteralSearch range:NSMakeRange(0, mutable.length)];
    
    return [mutable copy];
}

-(NSString*) XMLString
{
    if(!_element) return nil; // sanity check
 
    if([_element isEqualToString:@"whitePing"]) {
        return @" ";
    }

    if([_element isEqualToString:@"xml"]) {
         return [NSString stringWithFormat:@"<?xml version='1.0'?>"];
    }
    
    NSMutableString* outputString=[[NSMutableString alloc] init];
    [outputString appendString:[NSString stringWithFormat:@"<%@",_element]];
    
    //set attributes
    for(NSString* key in [_attributes allKeys])
    {
        [outputString appendString:[NSString stringWithFormat:@" %@='%@' ",key, [MLXMLNode escapeForXMPPSingleQuote:(NSString *)[_attributes objectForKey:key]]]];
    }
    
    if ([_element isEqualToString:@"starttls"]) {
        [outputString appendString:[NSString stringWithFormat:@"/>"]];
    }
    else
    {
        [outputString appendString:[NSString stringWithFormat:@">"]];
        
        //set children here
        for(MLXMLNode* child in _children)
        {
            [outputString appendString:[child XMLString]];
        }
        
        
        if(_data) {
            [outputString appendString:[MLXMLNode escapeForXMPP:_data]];
        }
        
        //dont close stream
        if(![_element isEqualToString:@"stream:stream"] && ![_element isEqualToString:@"/stream:stream"]) {
            [outputString appendString:[NSString stringWithFormat:@"</%@>", _element]];
        }
    }
    
    return (NSString*)outputString ;
}


@end
