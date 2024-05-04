//
//  MLSQLite.m
//  Monal
//
//  Created by Thilo Molitor on 31.07.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <pthread.h>
#import <sqlite3.h>
#import "MLSQLite.h"
#import "HelperTools.h"

@interface MLSQLite()
{
    NSString* _dbFile;
    sqlite3* _database;
}
@end

static NSMutableDictionary* currentTransactions;

@implementation MLSQLite

+(void) initialize
{
    currentTransactions = [NSMutableDictionary new];
    
    if(sqlite3_config(SQLITE_CONFIG_MULTITHREAD) == SQLITE_OK)
        DDLogInfo(@"sqlite initialize: sqlite3 configured ok");
    else
    {
        DDLogError(@"sqlite initialize: sqlite3 not configured ok");
        @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"sqlite3_config() failed" userInfo:nil];
    }
    
    sqlite3_initialize();
    DDLogInfo(@"sqlite initialize: using mysql lib version: %s", sqlite3_libversion());
}

//every thread gets its own instance having its own db connection
//this allows for concurrent reads/writes
+(id) sharedInstanceForFile:(NSString*) dbFile
{
    MLAssert(dbFile != nil, @"MLSQLite sharedInstanceForFile:nil: file MUST NOT be nil!");
    @synchronized(self) {
        NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
        if(threadData[@"_sqliteInstancesForThread"] && threadData[@"_sqliteInstancesForThread"][dbFile])
            return threadData[@"_sqliteInstancesForThread"][dbFile];
        MLSQLite* newInstance = [[self alloc] initWithFile:dbFile];
        //init dictionaries if neccessary
        if(!threadData[@"_sqliteInstancesForThread"])
            threadData[@"_sqliteInstancesForThread"] = [NSMutableDictionary new];
        if(!threadData[@"_sqliteTransactionsRunning"])
            threadData[@"_sqliteTransactionsRunning"] = [NSMutableDictionary new];
        if(!threadData[@"_sqliteStartedReadTransaction"])
            threadData[@"_sqliteStartedReadTransaction"] = [NSMutableDictionary new];
        //save thread-local instance
        threadData[@"_sqliteInstancesForThread"][dbFile] = newInstance;
        //init data for nested transactions
        threadData[@"_sqliteTransactionsRunning"][dbFile] = [NSNumber numberWithInt:0];
        threadData[@"_sqliteStartedReadTransaction"][dbFile] = @NO;
        return newInstance;
    }
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
        @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"sqlite3_open_v2() failed" userInfo:nil];
    }
    
    //use this observer because dealloc will not be called in the same thread as the sqlite statements got prepared in
    [[NSNotificationCenter defaultCenter] addObserverForName:NSThreadWillExitNotification object:[NSThread currentThread] queue:nil usingBlock:^(NSNotification* notification __unused) {
        @synchronized(self) {
            NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
            if([threadData[@"_sqliteTransactionsRunning"][self->_dbFile] intValue] > 1)
            {
                DDLogError(@"Transaction leak in NSThreadWillExitNotification: trying to close sqlite3 connection while transaction still open");
                @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"Transaction leak in NSThreadWillExitNotification: trying to close sqlite3 connection while transaction still open" userInfo:threadData];
            }
            if(self->_database)
            {
                DDLogInfo(@"Closing database in NSThreadWillExitNotification: %@", self->_dbFile);
                sqlite3_close(self->_database);
                self->_database = NULL;
            }
        }
    }];

    //some settings (e.g. truncate is faster than delete)
    //this uses the private api because we have no thread local instance added to the threadData dictionary yet and we don't use a transaction either (and public apis check both)
    //--> we must use the internal api because it does not call testThreadInstanceForQuery: testTransactionsForQuery:
    sqlite3_busy_timeout(self->_database, 2000);        //set the busy time as early as possible to make sure the pragma states don't trigger a retry too often
    while([self executeNonQuery:@"PRAGMA synchronous=NORMAL;" andArguments:@[] withException:NO] != YES)
        DDLogError(@"Database locked, while calling 'PRAGMA synchronous=NORMAL;', retrying...");
    while([self executeNonQuery:@"PRAGMA truncate;" andArguments:@[] withException:NO] != YES)
        DDLogError(@"Database locked, while calling 'PRAGMA truncate;', retrying...");
    while([self executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:@[] withException:NO] != YES)
        DDLogError(@"Database locked, while calling 'PRAGMA foreign_keys=on;', retrying...");

    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    @synchronized(self) {
        NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
        if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] > 1)
        {
            DDLogError(@"Transaction leak in dealloc: trying to close sqlite3 connection while transaction still open");
            @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"Transaction leak in dealloc: trying to close sqlite3 connection while transaction still open" userInfo:threadData];
        }
        if(self->_database)
        {
            DDLogInfo(@"Closing database in dealloc: %@", _dbFile);
            sqlite3_close(self->_database);
            self->_database = NULL;
        }
    }
}

-(NSString*) calcThreadName
{
    __uint64_t tid;
    if(pthread_threadid_np(NULL, &tid) == 0)
        return [[NSString alloc] initWithFormat:@"%llu(%@) --> %@", tid, [NSThread currentThread].name, [NSThread currentThread]];
    else
        return [[NSString alloc] initWithFormat:@"missing threadId (%@) --> %@", [NSThread currentThread].name, [NSThread currentThread]];
}

#pragma mark - private sql api

-(sqlite3_stmt*) prepareQuery:(NSString*) query withArgs:(NSArray*) args
{
    sqlite3_stmt* statement;

    if(sqlite3_prepare_v2(self->_database, [query cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) != SQLITE_OK)
    {
        [self throwErrorForQuery:query andArguments:args];
        return NULL;
    }
    
    if((int)args.count != sqlite3_bind_parameter_count(statement))
        @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"SQL parameter count not equals argument count!" userInfo:@{
            @"query": query,
            @"args": args,
            @"paramCount": @(sqlite3_bind_parameter_count(statement)),
            @"argCount": @(args.count),
        }];
    
    //bind args to statement
    sqlite3_reset(statement);
    [args enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop __unused) {
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
        else if([obj isKindOfClass:[NSNull class]])
        {
            if(sqlite3_bind_null(statement, (signed)idx+1) != SQLITE_OK)
            {
                DDLogError(@"null bind error");
                [self throwErrorForQuery:query andArguments:args];
            }
        }
        else
        {
            DDLogError(@"Binding unsupported parameter in: %@", statement);
            [self throwErrorForQuery:query andArguments:args];
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
    int errcode = sqlite3_extended_errcode(self->_database);
    NSString* error = [NSString stringWithUTF8String:sqlite3_errmsg(self->_database)];
    DDLogError(@"SQLite Exception: %d %@ for query '%@' having params %@", errcode, error, query ? query : @"", args ? args : @[]);
    @synchronized(currentTransactions) {
        DDLogError(@"currentTransactions: %@", currentTransactions);
        @throw [NSException exceptionWithName:@"SQLite3Exception" reason:[NSString stringWithFormat:@"%d: %@", errcode, error] userInfo:@{
            @"query": query ? query : [NSNull null],
            @"args": args ? args : [NSNull null],
            @"currentTransactions": currentTransactions,
        }];
    }
}

-(void) testThreadInstanceForQuery:(NSString*) query andArguments:(NSArray*) args
{
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    if(!threadData[@"_sqliteInstancesForThread"] || !threadData[@"_sqliteInstancesForThread"][_dbFile] || self != threadData[@"_sqliteInstancesForThread"][_dbFile])
    {
        DDLogError(@"Shared instance of MLSQLite used in wrong thread for query '%@' having params %@", query ? query : @"", args ? args : @[]);
        @synchronized(currentTransactions) {
            DDLogError(@"currentTransactions: %@", currentTransactions);
            @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"Shared instance of MLSQLite used in wrong thread!" userInfo:@{
                @"currentTransactions": currentTransactions,
                @"query": query ? query : [NSNull null],
                @"args": args ? args : [NSNull null]
            }];
        }
    }
}

-(void) testTransactionsForQuery:(NSString*) query andArguments:(NSArray*) args
{
    //ignore pragma "queries" in this test --> pragma "queries" are allowed outside of transactions, too
    if([[query uppercaseString] hasPrefix:@"PRAGMA "])
        return;
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] == 0)
    {
        DDLogError(@"Tried to run query outside of transaction: '%@' having params %@", query ? query : @"", args ? args : @[]);
        @synchronized(currentTransactions) {
            DDLogError(@"currentTransactions: %@", currentTransactions);
            @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"Tried to run query outside of transaction!" userInfo:@{
                @"currentTransactions": currentTransactions,
                @"query": query ? query : [NSNull null],
                @"args": args ? args : [NSNull null]
            }];
        }
    }
}

-(void) checkQuery:(NSString*) query
{
    if(!query || [query length] == 0)
        @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"Empty sql query!" userInfo:nil];
}

-(BOOL) executeNonQuery:(NSString*) query andArguments:(NSArray *) args withException:(BOOL) throwException
{
    [self checkQuery:query];
    
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
            DDLogVerbose(@"sqlite3_step(%@): %d (%d) [%s] --> %@",
                query,
                step,
                sqlite3_extended_errcode(self->_database),
                sqlite3_errmsg(self->_database),
                [[NSThread currentThread] threadDictionary]
            );
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

-(id) internalExecuteScalar:(NSString*) query andArguments:(NSArray*) args
{
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
        [self throwErrorForQuery:query andArguments:args];
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
#if !TARGET_OS_SIMULATOR
    NSDate* startTime = [NSDate date];
#endif
    id retval = operations();
#if !TARGET_OS_SIMULATOR
    NSDate* endTime = [NSDate date];
    if([endTime timeIntervalSinceDate:startTime] > 2.0)
        showErrorOnAlpha(nil, @"Write transaction blocking took %fs (longer than 2.0s): %@", (double)[endTime timeIntervalSinceDate:startTime], [NSThread callStackSymbols]);
#endif
    [self endWriteTransaction];
    return retval;
}

-(void) beginWriteTransaction
{
    [self testThreadInstanceForQuery:@"beginWriteTransaction" andArguments:nil];
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    if([threadData[@"_sqliteStartedReadTransaction"][_dbFile] boolValue])
        @synchronized(currentTransactions) {
            @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"Tried to start write transaction inside running read transaction!" userInfo:@{
                @"currentTransactions": currentTransactions,
            }];
        }
    threadData[@"_sqliteTransactionsRunning"][_dbFile] = [NSNumber numberWithInt:([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] + 1)];
    if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] > 1)
        return;			//begin only outermost transaction
    BOOL retval;
    do {
        retval = [self executeNonQuery:@"BEGIN IMMEDIATE TRANSACTION;" andArguments:@[] withException:NO];
        if(!retval)
        {
            [NSThread sleepForTimeInterval:0.001f];		//wait one millisecond and retry again
            @synchronized(currentTransactions) {
                DDLogWarn(@"Retrying write transaction start: %@", @{
                    @"newWriteTransactionVia": [NSThread callStackSymbols],
                    @"currentTransactions": currentTransactions,
                });
            }
        }
    } while(!retval);
    NSString* ownThread = [self calcThreadName];
    @synchronized(currentTransactions) {
        currentTransactions[ownThread] = [NSThread callStackSymbols];
    }
}

-(void) endWriteTransaction
{
    [self testThreadInstanceForQuery:@"endWriteTransaction" andArguments:nil];
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
		    threadData[@"_sqliteTransactionsRunning"][_dbFile] = [NSNumber numberWithInt:[threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] - 1];
    if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] == 0)
    {
        [self executeNonQuery:@"COMMIT;" andArguments:@[] withException:YES];        //commit only outermost transaction
        NSString* ownThread = [self calcThreadName];
        @synchronized(currentTransactions) {
            [currentTransactions removeObjectForKey:ownThread];
        }
    }
}

-(void) voidReadTransaction:(monal_void_block_t) operations
{
    [self idReadTransaction:^(void){
        operations();
        return (NSObject*)nil;      //dummy return value
    }];
}

-(BOOL) boolReadTransaction:(monal_sqlite_bool_operations_t) operations
{
    return [[self idReadTransaction:^(void){
        return [NSNumber numberWithBool:operations()];
    }] boolValue];
}

-(id) idReadTransaction:(monal_sqlite_operations_t) operations
{
    [self beginReadTransaction];
    id retval = operations();
    [self endReadTransaction];
    return retval;
}

-(void) beginReadTransaction
{
    [self testThreadInstanceForQuery:@"beginReadTransaction" andArguments:nil];
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    threadData[@"_sqliteTransactionsRunning"][_dbFile] = [NSNumber numberWithInt:([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] + 1)];
    if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] > 1)
        return;			//begin only outermost transaction
    BOOL retval;
    do {
        retval = [self executeNonQuery:@"BEGIN DEFERRED TRANSACTION;" andArguments:@[] withException:NO];
        if(!retval)
        {
            [NSThread sleepForTimeInterval:0.001f];		//wait one millisecond and retry again
            @synchronized(currentTransactions) {
                DDLogWarn(@"Retrying read transaction start: %@", @{
                    @"newReadTransactionVia": [NSThread callStackSymbols],
                    @"currentTransactions": currentTransactions,
                });
            }
        }
    } while(!retval);
    threadData[@"_sqliteStartedReadTransaction"][_dbFile] = @YES;
    NSString* ownThread = [self calcThreadName];
    @synchronized(currentTransactions) {
        currentTransactions[ownThread] = [NSThread callStackSymbols];
    }
}

-(void) endReadTransaction
{
    [self testThreadInstanceForQuery:@"endReadTransaction" andArguments:nil];
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    threadData[@"_sqliteTransactionsRunning"][_dbFile] = [NSNumber numberWithInt:[threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] - 1];
    if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] == 0)
    {
        [self executeNonQuery:@"COMMIT;" andArguments:@[] withException:YES];        //commit only outermost transaction
        threadData[@"_sqliteStartedReadTransaction"][_dbFile] = @NO;
        NSString* ownThread = [self calcThreadName];
        @synchronized(currentTransactions) {
            [currentTransactions removeObjectForKey:ownThread];
        }
    }
}

-(id) executeScalar:(NSString*) query
{
    return [self executeScalar:query andArguments:@[]];
}

-(id) executeScalar:(NSString*) query andArguments:(NSArray*) args
{
    [self checkQuery:query];
    [self testThreadInstanceForQuery:query andArguments:args];
    [self testTransactionsForQuery:query andArguments:args];
    
    return [self internalExecuteScalar:query andArguments:args];
}

-(NSArray*) executeScalarReader:(NSString*) query
{
    return [self executeScalarReader:query andArguments:@[]];
}

-(NSArray*) executeScalarReader:(NSString*) query andArguments:(NSArray*) args
{
    [self checkQuery:query];
    [self testThreadInstanceForQuery:query andArguments:args];
    [self testTransactionsForQuery:query andArguments:args];
    
    NSMutableArray* __block toReturn = [NSMutableArray new];
    sqlite3_stmt* statement = [self prepareQuery:query withArgs:args];
    if(statement != NULL)
    {
        int step;
        while((step=sqlite3_step(statement)) == SQLITE_ROW)
        {
            NSObject* returnData = [self getColumn:0 ofStatement:statement];
            //accessing an unset key in NSDictionary will return nil (nil can not be inserted directly into the dictionary)
            if(returnData)
                [toReturn addObject:returnData];
        }
        sqlite3_finalize(statement);
        if(step != SQLITE_DONE)
            [self throwErrorForQuery:query andArguments:args];
    }
    else
    {
        //if noting else
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
    [self checkQuery:query];
    [self testThreadInstanceForQuery:query andArguments:args];
    [self testTransactionsForQuery:query andArguments:args];

    NSMutableArray* toReturn = [NSMutableArray new];
    sqlite3_stmt* statement = [self prepareQuery:query withArgs:args];
    if(statement != NULL)
    {
        int step;
        while((step=sqlite3_step(statement)) == SQLITE_ROW)
        {
            NSMutableDictionary* row = [NSMutableDictionary new];
            int counter = 0;
            while(counter < sqlite3_column_count(statement))
            {
                NSString* columnName = [NSString stringWithUTF8String:sqlite3_column_name(statement, counter)];
                NSObject* returnData = [self getColumn:counter ofStatement:statement];
                //accessing an unset key in NSDictionary will return nil (nil can not be inserted directly into the dictionary)
                if(returnData)
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
        [self throwErrorForQuery:query andArguments:args];
    }
    return toReturn;
}

-(BOOL) executeNonQuery:(NSString*) query
{
    [self testThreadInstanceForQuery:query andArguments:@[]];
    [self testTransactionsForQuery:query andArguments:@[]];
    return [self executeNonQuery:query andArguments:@[] withException:YES];
}

-(BOOL) executeNonQuery:(NSString*) query andArguments:(NSArray*) args
{
    [self testThreadInstanceForQuery:query andArguments:args];
    [self testTransactionsForQuery:query andArguments:args];
    return [self executeNonQuery:query andArguments:args withException:YES];
}

-(NSNumber*) lastInsertId
{
    [self testThreadInstanceForQuery:@"lastInsertId" andArguments:nil];
    [self testTransactionsForQuery:@"lastInsertId" andArguments:nil];
    return [NSNumber numberWithInt:(int)sqlite3_last_insert_rowid(self->_database)];
}

-(void) enableWAL
{
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    MLAssert([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] == 0, @"Could not enable wal, inside transaction!", (@{
        @"threadDictionary": threadData
    }));
    NSString* mode = [self internalExecuteScalar:@"PRAGMA journal_mode;" andArguments:@[]];
    if([mode isEqualToString:@"wal"])
        return;
    mode = [self internalExecuteScalar:@"PRAGMA journal_mode=WAL;" andArguments:@[]];
    if([mode isEqualToString:@"wal"])
        DDLogWarn(@"Transaction mode set to WAL");
    else
        @throw [NSException exceptionWithName:@"SQLite3Exception" reason:@"Failed to enable sqlite WAL mode" userInfo:@{
            @"file": _dbFile,
            @"mode": mode
        }];
}

-(void) checkpointWal
{
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    //being inside a transaction is non-fatal, the db file will just not be up to date then
    if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] == 0)
    {
        NSArray* result = [self executeReader:@"PRAGMA wal_checkpoint(TRUNCATE);"];
        DDLogInfo(@"Chekpointing returned: %@", result);
    }
    else
        DDLogError(@"Could not checkpoint wal, inside transaction: %@", threadData);
}

// optimize db
-(void) vacuum
{
    //trying to vaccum the db inside a transaction is non-fatal, the db file will just not be shrinked then
    DDLogDebug(@"Vacuum DB");
    NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
    if([threadData[@"_sqliteTransactionsRunning"][_dbFile] intValue] == 0)
    {
        [self executeNonQuery:@"VACUUM;" andArguments:@[] withException:YES];
        DDLogDebug(@"Vacuum DB success");
    }
    else
        DDLogError(@"Could not vaccum db, inside transaction: %@", threadData);
}

@end
