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
}
@property (readonly, strong) MLSQLite* db;
@end

@implementation IPC

+(void) initializeForProcess:(NSString*) processName
{
    _responseHandlers = [[NSMutableDictionary alloc] init];
    _sharedInstance = [[self alloc] initWithProcessName:processName];
}

+(id) sharedInstance
{
    NSAssert(_responseHandlers!=nil, @"Please call [IPC initialize:@\"processName\" first!");
    return _sharedInstance;
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
    
    static dispatch_once_t once;
    static const int VERSION = 2;
    dispatch_once(&once, ^{
        //create initial database if file not exists
        if(![fileManager fileExistsAtPath:_dbFile])
        {
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
        if([version integerValue] < VERSION)
        {
            //always truncate ipc table on version upgrade
            [self.db executeNonQuery:@"DELETE FROM ipc;" andArguments:@[]];
            [self.db executeNonQuery:@"UPDATE versions SET version=? WHERE name='db';" andArguments:@[[NSNumber numberWithInt:VERSION]]];
            DDLogInfo(@"IPC db upgraded to version: %d", VERSION);
        }
        
        [self.db endWriteTransaction];
    });
    
    [self runServer];
    return self;
}

-(void) runServer
{
    //use high prio to make sure this always runs
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        DDLogInfo(@"Now running IPC server for: %@", _processName);
        while(YES)
        {
            NSDictionary* message = [self readNextMessage];     //this will be blocking
            DDLogVerbose(@"Got IPC message: %@", message);
            if(message[@"response_to"] && [message[@"response_to"] intValue] > 0)   //handle all responses
            {
                //call response handler if one is present (ignore the spurious response otherwise)
                if(_responseHandlers[message[@"response_to"]])
                {
                    ((IPC_response_handler_t)_responseHandlers[message[@"response_to"]])(message);
                    [_responseHandlers removeObjectForKey:message[@"response_to"]];      //responses can only be sent (and handled) once
                }
            }
            else        //publish all non-responses
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalIncomingIPC object:self userInfo:message];
        }
    });
}

-(NSDictionary*) readNextMessage
{
    while(YES)
    {
        NSDictionary* data = [self readIpcMessageFor:_processName];
        if(data)
            return data;
        //TODO: use blocking read on pipe to sleep until data is available instead of usleep()
        //TODO: alternative: use the last changed timestamp of a dedicated sqlite database
        usleep(50000);
    }
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
    
    //load a *single* message from table
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
    
    [self.db beginWriteTransaction];
    
    //delete old entries that timed out
    NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
    [self.db executeNonQuery:@"DELETE FROM ipc WHERE timeout<?;" andArguments:@[timestamp]];
    
    //save message to table
    NSNumber* timeout = @([timestamp intValue] + 10);        //10 seconds timeout
    [self.db executeNonQuery:@"INSERT INTO ipc (name, source, destination, data, timeout, response_to) VALUES(?, ?, ?, ?, ?, ?);" andArguments:@[name, _processName, destination, data, timeout, responseId]];
    NSNumber* id = [self.db lastInsertId];
    
    [self.db endWriteTransaction];
    //TODO: write to destination pipe to wake up remote process or just use the file changed time of a dedicated sqlite database
    DDLogVerbose(@"Wrote IPC message %@ to database", id);
    return id;
}

@end
