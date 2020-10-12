//
//  XMPPDataForm.m
//  monalxmpp
//
//  Created by ich on 12.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPPDataForm.h"

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
    for(NSString* key in vars)
    {
        if([vars[key] isKindOfClass:[NSDictionary class]])
            [self setFieldWithDictionary:vars[key]];
        else
            self[key] = vars[key];
    }
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

-(void) setField:(NSString* _Nonnull) name withType:(NSString*) type andValue:(NSString* _Nonnull) value
{
    NSArray* attrs = type ? @{@"type": type, @"var": name} : @{@"var": name};
    [self removeChild:[self findFirst:[NSString stringWithFormat:@"field<var=%@>", name]]];
    [self addChild:[[MLXMLNode alloc] initWithElement:@"field" withAttributes:attrs andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:value]
    ] andData:nil]];
}

-(NSDictionary* _Nullable) getField:(NSString* _Nonnull) name
{
    MLXMLNode* fieldNode = [self findFirst:[NSString stringWithFormat:@"field<var=%@>", name]];
    if(!fieldNode)
        return nil;
    if([fieldNode findFirst:@"/@type"])
        return @{
            @"name": [fieldNode findFirst:@"/@var"],
            @"type": [fieldNode findFirst:@"/@type"],
            @"value": [fieldNode findFirst:@"value#"]
        };
    return @{
        @"name": [fieldNode findFirst:@"/@var"],
        @"value": [fieldNode findFirst:@"value#"]
    };
}

-(void) removeField:(NSString* _Nonnull) name
{
    [self removeChild:[self findFirst:[NSString stringWithFormat:@"field<var=%@>", name]]];
}

-(id _Nullable) objectForKeyedSubscript:(NSString* _Nonnull) key
{
    return [self findFirst:[NSString stringWithFormat:@"field<var=%@>/value#", key]];
}

-(void) setObject:(id _Nullable) obj forKeyedSubscript:(NSString*) key
{
    if(!obj)
        return [self removeChild:[self findFirst:[NSString stringWithFormat:@"field<var=%@>", key]]];
    MLXMLNode* fieldNode = [self findFirst:[NSString stringWithFormat:@"field<var=%@>", key]];
    if(!fieldNode)
        return [self setField:key withValue:[NSString stringWithFormat:@"%@", obj]];
    MLXMLNode* valueNode = [fieldNode findFirst:@"value"];
    if(!valueNode)
        [fieldNode addChild:[[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:[NSString stringWithFormat:@"%@", obj]]];
    else
        valueNode.data = [NSString stringWithFormat:@"%@", obj];
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

@end
