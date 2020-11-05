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

-(instancetype) initWithDelegate:(id) delegate andMethod:(SEL) method
{
    self = [self init];
    return [self INTERNALinitWithDelegate:delegate method:method invalidationMethod:nil andBoundArguments:nil];
}

-(instancetype) initWithDelegate:(id) delegate method:(SEL) method andBoundArguments:(NSDictionary*) args
{
    self = [self init];
    return [self INTERNALinitWithDelegate:delegate method:method invalidationMethod:nil andBoundArguments:args];
}

-(instancetype) initWithDelegate:(id) delegate method:(SEL) method invalidationMethod:(SEL) invalidationMethod
{
    self = [self init];
    return [self INTERNALinitWithDelegate:delegate method:method invalidationMethod:invalidationMethod andBoundArguments:nil];
}

-(instancetype) initWithDelegate:(id) delegate method:(SEL) method invalidationMethod:(SEL) invalidationMethod andBoundArguments:(NSDictionary*) args
{
    self = [self init];
    return [self INTERNALinitWithDelegate:delegate method:method invalidationMethod:invalidationMethod andBoundArguments:args];
}

-(instancetype) INTERNALinitWithDelegate:(id) delegate method:(SEL) method invalidationMethod:(SEL _Nullable) invalidationMethod andBoundArguments:(NSDictionary* _Nullable) args
{
    if(![delegate respondsToSelector:method])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:[NSString stringWithFormat:@"Class '%@' does not provide handler implementation '%@'!", NSStringFromClass(delegate), [self selectorToHandlerName:method]] userInfo:@{
            @"delegate": NSStringFromClass(delegate),
            @"method": NSStringFromSelector(method),
        }];
    if(invalidationMethod && ![delegate respondsToSelector:invalidationMethod])
        @throw [NSException exceptionWithName:@"RuntimeException" reason:[NSString stringWithFormat:@"Class '%@' does not provide invalidation implementation '%@'!", NSStringFromClass(delegate), [self selectorToHandlerName:method]] userInfo:@{
            @"delegate": NSStringFromClass(delegate),
            @"method": NSStringFromSelector(method),
        }];
    _internalData = [[NSMutableDictionary alloc] init];
    _invalidated = NO;
    [_internalData addEntriesFromDictionary:@{
        @"delegate": NSStringFromClass(delegate),
        @"method": NSStringFromSelector(method),
    }];
    if(invalidationMethod)
        _internalData[@"invalidationMethod"] = NSStringFromSelector(invalidationMethod);
    [self bindArguments:args];
    return self;
}

-(void) bindArguments:(NSDictionary* _Nullable) args
{
    [self checkInvalidation];
    _internalData[@"boundArguments"] = [self sanitizeArguments:args];
}

-(void) call
{
    [self callWithArguments:nil];
}

-(void) callWithArguments:(NSDictionary* _Nullable) args
{
    [self checkInvalidation];
    if(_internalData[@"delegate"] && _internalData[@"method"])
    {
        args = [self sanitizeArguments:args];
        id cls = NSClassFromString(_internalData[@"delegate"]);
        SEL sel = NSSelectorFromString(_internalData[@"method"]);
        DDLogVerbose(@"Calling handler %@...", self);
        NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[cls methodSignatureForSelector:sel]];
        [inv setTarget:cls];
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

-(void) invalidate
{
    [self invalidateWithArguments:nil];
}

-(void) invalidateWithArguments:(NSDictionary* _Nullable) args
{
    [self checkInvalidation];
    if(_internalData[@"delegate"] && _internalData[@"invalidationMethod"])
    {
        args = [self sanitizeArguments:args];
        id cls = NSClassFromString(_internalData[@"delegate"]);
        SEL sel = NSSelectorFromString(_internalData[@"invalidationMethod"]);
        DDLogVerbose(@"Calling invalidation %@...", self);
        NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[cls methodSignatureForSelector:sel]];
        [inv setTarget:cls];
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
    if(!_internalData[@"delegate"] || !_internalData[@"method"])
        return @"{emptyHandler}";
    NSString* extras = @"";
    if(_internalData[@"invalidationMethod"])
        extras = [NSString stringWithFormat:@"<%@>", _internalData[@"invalidationMethod"]];
    return [NSString stringWithFormat:@"%@|%@%@", _internalData[@"delegate"], _internalData[@"method"], extras];
}

-(NSString*) description
{
    NSString* extras = @"";
    if(_internalData[@"invalidationMethod"])
        extras = [NSString stringWithFormat:@"<%@>", [self selectorStringToHandlerName:_internalData[@"invalidationMethod"]]];
    return [NSString stringWithFormat:@"{%@, %@%@}", _internalData[@"delegate"], [self selectorStringToHandlerName:_internalData[@"method"]], extras];
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

-(NSString*) selectorToHandlerName:(SEL) selector
{
    return [self selectorStringToHandlerName:NSStringFromSelector(selector)];
}

-(NSString*) selectorStringToHandlerName:(NSString*) methodName
{
    return [methodName substringWithRange:NSMakeRange(0, methodName.length - @"WithArguments:andBoundArguments:".length)];
}

@end
