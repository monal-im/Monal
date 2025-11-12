//
//  MLHandler.h
//  monalxmpp
//
//  Created by Thilo Molitor on 29.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

/**************************** <USAGE> ****************************

Complete usage with exhaustive explanations and examples
can be found over here:
https://github.com/monal-im/Monal/wiki/Handler-Framework

**************************** </USAGE> ****************************/

#include "metamacros.h"

//we need this in here, even if MLConstants.h was not included
#ifndef STRIP_PARENTHESES
    //see https://stackoverflow.com/a/62984543/3528174
    #define STRIP_PARENTHESES(X) __ESC(__ISH X)
    #define __ISH(...) __ISH __VA_ARGS__
    #define __ESC(...) __ESC_(__VA_ARGS__)
    #define __ESC_(...) __VAN ## __VA_ARGS__
    #define __VAN__ISH
#endif

//create handler object or bind vars to existing handler
#define $newHandler(delegate, name, ...)                                    _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wundeclared-selector\"") [[MLHandler alloc] initWithDelegate:[delegate class] handlerName:@#name andBoundArguments:@{ __VA_ARGS__ }] _Pragma("clang diagnostic pop")
#define $newHandlerWithInvalidation(delegate, name, invalidation, ...)      _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wundeclared-selector\"") [[MLHandler alloc] initWithDelegate:[delegate class] handlerName:@#name invalidationHandlerName:@#invalidation andBoundArguments:@{ __VA_ARGS__ }] _Pragma("clang diagnostic pop")
#define $bindArgs(handler, ...)                                             [handler bindArguments:@{ __VA_ARGS__ }]
#define $ID(name, ...)                                                      metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : nilWrapper(name) )( _packID(name, __VA_ARGS__) )
#define $HANDLER(name, ...)                                                 metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : nilWrapper(name) )( _packID(name, __VA_ARGS__) )
#define $PROMISE(name, ...)                                                 metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : nilWrapper(name) )( _packID(name, __VA_ARGS__) )
#define $BOOL(name, ...)                                                    metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithBool: name ] )( _packBOOL(name, __VA_ARGS__) )
#define $INT(name, ...)                                                     metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithInt: name ] )( _packINT(name, __VA_ARGS__) )
#define $DOUBLE(name, ...)                                                  metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithDouble: name ] )( _packDOUBLE(name, __VA_ARGS__) )
#define $INTEGER(name, ...)                                                 metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithInteger: name ] )( _packINTEGER(name, __VA_ARGS__) )
#define $UINTEGER(name, ...)                                                metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithUnsignedInteger: name ] )( _packUINTEGER(name, __VA_ARGS__) )

//declare handler, the order of provided arguments does not matter because we use named arguments
#define $$class_handler(name, ...)                                          +(void) MLHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) );
#define $$instance_handler(name, instance, ...)                             +(void) MLHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) ); [instance MLInstanceHandler_##name##_withArguments:_callerArgs andBoundArguments:_boundArgs]; } -(void) MLInstanceHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) );
#define $$returning_class_handler(name, ...)                                +(id) MLHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) );
#define $$returning_instance_handler(name, instance, ...)                   +(id) MLHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) ); return [instance MLInstanceHandler_##name##_withArguments:_callerArgs andBoundArguments:_boundArgs]; } -(id) MLInstanceHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) );
#define $_ID(type, var)                                                     (STRIP_PARENTHESES(type) var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]; if(var != nil && NSClassFromString(type_to_classname(@metamacro_foreach(_foreach_stringify, ",", STRIP_PARENTHESES(type)))) != nil && ![var isKindOfClass:NSClassFromString(type_to_classname(@metamacro_foreach(_foreach_stringify, ",", STRIP_PARENTHESES(type))))]) [MLHandler throwDynamicUnpackingExceptionForType:@"!"#type andVar:@#var andUserData:(@{@"actualType": NSStringFromClass([var class]), @"expectedType": @#type, @"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__];)
#define $$ID(type, var)                                                     (STRIP_PARENTHESES(type) var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]; if(var == nil) [MLHandler throwDynamicUnpackingExceptionForType:@"$$"#type andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; else if(NSClassFromString(type_to_classname(@metamacro_foreach(_foreach_stringify, ",", STRIP_PARENTHESES(type)))) != nil && ![var isKindOfClass:NSClassFromString(type_to_classname(@metamacro_foreach(_foreach_stringify, ",", STRIP_PARENTHESES(type))))]) [MLHandler throwDynamicUnpackingExceptionForType:@"!"#type andVar:@#var andUserData:(@{@"actualType": NSStringFromClass([var class]), @"expectedType": @#type, @"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__];)
#define $_HANDLER(var)                                                      (MLHandler* var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]; if(var != nil &&![var isKindOfClass:[MLHandler class]]) [MLHandler throwDynamicUnpackingExceptionForType:@"!Handler(MLHandler)" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__])
#define $$HANDLER(var)                                                      (MLHandler* var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]; if(var == nil) [MLHandler throwDynamicUnpackingExceptionForType:@"$$Handler" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; if(![var isKindOfClass:[MLHandler class]]) [MLHandler throwDynamicUnpackingExceptionForType:@"!Handler(MLHandler)" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__])
#define $_PROMISE(var)                                                      (MLPromise* var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]; if(var != nil &&![var isKindOfClass:[MLPromise class]]) [MLHandler throwDynamicUnpackingExceptionForType:@"!Promise(MLPromise)" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__])
#define $$PROMISE(var)                                                      (MLPromise* var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]; if(var == nil) [MLHandler throwDynamicUnpackingExceptionForType:@"$$Promise" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; if(![var isKindOfClass:[MLPromise class]]) [MLHandler throwDynamicUnpackingExceptionForType:@"!Promise(MLPromise)" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__])
#define $$BOOL(var)                                                         (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicUnpackingExceptionForType:@"$$BOOL" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; if(![(_callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]) isKindOfClass:[NSNumber class]]) [MLHandler throwDynamicUnpackingExceptionForType:@"!NSNumber(BOOL)" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; BOOL var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] boolValue] : [_boundArgs[@#var] boolValue])
#define $$INT(var)                                                          (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicUnpackingExceptionForType:@"$$int" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; if(![(_callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]) isKindOfClass:[NSNumber class]]) [MLHandler throwDynamicUnpackingExceptionForType:@"!NSNumber(int)" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; int var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] intValue] : [_boundArgs[@#var] intValue])
#define $$DOUBLE(var)                                                       (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicUnpackingExceptionForType:@"$$double" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; if(![(_callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]) isKindOfClass:[NSNumber class]]) [MLHandler throwDynamicUnpackingExceptionForType:@"!NSNumber(double)" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; double var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] doubleValue] : [_boundArgs[@#var] doubleValue])
#define $$INTEGER(var)                                                      (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicUnpackingExceptionForType:@"$$NSInteger" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; if(![(_callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]) isKindOfClass:[NSNumber class]]) [MLHandler throwDynamicUnpackingExceptionForType:@"!NSNumber(NSInteger)" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; NSInteger var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] integerValue] : [_boundArgs[@#var] integerValue])
#define $$UINTEGER(var)                                                     (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicUnpackingExceptionForType:@"$$NSUInteger" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; if(![(_callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]) isKindOfClass:[NSNumber class]]) [MLHandler throwDynamicUnpackingExceptionForType:@"!NSNumber(NSUInteger)" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; NSUInteger var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] unsignedIntegerValue] : [_boundArgs[@#var] unsignedIntegerValue])
#define $$                                                                  }

//call handler/invalidation
#define $call(handler, ...)                                                 [handler callWithArguments:@{ __VA_ARGS__ }]
#define $invalidate(handler, ...)                                           [handler invalidateWithArguments:@{ __VA_ARGS__ }]

//internal stuff
//$_*() and $$*() will add parentheses around its result to make sure all inner commas like those probably exposed by an inner STRIP_PARENTHESES() call get not
//interpreted as multiple arguments by metamacro_foreach()
//These additional parentheses around the result have to be stripped again by this call to STRIP_PARENTHESES() here
#define _expand_import(num, param)                                          STRIP_PARENTHESES(param)
#define _packID(name, value, ...)                                           @#name : nilWrapper(value)
#define _packHANDLER(name, value, ...)                                      @#name : (value != nil && ![value isKindOfClass:[MLHandler class]] ? [MLHandler throwDynamicPackingExceptionForType:@"!Handler(MLHandler)" andVar:@#name andUserData:(@{@"name": @#name, @"value": value}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__] : nilWrapper(value))
#define _packPROMISE(name, value, ...)                                      @#name : (value != nil && ![value isKindOfClass:[MLHandler class]] ? [MLHandler throwDynamicPackingExceptionForType:@"!Handler(MLHandler)" andVar:@#name andUserData:(@{@"name": @#name, @"value": value}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__] : nilWrapper(value))
#define _packBOOL(name, value, ...)                                         @#name : [NSNumber numberWithBool: value ]
#define _packINT(name, value, ...)                                          @#name : [NSNumber numberWithInt: value ]
#define _packDOUBLE(name, value, ...)                                       @#name : [NSNumber numberWithDouble: value ]
#define _packINTEGER(name, value, ...)                                      @#name : [NSNumber numberWithInteger: value ]
#define _packUINTEGER(name, value, ...)                                     @#name : [NSNumber numberWithUnsignedInteger: value ]
#define _foreach_stringify(_, var)                                          metamacro_stringify(var)


NS_ASSUME_NONNULL_BEGIN

NSString* type_to_classname(NSString* type);

@interface MLHandler : NSObject <NSSecureCoding>

+(BOOL) supportsSecureCoding;
+(void) throwDynamicUnpackingExceptionForType:(NSString*) type andVar:(NSString*) varName andUserData:(id) userInfo andFile:(char*) file andLine:(int) line andFunc:(char*) func;
+(NSString*) throwDynamicPackingExceptionForType:(NSString*) type andVar:(NSString*) varName andUserData:(id) userInfo andFile:(char*) file andLine:(int) line andFunc:(char*) func;

//id of this handler (consisting of class name, method name and invalidation method name)
@property (readonly, strong) NSString* id;

//init
-(instancetype) initWithDelegate:(id) delegate handlerName:(NSString*) handlerName andBoundArguments:(NSDictionary*) args;
-(instancetype) initWithDelegate:(id) delegate handlerName:(NSString*) handlerName invalidationHandlerName:(NSString*) invalidationHandlerName andBoundArguments:(NSDictionary*) args;

//bind new arguments dictionary
-(void) bindArguments:(NSDictionary* _Nullable) args;

//call and invalidate
-(id _Nullable) callWithArguments:(NSDictionary* _Nullable) defaultArgs;
-(id _Nullable) invalidateWithArguments:(NSDictionary* _Nullable) args;

@end

NS_ASSUME_NONNULL_END
