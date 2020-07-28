//
//  MLProcessLock.m
//  monalxmpp
//
//  Created by Thilo Molitor on 26.07.20.
//  Loosely based on https://ddeville.me/2015/02/interprocess-communication-on-ios-with-berkeley-sockets/
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <sys/socket.h>
//#import <sys/sysctl.h>
#import <sys/un.h>
#import "MLProcessLock.h"
#import "MLConstants.h"

static NSString* getSocketPath(NSString* processName)
{
    /*
     * `sockaddr_un.sun_path` has a max length of 104 characters
     * However, the container URL for the application group identifier in the simulator is much longer than that
     * Since the simulator has looser sandbox restrictions we just use /tmp
     */
#if TARGET_IPHONE_SIMULATOR
    NSString* dir = @"/tmp/Monal";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
#else
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    NSString* dir = [containerUrl path];
#endif
    NSString* socketPath = [dir stringByAppendingPathComponent:[[NSString alloc] initWithFormat:@"%@.socket", processName]];
    DDLogVerbose(@"Returning socketPath: %@", socketPath);
    return socketPath;
}

static struct sockaddr_un getAddr(NSString* processName)
{
    NSString* socketPath = getSocketPath(processName);
    const char* cSocketPath = [socketPath UTF8String];
    
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    
    strncpy(addr.sun_path, cSocketPath, sizeof(addr.sun_path) - 1);
    
    return addr;
}

@interface MLProcessLock()

@end

@implementation MLProcessLock

+(BOOL) checkRemoteRunning:(NSString*) processName
{
    dispatch_fd_t fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if(fd < 0)
    {
        DDLogError(@"Error creating MLProcessLock client fd for remote '%@': %@", processName, [NSString stringWithUTF8String:strerror(errno)]);
        return YES;     //this is an error case --> assume the remote process is running
    }
    struct sockaddr_un addr = getAddr(processName);
    if(connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0)
    {
        DDLogInfo(@"Failed to connect MLProcessLock client fd, remote '%@' seems not to run, but trying again in 100ms to make sure: %@", processName, [NSString stringWithUTF8String:strerror(errno)]);
        usleep(100000);
        if(connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0)
        {
            DDLogInfo(@"Failed to connect MLProcessLock client fd the second time --> remote '%@' is NOT running: %@", processName, [NSString stringWithUTF8String:strerror(errno)]);
            close(fd);
            return NO;
        }
    }
    DDLogInfo(@"MLProcessLock remote '%@' IS running", processName);
    close(fd);
    return YES;
}

+(BOOL) waitForRemoteStartup:(NSString*) processName
{
    dispatch_fd_t fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if(fd < 0)
    {
        DDLogError(@"Error creating MLProcessLock client fd for remote '%@': %@", processName, [NSString stringWithUTF8String:strerror(errno)]);
        return YES;     //this is an error case, signal it
    }
    struct sockaddr_un addr = getAddr(processName);
    DDLogInfo(@"Waiting for MLProcessLock client fd to connect to remote '%@'...", processName);
    int connected;
    do
    {
        connected = connect(fd, (struct sockaddr*)&addr, sizeof(addr));
        if(connected < 0)
            usleep(100000);
    } while(connected < 0);
    DDLogInfo(@"MLProcessLock remote '%@' IS now running", processName);
    close(fd);
    return NO;      //this is no error, remote is really running
}

+(BOOL) waitForRemoteTermination:(NSString*) processName
{
    BOOL __block retval = NO;
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_fd_t fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if(fd < 0)
        {
            DDLogError(@"Error creating MLProcessLock client fd for remote '%@': %@", processName, [NSString stringWithUTF8String:strerror(errno)]);
            retval = YES;     //this is an error case, signal it
            return;
        }
        struct sockaddr_un addr = getAddr(processName);
        int connected;
        int try = 0;
        do
        {
            connected = connect(fd, (struct sockaddr*)&addr, sizeof(addr));
            if(connected < 0)
                usleep(100000);
        } while(connected < 0 && try++ < 20);
        if(connected < 0)
        {
            close(fd);
            DDLogInfo(@"Failed to connect MLProcessLock client fd while waiting for remote '%@' termination, remote has already been terminated: %@", processName, [NSString stringWithUTF8String:strerror(errno)]);
            return;
        }
        //connection successful --> wait for remote termination
        DDLogInfo(@"Waiting for MLProcessLock termination of remote '%@'", processName);
        int len;
        do
        {
            char buffer[4096];
            len = recv(fd, buffer, sizeof(buffer), 0);
        } while(len);
        DDLogInfo(@"MLProcessLock remote '%@' got terminated", processName);
    });
    return retval;
}

CFDataRef callback(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info)
{
    return NULL;
}

-(id) initWithProcessName:(NSString*) processName
{
    [self runServerFor:processName];
    return self;
}

-(void) deinit
{
    DDLogInfo(@"Deallocating MLProcessLock");
}

-(void) runServerFor:(NSString*) processName
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_fd_t fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if(fd<0)
        {
            DDLogError(@"Error creating MLProcessLock server fd: %@", [NSString stringWithUTF8String:strerror(errno)]);
            return;
        }
        
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        
        struct sockaddr_un addr = getAddr(processName);
        unlink([getSocketPath(processName) UTF8String]);
        if(bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0)
        {
            DDLogError(@"Error binding MLProcessLock server fd: %@", [NSString stringWithUTF8String:strerror(errno)]);
            return;
        }
        if(listen(fd, 8) < 0)
        {
            DDLogError(@"Error listening on MLProcessLock server fd: %@", [NSString stringWithUTF8String:strerror(errno)]);
            return;
        }
        
        DDLogInfo(@"MLProcessLock server started and waiting for client connections");
        while(YES)
        {
            struct sockaddr client_addr;
            socklen_t client_addrlen = sizeof(client_addr);
            dispatch_fd_t client_fd = accept(fd, &client_addr, &client_addrlen);
            if(client_fd < 0)
            {
                DDLogError(@"Error accepting MLProcessLock client connection: %@", [NSString stringWithUTF8String:strerror(errno)]);
                continue;
            }
            DDLogInfo(@"Accepted MLProcessLock client connection");
        }
    });
}

@end
