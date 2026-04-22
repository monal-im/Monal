//
//  MLNotificationQueue.m
//  monalxmpp
//
//  Created by Thilo Molitor on 03.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import <monalxmpp/MLNotificationQueue.h>
#import <monalxmpp/HelperTools.h>

@interface ObserverEntry : NSObject
@property (nonatomic, weak) id observer;
@property (nonatomic) SEL selector;
@property (nonatomic) NSMethodSignature* sig;
@property (nonatomic) IMP imp;
@property (nonatomic, weak) id object;
@end
@implementation ObserverEntry
-(NSString*) description
{
    return [NSString stringWithFormat:@"ObserverEntry: selector %s on %@", sel_getName(self.selector), self.observer];
}
@end

@interface MLNotificationQueue()
{
    NSString* _queueName;
    NSMutableArray* _entries;
    id _lowerQueue;     //use id because this could be an MLNotificationQueue *or* [NSNotificationCenter defaultCenter]
    //for direct delivery without queueing
    NSMutableDictionary<NSNotificationName, NSMutableArray<ObserverEntry*>*>* _directObservers;
}
+(NSMutableArray*) getThreadLocalNotificationQueueStack;
@end

@implementation MLNotificationQueue

//this is a contextmanager (like the ones found in python)
+(void) queueNotificationsInBlock:(monal_void_block_t) block onQueue:(NSString*) queueName
{
    NSMutableArray* stack = [self getThreadLocalNotificationQueueStack];
    for(MLNotificationQueue* queue in stack)
        if([queue.name isEqualToString:queueName])
            @throw [NSException exceptionWithName:@"NotificationQueueException" reason:[NSString stringWithFormat:@"Tried to instanciate queue twice: %@", queueName] userInfo:@{
                @"stack": stack,
                @"alreadyExistingQueue": queue,
            }];
    //create new notification queue and put it onto our stack of queues
    MLNotificationQueue* queue = [[self alloc] initWithName:queueName];
    [stack addObject:queue];
    //call the context our contextmanager manages (a monal_void_block_t block)
    block();
    //remove own queue from stack again
    [stack removeLastObject];
    //flush the queue to the next queue in our stack (or send them to the notification center if no queue is left on the stack)
    //don't use the flush deallocate because we want our flush to be "inline" thread-wise
    [queue flush];
    [queue bubbleUpDirectObservers];
    //this will deallocate our queue (flushing was already done before)
    queue = nil;
}

+(instancetype) currentQueue
{
    NSMutableArray* stack = [self getThreadLocalNotificationQueueStack];
    if(![stack count])
        return (MLNotificationQueue*) [NSNotificationCenter defaultCenter];
    return [stack lastObject];
}

//this is compatible to [NSNotificationCenter defaultCenter]
-(void) postNotificationName:(NSNotificationName) notificationName object:(id _Nullable) notificationObject userInfo:(id _Nullable) notificationUserInfo
{
    DDLogDebug(@"Queueing notification: %@, object = %@, userInfo = %@", notificationName, notificationObject, notificationUserInfo);
    NSNotification* notification = [NSNotification notificationWithName:notificationName object:notificationObject userInfo:notificationUserInfo];
    @synchronized(_entries) {
        [_entries addObject:notification];
    }
    
    //allow observers in the same notification queue to receive the notification immediately rather than on queue flush
    NSArray* observers = @[];
    @synchronized(_directObservers) {
        if(_directObservers[notificationName] != nil)
            observers = [_directObservers[notificationName] copy];
    }
    if(observers.count > 0)
    {
        MLNotificationQueue* currentQueue = [MLNotificationQueue currentQueue];
        DDLogDebug(@"Calling direct handlers for notification created in the same queue (%@): %@", currentQueue.name, notificationName);
        for(ObserverEntry* entry in observers)
        {
            if(entry.observer == nil)
                continue;
            if(entry.object != nil && entry.object != notificationObject)
                continue;
            if(![entry.observer respondsToSelector:entry.selector])
                continue;
            
            switch(entry.sig.numberOfArguments)
            {
                case 2:
                    //-(void) handler;
                    ((void (*)(id, SEL))entry.imp)(entry.observer, entry.selector);
                    break;
                case 3:
                    //-(void) handler:(NSNotification*);
                    ((void (*)(id, SEL, NSNotification*))entry.imp)(entry.observer, entry.selector, notification);
                    break;
                default:
                    unreachable(@"We should never reach this because of previous sanity checks!");
                    break;
            }
        }
    }
}

//this is compatible to [NSNotificationCenter defaultCenter]
-(void) postNotificationName:(NSNotificationName) notificationName object:(id _Nullable) notificationObject
{
    [self postNotificationName:notificationName object:notificationObject userInfo:nil];
}

//this is compatible to [NSNotificationCenter defaultCenter]
-(void) postNotification:(NSNotification*) notification
{
    [self postNotificationName:notification.name object:notification.object userInfo:notification.userInfo];
}

//this is compatible to [NSNotificationCenter defaultCenter]
-(void) addObserver:(id) observer selector:(SEL) aSelector name:(NSNotificationName) aName object:(id _Nullable) anObject
{
    if(!observer || !aSelector || !aName)
        return;
    
    ObserverEntry* entry = [ObserverEntry new];
    entry.observer = observer;
    entry.selector = aSelector;
    entry.object = anObject;
    entry.imp = [observer methodForSelector:aSelector];
    entry.sig = [observer methodSignatureForSelector:aSelector];
    
    //sanity checks (do them here to have higher performance when calling handlers later)
    if(strcmp(entry.sig.methodReturnType, "v")!=0)
        @throw [NSException exceptionWithName:@"NotificationQueueException" reason:@"Tried to use notification handler with non-void return value!" userInfo:@{
            @"sig": entry.sig,
            @"sig.methodReturnType": @(entry.sig.methodReturnType),
        }];
    if(entry.sig.numberOfArguments > 3 || entry.sig.numberOfArguments < 2)
        @throw [NSException exceptionWithName:@"NotificationQueueException" reason:@"Tried to use notification handler with unsupported argument count!" userInfo:@{
            @"sig": entry.sig,
            @"sig.numberOfArguments": @(entry.sig.numberOfArguments),
        }];
        
    @synchronized(_directObservers) {
        if(_directObservers[aName] == nil)
            _directObservers[aName] = [NSMutableArray new];
        [_directObservers[aName] addObject:entry];
    }
}

//this is compatible to [NSNotificationCenter defaultCenter]
-(void) removeObserver:(id) observer
{
    @synchronized(_directObservers) {
        for(NSNotificationName name in _directObservers)
        {
            for(ObserverEntry* entry in [_directObservers[name] copy])
                if(entry.observer == observer)
                {
                    DDLogDebug(@"Removing observer for notification %@: %@", name, entry);
                    [_directObservers[name] removeObject:entry];
                }
        }
    }
}

-(NSUInteger) flush
{
    DDLogDebug(@"Flushing queue '%@', current stack: %@", [self name], [[[[self class] getThreadLocalNotificationQueueStack] reverseObjectEnumerator] allObjects]);
    NSArray* toFlush;
    @synchronized(_entries) {
        toFlush = _entries;
        _entries = [NSMutableArray new];
    }
    DDLogVerbose(@"Notifications in queue '%@': %@", [self name], toFlush);
    for(NSNotification* entry in toFlush)
        [_lowerQueue postNotificationName:entry.name object:entry.object userInfo:entry.userInfo];
    @synchronized(_entries) {
        if([_entries count])
            @throw [NSException exceptionWithName:@"NotificationQueueException" reason:[NSString stringWithFormat:@"Tried to add more entries to queue while flushing: %@", _queueName] userInfo:nil];
    }
    DDLogVerbose(@"Done flushing %@ notifications in queue '%@'", @([toFlush count]), [self name]);
    return [toFlush count];
}

-(NSUInteger) clear
{
    DDLogDebug(@"Clearing queue '%@', current stack: %@", [self name], [[[[self class] getThreadLocalNotificationQueueStack] reverseObjectEnumerator] allObjects]);
    NSUInteger retval;
    @synchronized(_entries) {
        retval = [_entries count];
        _entries = [NSMutableArray new];
    }
    return retval;
}

-(NSString*) name
{
    return _queueName;
}

-(NSString*) description
{
    NSMutableArray* queuedNotificationNames = [NSMutableArray new];
    @synchronized(_entries) {
        for(NSNotification* entry in _entries)
            [queuedNotificationNames addObject:entry.name];
    }
    return [NSString stringWithFormat:@"%@: %@", self.name, queuedNotificationNames];
}

+(NSMutableArray*) getThreadLocalNotificationQueueStack
{
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    //init dictionaries if neccessary
    if(!threadData[@"_notificationQueueStack"])
        threadData[@"_notificationQueueStack"] = [NSMutableArray new];
    return threadData[@"_notificationQueueStack"];
}

-(instancetype) initWithName:(NSString*) queueName
{
    self = [super init];
    _queueName = queueName;
    _entries = [NSMutableArray new];
    _lowerQueue = [MLNotificationQueue currentQueue];
    _directObservers = [NSMutableDictionary new];
    return self;
}

-(void) bubbleUpDirectObservers
{
    NSDictionary* observers;
    @synchronized(_directObservers) {
        observers = [_directObservers copy];
        _directObservers = [NSMutableDictionary new];
    }
    if(observers.count > 0)
    {
        MLNotificationQueue* currentQueue = [MLNotificationQueue currentQueue];
        for(NSNotificationName name in observers)
        {
            DDLogDebug(@"Promoting all %lu direct handlers for '%@' to next queue: %@", (unsigned long)[observers[name] count], name, currentQueue);
            for(ObserverEntry* entry in observers[name])
                if(entry.observer != nil)
                    [currentQueue addObserver:entry.observer selector:entry.selector name:name object:entry.object];
        }
    }
}

-(void) dealloc
{
    //there should only be one thread calling dealloc ever (per objc runtime) --> no @synchronized needed
    if([_entries count])
        [self flush];
    
    //bubble up all observers still registered with us
    if([_directObservers count])
        [self bubbleUpDirectObservers];
}

@end
