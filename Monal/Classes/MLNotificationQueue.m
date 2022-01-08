//
//  MLNotificationQueue.m
//  monalxmpp
//
//  Created by Thilo Molitor on 03.04.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

#import "MLNotificationQueue.h"

@interface MLNotificationQueue()
{
    NSString* _queueName;
    NSMutableArray* _entries;
    id _lowerQueue;     //use id because this could be an MLNotificationQueue *or* [NSNotificationCenter defaultCenter]
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
    //this will deallocate our queue (flushing was already done before)
    queue = nil;
}

+(id) currentQueue
{
    NSMutableArray* stack = [self getThreadLocalNotificationQueueStack];
    if(![stack count])
        return [NSNotificationCenter defaultCenter];
    return [stack lastObject];
}

//this is compatible to [NSNotificationCenter defaultCenter]
-(void) postNotificationName:(NSNotificationName) notificationName object:(id _Nullable) notificationObject userInfo:(id _Nullable) notificationUserInfo
{
    DDLogDebug(@"Queueing notification: %@", notificationName);
    //create queue entry (handle nil arguments)
    NSMutableDictionary* entry = [[NSMutableDictionary alloc] init];
    entry[@"name"] = notificationName;
    if(notificationObject != nil)
        entry[@"obj"] = notificationObject;
    if(notificationUserInfo != nil)
        entry[@"userInfo"] = notificationUserInfo;
    
    //add entry to our queue
    @synchronized(_entries) {
        [_entries addObject:entry];
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

-(NSUInteger) flush
{
    DDLogDebug(@"Flushing queue '%@', current stack: %@", [self name], [[[[self class] getThreadLocalNotificationQueueStack] reverseObjectEnumerator] allObjects]);
    NSArray* toFlush;
    @synchronized(_entries) {
        toFlush = _entries;
        _entries = [[NSMutableArray alloc] init];
    }
    DDLogVerbose(@"Notifications in queue '%@': %@", [self name], toFlush);
    for(NSDictionary* entry in toFlush)
        [_lowerQueue postNotificationName:entry[@"name"] object:entry[@"obj"] userInfo:entry[@"userInfo"]];
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
        _entries = [[NSMutableArray alloc] init];
    }
    return retval;
}

-(NSString*) name
{
    return _queueName;
}

-(NSString*) description
{
    NSMutableArray* queuedNotificationNames = [[NSMutableArray alloc] init];
    @synchronized(_entries) {
        for(NSDictionary* entry in _entries)
            [queuedNotificationNames addObject:entry[@"name"]];
    }
    return [NSString stringWithFormat:@"%@: %@", self.name, queuedNotificationNames];
}

+(NSMutableArray*) getThreadLocalNotificationQueueStack
{
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    //init dictionaries if neccessary
    if(!threadData[@"_notificationQueueStack"])
        threadData[@"_notificationQueueStack"] = [[NSMutableArray alloc] init];
    return threadData[@"_notificationQueueStack"];
}

-(instancetype) initWithName:(NSString*) queueName
{
    self = [super init];
    _queueName = queueName;
    _entries = [[NSMutableArray alloc] init];
    _lowerQueue = [MLNotificationQueue currentQueue];
    return self;
}

-(void) dealloc
{
    //there should only be one thread calling dealloc ever (per objc runtime) --> no @synchronized needed
    if([_entries count])
        [self flush];
}

@end
