//
//  MLDelayedDealloc.m
//  monalxmpp
//
//  Created by Thilo Molitor on 04.03.26.
//  Copyright © 2026 Monal.im. All rights reserved.
//

//#define DEBUG_DEALLOC_DEBUGGING

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/MLDelayedDealloc.h>

static NSMutableArray* _deallocList;
static dispatch_source_t _timer;
static dispatch_queue_t _queue;

#ifdef DEBUG
static NSString* _oldDebugOutput = nil;
static NSArray* ContainerChildren(id obj);
static NSMutableSet* IvarChildren(id obj);
static NSString* NodeName(id obj);
static void DumpMemoryGraph(NSSet* objects);
#endif

@implementation MLDelayedDealloc

+(void) initialize
{
    _deallocList = [NSMutableArray new];
    
    //configure timer
    _queue = dispatch_queue_create("im.monal.dealloc.timer", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0));
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer,
                              dispatch_time(DISPATCH_TIME_NOW, 0),
                              500 * NSEC_PER_MSEC,   //500ms period
                              100 * NSEC_PER_MSEC);  //100ms leeway
    
    //periodically dealloc objects
    dispatch_source_set_event_handler(_timer, ^{
        NSMutableArray* deallocCopy = nil;
        //cleanup _deallocList, make this section short to not block other threads
        @synchronized(_deallocList) {
            deallocCopy = [_deallocList mutableCopy];
            [_deallocList removeAllObjects];            //this won't deallocate anything, because we still reference everything in deallocCopy
        }
        
        NSUInteger count = [deallocCopy count];
        if(count > 0)
        {
            //requeue all entries that are still used by somebody else (retainCount == 1 being only us holding the object in deallocCopy)
            NSUInteger requeuedCount = 0;
            @autoreleasepool {
                NSMutableSet* retainedSet = [NSMutableSet new];
                for(id entry in deallocCopy)
                {
                    NSUInteger retainCount = CFGetRetainCount((__bridge CFTypeRef)entry);
                    if(retainCount > 1 && retainCount < 65536)      //only requeue if still used but not due to some tagged pointer foo etc.
                    {
                        [self delayFor:entry];
                        count--;
                        requeuedCount++;
#ifdef DEBUG
                        [retainedSet addObject:entry];
                        //DDLogDebug(@"Requeued deallocation with retain count %lu (%lu) of: %p %@", retainCount, CFGetRetainCount((__bridge CFTypeRef)entry), entry, entry);
#endif
                    }
                }
#ifdef DEBUG
                DumpMemoryGraph(retainedSet);
#endif
                retainedSet = nil;
            }
            
            //check if, after removing still retained entries, count is still > 0 and start deallocation, if so
            if(count > 0)
            {
                //for(id entry in deallocCopy)
                //    DDLogVerbose(@"Deallocating: %@", NodeName(entry));
                DDLogVerbose(@"Deallocating %lu objects, %lu still used objects requeued for later deallocation...", count, requeuedCount);
                NSDate* start = [NSDate date];
                deallocCopy = nil;
                NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
                if(elapsed > 1.0)
                    DDLogWarn(@"Done deallocating %lu objects in %.3fs (%lu still used objects requeued for later deallocation)...", count, elapsed, requeuedCount);
                else
                    DDLogVerbose(@"Done deallocating %lu objects in %.3fs (%lu still used objects requeued for later deallocation)...", count, elapsed, requeuedCount);
            }
        }
    });
    dispatch_resume(_timer);
}

+(void) delayFor:(id) obj
{
    if(obj == nil)
        return;
    @synchronized(_deallocList) {
        [_deallocList addObject:obj];
    }
}

@end

//****************************** FOR DEBUGGING ******************************
#ifdef DEBUG
static inline __attribute__((always_inline)) NSArray* ContainerChildren(id obj)
{
    if([obj isKindOfClass:[NSArray class]])
        return obj;
    if([obj isKindOfClass:[NSSet class]])
        return [obj allObjects];
    if([obj isKindOfClass:[NSDictionary class]])
        return [[(NSDictionary*)obj allKeys] arrayByAddingObjectsFromArray:[(NSDictionary*)obj allValues]];
    return @[];
}

static inline __attribute__((always_inline)) BOOL slotMatchesLayout(const uint8_t* layout, size_t slotIndex)
{
    if(!layout)
        return NO;
    size_t cursor = 0;
    while(*layout)
    {
        uint8_t skip = *layout++;
        uint8_t count = *layout++;
// #ifdef DEBUG_DEALLOC_DEBUGGING
//         DDLogVerbose(@"slotIndex=%d, skip=%d, count=%d", (int)slotIndex, (int)skip, (int)count);
// #endif
        cursor += skip;
        if(slotIndex >= cursor && slotIndex < cursor + count)
            return YES;
        cursor += count;
    }
    return NO;
}

static inline __attribute__((always_inline)) BOOL propertyIsWeak(objc_property_t prop)
{
    if(!prop)
        return NO;
    const char* attrs = property_getAttributes(prop);
    if(!attrs)
        return NO;
// #ifdef DEBUG_DEALLOC_DEBUGGING
//     DDLogVerbose(@"Property attributes: %s", attrs);
// #endif
    BOOL retval = strstr(attrs, ",W") != NULL;
    return retval;
}

static inline __attribute__((always_inline)) NSMutableSet* IvarChildren(id obj)
{
    NSMutableSet* children = [NSMutableSet new];
    [children addObjectsFromArray:ContainerChildren(obj)];      //if we are a container
    if([children count] == 0)                                   //if we aren't a container
    {
        Class cls = object_getClass(obj);
        while(cls)
        {
            unsigned int count = 0;
            Ivar* ivars = class_copyIvarList(cls, &count);
            //const uint8_t* strongLayout = class_getIvarLayout(cls);
            const uint8_t* weakLayout = class_getWeakIvarLayout(cls);
            for(unsigned int i = 0; i < count; i++)
            {
                const char* ivarName = ivar_getName(ivars[i]);
                const char* ivarType = ivar_getTypeEncoding(ivars[i]);
                if(ivarType[0] == '@')
                {
                    //check ivar slot for weakness
                    ptrdiff_t offset = ivar_getOffset(ivars[i]);
                    size_t slotIndex = offset / sizeof(void*);
                    //DDLogVerbose(@"Checking strong for %d: %s", (int)slotIndex, ivarName);
                    //BOOL isStrong = slotMatchesLayout(strongLayout, slotIndex);
                    BOOL isWeak = slotMatchesLayout(weakLayout, slotIndex);
                    
                    //check property wrapping this ivar for weakness
                    objc_property_t prop = class_getProperty(cls, ivarName);
                    if(!prop)
                        if(ivarName[0] == '_')      //ivars usually start with '_' while properties don't
                            prop = class_getProperty(cls, ivarName + 1);
                    if(propertyIsWeak(prop))
                        isWeak = YES;
                    
                    id ivarValue = object_getIvar(obj, ivars[i]);
#ifdef DEBUG_DEALLOC_DEBUGGING
                    if(ivarValue && isWeak)
                        DDLogError(@"WEAK IVAR[%u](%s::%s): %@", i, ivarType, ivarName, ivarValue);
#endif
                    if(ivarValue && !isWeak)
                    {
#ifdef DEBUG_DEALLOC_DEBUGGING
                        DDLogError(@"STRONG IVAR[%u](%s::%s): %@", i, ivarType, ivarName, ivarValue);
#endif
                        [children addObjectsFromArray:@[ivarValue]];
                        [children addObjectsFromArray:ContainerChildren(ivarValue)];
                    }
                }
            }
            free(ivars);
            cls = class_getSuperclass(cls);
        }
    }
    return children;
}

static inline NSString* NodeName(id obj)
{
    return [NSString stringWithFormat:@"%s_%p_%lu --> %@", class_getName(object_getClass(obj)), obj, CFGetRetainCount((__bridge CFTypeRef)obj), obj];
}

static inline __attribute__((always_inline)) __unused void DumpMemoryGraph(NSMutableSet* objects)
{
    @autoreleasepool {
        NSDate* start = [NSDate date];
        NSMutableSet* referenced = [NSMutableSet set];
        for(id obj in objects)
        {
            NSMutableSet* targets = [NSMutableSet set];
            NSMutableSet* printableTargets = [NSMutableSet set];
            for(id child in IvarChildren(obj))
                if(child != obj && [objects containsObject:child])
                {
                    [targets addObject:child];
                    [printableTargets addObject:NodeName(child)];
                }
#ifdef DEBUG_DEALLOC_DEBUGGING
            DDLogDebug(@"TARGETS OF %@: %@", NodeName(obj), printableTargets);
#endif
            [referenced unionSet:targets];
        }
        [objects minusSet:referenced];

        NSMutableString* output = [NSMutableString new];
        [output appendString:@"\n// Roots:\n"];
        for(id root in objects)
            [output appendFormat:@"// %@\n", NodeName(root)];
        
        if(![output isEqualToString:_oldDebugOutput])
            DDLogDebug(@"Still used root nodes (calculated in %.3fs): %@", [[NSDate date] timeIntervalSinceDate:start], output);
        _oldDebugOutput = output;
    }
}
#endif
