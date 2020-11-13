//
//  MLHandler.m
//  monalxmpp
//
//  Created by Thilo Molitor on 29.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"
#import "MLHandler.h"

#define HANDLER_VERSION 1

@interface MLHandler ()
{
    NSMutableDictionary* _internalData;
    BOOL _invalidated;
}
@end

@implementation MLHandler

-(instancetype) init
{
    self = [super init];
    return self;
}

-(instancetype) initWithDelegate:(id) delegate handlerName:(NSString*) handlerName andBoundArguments:(NSDictionary*) args
{
    self = [self init];
    return [self INTERNALinitWithDelegate:delegate handlerName:handlerName invalidationHandlerName:nil andBoundArguments:args];
}

-(instancetype) initWithDelegate:(id) delegate handlerName:(NSString*) handlerName invalidationHandlerName:(NSString*) invalidationHandlerName andBoundArguments:(NSDictionary*) args
{
    self = [self init];
    return [self INTERNALinitWithDelegate:delegate handlerName:handlerName invalidationHandlerName:invalidationHandlerName andBoundArguments:args];
}

-(instancetype) INTERNALinitWithDelegate:(id) delegate handlerName:(NSString*) handlerName invalidationHandlerName:(NSString* _Nullable) invalidationHandlerName andBoundArguments:(NSDictionary* _Nullable) args
{
    if(![delegate respondsToSelector:[self handlerNameToSelector:handlerName]])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:[NSString stringWithFormat:@"Class '%@' does not provide handler implementation '%@'!", NSStringFromClass(delegate), handlerName] userInfo:@{
            @"delegate": NSStringFromClass(delegate),
            @"handlerSelector": NSStringFromSelector([self handlerNameToSelector:handlerName]),
        }];
    if(invalidationHandlerName && ![delegate respondsToSelector:[self handlerNameToSelector:invalidationHandlerName]])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:[NSString stringWithFormat:@"Class '%@' does not provide invalidation implementation '%@'!", NSStringFromClass(delegate), invalidationHandlerName] userInfo:@{
            @"delegate": NSStringFromClass(delegate),
            @"handlerSelector": NSStringFromSelector([self handlerNameToSelector:handlerName]),
            @"invalidationSelector": NSStringFromSelector([self handlerNameToSelector:invalidationHandlerName]),
        }];
    _internalData = [[NSMutableDictionary alloc] init];
    _invalidated = NO;
    [_internalData addEntriesFromDictionary:@{
        @"version": @(HANDLER_VERSION),
        @"delegate": NSStringFromClass(delegate),
        @"handlerName": handlerName,
    }];
    if(invalidationHandlerName)
        _internalData[@"invalidationName"] = invalidationHandlerName;
    [self bindArguments:args];
    return self;
}

-(void) bindArguments:(NSDictionary* _Nullable) args
{
    [self checkInvalidation];
    _internalData[@"boundArguments"] = [self sanitizeArguments:args];
}

-(void) callWithArguments:(NSDictionary* _Nullable) args
{
    [self checkInvalidation];
    if(_internalData[@"delegate"] && _internalData[@"handlerName"])
    {
        args = [self sanitizeArguments:args];
        id delegate = NSClassFromString(_internalData[@"delegate"]);
        SEL sel = [self handlerNameToSelector:_internalData[@"handlerName"]];
        if(![delegate respondsToSelector:sel])
            @throw [NSException exceptionWithName:@"RuntimeException" reason:[NSString stringWithFormat:@"Class '%@' does not provide handler implementation '%@'!", _internalData[@"delegate"], _internalData[@"handlerName"]] userInfo:@{
                @"delegate": _internalData[@"delegate"],
                @"handlerSelector": NSStringFromSelector(sel),
            }];
        DDLogVerbose(@"Calling handler %@...", self);
        NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[delegate methodSignatureForSelector:sel]];
        [inv setTarget:delegate];
        [inv setSelector:sel];
        //arguments 0 and 1 are self and _cmd respectively, automatically set by NSInvocation
        //default arguments of the caller
        [inv setArgument:(void* _Nonnull)&args atIndex:2];
        //bound arguments of the handler
        NSDictionary* boundArgs = _internalData[@"boundArguments"];
        [inv setArgument:(void* _Nonnull)&boundArgs atIndex:3];
        //now call it
        [inv invoke];
    }
}

-(void) invalidateWithArguments:(NSDictionary* _Nullable) args
{
    [self checkInvalidation];
    if(_internalData[@"delegate"] && _internalData[@"invalidationName"])
    {
        args = [self sanitizeArguments:args];
        id delegate = NSClassFromString(_internalData[@"delegate"]);
        SEL sel = [self handlerNameToSelector:_internalData[@"invalidationName"]];
        if(![delegate respondsToSelector:sel])
            @throw [NSException exceptionWithName:@"RuntimeException" reason:[NSString stringWithFormat:@"Class '%@' does not provide invalidation implementation '%@'!", _internalData[@"delegate"], _internalData[@"invalidationName"]] userInfo:@{
                @"delegate": _internalData[@"delegate"],
                @"handlerSelector": NSStringFromSelector([self handlerNameToSelector:_internalData[@"handlerName"]]),
                @"invalidationSelector": NSStringFromSelector(sel),
            }];
        DDLogVerbose(@"Calling invalidation %@...", self);
        NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[delegate methodSignatureForSelector:sel]];
        [inv setTarget:delegate];
        [inv setSelector:sel];
        //arguments 0 and 1 are self and _cmd respectively, automatically set by NSInvocation
        //default arguments of the caller
        [inv setArgument:(void* _Nonnull)&args atIndex:2];
        //bound arguments of the handler
        NSDictionary* boundArgs = _internalData[@"boundArguments"];
        [inv setArgument:(void* _Nonnull)&boundArgs atIndex:3];
        //now call it
        [inv invoke];
    }
    _invalidated = YES;
}

-(NSString*) id
{
    if(!_internalData[@"delegate"] || !_internalData[@"handlerName"])
        return @"{emptyHandler}";
    NSString* extras = @"";
    if(_internalData[@"invalidationName"])
        extras = [NSString stringWithFormat:@"<%@>", _internalData[@"invalidationName"]];
    return [NSString stringWithFormat:@"%@|%@%@", _internalData[@"delegate"], _internalData[@"handlerName"], extras];
}

-(NSString*) description
{
    NSString* extras = @"";
    if(_internalData[@"invalidationName"])
        extras = [NSString stringWithFormat:@"<%@>", _internalData[@"invalidationName"]];
    return [NSString stringWithFormat:@"{%@, %@%@}", _internalData[@"delegate"], _internalData[@"handlerName"], extras];
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:_internalData forKey:@"internalData"];
    [coder encodeBool:_invalidated forKey:@"invalidated"];
}

-(instancetype) initWithCoder:(NSCoder*) coder
{
    self = [super init];
    _internalData = [coder decodeObjectForKey:@"internalData"];
    _invalidated = [coder decodeBoolForKey:@"invalidated"];
    return self;
}

-(id) copyWithZone:(NSZone*) zone
{
    MLHandler* copy = [[[self class] alloc] init];
    copy->_internalData = [[NSMutableDictionary alloc] initWithDictionary:_internalData copyItems:YES];
    copy->_invalidated = _invalidated;
    return copy;
}

-(NSMutableDictionary*) sanitizeArguments:(NSDictionary* _Nullable) args
{
    NSMutableDictionary* retval = [[NSMutableDictionary alloc] init];
    if(args)
        for(NSString* key in args)
            if(args[key] != [NSNull null])
                retval[key] = args[key];
    return retval;
}

-(void) checkInvalidation
{
    if(_invalidated)
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Tried to call or bind vars to already invalidated handler!" userInfo:@{
            @"handler": _internalData,
        }];
}

-(SEL) handlerNameToSelector:(NSString*) handlerName
{
    return NSSelectorFromString([NSString stringWithFormat:@"MLHandler_%@_withArguments:andBoundArguments:", handlerName]);
}

@end
