//
//  IPC.m
//  Monal
//
//  Created by Thilo Molitor on 31.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#include <CommonCrypto/CommonDigest.h>
#import "IPC.h"
#import "MLSQLite.h"

static NSMutableDictionary* _responseHandlers;
static IPC* _sharedInstance;

@interface IPC()
{
    NSString* _processName;
    NSString* _dbFile;
    NSMutableDictionary* _ipcQueues;
}
@property (readonly, strong) MLSQLite* db;
@property (readonly, strong) NSThread* serverThread;
@end

@implementation IPC

+(void) initializeForProcess:(NSString*) processName
{
    NSAssert(_responseHandlers==nil, @"Please don't call [IPC initialize:@\"processName\" twice!");
    _responseHandlers = [[NSMutableDictionary alloc] init];
    _sharedInstance = [[self alloc] initWithProcessName:processName];
}

+(id) sharedInstance
{
    NSAssert(_responseHandlers!=nil, @"Please call [IPC initialize:@\"processName\" first!");
    return _sharedInstance;
}

+(void) terminate
{
    //cancel server thread and deallocate everything
    [_sharedInstance.serverThread cancel];
    _responseHandlers = nil;
    _sharedInstance = nil;
}

-(void) sendMessage:(NSString*) name withData:(NSData*) data to:(NSString*) destination
{
    [self sendMessage:name withData:data to:destination withResponseHandler:nil];
}

-(void) sendMessage:(NSString*) name withData:(NSData*) data to:(NSString*) destination withResponseHandler:(IPC_response_handler_t) responseHandler
{
    NSNumber* id = [self writeIpcMessage:name withData:data andResponseId:[NSNumber numberWithInt:0] to:destination];
    //save response handler for later execution (if one is specified)
    if(responseHandler)
        _responseHandlers[id] = responseHandler;
}

-(void) respondToMessage:(NSDictionary*) message withData:(NSData*) data
{
    [self writeIpcMessage:message[@"name"] withData:data andResponseId:message[@"id"] to:message[@"source"]];
}

-(id) initWithProcessName:(NSString*) processName
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    _dbFile = [[containerUrl path] stringByAppendingPathComponent:@"ipc.sqlite"];
    _processName = processName;
    _ipcQueues = [[NSMutableDictionary alloc] init];
    
    static dispatch_once_t once;
    static const int VERSION = 2;
    dispatch_once(&once, ^{
        //create initial database if file not exists
        if(![fileManager fileExistsAtPath:_dbFile])
        {
            //this can not be used inside a transaction --> turn on WAL mode before executing any other db operations
            [self.db executeNonQuery:@"pragma journal_mode=WAL;" andArguments:nil];
            [self.db beginWriteTransaction];
            [self.db executeNonQuery:@"CREATE TABLE ipc(id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, name VARCHAR(255), source VARCHAR(255), destination VARCHAR(255), data BLOB, timeout INTEGER NOT NULL DEFAULT 0);" andArguments:nil];
            [self.db executeNonQuery:@"CREATE TABLE versions(name VARCHAR(255) NOT NULL PRIMARY KEY, version INTEGER NOT NULL);" andArguments:nil];
            [self.db executeNonQuery:@"INSERT INTO versions (name, version) VALUES('db', '1');" andArguments:nil];
        }
        else
            [self.db beginWriteTransaction];
        
        //upgrade database version if needed
        NSNumber* version = [self.db executeScalar:@"SELECT version FROM versions WHERE name='db';" andArguments:nil];
        DDLogInfo(@"IPC db version: %@", version);
        if([version integerValue] < 2)
        {
            [self.db executeNonQuery:@"ALTER TABLE ipc ADD COLUMN response_to INTEGER NOT NULL DEFAULT 0;" andArguments:@[]];
        }
        //any upgrade done --> update version table and delete all old ipc messages
        if([version integerValue] < VERSION)
        {
            //always truncate ipc table on version upgrade
            [self.db executeNonQuery:@"DELETE FROM ipc;" andArguments:@[]];
            [self.db executeNonQuery:@"UPDATE versions SET version=? WHERE name='db';" andArguments:@[[NSNumber numberWithInt:VERSION]]];
            DDLogInfo(@"IPC db upgraded to version: %d", VERSION);
        }
        
        [self.db endWriteTransaction];
    });
    
    //use a dedicated thread to make sure this always runs
    _serverThread = [[NSThread alloc] initWithTarget:self selector:@selector(serverThreadMain) object:nil];
    [_serverThread setName:@"IPCServerThread"];
    [_serverThread start];
    
    return self;
}

-(void) serverThreadMain
{
    DDLogInfo(@"Now running IPC server for '%@'", _processName);
    while(![[NSThread currentThread] isCancelled])
    {
        NSDictionary* message = [self readNextMessage];     //this will be blocking
        if(!message)
            continue;
        DDLogVerbose(@"Got IPC message: %@", message);
        
        //use a dedicated serial queue for every IPC receiver to maintain IPC message ordering while not blocking other receivers or this serverThread)
        NSArray* parts = [message[@"name"] componentsSeparatedByString:@"."];
        NSString* queueName = [parts objectAtIndex:0];
        if(!queueName || [parts count]<2)
            queueName = @"_default";
        queueName = [NSString stringWithFormat:@"ipc.queue:%@", queueName];
        if(!_ipcQueues[queueName])
            _ipcQueues[queueName] = dispatch_queue_create([queueName cStringUsingEncoding:NSUTF8StringEncoding], DISPATCH_QUEUE_SERIAL);
        
        //handle all responses (don't trigger a kMonalIncomingIPC for responses)
        if(message[@"response_to"] && [message[@"response_to"] intValue] > 0)
        {
            //call response handler if one is present (ignore the spurious response otherwise)
            if(_responseHandlers[message[@"response_to"]])
            {
                IPC_response_handler_t responseHandler = (IPC_response_handler_t)_responseHandlers[message[@"response_to"]];
                [_responseHandlers removeObjectForKey:message[@"response_to"]];      //responses can only be sent (and handled) once
                dispatch_async(_ipcQueues[queueName], ^{
                    responseHandler(message);
                });
            }
        }
        else        //publish all non-responses (using the message name as object allows for filtering by ipc message name)
            dispatch_async(_ipcQueues[queueName], ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalIncomingIPC object:message[@"name"] userInfo:message];
            });
    }
    DDLogInfo(@"IPC server for '%@' now terminated", _processName);
}

-(NSDictionary*) readNextMessage
{
    while(![[NSThread currentThread] isCancelled])
    {
        NSDictionary* data = [self readIpcMessageFor:_processName];
        if(data)
            return data;
        //TODO: use blocking read on pipe to sleep until data is available instead of usleep()
        //TODO: alternative: use the last changed timestamp of a dedicated sqlite database
        usleep(50000);
    }
    return nil;     //thread cancelled or something else happened
}

//this is the getter of our readonly "db" property always returning the thread-local instance of the MLSQLite class
-(MLSQLite*) db
{
    //always return thread-local instance of sqlite class (this is important for performance!)
    return [MLSQLite sharedInstanceForFile:_dbFile];
}

-(NSDictionary*) readIpcMessageFor:(NSString*) destination
{
    NSDictionary* retval = nil;
    
    [self.db beginWriteTransaction];
    
    //delete old entries that timed out
    NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
    [self.db executeNonQuery:@"DELETE FROM ipc WHERE timeout<?;" andArguments:@[timestamp]];
    
    //load a *single* message from table and delete it afterwards
    NSArray* rows = [self.db executeReader:@"SELECT * FROM ipc WHERE destination=? ORDER BY id ASC LIMIT 1;" andArguments:@[destination]];
    if([rows count])
    {
        retval = rows[0];
        [self.db executeNonQuery:@"DELETE FROM ipc WHERE id=?;" andArguments:@[retval[@"id"]]];
    }
    
    [self.db endWriteTransaction];
    
    return retval;
}

-(NSNumber*) writeIpcMessage:(NSString*) name withData:(NSData*) data andResponseId:(NSNumber*) responseId to:(NSString*) destination
{
    //empty data is default if not specified
    if(!data)
        data = [[NSData alloc] init];
    
    DDLogVerbose(@"writeIpcMessage:%@ withData:%@ andResponseId:%@ to:%@", name, data, responseId, destination);
    
    [self.db beginWriteTransaction];
    
    //delete old entries that timed out
    NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
    [self.db executeNonQuery:@"DELETE FROM ipc WHERE timeout<?;" andArguments:@[timestamp]];
    
    //save message to table
    NSNumber* timeout = @([timestamp intValue] + 2);        //2 seconds timeout for every message
    [self.db executeNonQuery:@"INSERT INTO ipc (name, source, destination, data, timeout, response_to) VALUES(?, ?, ?, ?, ?, ?);" andArguments:@[name, _processName, destination, data, timeout, responseId]];
    NSNumber* id = [self.db lastInsertId];
    
    [self.db endWriteTransaction];
    //TODO: write to destination pipe to wake up remote process or just use the file changed time of a dedicated sqlite database
    DDLogVerbose(@"Wrote IPC message %@ to database", id);
    return id;
}

@end
