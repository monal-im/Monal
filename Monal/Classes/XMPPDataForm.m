//
//  XMPPDataForm.m
//  monalxmpp
//
//  Created by ich on 12.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPPDataForm.h"

@interface MLXMLNode()
@property (atomic, strong, readwrite) NSString* element;
@end

@implementation XMPPDataForm

//this simple init is not public api because type and form type are mandatory in xep-0004
-(id _Nonnull) init
{
    self = [super init];
    self.element = @"x";
    [self setXMLNS:@"jabber:x:data"];
    return self;
}

-(id _Nonnull) initWithType:(NSString* _Nonnull) type andFormType:(NSString* _Nonnull) formType
{
    self = [self init];
    self.attributes[@"type"] = type;
    [self setField:@"FORM_TYPE" withType:@"hidden" andValue:formType];
    return self;
}

-(id _Nonnull) initWithType:(NSString* _Nonnull) type formType:(NSString* _Nonnull) formType andDictionary:(NSDictionary* _Nonnull) vars
{
    self = [self initWithType:type andFormType:formType];
    [self addEntriesFromDictionary:vars];
    return self;
}

-(void) setFieldWithDictionary:(NSDictionary*) field
{
    [self setField:field[@"name"] withType:field[@"type"] andValue:[NSString stringWithFormat:@"%@", field[@"value"]]];
}

-(void) setField:(NSString* _Nonnull) name withValue:(NSString* _Nonnull) value
{
    [self setField:name withType:nil andValue:value];
}

-(void) setField:(NSString* _Nonnull) name withType:(NSString* _Nullable) type andValue:(NSString* _Nonnull) value
{
    NSDictionary* attrs = type ? @{@"type": type, @"var": name} : @{@"var": name};
    [self removeChild:[self findFirst:[NSString stringWithFormat:@"field<var=%@>", name]]];
    [self addChild:[[MLXMLNode alloc] initWithElement:@"field" withAttributes:attrs andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:value]
    ] andData:nil]];
}

-(NSDictionary* _Nullable) getField:(NSString* _Nonnull) name
{
    MLXMLNode* fieldNode = [self findFirst:[NSString stringWithFormat:@"field<var=%@>", [NSRegularExpression escapedPatternForString:name]]];
    if(!fieldNode)
        return nil;
    if([fieldNode check:@"/@type"])
        return @{
            @"name": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"/@var"]],
            @"type": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"/@type"]],
            @"value": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"value#"]],
            @"options": [fieldNode find:@"option/value#"]
        };
    return @{
        @"name": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"/@var"]],
        @"value": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"value#"]],
        @"options": [fieldNode find:@"option/value#"]
    };
}

-(void) removeField:(NSString* _Nonnull) name
{
    [self removeChild:[self findFirst:[NSString stringWithFormat:@"field<var=%@>", [NSRegularExpression escapedPatternForString:name]]]];
}

-(void) setType:(NSString* _Nonnull) type
{
    self.attributes[@"type"] = type;
}
-(NSString*) type
{
    return self.attributes[@"type"];
}

-(void) setFormType:(NSString* _Nonnull) formType
{
    [self setField:@"FORM_TYPE" withType:@"hidden" andValue:formType];
}
-(NSString*) formType
{
    return self[@"FORM_TYPE"];
}

-(NSString*) description
{
    NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
    for(NSString* key in [self allKeys])
        dict[key] = [self getField:key];
    return [NSString stringWithFormat:@"XMPPDataForm%@%@ %@",
        self.type ? [NSString stringWithFormat:@"[%@]", self.type] : @"",
        self.formType ? [NSString stringWithFormat:@"{%@}", self.formType] : @"",
        dict
    ];
}

//*** NSMutableDictionary interface below

-(id _Nullable) objectForKeyedSubscript:(NSString* _Nonnull) key
{
    return [self findFirst:[NSString stringWithFormat:@"field<var=%@>/value#", [NSRegularExpression escapedPatternForString:key]]];
}

-(void) setObject:(id _Nullable) obj forKeyedSubscript:(NSString*) key
{
    if(!obj)
        return [self removeChild:[self findFirst:[NSString stringWithFormat:@"field<var=%@>", [NSRegularExpression escapedPatternForString:key]]]];
    MLXMLNode* fieldNode = [self findFirst:[NSString stringWithFormat:@"field<var=%@>", [NSRegularExpression escapedPatternForString:key]]];
    if(!fieldNode)
        return [self setField:key withValue:[NSString stringWithFormat:@"%@", obj]];
    MLXMLNode* valueNode = [fieldNode findFirst:@"value"];
    if(!valueNode)
        [fieldNode addChild:[[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:[NSString stringWithFormat:@"%@", obj]]];
    else
        valueNode.data = [NSString stringWithFormat:@"%@", obj];
}

-(NSArray*) allKeys
{
    return [self find:@"field@var"];
}

-(NSArray*) allValues
{
    return [self find:@"field/value#"];
}

-(NSUInteger) count
{
    return [[self allKeys] count];
}

-(NSArray*) allKeysForObject:(id) anObject
{
    NSMutableArray* retval = [[NSMutableArray alloc] init];
    for(MLXMLNode* field in [self find:@"field"])
        if([anObject isEqual:[field findFirst:@"value#"]])
            [retval addObject:[field findFirst:@"/@var"]];
    return retval;
}

-(id) valueForKey:(NSString*) key
{
    return [self findFirst:[NSString stringWithFormat:@"field<var=%@>/value#", [NSRegularExpression escapedPatternForString:key]]];
}

-(id) objectForKey:(NSString*) key
{
    return [self valueForKey:key];
}

-(void) removeObjectForKey:(NSString*) key
{
    [self removeField:key];
}

-(void) removeAllObjects
{
    for(MLXMLNode* child in self.children)
        [self removeChild:child];
}

-(void) removeObjectsForKeys:(NSArray*) keyArray
{
    for(NSString* key in keyArray)
        [self removeObjectForKey:key];
}

-(void) setObject:(NSString*) value forKey:(NSString*) key
{
    [self setField:key withValue:value];
}

-(void) setValue:(NSString* _Nullable) value forKey:(NSString*) key
{
    if(!value)
        [self removeObjectForKey:key];
    else
        [self setObject:value forKey:key];
}

-(void) addEntriesFromDictionary:(NSDictionary*) vars
{
    for(NSString* key in vars)
    {
        if([vars[key] isKindOfClass:[NSDictionary class]])
            [self setFieldWithDictionary:vars[key]];
        else
            self[key] = vars[key];
    }
}

-(void) setDictionary:(NSDictionary*) vars
{
    [self removeAllObjects];
    [self addEntriesFromDictionary:vars];
}

@end
