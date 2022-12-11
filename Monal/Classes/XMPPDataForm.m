//
//  XMPPDataForm.m
//  monalxmpp
//
//  Created by ich on 12.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XMPPDataForm.h"
#import "HelperTools.h"

@interface MLXMLNode()
@property (atomic, strong, readwrite) NSString* element;
-(void) invalidateUpstreamCache;
@end

@implementation XMPPDataForm

static NSRegularExpression* dataFormQueryRegex;

+(void) initialize
{
    dataFormQueryRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\{(\\*|[^}]+)\\})?([!a-zA-Z0-9_:-]+|\\*)?(\\[([0-9]+)\\])?(@[a-zA-Z0-9_:#-]+|%[a-zA-Z0-9_:#-]+)?" options:0 error:nil];
}

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

-(MLXMLNode*) setFieldWithDictionary:(NSDictionary*) field
{
    return [self setFieldWithDictionary:field atIndex:nil];
}

-(MLXMLNode*) setFieldWithDictionary:(NSDictionary*) field  atIndex:(NSNumber* _Nullable) index
{
    MLXMLNode* fieldNode = [self setField:field[@"name"] withType:field[@"type"] andValue:[NSString stringWithFormat:@"%@", field[@"value"]] atIndex:index];
    if(field[@"options"])
    {
        for(NSString* option in field[@"options"])
            if([field[@"options"][option] isEqualToString:option])
                [fieldNode addChildNode:[[MLXMLNode alloc] initWithElement:@"option" withAttributes:@{} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:option]
                ] andData:nil]];
            else
                [fieldNode addChildNode:[[MLXMLNode alloc] initWithElement:@"option" withAttributes:@{@"label": field[@"options"][option]} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:option]
                ] andData:nil]];
    }
    if(field[@"description"])
        [fieldNode addChildNode:[[MLXMLNode alloc] initWithElement:@"desc" withAttributes:@{} andChildren:@[] andData:field[@"description"]]];
    if(field[@"required"] && [field[@"required"] boolValue])
        [fieldNode addChildNode:[[MLXMLNode alloc] initWithElement:@"required" withAttributes:@{} andChildren:@[] andData:nil]];
    return fieldNode;
}

-(MLXMLNode*) setField:(NSString* _Nonnull) name withValue:(NSString* _Nonnull) value
{
    return [self setField:name withValue:value atIndex:nil];
}

-(MLXMLNode*) setField:(NSString* _Nonnull) name withValue:(NSString* _Nonnull) value atIndex:(NSNumber* _Nullable) index
{
    return [self setField:name withType:nil andValue:value atIndex:index];
}

-(MLXMLNode*) setField:(NSString* _Nonnull) name withType:(NSString* _Nullable) type andValue:(NSString* _Nonnull) value
{
    return [self setField:name withType:type andValue:value atIndex:nil];
}

-(MLXMLNode*) setField:(NSString* _Nonnull) name withType:(NSString* _Nullable) type andValue:(NSString* _Nonnull) value atIndex:(NSNumber* _Nullable) index
{
    MLXMLNode* operateAtNode = self;
    if(index != nil)
    {
        NSArray<MLXMLNode*>* items = [self find:@"item"];
        operateAtNode = items[[index unsignedIntegerValue]];
    }
    MLAssert(operateAtNode != nil, @"index out of bounds for multi-item form!", (@{
        @"index": index,
        @"dataform": self,
    }));
    NSDictionary* attrs = type ? @{@"type": type, @"var": name} : @{@"var": name};
    [operateAtNode removeChildNode:[operateAtNode findFirst:@"field<var=%@>", name]];
    MLXMLNode* field = [operateAtNode addChildNode:[[MLXMLNode alloc] initWithElement:@"field" withAttributes:attrs andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:value]
    ] andData:nil]];
    [self invalidateUpstreamCache];     //make sure future queries accurately reflect this change
    return field;
}

-(NSDictionary* _Nullable) getField:(NSString* _Nonnull) name
{
    return [self getField:name atIndex:nil];
}

-(NSDictionary* _Nullable) getField:(NSString* _Nonnull) name atIndex:(NSNumber* _Nullable) index
{
    MLXMLNode* fieldNode;
    MLXMLNode* descriptionNode;
    if(index != nil)
    {
        descriptionNode = [self findFirst:@"reported/field<var=%@>", name];
        NSArray<MLXMLNode*>* items = [self find:@"item"];
        fieldNode = [items[[index unsignedIntegerValue]] findFirst:@"field<var=%@>", name];
    }
    else
    {
        fieldNode = [self findFirst:@"field<var=%@>", name];
    }
    if(!fieldNode)
        return nil;
    if(descriptionNode == nil)
        descriptionNode = fieldNode;
    
    NSMutableDictionary* options = [[NSMutableDictionary alloc] init];
    for(MLXMLNode* option in [fieldNode find:@"option"])
        options[[NSString stringWithFormat:@"%@", [option findFirst:@"value#"]]] = [NSString stringWithFormat:@"%@", ([option check:@"/@label"] ? [option findFirst:@"/@label"] : [option findFirst:@"value#"])];
    NSMutableArray* allValues = [[NSMutableArray alloc] init];
    for(id value in [fieldNode find:@"value#"])
        if(value != nil)        //only safeguard, should never happen
            [allValues addObject:[NSString stringWithFormat:@"%@", value]];
    if([descriptionNode check:@"/@type"])
        return @{
            @"name": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"/@var"]],
            @"type": [NSString stringWithFormat:@"%@", [descriptionNode findFirst:@"/@type"]],
            @"value": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"value#"]],
            @"allValues": [allValues copy],     //immutable copy
            @"options": [options copy],         //immutable copy
            @"description": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"description#"]],
            @"required": @([fieldNode check:@"required"]),
        };
    return @{
        @"name": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"/@var"]],
        @"value": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"value#"]],
        @"allValues": [allValues copy],     //immutable copy
        @"options": [options copy],         //immutable copy
        @"description": [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"description#"]],
        @"required": @([fieldNode check:@"required"]),
    };
}

-(void) removeField:(NSString* _Nonnull) name
{
    [self removeField:name atIndex:nil];
}

-(void) removeField:(NSString* _Nonnull) name atIndex:(NSNumber* _Nullable) index
{
    if(index != nil)
    {
        NSArray<MLXMLNode*>* items = [self find:@"item"];
        [self removeChildNode:[items[[index unsignedIntegerValue]] findFirst:@"field<var=%@>", name]];
    }
    else
        [self removeChildNode:[self findFirst:@"field<var=%@>", name]];
    [self invalidateUpstreamCache];     //make sure future queries accurately reflect this change
}

-(void) setType:(NSString* _Nonnull) type
{
    self.attributes[@"type"] = type;
    [self invalidateUpstreamCache];     //make sure future queries accurately reflect this change
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

-(NSString* _Nullable) title
{
    return [self findFirst:@"title"];
}
-(void) setTitle:(NSString* _Nullable) title
{
    if([self check:@"title"])
        ((MLXMLNode*)[self findFirst:@"title"]).data = title;
    else
        [self addChildNode:[[MLXMLNode alloc] initWithElement:@"title" andData:title]];
}

-(NSString* _Nullable) instructions
{
    return [self findFirst:@"instructions"];
}
-(void) setInstructions:(NSString* _Nullable) instructions
{
    if([self check:@"instructions"])
        ((MLXMLNode*)[self findFirst:@"instructions"]).data = instructions;
    else
        [self addChildNode:[[MLXMLNode alloc] initWithElement:@"instructions" andData:instructions]];
}

-(id _Nullable) processDataFormQuery:(NSString*) query
{
    //parse query
    NSMutableDictionary* parsedQuery = [[NSMutableDictionary alloc] init];
    NSArray* matches = [dataFormQueryRegex matchesInString:query options:0 range:NSMakeRange(0, [query length])];
    if(![matches count])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Could not parse data form query!" userInfo:@{
            @"node": self,
            @"query": query
        }];
    NSTextCheckingResult* match = matches.firstObject;
    NSRange formTypeRange = [match rangeAtIndex:2];
    NSRange typeRange = [match rangeAtIndex:3];
    NSRange indexRange = [match rangeAtIndex:5];
    NSRange extractionCommandRange = [match rangeAtIndex:6];
    if(formTypeRange.location != NSNotFound)
        parsedQuery[@"formType"] = [query substringWithRange:formTypeRange];
    else
        parsedQuery[@"formType"] = @"*";
    if(typeRange.location != NSNotFound)
        parsedQuery[@"type"] = [query substringWithRange:typeRange];
    else
        parsedQuery[@"type"] = @"*";
    if(indexRange.location != NSNotFound)
        parsedQuery[@"index"] = [NSNumber numberWithUnsignedInteger:(NSUInteger)[[query substringWithRange:indexRange] longLongValue]];
    if(extractionCommandRange.location != NSNotFound)
    {
        NSString* extractionCommand = [query substringWithRange:extractionCommandRange];
        parsedQuery[@"extractionCommand"] = [extractionCommand substringToIndex:1];
        parsedQuery[@"var"] = [extractionCommand substringFromIndex:1];
    }
    
    //process query
    if(!([@"*" isEqualToString:parsedQuery[@"formType"]] || (self.formType != nil && [self.formType isEqualToString:parsedQuery[@"formType"]])))
        return nil;
    if(!([@"*" isEqualToString:parsedQuery[@"type"]] || (self.type != nil && [self.type isEqualToString:parsedQuery[@"type"]])))
        return nil;
    
    //handle non-item dataforms and queries with index out of bounds as nil result of our query
    if(parsedQuery[@"index"] != nil)
    {
        if(![self check:@"item"])
            return nil;
        if([self count] < [parsedQuery[@"index"] unsignedIntegerValue])
            return nil;
    }
        
    if([parsedQuery[@"extractionCommand"] isEqualToString:@"@"])
    {
        if(parsedQuery[@"index"] != nil)
            return self[[parsedQuery[@"index"] unsignedIntegerValue]][parsedQuery[@"var"]];
        return self[parsedQuery[@"var"]];
    }
    if([parsedQuery[@"extractionCommand"] isEqualToString:@"%"])
    {
        if(parsedQuery[@"index"] != nil)
            return [self getField:parsedQuery[@"var"] atIndex:parsedQuery[@"index"]];
        return [self getField:parsedQuery[@"var"]];
    }
    return self;        //we did not use any extraction command, but filtered by formType and type only
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

//*** NSArray interface below (only indexed subscript parts)

-(id) objectAtIndexedSubscript:(NSInteger) idx
{
    NSArray<MLXMLNode*>* items = [self find:@"item"];
    if(items[idx] == nil)
        return nil;
    
    NSMutableDictionary* retval = [NSMutableDictionary new];
    for(MLXMLNode* fieldNode in [items[idx] find:@"field"])
        retval[[NSString stringWithFormat:@"%@", [fieldNode findFirst:@"/@var"]]] = [NSString stringWithFormat:@"%@", [fieldNode findFirst:@"value#"]];
    return [retval copy];       //immutable copy
}

-(void) setObject:(id _Nullable) obj atIndexedSubscript:(NSInteger) idx
{
    NSArray<MLXMLNode*>* items = [self find:@"item"];
    
    //remove whole item if nil was given
    if(obj == nil)
    {
        [self removeChildNode:items[idx]];
        [self invalidateUpstreamCache];     //make sure future queries accurately reflect this change
        return;
    }
    
    MLAssert([obj isKindOfClass:[NSDictionary class]], @"LHS number subscripts into a XMPPDataForm MUST have a NSDictionary on the RHS side!", (@{
        @"index": @(idx),
        @"obj": nilWrapper(obj),
    }));
        
    //remove all present fields nodes first
    for(MLXMLNode* fieldNode in [items[idx] find:@"field"])
        [items[idx] removeChildNode:fieldNode];
    
    //then create new field nodes as specified
    NSDictionary* fields = (NSDictionary*)obj;
    for(NSString* name in fields)
        [items[idx] addChildNode:[[MLXMLNode alloc] initWithElement:@"field" withAttributes:@{@"var": name} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:fields[name]]
        ] andData:nil]];
    [self invalidateUpstreamCache];     //make sure future queries accurately reflect this change
}

//*** NSMutableDictionary interface below

-(id _Nullable) objectForKeyedSubscript:(NSString* _Nonnull) key
{
    MLXMLNode* firstItem = [self findFirst:@"item"];
    if(firstItem == nil)
        firstItem = self;
    return [firstItem findFirst:@"field<var=%@>/value#", key];
}

-(void) setObject:(id _Nullable) obj forKeyedSubscript:(NSString*) key
{
    MLXMLNode* firstItem = [self findFirst:@"item"];
    if(firstItem == nil)
        firstItem = self;
    if(!obj)
    {
        [firstItem removeChildNode:[firstItem findFirst:@"field<var=%@>", key]];
        [self invalidateUpstreamCache];     //make sure future queries accurately reflect this change
        return;
    }
    MLXMLNode* fieldNode;
    fieldNode = [firstItem findFirst:@"field<var=%@>", key];
    if(!fieldNode)
    {
        [self setField:key withValue:[NSString stringWithFormat:@"%@", obj] atIndex:(firstItem != nil ? 0 : nil)];
        return;
    }
    MLXMLNode* valueNode = [fieldNode findFirst:@"value"];
    if(!valueNode)
        [fieldNode addChildNode:[[MLXMLNode alloc] initWithElement:@"value" withAttributes:@{} andChildren:@[] andData:[NSString stringWithFormat:@"%@", obj]]];
    else
        valueNode.data = [NSString stringWithFormat:@"%@", obj];
    [self invalidateUpstreamCache];     //make sure future queries accurately reflect this change
}

//for multi-item forms it will only return the list of var names of the first item
//(as according to XEP-0004 all items should have the same set of field nodes --> this should contain all var names possible in any item)
-(NSArray*) allKeys
{
    MLXMLNode* firstItem = [self findFirst:@"item"];
    if(firstItem == nil)
        firstItem = self;
    return [firstItem find:@"field@var"];
}

-(NSArray*) allValues
{
    MLXMLNode* firstItem = [self findFirst:@"item"];
    if(firstItem == nil)
        firstItem = self;
    return [firstItem find:@"field/value#"];
}

//will return the count of items for a multi-item form and the count of vars otherwise
-(NSUInteger) count
{
    if([self check:@"item"])
        return [[self find:@"item"] count];
    return [[self allKeys] count];
}


-(NSArray*) allKeysForObject:(id) anObject
{
    NSMutableArray* retval = [[NSMutableArray alloc] init];
    MLXMLNode* firstItem = [self findFirst:@"item"];
    for(MLXMLNode* field in (firstItem != nil ? [firstItem find:@"field"] : [self find:@"field"]))
        if([anObject isEqual:[field findFirst:@"value#"]])
            [retval addObject:[field findFirst:@"/@var"]];
    return retval;
}

-(id) valueForKey:(NSString*) key
{
    MLXMLNode* firstItem = [self findFirst:@"item"];
    if(firstItem == nil)
        firstItem = self;
    return [firstItem findFirst:@"field<var=%@>/value#", key];
}

-(id) objectForKey:(NSString*) key
{
    return [self valueForKey:key];
}

-(void) removeObjectForKey:(NSString*) key
{
    [self removeField:key atIndex:([self check:@"item"] ? 0 : nil)];
}

-(void) removeAllObjects
{
    MLXMLNode* firstItem = [self findFirst:@"item"];
    if(firstItem == nil)
        firstItem = self;
    for(MLXMLNode* child in [firstItem find:@"field"])
        [firstItem removeChildNode:child];
    [self invalidateUpstreamCache];     //make sure future queries accurately reflect this change
}

-(void) removeObjectsForKeys:(NSArray*) keyArray
{
    for(NSString* key in keyArray)
        [self removeObjectForKey:key];
}

-(void) setObject:(NSString*) value forKey:(NSString*) key
{
    [self setField:key withValue:value atIndex:([self check:@"item"] ? 0 : nil)];
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
            [self setFieldWithDictionary:vars[key] atIndex:([self check:@"item"] ? 0 : nil)];
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
