//
//  MLSQLite.m
//  Monal
//
//  Created by Thilo Molitor on 31.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <sqlite3.h>
#import "MLSQLite.h"
#import "HelperTools.h"

@interface MLSQLite()
{
    NSString* _dbFile;
    sqlite3* _database;
}
@end

#ifdef DEBUG
static NSMutableDictionary* currentTransactions;
#endif

@implementation MLSQLite

+(void) initialize
{
#ifdef DEBUG
    currentTransactions = [[NSMutableDictionary alloc] init];
#endif
    
    if(sqlite3_config(SQLITE_CONFIG_MULTITHREAD) == SQLITE_OK)
        DDLogInfo(@"sqlite initialize: sqlite3 configured ok");
    else
    {
        DDLogError(@"sqlite initialize: sqlite3 not configured ok");
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"sqlite3_config() failed" userInfo:nil];
    }
    
    sqlite3_initialize();
}

//every thread gets its own instance having its own db connection
//this allows for concurrent reads/writes
+(id) sharedInstanceForFile:(NSString*) dbFile
{
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    if(threadData[@"_sqliteInstancesForThread"] && threadData[@"_sqliteInstancesForThread"][dbFile])
        return threadData[@"_sqliteInstancesForThread"][dbFile];
    MLSQLite* newInstance = [[self alloc] initWithFile:dbFile];
    //init dictionaries if neccessary
    if(!threadData[@"_sqliteInstancesForThread"])
        threadData[@"_sqliteInstancesForThread"] = [[NSMutableDictionary alloc] init];
    if(!threadData[@"_sqliteTransactionsRunning"])
        threadData[@"_sqliteTransactionsRunning"] = [[NSMutableDictionary alloc] init];
    //save thread local data
    threadData[@"_sqliteInstancesForThread"][dbFile] = newInstance;                    //save thread-local instance
    threadData[@"_sqliteTransactionsRunning"][dbFile] = [NSNumber numberWithInt:0];    //init data for nested transactions
    return newInstance;
}

-(id) initWithFile:(NSString*) dbFile
{
    _dbFile = dbFile;
    DDLogVerbose(@"db path %@", _dbFile);
    
    //mark all files to stay unlocked even if device gets locked again
    [HelperTools configureFileProtectionFor:_dbFile];
    [HelperTools configureFileProtectionFor:[NSString stringWithFormat:@"%@-wal", _dbFile]];
    [HelperTools configureFileProtectionFor:[NSString stringWithFormat:@"%@-shm", _dbFile]];
    
    if(sqlite3_open_v2([_dbFile UTF8String], &(self->_database), SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
    {
        DDLogInfo(@"Database opened: %@", _dbFile);
    }
    else
    {
        //database error message
        DDLogError(@"Error opening database: %@", _dbFile);
        @throw [NSException exceptionWithName:@"RuntimeException" reason:@"sqlite3_open_v2() failed" userInfo:nil];
    }
    
    //use this observer because dealloc will not be called in the same thread as the sqlite statements got prepared
    [[NSNotificationCenter defaultCenter] addObserverForName:NSThreadWillExitNotification object:[NSThread currentThread] queue:nil usingBlock:^(NSNotification* notification) {
        @synchronized(self) {
            NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
            if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] > 1)
            {
                DDLogError(@"Transaction leak in NSThreadWillExitNotification: trying to close sqlite3 connection while transaction still open");
                @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Transaction leak in NSThreadWillExitNotification: trying to close sqlite3 connection while transaction still open" userInfo:threadData];
            }
            if(self->_database)
            {
                DDLogInfo(@"Closing database in NSThreadWillExitNotification: %@", _dbFile);
                sqlite3_close(self->_database);
                self->_database = NULL;
            }
        }
    }];

    //some settings (e.g. truncate is faster than delete)
    //this uses the private api because we have no thread local instance added to the threadData dictionary yet (and public apis check that)
    sqlite3_busy_timeout(self->_database, 4000);
    [self executeNonQuery:@"pragma synchronous=NORMAL;" andArguments:@[] withException:YES];
    [self executeNonQuery:@"pragma truncate;" andArguments:@[] withException:YES];

    return self;
}

-(void) dealloc
{
    @synchronized(self) {
        NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
        if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] > 1)
        {
            DDLogError(@"Transaction leak in dealloc: trying to close sqlite3 connection while transaction still open");
            @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Transaction leak in dealloc: trying to close sqlite3 connection while transaction still open" userInfo:threadData];
        }
        if(self->_database)
        {
            DDLogInfo(@"Closing database in dealloc: %@", _dbFile);
            sqlite3_close(self->_database);
            self->_database = NULL;
        }
    }
}

#pragma mark - private sql api

-(sqlite3_stmt*) prepareQuery:(NSString*) query withArgs:(NSArray*) args
{
    sqlite3_stmt* statement;

    if(sqlite3_prepare_v2(self->_database, [query cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) != SQLITE_OK)
    {
        DDLogError(@"sqlite prepare '%@' failed: %s", query, sqlite3_errmsg(self->_database));
        return NULL;
    }
    
    //bind args to statement
    sqlite3_reset(statement);
    [args enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if([obj isKindOfClass:[NSNumber class]])
        {
            NSNumber* number = (NSNumber*)obj;
            if(sqlite3_bind_double(statement, (signed)idx+1, [number doubleValue]) != SQLITE_OK)
            {
                DDLogError(@"number bind error: %@", number);
                [self throwErrorForQuery:query andArguments:args];
            }
        }
        else if([obj isKindOfClass:[NSString class]])
        {
            NSString* text = (NSString*)obj;
            if(sqlite3_bind_text(statement, (signed)idx+1, [text cStringUsingEncoding:NSUTF8StringEncoding], -1, SQLITE_TRANSIENT) != SQLITE_OK)
            {
                DDLogError(@"text bind error: %@", text);
                [self throwErrorForQuery:query andArguments:args];
            }
        }
        else if([obj isKindOfClass:[NSData class]])
        {
            NSData* data = (NSData*)obj;
            if(sqlite3_bind_blob(statement, (signed)idx+1, [data bytes], (int)data.length, SQLITE_TRANSIENT) != SQLITE_OK)
            {
                DDLogError(@"blob bind error: %@", data);
                [self throwErrorForQuery:query andArguments:args];
            }
        }
    }];
    
    return statement;
}

-(id) getColumn:(int) column ofStatement:(sqlite3_stmt*) statement
{
    switch(sqlite3_column_type(statement, column))
    {
        //SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
        case(SQLITE_INTEGER):
        {
            NSNumber* returnInt = [NSNumber numberWithInt:sqlite3_column_int(statement, column)];
            return returnInt;
        }
        case(SQLITE_FLOAT):
        {
            NSNumber* returnFloat = [NSNumber numberWithDouble:sqlite3_column_double(statement, column)];
            return returnFloat;
        }
        case(SQLITE_TEXT):
        {
            NSString* returnString = [NSString stringWithUTF8String:(const char* _Nonnull) sqlite3_column_text(statement, column)];
            return returnString;
        }
        case(SQLITE_BLOB):
        {
            const char* bytes = (const char* _Nonnull) sqlite3_column_blob(statement, column);
            int size = sqlite3_column_bytes(statement, column);
            NSData* returnData = [NSData dataWithBytes:bytes length:size];
            return returnData;
        }
        case(SQLITE_NULL):
        {
            return nil;
        }
    }
    return nil;
}

-(void) throwErrorForQuery:(NSString*) query andArguments:(NSArray*) args
{
    NSString* error = [NSString stringWithUTF8String:sqlite3_errmsg(self->_database)];
    DDLogError(@"SQLite Exception: %@ for query '%@' having params %@", error, query ? query : @"", args ? args : @[]);
#ifdef DEBUG
    DDLogError(@"currentTransactions: %@", currentTransactions);
#endif
    @throw [NSException exceptionWithName:@"SQLite3Exception" reason:error userInfo:@{
#ifdef DEBUG
        @"currentTransactions": currentTransactions,
#endif
        @"query": query ? query : [NSNull null],
        @"args": args ? args : [NSNull null]
    }];
}

-(void) testThreadInstanceForQuery:(NSString*) query andArguments:(NSArray*) args
{
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    if(!threadData[@"_sqliteInstancesForThread"] || !threadData[@"_sqliteInstancesForThread"][_dbFile] || self != threadData[@"_sqliteInstancesForThread"][_dbFile])
    {
        DDLogError(@"Shared instance of MLSQLite used in wrong thread for query '%@' having params %@", query ? query : @"", args ? args : @[]);
#ifdef DEBUG
        DDLogError(@"currentTransactions: %@", currentTransactions);
#endif
        @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"Shared instance of MLSQLite used in wrong thread!" userInfo:@{
#ifdef DEBUG
            @"currentTransactions": currentTransactions,
#endif
            @"query": query ? query : [NSNull null],
            @"args": args ? args : [NSNull null]
        }];
    }
}

-(BOOL) executeNonQuery:(NSString*) query andArguments:(NSArray *) args withException:(BOOL) throwException
{
    if(!query)
        return NO;
    
    //NOTE: we are not checking the thread instance here in this private api, but in the public api proxy methods
    
    BOOL toReturn;
    sqlite3_stmt* statement = [self prepareQuery:query withArgs:args];
    if(statement != NULL)
    {
        int step;
        while((step=sqlite3_step(statement)) == SQLITE_ROW) {}     //clear data of all returned rows
        sqlite3_finalize(statement);
        if(step == SQLITE_DONE)
            toReturn = YES;
        else
        {
            DDLogVerbose(@"sqlite3_step(%@): %d --> %@", query, step, [[NSThread currentThread] threadDictionary]);
            if(throwException)
                [self throwErrorForQuery:query andArguments:args];
            toReturn = NO;
        }
    }
    else
    {
        DDLogError(@"nonquery returning NO with out OK %@", query);
        if(throwException)
            [self throwErrorForQuery:query andArguments:args];
        toReturn = NO;
    }
    return toReturn;
}

#pragma mark - public API

-(void) voidWriteTransaction:(monal_void_block_t) operations
{
    [self idWriteTransaction:^(void){
        operations();
        return (NSObject*)nil;      //dummy return value
    }];
}

-(BOOL) boolWriteTransaction:(monal_sqlite_bool_operations_t) operations
{
    return [[self idWriteTransaction:^(void){
        return [NSNumber numberWithBool:operations()];
    }] boolValue];
}

-(id) idWriteTransaction:(monal_sqlite_operations_t) operations
{
    [self beginWriteTransaction];
    id retval = operations();
    [self endWriteTransaction];
    return retval;
}

-(void) beginWriteTransaction
{
    [self testThreadInstanceForQuery:@"beginWriteTransaction" andArguments:nil];
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    threadData[@"_sqliteTransactionsRunning"][_dbFile] = [NSNumber numberWithInt:([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] + 1)];
    if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] > 1)
        return;			//begin only outermost transaction
    BOOL retval;
    do {
        retval=[self executeNonQuery:@"BEGIN IMMEDIATE TRANSACTION;" andArguments:@[] withException:NO];
        if(!retval)
        {
            [NSThread sleepForTimeInterval:0.001f];		//wait one millisecond and retry again
            DDLogWarn(@"Retrying transaction start...");
        }
    } while(!retval);
#ifdef DEBUG
    NSString* ownThread = [NSString stringWithFormat:@"%@", [NSThread currentThread]];
    @synchronized(currentTransactions) {
        currentTransactions[ownThread] = [NSThread callStackSymbols];
    }
#endif
}

-(void) endWriteTransaction
{
    [self testThreadInstanceForQuery:@"endWriteTransaction" andArguments:nil];
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    threadData[@"_sqliteTransactionsRunning"][_dbFile] = [NSNumber numberWithInt:[threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] - 1];
    if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] == 0)
    {
        [self executeNonQuery:@"COMMIT;"];		//commit only outermost transaction
#ifdef DEBUG
        NSString* ownThread = [NSString stringWithFormat:@"%@", [NSThread currentThread]];
        @synchronized(currentTransactions) {
            [currentTransactions removeObjectForKey:ownThread];
        }
#endif
    }
}

-(id) executeScalar:(NSString*) query
{
    return [self executeScalar:query andArguments:@[]];
}

-(id) executeScalar:(NSString*) query andArguments:(NSArray*) args
{
    if(!query)
        return nil;
    
    [self testThreadInstanceForQuery:query andArguments:args];
    
    id __block toReturn;
    sqlite3_stmt* statement = [self prepareQuery:query withArgs:args];
    if(statement != NULL)
    {
        int step;
        if((step=sqlite3_step(statement)) == SQLITE_ROW)
        {
            toReturn = [self getColumn:0 ofStatement:statement];
            while((step=sqlite3_step(statement)) == SQLITE_ROW) {}     //clear data of all other rows
        }
        sqlite3_finalize(statement);
        if(step != SQLITE_DONE)
            [self throwErrorForQuery:query andArguments:args];
    }
    else
    {
        //if noting else
        DDLogVerbose(@"returning nil with out OK %@", query);
        toReturn = nil;
        [self throwErrorForQuery:query andArguments:args];
    }
    return toReturn;
}

-(NSMutableArray*) executeReader:(NSString*) query
{
    return [self executeReader:query andArguments:@[]];
}

-(NSMutableArray*) executeReader:(NSString*) query andArguments:(NSArray*) args
{
    if(!query)
        return nil;
    
    [self testThreadInstanceForQuery:query andArguments:args];

    NSMutableArray* toReturn = [[NSMutableArray alloc] init];
    sqlite3_stmt* statement = [self prepareQuery:query withArgs:args];
    if(statement != NULL)
    {
        int step;
        while((step=sqlite3_step(statement)) == SQLITE_ROW)
        {
            NSMutableDictionary* row = [[NSMutableDictionary alloc] init];
            int counter = 0;
            while(counter < sqlite3_column_count(statement))
            {
                NSString* columnName = [NSString stringWithUTF8String:sqlite3_column_name(statement, counter)];
                NSObject* returnData = [self getColumn:counter ofStatement:statement];
                //accessing an unset key in NSDictionary will return nil (nil can not be inserted directly into the dictionary)
                if(returnData != nil)
                    [row setObject:returnData forKey:columnName];
                counter++;
            }
            [toReturn addObject:row];
        }
        sqlite3_finalize(statement);
        if(step != SQLITE_DONE)
            [self throwErrorForQuery:query andArguments:args];
    }
    else
    {
        //if noting else
        DDLogVerbose(@"reader nil with sql not ok: %@", query);
        toReturn = nil;
        [self throwErrorForQuery:query andArguments:args];
    }
    return toReturn;
}

-(BOOL) executeNonQuery:(NSString*) query
{
    [self testThreadInstanceForQuery:query andArguments:@[]];
    return [self executeNonQuery:query andArguments:@[] withException:YES];
}

-(BOOL) executeNonQuery:(NSString*) query andArguments:(NSArray*) args
{
    [self testThreadInstanceForQuery:query andArguments:args];
    return [self executeNonQuery:query andArguments:args withException:YES];
}

-(NSNumber*) lastInsertId
{
    [self testThreadInstanceForQuery:@"lastInsertId" andArguments:nil];
    return [NSNumber numberWithInt:(int)sqlite3_last_insert_rowid(self->_database)];
}

@end
