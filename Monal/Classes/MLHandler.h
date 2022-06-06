//
//  MLHandler.h
//  monalxmpp
//
//  Created by Thilo Molitor on 29.10.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

/**************************** <USAGE> ****************************

- Define handler method (this will be a static class method and doesn't
have to be declared in any interface to be usable). The argument number
or order does not matter, feel free to reorder or even remove arguments
you don't need. Arguments declared with $$-prefix are mandatory, arguments
with $_-prefix are optional.
Primitive datatypes like BOOL, int etc. can not be imported as optional.
Syntax:
```
$$class_handler(myHandlerName, $_ID(xmpp*, account), $$BOOL(success))
    // your code comes here
    // variables defined/imported: account (optional), success (mandatory)
$$
```

Instance handlers are instance methods instead of static methods.
You need to specify on which instance these handlers should operate.
The instance extraxtion statement (the second argument to $$instance_handler() can be everything that
returns an objc object. For example: "account.omemo" or "[account getInstanceToUse]" or just "account".
Synax:
```
$$instance_handler(myHandlerName, instanceToUse, $$ID(xmpp*, account), $$BOOL(success))
    // your code comes here
    // 'self' is now the instance of the class extracted by the instanceToUse statement.
    // instead of the class instance as it would be if $$class_handler() was used instead of $$instance_handler()
    // variables defined/imported: account, success (both mandatory)
$$
```

- Call defined handlers by:
```
MLHandler* h = $newHandler(ClassName, myHandlerName);
$call(h);
```

- You can bind variables to MLHandler objects when creating them and when
invoking them. Variables supplied on invocation overwrite variables
supplied when creating the handler if the names are equal.
Variables bound to the handler when creating it have to conform to the
NSCoding protocol to make the handler serializable.
Variable binding example:
```
NSString* var1 = @"value";
MLHandler* h = $newHandler(ClassName, myHandlerName,
        $ID(var1),
        $BOOL(success, YES)
}));
xmpp* account = nil;
$call(h, $ID(account), $ID(otherAccountVarWithSameValue, account))
```

- Usable shortcuts to create MLHandler objects:
  - $newHandler(ClassName, handlerName, boundArgs...)
  - $newHandlerWithInvalidation(ClassName, handlerName, invalidationHandlerName, boundArgs...)

- You can add an invalidation method to a handler when creating the
MLHandler object (after invalidating a handler you can not call or
invalidate it again!). Invalidation handlers can be instance handlers or static handlers,
just like with "normal" handlers:
```
// definition of normal handler method as instance_handler
$$instance_handler(myHandlerName, [account getInstanceToUse], $_ID(xmpp*, account), $$BOOL(success))
        // your code comes here
        // 'self' is now the instance of the class extracted by [account getInstanceToUse]
        // instead of the class instance as it would be if $$class_handler() was used instead of $$instance_handler()
$$

// definition of invalidation method
$$class_handler(myInvalidationHandlerName, $$BOOL(done), $_ID(NSString*, var1))
        // your code comes here
        // variables imported: var1, done
        // variables that could have been imported according to $newHandler and $call below: var1, success, done
$$

MLHandler* h = $newHandlerWithInvalidation(ClassName, myHandlerName, myInvalidationHandlerName,
        $ID(var1, @"value"),
        $BOOL(success, YES)
}));

// call invalidation method with "done" argument set to YES
$invalidate(h, $BOOL(done, YES))
```

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
#define $newHandler(delegate, name, ...)                                  _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wundeclared-selector\"") [[MLHandler alloc] initWithDelegate:[delegate class] handlerName:@#name andBoundArguments:@{ __VA_ARGS__ }] _Pragma("clang diagnostic pop")
#define $newHandlerWithInvalidation(delegate, name, invalidation, ...)    _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wundeclared-selector\"") [[MLHandler alloc] initWithDelegate:[delegate class] handlerName:@#name invalidationHandlerName:@#invalidation andBoundArguments:@{ __VA_ARGS__ }] _Pragma("clang diagnostic pop")
#define $bindArgs(handler, ...)                                           [handler bindArguments:@{ __VA_ARGS__ }]
#define $ID(name, ...)                                                    metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : nilWrapper(name) )( _packID(name, __VA_ARGS__) )
#define $HANDLER(name, ...)                                               metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : nilWrapper(name) )( _packID(name, __VA_ARGS__) )
#define $BOOL(name, ...)                                                  metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithBool: name ] )( _packBOOL(name, __VA_ARGS__) )
#define $INT(name, ...)                                                   metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithInt: name ] )( _packINT(name, __VA_ARGS__) )
#define $DOUBLE(name, ...)                                                metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithDouble: name ] )( _packDOUBLE(name, __VA_ARGS__) )
#define $INTEGER(name, ...)                                               metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithInteger: name ] )( _packINTEGER(name, __VA_ARGS__) )
#define $UINTEGER(name, ...)                                              metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithUnsignedInteger: name ] )( _packUINTEGER(name, __VA_ARGS__) )

//declare handler, the order of provided arguments does not matter because we use named arguments
#define $$class_handler(name, ...)                                        +(void) MLHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) );
#define $$instance_handler(name, instance, ...)                           +(void) MLHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) ); [instance MLInstanceHandler_##name##_withArguments:_callerArgs andBoundArguments:_boundArgs]; } -(void) MLInstanceHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) );
#define $_ID(type, var)                                                   (STRIP_PARENTHESES(type) var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var])
//#define $$ID(type, var)                                                   (STRIP_PARENTHESES(type) var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var])
#define $$ID(type, var)                                                   (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicExceptionForType:@#type andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; STRIP_PARENTHESES(type) var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var])
#define $_HANDLER(var)                                                    (MLHandler* var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var])
#define $$HANDLER(var)                                                    (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicExceptionForType:@"MLHandler" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; MLHandler* var __unused = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var])
#define $$BOOL(var)                                                       (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicExceptionForType:@"BOOL" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; BOOL var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] boolValue] : [_boundArgs[@#var] boolValue])
#define $$INT(var)                                                        (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicExceptionForType:@"int" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; int var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] intValue] : [_boundArgs[@#var] intValue])
#define $$DOUBLE(var)                                                     (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicExceptionForType:@"double" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; double var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] doubleValue] : [_boundArgs[@#var] doubleValue])
#define $$INTEGER(var)                                                    (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicExceptionForType:@"NSInteger" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; NSInteger var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] integerValue] : [_boundArgs[@#var] integerValue])
#define $$UINTEGER(var)                                                   (if(_callerArgs[@#var]==nil && _boundArgs[@#var]==nil) [MLHandler throwDynamicExceptionForType:@"NSUInteger" andVar:@#var andUserData:(@{@"_boundArgs": _boundArgs, @"_callerArgs": _callerArgs}) andFile:(char*)__FILE__ andLine:__LINE__ andFunc:(char*)__func__]; NSInteger var __unused = _callerArgs[@#var] ? [_callerArgs[@#var] integerValue] : [_boundArgs[@#var] unsignedIntegerValue])
#define $$                                                                }

//call handler/invalidation
#define $call(handler, ...)                                               [handler callWithArguments:@{ __VA_ARGS__ }]
#define $invalidate(handler, ...)                                         [handler invalidateWithArguments:@{ __VA_ARGS__ }]

//internal stuff
//$_*() and $$*() will add parentheses around its result to make sure all inner commas like those probably exposed by an inner STRIP_PARENTHESES() call get not
//interpreted as multiple arguments by metamacro_foreach()
//These additional parentheses around the result have to be stripped again by this call to STRIP_PARENTHESES() here
#define _expand_import(num, param)                                        STRIP_PARENTHESES(param)
#define _packID(name, value, ...)                                         @#name : nilWrapper(value)
#define _packHANDLER(name, value, ...)                                    @#name : nilWrapper(value)
#define _packBOOL(name, value, ...)                                       @#name : [NSNumber numberWithBool: value ]
#define _packINT(name, value, ...)                                        @#name : [NSNumber numberWithInt: value ]
#define _packDOUBLE(name, value, ...)                                     @#name : [NSNumber numberWithDouble: value ]
#define _packINTEGER(name, value, ...)                                    @#name : [NSNumber numberWithInteger: value ]
#define _packUINTEGER(name, value, ...)                                   @#name : [NSNumber numberWithUnsignedInteger: value ]

NS_ASSUME_NONNULL_BEGIN

@interface MLHandler : NSObject <NSSecureCoding>
{
}
+(BOOL) supportsSecureCoding;
+(void) throwDynamicExceptionForType:(NSString*) type andVar:(NSString*) var andUserData:(id) userInfo andFile:(char*) file andLine:(int) line andFunc:(char*) func;

//id of this handler (consisting of class name, method name and invalidation method name)
@property (readonly, strong) NSString* id;

//init
-(instancetype) initWithDelegate:(id) delegate handlerName:(NSString*) handlerName andBoundArguments:(NSDictionary*) args;
-(instancetype) initWithDelegate:(id) delegate handlerName:(NSString*) handlerName invalidationHandlerName:(NSString*) invalidationHandlerName andBoundArguments:(NSDictionary*) args;

//bind new arguments dictionary
-(void) bindArguments:(NSDictionary* _Nullable) args;

//call and invalidate
-(void) callWithArguments:(NSDictionary* _Nullable) defaultArgs;
-(void) invalidateWithArguments:(NSDictionary* _Nullable) args;

@end

NS_ASSUME_NONNULL_END
