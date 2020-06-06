//
//  XMLNode.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import "MLXMLNode.h"
#import "MLXMPPConstants.h"

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

-(id) initWithCoder:(NSCoder*)decoder
{
    self = [super init];
    if(!self)
        return nil;

    _element = [decoder decodeObjectForKey:@"element"];
    _attributes = [decoder decodeObjectForKey:@"attributes"];
    _children = [decoder decodeObjectForKey:@"children"];
    _data = [decoder decodeObjectForKey:@"data"];

    return self;
}

-(void) encodeWithCoder:(NSCoder*)encoder
{
    [encoder encodeObject:_element forKey:@"element"];
    [encoder encodeObject:_attributes forKey:@"attributes"];
    [encoder encodeObject:_children forKey:@"children"];
    [encoder encodeObject:_data forKey:@"data"];
}

-(void) setXMLNS:(NSString*) xmlns
{
    [self.attributes setObject:xmlns forKey:kXMLNS];
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
    if(!_element)
        return nil; // sanity check
    
    if([_element isEqualToString:@"__whitePing"])
        return @" ";
    
    if([_element isEqualToString:@"__xml"])
         return [NSString stringWithFormat:@"<?xml version='1.0'?>"];
    
    NSMutableString* outputString=[[NSMutableString alloc] init];
    [outputString appendString:[NSString stringWithFormat:@"<%@", _element]];
    
    //set attributes
    for(NSString* key in [_attributes allKeys])
        [outputString appendString:[NSString stringWithFormat:@" %@='%@'", key, [MLXMLNode escapeForXMPPSingleQuote:(NSString *)[_attributes objectForKey:key]]]];
    
    if([_children count] || (_data && ![_data isEqualToString:@""]))
    {
        [outputString appendString:[NSString stringWithFormat:@">"]];
        
        //set children here
        for(MLXMLNode* child in _children)
            [outputString appendString:[child XMLString]];
        
        if(_data)
            [outputString appendString:[MLXMLNode escapeForXMPP:_data]];
        
        //dont close stream element
        if(![_element isEqualToString:@"stream:stream"] && ![_element isEqualToString:@"/stream:stream"])
            [outputString appendString:[NSString stringWithFormat:@"</%@>", _element]];
    }
    else
    {
        //dont close stream element
        if(![_element isEqualToString:@"stream:stream"] && ![_element isEqualToString:@"/stream:stream"])
            [outputString appendString:[NSString stringWithFormat:@"/>"]];
        else
            [outputString appendString:[NSString stringWithFormat:@">"]];
    }
    
    return (NSString*)outputString;
}

@end
