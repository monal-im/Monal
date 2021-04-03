//
//  IPC.m
//  Monal
//
//  Created by Thilo Molitor on 31.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <notify.h>
#import "IPC.h"
#import "MLSQLite.h"
#import "HelperTools.h"

#define MSG_TIMEOUT 2.0

@interface IPC()
{
    NSString* _processName;
    NSString* _dbFile;
    NSMutableDictionary* _ipcQueues;
    NSCondition* _serverThreadCondition;
}
@property (readonly, strong) MLSQLite* db;
@property (readonly, strong) NSThread* serverThread;

-(void) incomingDarwinNotification:(NSString*) name;
@end

static NSMutableDictionary* _responseHandlers;
static IPC* _sharedInstance;
static CFNotificationCenterRef _darwinNotificationCenterRef;

//forward notifications to the IPC instance that is waiting (the instance running the server thread)
void darwinNotificationCenterCallback(CFNotificationCenterRef center, void* observer, CFNotificationName name, const void* object, CFDictionaryRef userInfo)
{
    [(__bridge IPC*)observer incomingDarwinNotification:(__bridge NSString*)name];
}

@implementation IPC

+(void) initializeForProcess:(NSString*) processName
{
    @synchronized(self) {
        NSAssert(_responseHandlers==nil, @"Please don't call [IPC initialize:@\"processName\" twice!");
        _responseHandlers = [[NSMutableDictionary alloc] init];
        _darwinNotificationCenterRef = CFNotificationCenterGetDarwinNotifyCenter();
        _sharedInstance = [[self alloc] initWithProcessName:processName];       //has to be last because it starts the thread which needs those global vars
    }
}

+(id) sharedInstance
{
    @synchronized(self) {
        NSAssert(_responseHandlers!=nil, @"Please call [IPC initialize:@\"processName\"] first!");
        return _sharedInstance;
    }
}

+(void) terminate
{
    @synchronized(self) {
        //cancel server thread and wake it up to let it terminate properly
        if(_sharedInstance.serverThread)
            [_sharedInstance.serverThread cancel];
        [_sharedInstance->_serverThreadCondition signal];
        //deallocate everything
        _responseHandlers = nil;
        _sharedInstance = nil;
    }
}

-(void) sendMessage:(NSString*) name withData:(NSData* _Nullable) data to:(NSString*) destination
{
    [self sendMessage:name withData:data to:destination withResponseHandler:nil];
}

-(void) sendMessage:(NSString*) name withData:(NSData* _Nullable) data to:(NSString*) destination withResponseHandler:(IPC_response_handler_t _Nullable) responseHandler
{
    NSNumber* id = [self writeIpcMessage:name withData:data andResponseId:[NSNumber numberWithInt:0] to:destination];
    //save response handler for later execution (if one is specified)
    if(responseHandler)
        _responseHandlers[id] = responseHandler;
}

-(void) sendBroadcastMessage:(NSString*) name withData:(NSData* _Nullable) data
{
    [self sendMessage:name withData:data to:@"*" withResponseHandler:nil];
}

-(void) sendBroadcastMessage:(NSString*) name withData:(NSData* _Nullable) data withResponseHandler:(IPC_response_handler_t _Nullable) responseHandler
{
    [self sendMessage:name withData:data to:@"*" withResponseHandler:responseHandler];
}

-(void) respondToMessage:(NSDictionary*) message withData:(NSData* _Nullable) data
{
    [self writeIpcMessage:message[@"name"] withData:data andResponseId:message[@"id"] to:message[@"source"]];
}

-(id) initWithProcessName:(NSString*) processName
{
    self = [super init];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    _dbFile = [[containerUrl path] stringByAppendingPathComponent:@"ipc.sqlite"];
    _processName = processName;
    _ipcQueues = [[NSMutableDictionary alloc] init];
    _serverThreadCondition = [[NSCondition alloc] init];
    
    static dispatch_once_t once;
    static const int VERSION = 2;
    dispatch_once(&once, ^{
        BOOL fileExists = [fileManager fileExistsAtPath:_dbFile];
        //create initial database if file not exists
        if(!fileExists)
        {
            //this can not be used inside a transaction --> turn on WAL mode before executing any other db operations
            //this will create the database file and open the database because it is the first MLSQlite call done for this file
            //turning on WAL mode has to be done *outside* of any transactions
            [self.db executeNonQuery:@"PRAGMA journal_mode=WAL;"];
        }
        [self.db voidWriteTransaction:^{
            if(!fileExists)
            {
                [self.db executeNonQuery:@"CREATE TABLE ipc(id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name VARCHAR(255), source VARCHAR(255), destination VARCHAR(255), data BLOB, timeout INTEGER NOT NULL DEFAULT 0);"];
                [self.db executeNonQuery:@"CREATE TABLE versions(name VARCHAR(255) NOT NULL PRIMARY KEY, version INTEGER NOT NULL);"];
                [self.db executeNonQuery:@"INSERT INTO versions (name, version) VALUES('db', '1');"];
            }
            
            //upgrade database version if needed
            NSNumber* version = (NSNumber*)[self.db executeScalar:@"SELECT version FROM versions WHERE name='db';"];
            DDLogInfo(@"IPC db version: %@", version);
            if([version integerValue] < 2)
            {
                [self.db executeNonQuery:@"ALTER TABLE ipc ADD COLUMN response_to INTEGER NOT NULL DEFAULT 0;"];
            }
            //any upgrade done --> update version table and delete all old ipc messages
            if([version integerValue] < VERSION)
            {
                //always truncate ipc table on version upgrade
                [self.db executeNonQuery:@"DELETE FROM ipc;"];
                [self.db executeNonQuery:@"UPDATE versions SET version=? WHERE name='db';" andArguments:@[[NSNumber numberWithInt:VERSION]]];
                DDLogInfo(@"IPC db upgraded to version: %d", VERSION);
            }
        }];
    });
    
    //use a dedicated and very high priority thread to make sure this always runs
    _serverThread = [[NSThread alloc] initWithTarget:self selector:@selector(serverThreadMain) object:nil];
    //_serverThread.threadPriority = 1.0;
    _serverThread.qualityOfService = NSQualityOfServiceUserInteractive;
    [_serverThread setName:@"IPCServerThread"];
    [_serverThread start];
    
    return self;
}

-(void) serverThreadMain
{
    DDLogInfo(@"Now running IPC server for '%@' with thread priority %f...", _processName, [NSThread threadPriority]);
    //register darwin notification handler for "im.monal.ipc.wakeup:<process name>" which is used to wake up readNextMessage using the NSCondition
    CFNotificationCenterAddObserver(_darwinNotificationCenterRef, (__bridge void*) self, &darwinNotificationCenterCallback, (__bridge CFNotificationName)[NSString stringWithFormat:@"im.monal.ipc.wakeup:%@", _processName], NULL, 0);
    CFNotificationCenterAddObserver(_darwinNotificationCenterRef, (__bridge void*) self, &darwinNotificationCenterCallback, (__bridge CFNotificationName)@"im.monal.ipc.wakeup:*", NULL, 0);
    while(![[NSThread currentThread] isCancelled])
    {
        NSDictionary* message = [self readNextMessage];     //this will be blocking
        if(!message)
            continue;
        DDLogDebug(@"Got IPC message: %@", message);
        
        //use a dedicated serial queue for every IPC receiver to maintain IPC message ordering while not blocking other receivers or this serverThread)
        NSArray* parts = [message[@"name"] componentsSeparatedByString:@"."];
        NSString* queueName = [parts objectAtIndex:0];
        if(!queueName || [parts count]<2)
            queueName = @"_default";
        queueName = [NSString stringWithFormat:@"ipc.queue:%@", queueName];
        if(!_ipcQueues[queueName])
            _ipcQueues[queueName] = dispatch_queue_create([queueName cStringUsingEncoding:NSUTF8StringEncoding], dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
        
        //handle all responses (don't trigger a kMonalIncomingIPC for responses)
        if(message[@"response_to"] && [message[@"response_to"] intValue] > 0)
        {
            //call response handler if one is present (ignore the spurious response otherwise)
            if(_responseHandlers[message[@"response_to"]])
            {
                IPC_response_handler_t responseHandler = (IPC_response_handler_t)_responseHandlers[message[@"response_to"]];
                if(responseHandler)
                {
                    //responses handlers are only valid for the maximum RTT of messages (+ some safety margin)
                    createTimer(MSG_TIMEOUT*2 + 1, (^{
                        [_responseHandlers removeObjectForKey:message[@"response_to"]];
                    }));
                    dispatch_async(_ipcQueues[queueName], ^{
                        responseHandler(message);
                    });
                }
            }
        }
        else        //publish all non-responses (using the message name as object allows for filtering by ipc message name)
            dispatch_async(_ipcQueues[queueName], ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalIncomingIPC object:message[@"name"] userInfo:message];
            });
        
        DDLogDebug(@"Handled IPC message: %@", message);
    }
    //unregister darwin notification handler
    CFNotificationCenterRemoveObserver(_darwinNotificationCenterRef, (__bridge void*) self, (__bridge CFNotificationName)[NSString stringWithFormat:@"im.monal.ipc.wakeup:%@", _processName], NULL);
    CFNotificationCenterRemoveObserver(_darwinNotificationCenterRef, (__bridge void*) self, (__bridge CFNotificationName)@"im.monal.ipc.wakeup:*", NULL);
    DDLogInfo(@"IPC server for '%@' now terminated", _processName);
}

-(void) incomingDarwinNotification:(NSString*) name
{
    DDLogDebug(@"Got incoming darwin notification: %@", name);
    [_serverThreadCondition signal];        //wake up server thread to process new messages
}

-(NSDictionary*) readNextMessage
{
    while(![[NSThread currentThread] isCancelled])
    {
        NSDictionary* data = [self readIpcMessageFor:_processName];
        if(data)
            return data;
        //wait for wakeup (incoming darwin notification or thread termination)
        DDLogVerbose(@"IPC readNextMessage waiting for wakeup via darwin notification");
        [_serverThreadCondition wait];
    }
    return nil;     //thread cancelled
}

//this is the getter of our readonly "db" property always returning the thread-local instance of the MLSQLite class
-(MLSQLite*) db
{
    //always return thread-local instance of sqlite class (this is important for performance!)
    return [MLSQLite sharedInstanceForFile:_dbFile];
}

-(NSDictionary*) readIpcMessageFor:(NSString*) destination
{
    return [self.db idWriteTransaction:^{
        NSDictionary* retval = nil;
        
        //delete old entries that timed out
        NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
        [self.db executeNonQuery:@"DELETE FROM ipc WHERE timeout<?;" andArguments:@[timestamp]];
        
        //load a *single* message from table and delete it afterwards
        NSArray* rows = [self.db executeReader:@"SELECT * FROM ipc WHERE destination=? OR destination='*' ORDER BY id ASC LIMIT 1;" andArguments:@[destination]];
        if([rows count])
        {
            retval = rows[0];
            if(![retval[@"destination"] isEqualToString:@"*"])      //broadcast will be deleted by their timeout value only
                [self.db executeNonQuery:@"DELETE FROM ipc WHERE id=?;" andArguments:@[retval[@"id"]]];
        }
        return retval;
    }];
}

-(NSNumber*) writeIpcMessage:(NSString*) name withData:(NSData* _Nullable) data andResponseId:(NSNumber*) responseId to:(NSString*) destination
{
    //empty data is default if not specified
    if(!data)
        data = [[NSData alloc] init];
    
    DDLogDebug(@"writeIpcMessage:%@ withData:%@ andResponseId:%@ to:%@", name, data, responseId, destination);
    
    NSNumber* id = [self.db idWriteTransaction:^{
        //delete old entries that timed out
        NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
        [self.db executeNonQuery:@"DELETE FROM ipc WHERE timeout<?;" andArguments:@[timestamp]];
        
        //save message to table
        NSNumber* timeout = @([timestamp intValue] + MSG_TIMEOUT);        //timeout for every message
        [self.db executeNonQuery:@"INSERT INTO ipc (name, source, destination, data, timeout, response_to) VALUES(?, ?, ?, ?, ?, ?);" andArguments:@[name, _processName, destination, data, timeout, responseId]];
        return [self.db lastInsertId];
    }];
    
    //send out darwin notification to wake up other processes waiting for IPC
    if(![destination isEqualToString:@"*"])
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFNotificationName)[NSString stringWithFormat:@"im.monal.ipc.wakeup:%@", destination], NULL, NULL, NO);
    else
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFNotificationName)@"im.monal.ipc.wakeup:*", NULL, NULL, NO);
    
    DDLogDebug(@"Wrote IPC message %@ to database", id);
    return id;
}

@end
