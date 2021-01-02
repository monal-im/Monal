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
you don't need. Syntax:
```
$$handler(myHandlerName, $_ID(xmpp*, account), $_BOOL(success))
        // your code comes here
        // variables defined/imported: account, success
        // variables that could be defined/imported: var1, success, account
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
  - $newHandler(delegateClassName, handlerName, boundArgs...)
  - $newHandlerWithInvalidation(delegateClassName, handlerName, invalidationHandlerName, boundArgs...)

- You can add an invalidation method to a handler when creating the
MLHandler object (after invalidating a handler you can not call or
invalidate it again!):
```
// definition of normal handler method
$$handler(myHandlerName, $_ID(xmpp*, account), $_BOOL(success))
        // your code comes here
$$

// definition of invalidation method
$$handler(myInvalidationName, $_BOOL(done), $_ID(NSString*, var1))
        // your code comes here
        // variables imported: var1, done
        // variables that could have been imported: var1, success, done
$$

MLHandler* h = $newHandlerWithInvalidation(delegateClassName, myHandlerName, myInvalidationHandlerName,
        $ID(var1, @"value"),
        $BOOL(success, YES)
}));

// call invalidation method with "done" argument set to YES
$invalidate(h, $BOOL(done, YES))
```

**************************** </USAGE> ****************************/

#include "metamacros.h"

//create handler object or bind vars to existing handler
#define $newHandler(delegate, name, ...)                                  _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wundeclared-selector\"") [[MLHandler alloc] initWithDelegate:[delegate class] handlerName:@#name andBoundArguments:@{ __VA_ARGS__ }] _Pragma("clang diagnostic pop")
#define $newHandlerWithInvalidation(delegate, name, invalidation, ...)    _Pragma("clang diagnostic push") _Pragma("clang diagnostic ignored \"-Wundeclared-selector\"") [[MLHandler alloc] initWithDelegate:[delegate class] handlerName:@#name invalidationHandlerName:@#invalidation andBoundArguments:@{ __VA_ARGS__ }] _Pragma("clang diagnostic pop")
#define $bindArgs(handler, ...)                                           [handler bindArguments:@{ __VA_ARGS__ }]
#define $ID(name, ...)                                                    metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : nilWrapper(name) )( _packID(name, __VA_ARGS__) )
#define $BOOL(name, ...)                                                  metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithBool: name ] )( _packBOOL(name, __VA_ARGS__) )
#define $INT(name, ...)                                                   metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithInt: name ] )( _packINT(name, __VA_ARGS__) )
#define $DOUBLE(name, ...)                                                metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithDouble: name ] )( _packINT(name, __VA_ARGS__) )
#define $INTEGER(name, ...)                                               metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : [NSNumber numberWithInteger: name ] )( _packINT(name, __VA_ARGS__) )
#define $HANDLER(name, ...)                                               metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( @#name : nilWrapper(name) )( _packID(name, __VA_ARGS__) )

//declare handler, the order of provided arguments does not matter because we use named arguments
#define $$handler(name, ...)                                              +(void) MLHandler_##name##_withArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) );
#define $_ID(type, var)                                                   type var = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]
#define $_BOOL(var)                                                       BOOL var = _callerArgs[@#var] ? [_callerArgs[@#var] boolValue] : [_boundArgs[@#var] boolValue]
#define $_INT(var)                                                        int var = _callerArgs[@#var] ? [_callerArgs[@#var] intValue] : [_boundArgs[@#var] boolValue]
#define $_DOUBLE(var)                                                     double var = _callerArgs[@#var] ? [_callerArgs[@#var] doubleValue] : [_boundArgs[@#var] boolValue]
#define $_INTEGER(var)                                                    NSInteger var = _callerArgs[@#var] ? [_callerArgs[@#var] integerValue] : [_boundArgs[@#var] boolValue]
#define $_HANDLER(var)                                                    MLHandler* var = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]
#define $$                                                                }

//call handler/invalidation
#define $call(handler, ...)                                               [handler callWithArguments:@{ __VA_ARGS__ }]
#define $invalidate(handler, ...)                                         [handler invalidateWithArguments:@{ __VA_ARGS__ }]

//internal stuff
#define _expand_import(num, param)                                        param
#define _packID(name, value, ...)                                         @#name : nilWrapper(value)
#define _packBOOL(name, value, ...)                                       @#name : [NSNumber numberWithBool: value ]
#define _packINT(name, value, ...)                                        @#name : [NSNumber numberWithInt: value ]
#define _packDOUBLE(name, value, ...)                                     @#name : [NSNumber numberWithDouble: value ]
#define _packINTEGER(name, value, ...)                                    @#name : [NSNumber numberWithInteger: value ]
#define _packHANDLER(name, value, ...)                                    @#name : nilWrapper(value)

NS_ASSUME_NONNULL_BEGIN

@interface MLHandler : NSObject <NSSecureCoding>
{
}
+(BOOL) supportsSecureCoding;

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
