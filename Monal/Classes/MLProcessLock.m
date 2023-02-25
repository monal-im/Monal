//
//  MLProcessLock.m
//  monalxmpp
//
//  Created by Thilo Molitor on 26.07.20.
//  Loosely based on https://ddeville.me/2015/02/interprocess-communication-on-ios-with-berkeley-sockets/
//  and https://ddeville.me/2015/02/interprocess-communication-on-ios-with-mach-messages/
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <sys/file.h>
#include <errno.h>

#import "MLProcessLock.h"
#import "MLConstants.h"
#import "HelperTools.h"


@interface MLProcessLock()

@end

static NSString* _locksDir;
static char* _ownLockPath;
static volatile int _ownLockFD;

@implementation MLProcessLock

+(void) initializeForProcess:(NSString*) processName
{
    NSError*  error;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* documentsDirectory = [[HelperTools getContainerURLForPathComponents:@[]] path];
    _locksDir = [documentsDirectory stringByAppendingPathComponent:@"locks"];
    [fileManager createDirectoryAtPath:_locksDir withIntermediateDirectories:YES attributes:nil error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    [HelperTools configureFileProtectionFor:_locksDir];
    
    const char* path = [[NSFileManager defaultManager] fileSystemRepresentationWithPath:[_locksDir stringByAppendingPathComponent:processName]];
    _ownLockPath = calloc(strlen(path)+1, sizeof(*_ownLockPath));
    strncpy(_ownLockPath, path, strlen(path));
    DDLogInfo(@"Set _ownLockPath to '%s'...", _ownLockPath);
}

+(void) lock
{
    int lock;
    DDLogVerbose(@"Locking process (_ownLockPath=%s)...", _ownLockPath);
    @synchronized(self) {
        if(_ownLockFD != 0)
        {
            lock = flock(_ownLockFD, LOCK_EX | LOCK_NB);
            if(lock == 0)
            {
                DDLogVerbose(@"Process still locked, doing nothing...");
                return;
            }
            @throw [NSException exceptionWithName:@"LockingError" reason:[NSString stringWithFormat:@"flock returned: %d (%d) on file: %s", lock, errno, _ownLockPath] userInfo:nil];
        }
        _ownLockFD = open(_ownLockPath, O_CREAT, S_IRWXU | S_IRWXG);
        if(_ownLockFD == 0)
            @throw [NSException exceptionWithName:@"LockingError" reason:[NSString stringWithFormat:@"failed to fopen file (%d): %s", errno, _ownLockPath] userInfo:nil];
        lock = flock(_ownLockFD, LOCK_EX | LOCK_NB);
        if(lock != 0)
            @throw [NSException exceptionWithName:@"LockingError" reason:[NSString stringWithFormat:@"flock returned: %d (%d) on file: %s", lock, errno, _ownLockPath] userInfo:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(unlock) name:kMonalIsFreezed object:nil];
    }
}

+(void) unlock
{
    DDLogVerbose(@"Unlocking process (_ownLockPath=%s)...", _ownLockPath);
    @synchronized(self) {
        if(_ownLockFD != 0)
        {
            close(_ownLockFD);
            _ownLockFD = 0;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

+(BOOL) checkRemoteRunning:(NSString*) processName
{
    char const* path = [[NSFileManager defaultManager] fileSystemRepresentationWithPath:[_locksDir stringByAppendingPathComponent:processName]];
    DDLogVerbose(@"Checking if remote %@ is running (path=%s)...", processName, path);
    int fd = open(path, O_CREAT, S_IRWXU | S_IRWXG);
    if(fd == 0)
        @throw [NSException exceptionWithName:@"LockingError" reason:[NSString stringWithFormat:@"failed to fopen file (%d): %s", errno, path] userInfo:@{@"processName": processName}];
    int lock = flock(fd, LOCK_EX | LOCK_NB);
    //try again if the file was not locked
    //this makes sure we don't run into race conditions after app freezes/unfreezes
    if(lock == 0)
    {
        flock(fd, LOCK_UN);
        [self sleep:0.050];
        lock = flock(fd, LOCK_EX | LOCK_NB);
    }
    close(fd);
    DDLogVerbose(@"Remote %@ running: %@", processName, bool2str(lock != 0));
    return lock != 0;
}

+(void) waitForRemoteStartup:(NSString*) processName
{
    [self waitForRemoteStartup:processName withLoopHandler:nil];
}

+(void) waitForRemoteStartup:(NSString*) processName withLoopHandler:(monal_void_block_t _Nullable) handler
{
    while(![[NSThread currentThread] isCancelled] && ![self checkRemoteRunning:processName])
    {
        if(handler)
            handler();
        [self sleep:1.0];
    }
}

+(void) waitForRemoteTermination:(NSString*) processName
{
    [self waitForRemoteTermination:processName withLoopHandler:nil];
}

+(void) waitForRemoteTermination:(NSString*) processName withLoopHandler:(monal_void_block_t _Nullable) handler
{
    //wait 250ms (in case this method will be used by the appex to wait for the mainapp in the future)
    //--> we want to make sure the mainapp *really* isn't running anymore while still not waiting too long
    //(this 250ms is a tradeoff, a longer timeout would be safer but could result in long mainapp startup delays or startup kills by iOS)
    //see the explanation of checkRemoteRunning: for further details
    while(![[NSThread currentThread] isCancelled] && [self checkRemoteRunning:processName])
    {
        if(handler)
            handler();
        [self sleep:0.250];
    }
}

+(void) sleep:(NSTimeInterval) time
{
    BOOL was_called_in_mainthread = [NSThread isMainThread];
    NSRunLoop* main_runloop = [NSRunLoop mainRunLoop];
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow:time];
    //we have to spin the runloop instead of simply sleeping to not get killed for unresponsiveness
    if(was_called_in_mainthread)
        while([timeout timeIntervalSinceNow] > 0)
            [main_runloop runMode:[main_runloop currentMode] beforeDate:timeout];
    else
        [NSThread sleepForTimeInterval:time];
}

@end
