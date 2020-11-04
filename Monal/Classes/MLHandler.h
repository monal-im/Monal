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
$$handler(myHandlerName, $ID(xmpp*, account), $BOOL(success))
        // your code comes here
        // variables defined/imported: account, success
        // variables that could be defined/imported: var1, success, account
$$
```

- Call defined handlers by:
```
MLHandler* h = makeHandler(ClassName, myHandlerName);
[h call];
```

- You can bind variables to MLHandler objects when creating them or when
invoking them. Variables supplied on invocation overwrite variables
supplied when creating the handler if the names are equal.
Variables bound to the handler when creating it have to conform to the
NSCoding protocol to make the handler serializable.
Variable binding example:
```
MLHandler* h = makeHandlerWithArgs(ClassName, myHandlerName, (@{
        @"var1": @"value",
        @"success": @YES
}));
[h callWithArguments:@{
        @"account": xmppAccount
}];
```

- Usable shortcuts to create MLHandler objects:
  - makeHandler(delegate, name)
  - makeHandlerWithArgs(delegate, name, args)
  - makeHandlerWithInvalidation(delegate, name, invalidation)
  - makeHandlerWithInvalidationAndArgs(delegate, name, invalidation, args)

- You can add an invalidation method to a handler when creating the
MLHandler object (after invalidating a handler you can not call or
invalidate it again!):
```
// definition of normal handler method
$$handler(myHandlerName, $ID(xmpp*, account), $BOOL(success))
        // your code comes here
$$

// definition of invalidation method
$$handler(myInvalidationName, $BOOL(done), $ID(NSString*, var1))
        // your code comes here
        // variables defined/imported: var1, done
        // variables that could be defined/imported: var1, success, done
$$

MLHandler* h = makeHandlerWithInvalidationAndArgs(ClassName, myHandlerName, myInvalidationName, (@{
        @"var1": @"value",
        @"success": @YES
}));

// call invalidation method with "done" argument
[h callInvalidationWithArguments:@{
        @"done": @YES
}]
```

**************************** </USAGE> ****************************/

#include "metamacros.h"

//create handler object
#define makeHandler(delegate, name)                                               [[MLHandler alloc] initWithDelegate:[delegate class] andMethod:@selector(name##WithArguments:andBoundArguments:)]
#define makeHandlerWithArgs(delegate, name, args)                                 [[MLHandler alloc] initWithDelegate:[delegate class] method:@selector(name##WithArguments:andBoundArguments:) andBoundArguments:args]
#define makeHandlerWithInvalidation(delegate, name, invalidation)                 [[MLHandler alloc] initWithDelegate:[delegate class] method:@selector(name##WithArguments:andBoundArguments:) invalidationMethod:@selector(invalidation##WithArguments:andBoundArguments:)]
#define makeHandlerWithInvalidationAndArgs(delegate, name, invalidation, args)    [[MLHandler alloc] initWithDelegate:[delegate class] method:@selector(name##WithArguments:andBoundArguments:) invalidationMethod:@selector(invalidation##WithArguments:andBoundArguments:) andBoundArguments:args]

//declare handler, the order of provided arguments does not matter because we use named arguments
#define $$handler(name, ...)                                                      +(void) name##WithArguments:(NSDictionary*) _callerArgs andBoundArguments:(NSDictionary*) _boundArgs { metamacro_if_eq(0, metamacro_argcount(__VA_ARGS__))( )( metamacro_foreach(_expand_import, ;, __VA_ARGS__) );
#define $$                                                                        }

//internal stuff
#define _expand_import(num, param)                                                param
#define $ID(type, var)                                                            type var = _callerArgs[@#var] ? _callerArgs[@#var] : _boundArgs[@#var]
#define $BOOL(var)                                                                BOOL var = _callerArgs[@#var] ? [_callerArgs[@#var] boolValue] : [_boundArgs[@#var] boolValue]
#define $INT(var)                                                                 int var = _callerArgs[@#var] ? [_callerArgs[@#var] intValue] : [_boundArgs[@#var] boolValue]
#define $DOUBLE(var)                                                              double var = _callerArgs[@#var] ? [_callerArgs[@#var] doubleValue] : [_boundArgs[@#var] boolValue]
#define $INTEGER(var)                                                             NSInteger var = _callerArgs[@#var] ? [_callerArgs[@#var] integerValue] : [_boundArgs[@#var] boolValue]

NS_ASSUME_NONNULL_BEGIN

@interface MLHandler : NSObject <NSSecureCoding>
{
}
+(BOOL) supportsSecureCoding;

//id of this handler (consisting of class name, method name and invalidation method name)
@property (readonly, strong) NSString* id;

//init
-(instancetype) initWithDelegate:(id) delegate andMethod:(SEL) method;
-(instancetype) initWithDelegate:(id) delegate method:(SEL) method andBoundArguments:(NSDictionary*) args;
-(instancetype) initWithDelegate:(id) delegate method:(SEL) method invalidationMethod:(SEL) invalidationMethod;
-(instancetype) initWithDelegate:(id) delegate method:(SEL) method invalidationMethod:(SEL) invalidationMethod andBoundArguments:(NSDictionary*) args;

//bind new arguments dictionary
-(void) bindArguments:(NSDictionary*) args;

//call and invalidate
-(void) call;
-(void) callWithArguments:(NSDictionary*) defaultArgs;
-(void) invalidate;
-(void) invalidateWithArguments:(NSDictionary*) args;

@end

NS_ASSUME_NONNULL_END
