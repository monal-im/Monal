//
//  DataLayer.m
//  SworIM
//
//  Created by Anurodh Pokharel on 3/28/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "DataLayer.h"
#import "HelperTools.h"

@interface DataLayer()

@property (nonatomic, strong) NSDateFormatter *dbFormatter;

@end

static BOOL _version_check_done = NO;

@implementation DataLayer


NSString* const kAccountID = @"account_id";
NSString* const kAccountState = @"account_state";
NSString* const kAccountHibernate = @"account_hibernate";

//used for account rows
NSString *const kDomain = @"domain";
NSString *const kEnabled = @"enabled";

NSString *const kServer = @"server";
NSString *const kPort = @"other_port";
NSString *const kResource = @"resource";
NSString *const kDirectTLS = @"directTLS";
NSString *const kSelfSigned = @"selfsigned";

NSString *const kUsername = @"username";
NSString *const kFullName = @"full_name";

NSString *const kMessageType = @"messageType";
NSString *const kMessageTypeGeo = @"Geo";
NSString *const kMessageTypeImage = @"Image";
NSString *const kMessageTypeMessageDraft = @"MessageDraft";
NSString *const kMessageTypeStatus = @"Status";
NSString *const kMessageTypeText = @"Text";
NSString *const kMessageTypeUrl = @"Url";

// used for contact rows
NSString *const kContactName = @"buddy_name";
NSString *const kCount = @"count";


+(void) initialize
{
    NSFileManager* fileManager = [NSFileManager defaultManager];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writableDBPath = [documentsDirectory stringByAppendingPathComponent:@"sworim.sqlite"];
    DDLogInfo(@"initialize: db path %@", writableDBPath);
    if( ![fileManager fileExistsAtPath:writableDBPath])
    {
        // The writable database does not exist, so copy the default to the appropriate location.
        NSString *defaultDBPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"sworim.sqlite"];
        NSError* error;
        [fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:&error];
    }
#if TARGET_OS_IPHONE
    NSDictionary *attributes =@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication};
    NSError *error;
    [fileManager setAttributes:attributes ofItemAtPath:writableDBPath error:&error];
#endif

    //  sqlite3_shutdown();
    if (sqlite3_config(SQLITE_CONFIG_MULTITHREAD) == SQLITE_OK) {
        DDLogInfo(@"initialize: Database configured ok");
    } else DDLogInfo(@"initialize: Database not configured ok");

    sqlite3_initialize();
}

//every thread gets its own instance having its own db connection
//this allows for concurrent reads/writes
+(DataLayer*) sharedInstance
{
	NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
	if(threadData[@"_dbInstanceForThread"])
		return threadData[@"_dbInstanceForThread"];
	DataLayer* newInstance = [DataLayer alloc];
	[newInstance openDB];
	threadData[@"_dbInstanceForThread"] = newInstance;						//save thread-local instance
	threadData[@"_dbTransactionRunning"] = [NSNumber numberWithInt:0];		//init data for nested transactions
	return newInstance;
}

#pragma mark  - V1 low level
-(NSObject*) executeScalar:(NSString*) query andArguments:(NSArray*) args
{
    if(!query)
        return nil;
    NSObject* __block toReturn;
	sqlite3_stmt *statement;
	if (sqlite3_prepare_v2(self->database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
		sqlite3_reset(statement);
		[args enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			if([obj isKindOfClass:[NSNumber class]])
			{
				NSNumber *number = (NSNumber *) obj;
				if(sqlite3_bind_double(statement, (signed)idx+1, [number doubleValue]) != SQLITE_OK)
				{
					DDLogError(@"number bind error");

				}
			}
			else if([obj isKindOfClass:[NSString class]])
			{
				NSString *text = (NSString *) obj;

				if(sqlite3_bind_text(statement, (signed)idx+1, [text cStringUsingEncoding:NSUTF8StringEncoding], -1, SQLITE_TRANSIENT) != SQLITE_OK) {
					DDLogError(@"string bind error");

				};
			}
		}];

		if (sqlite3_step(statement) == SQLITE_ROW)
		{
			switch(sqlite3_column_type(statement,0))
			{
				// SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
				case (SQLITE_INTEGER):
				{
					NSNumber* returnInt= [NSNumber numberWithInt:sqlite3_column_int(statement, 0)];
					while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
					toReturn= returnInt;
					break;
				}

				case (SQLITE_FLOAT):
				{
					NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement, 0)];
					while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
					toReturn= returnInt;
					break;
				}

				case (SQLITE_TEXT):
				{
					NSString* returnString = [NSString stringWithUTF8String:(const char* _Nonnull) sqlite3_column_text(statement, 0)];
					//	DDLogVerbose(@"got %@", returnString);
					while(sqlite3_step(statement) == SQLITE_ROW ){} //clear
					toReturn= [returnString stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
					break;

				}

				case (SQLITE_BLOB):
				{
					const char* bytes=(const char* _Nonnull)sqlite3_column_blob(statement, 0);
					int size = sqlite3_column_bytes(statement,0);
					NSData* returnData = [NSData dataWithBytes:bytes length:size];
					while(sqlite3_step(statement) == SQLITE_ROW) {} //clear
					toReturn= returnData;

					break;
				}

				case (SQLITE_NULL):
				{
					DDLogDebug(@"return nil with sql null: %@", query);
					while(sqlite3_step(statement) == SQLITE_ROW) {} //clear
					toReturn= nil;
					break;
				}

			}
		} else {
           // DDLogVerbose(@"return nil with no row");
			toReturn= nil;
        };
	} else{
		//if noting else
		DDLogVerbose(@"returning nil with out OK %@", query);
		toReturn= nil;
	}
    sqlite3_finalize(statement);
    return toReturn;
}

-(NSArray*) executeReader:(NSString*) query andArguments:(NSArray *) args
{
    if(!query) return nil;
    NSMutableArray* __block toReturn = [[NSMutableArray alloc] init];
	sqlite3_stmt *statement;
	if (sqlite3_prepare_v2(self->database, [query cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {

		sqlite3_reset(statement);
		[args enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			if([obj isKindOfClass:[NSNumber class]])
			{
				NSNumber *number = (NSNumber *) obj;
				if(sqlite3_bind_double(statement, (signed)idx+1, [number doubleValue]) != SQLITE_OK)
				{
					DDLogError(@"number bind error");

				}
			}
			else if([obj isKindOfClass:[NSString class]])
			{
				NSString *text = (NSString *) obj;

				if(sqlite3_bind_text(statement, (signed)idx+1, [text cStringUsingEncoding:NSUTF8StringEncoding], -1, SQLITE_TRANSIENT) != SQLITE_OK) {
					DDLogError(@"string bind error");

				};
			}
		}];

		while (sqlite3_step(statement) == SQLITE_ROW) {
			NSMutableDictionary* row = [[NSMutableDictionary alloc] init];
			int counter = 0;
			while(counter < sqlite3_column_count(statement))
			{
				NSString* columnName = [NSString stringWithUTF8String:sqlite3_column_name(statement, counter)];

				switch(sqlite3_column_type(statement, counter))
				{
						// SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
					case (SQLITE_INTEGER):
					{
						NSNumber* returnInt = [NSNumber numberWithInt:sqlite3_column_int(statement, counter)];
						[row setObject:returnInt forKey:columnName];
						break;
					}

					case (SQLITE_FLOAT):
					{
						NSNumber* returnDouble = [NSNumber numberWithDouble:sqlite3_column_double(statement, counter)];
						[row setObject:returnDouble forKey:columnName];
						break;
					}

					case (SQLITE_TEXT):
					{
						NSString* returnString = [NSString stringWithUTF8String:(const char* _Nonnull)sqlite3_column_text(statement, counter)];
						[row setObject:returnString forKey:columnName];
						break;

					}

					case (SQLITE_BLOB):
					{
						const char* bytes = (const char* _Nonnull)sqlite3_column_blob(statement, counter);
						int size = sqlite3_column_bytes(statement, counter);
						NSData* returnData = [NSData dataWithBytes:bytes length:size];

						[row setObject:returnData forKey:columnName];
						break;
					}

					case (SQLITE_NULL):
					{
						//DDLogDebug(@"return nil with sql null: %@", query);
						[row setObject:@"" forKey:columnName];
						break;
					}

				}
				counter++;
			}

			[toReturn addObject:row];
		}
	} else {
		DDLogVerbose(@"reader nil with sql not ok: %@", query);
		toReturn = nil;
	}
    sqlite3_finalize(statement);
    return toReturn;
}

-(BOOL) executeNonQuery:(NSString*) query andArguments:(NSArray *) args
{
    if(!query) return NO;
    BOOL __block toReturn;
	sqlite3_stmt *statement;
	if (sqlite3_prepare_v2(self->database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK)
	{
		[args enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			if([obj isKindOfClass:[NSNumber class]])
			{
				NSNumber* number = (NSNumber *) obj;
				if(sqlite3_bind_double(statement, (signed)idx+1, [number doubleValue]) != SQLITE_OK)
				{
					DDLogError(@"number bind error");

				}
			}
			else if([obj isKindOfClass:[NSString class]])
			{
				NSString* text = (NSString *) obj;

				if(sqlite3_bind_text(statement, (signed)idx+1, [text cStringUsingEncoding:NSUTF8StringEncoding], -1, SQLITE_TRANSIENT) != SQLITE_OK) {
					DDLogError(@"string bind error");
				};
			}

			else if([obj isKindOfClass:[NSData class]])
			{
				NSData* data = (NSData *) obj;

				if(sqlite3_bind_blob(statement, (signed)idx+1, [data bytes], (int)data.length, SQLITE_TRANSIENT) != SQLITE_OK) {
					DDLogError(@"string bind error");
				};
			}
		}];

		if(sqlite3_step(statement)==SQLITE_DONE)
			toReturn=YES;
		else
			toReturn=NO;
	}

	else
	{
		DDLogError(@"nonquery returning NO with out OK %@", query);
		toReturn=NO;
	}
    sqlite3_finalize(statement);
    return toReturn;
}

#pragma mark - V2 low level

-(void) beginWriteTransaction
{
	NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
	threadData[@"_dbTransactionRunning"] = [NSNumber numberWithInt:[threadData[@"_dbTransactionRunning"] intValue] + 1];
	if([threadData[@"_dbTransactionRunning"] intValue] > 1)
		return;			//begin only outermost transaction
	BOOL retval;
	do {
		retval=[self executeNonQuery:@"BEGIN IMMEDIATE TRANSACTION;" andArguments:nil];
		if(!retval)
			[NSThread sleepForTimeInterval:0.001f];		//wait one millisecond and retry again
	} while(!retval);
}

-(void) endWriteTransaction
{
	NSMutableDictionary* threadData = [[NSThread currentThread] threadDictionary];
	threadData[@"_dbTransactionRunning"] = [NSNumber numberWithInt:[threadData[@"_dbTransactionRunning"] intValue] - 1];
	if([threadData[@"_dbTransactionRunning"] intValue] == 0)
		[self executeNonQuery:@"COMMIT;" andArguments:nil];		//commit only outermost transaction
}

-(void) executeScalar:(NSString*) query withCompletion: (void (^)(NSObject *))completion
{
    [self executeScalar:query andArguments:nil withCompletion:completion];
}

-(void) executeReader:(NSString*) query withCompletion: (void (^)(NSMutableArray *))completion;
{
    [self executeReader:query andArguments:nil withCompletion:completion];
}

-(void) executeNonQuery:(NSString*) query withCompletion: (void (^)(BOOL))completion
{
    [self executeNonQuery:query andArguments:nil withCompletion:completion];
}

-(void) executeScalar:(NSString*) query andArguments:(NSArray *) args withCompletion: (void (^)(NSObject *))completion
{
    if(!query)
    {
        if(completion) {
            completion(nil);
        }
    }

	NSObject* toReturn;
	sqlite3_stmt *statement;
	if (sqlite3_prepare_v2(self->database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
		sqlite3_reset(statement);
		[args enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			if([obj isKindOfClass:[NSNumber class]])
			{
				NSNumber* number = (NSNumber *) obj;
				if(sqlite3_bind_double(statement, (signed)idx+1, [number doubleValue]) != SQLITE_OK)
				{
					DDLogError(@"number bind error");

				}
			}
			else if([obj isKindOfClass:[NSString class]])
			{
				NSString* text = (NSString *) obj;

				if(sqlite3_bind_text(statement, (signed)idx+1, [text cStringUsingEncoding:NSUTF8StringEncoding], -1, SQLITE_TRANSIENT) != SQLITE_OK) {
					DDLogError(@"string bind error");

				};
			}
			else if([obj isKindOfClass:[NSData class]])
			{
				NSData* data = (NSData *) obj;

				if(sqlite3_bind_blob(statement, (signed)idx+1,[data bytes], data.length, SQLITE_TRANSIENT) != SQLITE_OK) {
					DDLogError(@"string bind error");

				};
			}
		}];

		if (sqlite3_step(statement) == SQLITE_ROW)
		{
			switch(sqlite3_column_type(statement, 0))
			{
				// SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
				case (SQLITE_INTEGER):
				{
					NSNumber* returnInt= [NSNumber numberWithInt:sqlite3_column_int(statement, 0)];
					while(sqlite3_step(statement) == SQLITE_ROW) {} //clear
					toReturn = returnInt;
					break;
				}

				case (SQLITE_FLOAT):
				{
					NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement, 0)];
					while(sqlite3_step(statement) == SQLITE_ROW) {} //clear
					toReturn = returnInt;
					break;
				}

				case (SQLITE_TEXT):
				{
					NSString* returnString = [NSString stringWithUTF8String:(const char* _Nonnull)sqlite3_column_text(statement, 0)];
					//    DDLogVerbose(@"got %@", returnString);
					while(sqlite3_step(statement) == SQLITE_ROW ){} //clear
					toReturn = returnString;
					break;

				}

				case (SQLITE_BLOB):
				{
					const char* bytes = (const char* _Nonnull)sqlite3_column_blob(statement,0);
					int size = sqlite3_column_bytes(statement,0);
					NSData* returnData = [NSData dataWithBytes:bytes length:size];
					while(sqlite3_step(statement) == SQLITE_ROW) {} //clear
					toReturn = returnData;

					break;
				}

				case (SQLITE_NULL):
				{
					DDLogDebug(@"return nil with sql null: %@", query);
					while(sqlite3_step(statement) == SQLITE_ROW) {} //clear
					toReturn = nil;
					break;
				}

			}
		} else {
         //   DDLogVerbose(@"return nil with no row");
			toReturn = nil;
        };
	}
	else{
		//if noting else
		DDLogVerbose(@"returning nil with out OK %@", query);
		toReturn = nil;
	}

	sqlite3_finalize(statement);

	if(completion) {
		completion(toReturn);
	}
}

-(void) executeReader:(NSString*) query andArguments:(NSArray *) args withCompletion: (void (^)(NSMutableArray *))completion
{
    if(!query)
    {
        if(completion) {
            completion(nil);
        }
    }

	NSMutableArray* toReturn =  [[NSMutableArray alloc] init] ;

	sqlite3_stmt *statement;
	if (sqlite3_prepare_v2(self->database, [query cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
		sqlite3_reset(statement);
		[args enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			if([obj isKindOfClass:[NSNumber class]])
			{
				NSNumber *number = (NSNumber *) obj;
				if(sqlite3_bind_double(statement, (signed)idx+1, [number doubleValue]) != SQLITE_OK)
				{
					DDLogError(@"number bind error");

				}
			}
			else if([obj isKindOfClass:[NSString class]])
			{
				NSString *text = (NSString*) obj;

				if(sqlite3_bind_text(statement, (signed)idx+1,[text cStringUsingEncoding:NSUTF8StringEncoding], -1, SQLITE_TRANSIENT) != SQLITE_OK) {
					DDLogError(@"string bind error");

				};
			}
		}];

		while (sqlite3_step(statement) == SQLITE_ROW) {
			NSMutableDictionary* row = [[NSMutableDictionary alloc] init];
			int counter = 0;
			while(counter < sqlite3_column_count(statement) )
			{
				NSString* columnName= [NSString stringWithUTF8String:sqlite3_column_name(statement, counter)];

				switch(sqlite3_column_type(statement, counter))
				{
						// SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
					case (SQLITE_INTEGER):
					{
						NSNumber* returnInt = [NSNumber numberWithInt:sqlite3_column_int(statement, counter)];
						[row setObject:returnInt forKey:columnName];
						break;
					}

					case (SQLITE_FLOAT):
					{
						NSNumber* returnInt = [NSNumber numberWithDouble:sqlite3_column_double(statement, counter)];
						[row setObject:returnInt forKey:columnName];
						break;
					}

					case (SQLITE_TEXT):
					{
						NSString* returnString = [NSString stringWithUTF8String:(const char* _Nonnull)sqlite3_column_text(statement, counter)];
						[row setObject:[returnString stringByReplacingOccurrencesOfString:@"''" withString:@"'"] forKey:columnName];
						break;

					}

					case (SQLITE_BLOB):
					{

						const char* bytes=(const char* _Nonnull)sqlite3_column_blob(statement, counter);
						int size = sqlite3_column_bytes(statement, counter);
						NSData* returnData = [NSData dataWithBytes:bytes length:size];


						[row setObject:returnData forKey:columnName];
						break;
					}

					case (SQLITE_NULL):
					{
						//DDLogDebug(@"return nil with sql null: %@", query);

						[row setObject:@"" forKey:columnName];
						break;
					}

				}

				counter++;
			}

			[toReturn addObject:row];
		}
	}
	else
	{
		DDLogVerbose(@"reader nil with sql not ok: %@", query );
		toReturn= nil;
	}

	sqlite3_finalize(statement);

	if(completion) {
		completion(toReturn);
	}
}

-(void) executeNonQuery:(NSString*) query andArguments:(NSArray *) args  withCompletion: (void (^)(BOOL))completion
{
    if(!query)
    {
        if(completion) {
            completion(NO);
        }
    }

    BOOL __block toReturn;
	sqlite3_stmt *statement;
	if (sqlite3_prepare_v2(self->database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK)
	{
		sqlite3_reset(statement);
		[args enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			if([obj isKindOfClass:[NSNumber class]])
			{
				NSNumber* number = (NSNumber *) obj;
				if(sqlite3_bind_double(statement, (signed)idx+1, [number doubleValue]) != SQLITE_OK)
				{
					DDLogError(@"number bind error");
				}
			}
			else if([obj isKindOfClass:[NSString class]])
			{
				NSString* text = (NSString *) obj;

				if(sqlite3_bind_text(statement, (signed)idx+1,[text cStringUsingEncoding:NSUTF8StringEncoding], -1, SQLITE_TRANSIENT) != SQLITE_OK) {
					DDLogError(@"string bind error");
				};
			}
			else if([obj isKindOfClass:[NSData class]])
			{
				NSData *data = (NSData *) obj;

				if(sqlite3_bind_blob(statement, (signed)idx+1,[data bytes], data.length, SQLITE_TRANSIENT) != SQLITE_OK) {
					DDLogError(@"string bind error");
				};
			}
		}];

        if(sqlite3_step(statement) == SQLITE_DONE) {
			toReturn=YES;
        } else {
			toReturn=NO;
        }
	} else {
		DDLogError(@"nonquery returning NO with out OK %@", query);
		toReturn=NO;
	}

	sqlite3_finalize(statement);

	if (completion)
	{
		completion(toReturn);
	}
}

#pragma mark account commands

-(void) accountListWithCompletion: (void (^)(NSArray* result))completion
{
    NSString* query = [NSString stringWithFormat:@"select * from account order by account_id asc"];
    [self executeReader:query withCompletion:^(NSMutableArray* result) {
        if(completion) completion(result);
    }];
}

-(void) accountListEnabledWithCompletion: (void (^)(NSArray* result))completion
{
    NSString* query = [NSString stringWithFormat:@"select * from account where enabled=1 order by account_id asc"];
    [self executeReader:query withCompletion:^(NSMutableArray* result) {
        if(completion) completion(result);
    }];
}

-(NSArray*) enabledAccountList
{
    NSString* query = [NSString stringWithFormat:@"select * from account where enabled=1 order by account_id asc"];
    NSArray* toReturn = [self executeReader:query andArguments:nil] ;

    if(toReturn!=nil)
    {
        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count]);

        return toReturn;
    }
    else
    {
        DDLogError(@"account list  is empty or failed to read");

        return nil;
    }
}

-(BOOL) isAccountEnabled:(NSString*) accountNo
{
    NSArray* enabledAccounts = [self enabledAccountList];
    for (NSDictionary* account in enabledAccounts)
    {
        if([[account objectForKey:@"account_id"] integerValue] == [accountNo integerValue])
        {
            return YES;
        }
    }

    return NO;
}

-(void) accountIDForUser:(NSString *) user andDomain:(NSString *) domain withCompletion:(void (^)(NSString *result))completion
{
    if(!user && !domain) return;
    NSString* cleanUser =user;
    NSString* cleanDomain = domain;

    if(!cleanDomain) cleanDomain= @"";
    if(!cleanUser) cleanUser= @"";

    NSString *query = [NSString stringWithFormat:@"select account_id from account where domain=? and username=?"];
    [self executeReader:query andArguments:@[cleanDomain, cleanUser] withCompletion:^(NSMutableArray * result) {
        NSString* toreturn;
        if(result.count>0) {
            NSNumber* account = [result[0] objectForKey:@"account_id"];
            toreturn = [NSString stringWithFormat:@"%@", account];
        }
        if(completion) completion(toreturn);
    }];
}

-(void) doesAccountExistUser:(NSString*) user andDomain:(NSString *) domain withCompletion:(void (^)(BOOL result))completion
{
    NSString* query = [NSString stringWithFormat:@"select * from account where domain=? and username=?"];
    [self executeReader:query andArguments:@[domain, user] withCompletion:^(NSMutableArray * result) {
        if(completion) completion(result.count>0);
    }];
}

-(void) detailsForAccount:(NSString*) accountNo withCompletion:(void (^)(NSArray* result))completion
{
    if(!accountNo) return;
    NSString* query = [NSString stringWithFormat:@"select * from account where account_id=?"];
    NSArray* params = @[accountNo];
    [self executeReader:query andArguments:params withCompletion:^(NSMutableArray *result) {
        if(result!=nil)
        {
            DDLogVerbose(@" count: %lu", (unsigned long)[result count]);
        }
        else
        {
            DDLogError(@"account list is empty or failed to read");
        }

        if(completion) completion(result);
    }];
}

-(void) updateAccounWithDictionary:(NSDictionary *) dictionary andCompletion:(void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"update account set server=?, other_port=?, username=?, resource=?, domain=?, enabled=?, selfsigned=?, directTLS=? where account_id=?"];

    NSString* server = (NSString *) [dictionary objectForKey:kServer];
    NSString* port = (NSString *)[dictionary objectForKey:kPort];
    NSArray* params = @[server == nil ? @"" : server,
                       port == nil ? @"5222" : port,
                       ((NSString*)[dictionary objectForKey:kUsername]),
                       ((NSString*)[dictionary objectForKey:kResource]),
                       ((NSString*)[dictionary objectForKey:kDomain]),
                       [dictionary objectForKey:kEnabled],
                       [dictionary objectForKey:kSelfSigned],
                       [dictionary objectForKey:kDirectTLS],
                       [dictionary objectForKey:kAccountID]
    ];

    [self executeNonQuery:query andArguments:params withCompletion:completion];
}

-(void) addAccountWithDictionary:(NSDictionary*) dictionary andCompletion: (void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"insert into account (server, other_port, resource, domain, enabled, selfsigned, directTLS, username) values(?, ?, ?, ?, ?, ?, ?, ?)"];
    
    NSString* server = (NSString*) [dictionary objectForKey:kServer];
    NSString* port = (NSString*)[dictionary objectForKey:kPort];
    NSArray* params = @[
        server == nil ? @"" : server,
        port == nil ? @"5222" : port,
        ((NSString *)[dictionary objectForKey:kResource]),
        ((NSString *)[dictionary objectForKey:kDomain]),
        [dictionary objectForKey:kEnabled] ,
        [dictionary objectForKey:kSelfSigned],
        [dictionary objectForKey:kDirectTLS],
        ((NSString *)[dictionary objectForKey:kUsername])
    ];
    [self executeNonQuery:query andArguments:params withCompletion:completion];
}

-(BOOL) removeAccount:(NSString*) accountNo
{
    // remove all other traces of the account_id in one transaction
    [self beginWriteTransaction];

    NSString* query1 = [NSString stringWithFormat:@"delete from buddylist  where account_id=%@;", accountNo];
    [self executeNonQuery:query1 andArguments:nil];

    NSString* query3= [NSString stringWithFormat:@"delete from message_history  where account_id=%@;", accountNo];
    [self executeNonQuery:query3 andArguments:nil];

    NSString* query4= [NSString stringWithFormat:@"delete from activechats  where account_id=%@;", accountNo];
    [self executeNonQuery:query4 andArguments:nil];

    NSString* query = [NSString stringWithFormat:@"delete from account  where account_id=%@;", accountNo];
    BOOL lastResult = [self executeNonQuery:query andArguments:nil];

    [self endWriteTransaction];

    return (lastResult != NO);
}

-(BOOL) disableEnabledAccount:(NSString*) accountNo
{

    NSString* query = [NSString stringWithFormat:@"update account set enabled=0 where account_id=%@  ", accountNo];
    return ([self executeNonQuery:query andArguments:nil]!=NO);
}

-(NSMutableDictionary *) readStateForAccount:(NSString*) accountNo
{
    if(!accountNo) return nil;
    NSString* query = [NSString stringWithFormat:@"SELECT state from account where account_id=?"];
    NSArray* params = @[accountNo];
    NSData* data = (NSData*)[self executeScalar:query andArguments:params];
    if(data)
    {
        NSMutableDictionary* dic=(NSMutableDictionary *) [NSKeyedUnarchiver unarchiveObjectWithData:data];
        return dic;
    }
    return nil;
}

-(void) persistState:(NSMutableDictionary *) state forAccount:(NSString*) accountNo
{
    if(!accountNo || !state) return;
    NSString* query = [NSString stringWithFormat:@"update account set state=? where account_id=?"];
    NSArray *params = @[[NSKeyedArchiver archivedDataWithRootObject:state], accountNo];
    [self executeNonQuery:query andArguments:params withCompletion:nil];
}

#pragma mark contact Commands

-(void) addContact:(NSString*) contact forAccount:(NSString*) accountNo fullname:(NSString*) fullName nickname:(NSString*) nickName andMucNick:(NSString*) mucNick withCompletion: (void (^)(BOOL))completion
{
    // no blank full names
    NSString* actualfull = fullName;
    if([[actualfull stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0)
        actualfull = contact;

    NSString* query = [NSString stringWithFormat:@"insert into buddylist ('account_id', 'buddy_name', 'full_name', 'nick_name', 'new', 'online', 'dirty', 'muc', 'muc_nick') values(?, ?, ?, ?, 1, 0, 0, ?, ?);"];

    if(!(accountNo && contact && actualfull && nickName)) {
        if(completion)
        {
            completion(NO);
        }
    } else  {
        NSArray* params = @[accountNo, contact, actualfull, nickName, mucNick?@1:@0, mucNick?mucNick:@""];
        [self executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {
            if(completion)
            {
                completion(success);
            }
        }];
    }
}

-(void) removeBuddy:(NSString*) buddy forAccount:(NSString*) accountNo
{
    [self beginWriteTransaction];
    //clean up logs
    [self messageHistoryClean:buddy :accountNo];

    NSString* query = [NSString stringWithFormat:@"delete from buddylist where account_id=? and buddy_name=?;"];
    NSArray* params = @[accountNo, buddy];

    [self executeNonQuery:query andArguments:params withCompletion:nil];

    [self setSubscription:kSubNone andAsk:@"" forContact:buddy andAccount:accountNo];
    [self endWriteTransaction];
}

-(BOOL) clearBuddies:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"delete from buddylist where account_id=%@;", accountNo];
    return ([self executeNonQuery:query andArguments:nil] != NO);
}

#pragma mark Buddy Property commands

-(BOOL) resetContactsForAccount:(NSString*) accountNo
{
    if(!accountNo) return NO;
	[self beginWriteTransaction];
    NSString* query2 = [NSString stringWithFormat:@"delete from buddy_resources where buddy_id in (select buddy_id from buddylist where account_id=?)"];
    NSArray* params = @[accountNo];
    [self executeNonQuery:query2 andArguments:params];


    NSString* query = [NSString stringWithFormat:@"update buddylist set dirty=0, new=0, online=0, state='offline', status='' where account_id=?"];
    BOOL retval = [self executeNonQuery:query andArguments:params];
	[self endWriteTransaction];

    return (retval != NO);
}

-(void) contactForUsername:(NSString*) username forAccount: (NSString*) accountNo withCompletion: (void (^)(NSArray *))completion
{
    if(!username || !accountNo) return;
    NSString* query = query = [NSString stringWithFormat:@"select buddy_name, state, status, filename, 0, ifnull(full_name, buddy_name) as full_name, nick_name, account_id, MUC, muc_subject, muc_nick , full_name as raw_full, subscription, ask from buddylist where buddy_name=? and account_id=?"];
    NSArray *params= @[username, accountNo];

    [self executeReader:query andArguments:params  withCompletion:^(NSArray * results) {
        if(results!=nil)
        {
            DDLogVerbose(@" count: %lu",  (unsigned long)[results count]);

        }
        else
        {
            DDLogError(@"buddylist is empty or failed to read");
        }

        NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
        [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic = (NSDictionary *) obj;
            [toReturn addObject:[MLContact contactFromDictionary:dic]];
        }];

        if(completion) {
            completion(toReturn);
        }
    }];
}


-(NSArray*) searchContactsWithString:(NSString*) search
{
    NSString *likeString = [NSString stringWithFormat:@"%%%@%%", search];
    NSString* query = @"";
    query = [NSString stringWithFormat:@"select buddy_name, state, status, filename, 0 as 'count', ifnull(full_name, buddy_name) as full_name, account_id, online from buddylist where buddy_name like ? or full_name like ? order by full_name COLLATE NOCASE asc "];

    NSArray *params = @[likeString, likeString];

    //DDLogVerbose(query);
    NSArray* results = [self executeReader:query andArguments:params];

    NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
          [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
              NSDictionary *dic = (NSDictionary *) obj;
              [toReturn addObject:[MLContact contactFromDictionary:dic]];
          }];

    if(toReturn != nil)
    {
        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count]);
        return toReturn;
    }
    else
    {
        DDLogError(@"buddylist is empty or failed to read");
        return nil;
    }
}

-(void) onlineContactsSortedBy:(NSString*) sort withCompeltion: (void (^)(NSMutableArray *))completion
{
    NSString* query = @"";

    if([sort isEqualToString:@"Name"])
    {
        query = [NSString stringWithFormat:@"select buddy_name, state, status,filename, 0 as 'count', ifnull(full_name, buddy_name) as full_name, nick_name, MUC, muc_subject, muc_nick, account_id from buddylist where online=1 and subscription='both'  order by full_name COLLATE NOCASE asc"];
    }

    if([sort isEqualToString:@"Status"])
    {
        query = [NSString stringWithFormat:@"select buddy_name, state, status, filename, 0 as 'count', ifnull(full_name, buddy_name) as full_name, nick_name, MUC, muc_subject, muc_nick, account_id from buddylist where online=1 and subscription='both' order by state, full_name COLLATE NOCASE asc"];
    }

    [self executeReader:query withCompletion:^(NSMutableArray *results) {

        NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
        [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic = (NSDictionary *) obj;
            [toReturn addObject:[MLContact contactFromDictionary:dic]];
        }];

        if(completion) completion(toReturn);
    }];
}

-(void) offlineContactsWithCompletion: (void (^)(NSMutableArray *))completion
{
    NSString* query = [NSString stringWithFormat:@"select buddy_name, A.state, status, filename, 0, ifnull(full_name, buddy_name) as full_name,nick_name, a.account_id, MUC, muc_subject, muc_nick from buddylist as A inner join account as b  on a.account_id=b.account_id  where  online=0 and enabled=1 order by full_name COLLATE NOCASE "];
    [self executeReader:query withCompletion:^(NSMutableArray *results) {

        NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
        [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic = (NSDictionary *) obj;
            [toReturn addObject:[MLContact contactFromDictionary:dic]];
        }];

        if(completion) completion(toReturn);
    }];
}

#pragma mark entity capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andAccountNo:(NSString*) acctNo
{
    NSString* query = [NSString stringWithFormat:@"select count(*) from buddylist as a inner join buddy_resources as b on a.buddy_id=b.buddy_id inner join ver_info as c on b.ver=c.ver where buddy_name=? and account_id=? and cap=?"];
    NSArray *params = @[user, acctNo, cap];
    NSNumber* count = (NSNumber*) [self executeScalar:query andArguments:params];
    return [count integerValue]>0;
}

-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource
{
    NSString* query = [NSString stringWithFormat:@"select ver from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where resource=? and buddy_name=?"];
    NSArray * params = @[resource, user];
    NSString* ver = (NSString*) [self executeScalar:query andArguments:params];
    return ver;
}

-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource
{
    NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
    [self beginWriteTransaction];
    
    //set ver for user and resource
    NSString* query = [NSString stringWithFormat:@"UPDATE buddy_resources SET ver=? WHERE EXISTS(SELECT * FROM buddylist WHERE buddy_resources.buddy_id=buddylist.buddy_id AND resource=? AND buddy_name=?)"];
    NSArray * params = @[ver, resource, user];
    [self executeNonQuery:query andArguments:params];
    
    //update timestamp for this ver string to make it not timeout (old ver strings and features are removed from feature cache after 28 days)
    NSString* query2 = [NSString stringWithFormat:@"INSERT INTO ver_timestamp (ver, timestamp) VALUES (?, ?) ON CONFLICT(ver) DO UPDATE SET timestamp=?;"];
    NSArray * params2 = @[ver, timestamp, timestamp];
    [self executeNonQuery:query2 andArguments:params2];
    
    [self endWriteTransaction];
}

-(NSSet*) getCapsforVer:(NSString*) ver
{
    NSString* query = [NSString stringWithFormat:@"select cap from ver_info where ver=?"];
    NSArray * params = @[ver];
    NSArray* resultArray = [self executeReader:query andArguments:params];
    
    if(resultArray != nil)
    {
        DDLogVerbose(@"caps count: %lu", (unsigned long)[resultArray count]);
        if([resultArray count] == 0)
            return nil;
        NSMutableSet* retval = [[NSMutableSet alloc] init];
        for(NSDictionary* row in resultArray)
            [retval addObject:row[@"cap"]];
        return retval;
    }
    else
    {
        DDLogError(@"caps list is empty");
        return nil;
    }
}

-(void) setCaps:(NSSet*) caps forVer:(NSString*) ver
{
    NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
    [self beginWriteTransaction];
    
    //remove old caps for this ver
    NSString* query0 = [NSString stringWithFormat:@"DELETE FROM ver_info WHERE ver=?;"];
    NSArray * params0 = @[ver];
    [self executeNonQuery:query0 andArguments:params0];
    
    //insert new caps
    for(NSString* feature in caps)
    {
        NSString* query1 = [NSString stringWithFormat:@"INSERT INTO ver_info (ver, cap) VALUES (?, ?);"];
        NSArray * params1 = @[ver, feature];
        [self executeNonQuery:query1 andArguments:params1];
    }
    
    //update timestamp for this ver string
    NSString* query2 = [NSString stringWithFormat:@"INSERT INTO ver_timestamp (ver, timestamp) VALUES (?, ?) ON CONFLICT(ver) DO UPDATE SET timestamp=?;"];
    NSArray * params2 = @[ver, timestamp, timestamp];
    [self executeNonQuery:query2 andArguments:params2];
    
    //cleanup old entries
    NSString* query3 = [NSString stringWithFormat:@"SELECT ver FROM ver_timestamp WHERE timestamp<?"];
    NSArray* params3 = @[[NSNumber numberWithInt:[timestamp integerValue] - (86400 * 28)]];     //cache timeout is 28 days
    NSArray* oldEntries = [self executeReader:query3 andArguments:params3];
    if(oldEntries)
        for(NSDictionary* row in oldEntries)
        {
            NSString* query4 = [NSString stringWithFormat:@"DELETE FROM ver_info WHERE ver=?;"];
            NSArray * params4 = @[row[@"ver"]];
            [self executeNonQuery:query4 andArguments:params4];
        }
    
    [self endWriteTransaction];
}

#pragma mark presence functions

-(void) setResourceOnline:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
    if(!presenceObj.resource) return;
	[self beginWriteTransaction];
    //get buddyid for name and account
    NSString* query1 = [NSString stringWithFormat:@"select buddy_id from buddylist where account_id=? and buddy_name=?;"];
    [self executeScalar:query1 andArguments:@[accountNo, presenceObj.user] withCompletion:^(NSObject *buddyid) {
        if(buddyid)  {
            NSString* query = [NSString stringWithFormat:@"insert into buddy_resources ('buddy_id', 'resource', 'ver') values (?, ?, '')"];
            [self executeNonQuery:query andArguments:@[buddyid, presenceObj.resource] withCompletion:nil];
        }
    }];
	[self endWriteTransaction];
}


-(NSArray*)resourcesForContact:(NSString*)contact
{
    if(!contact) return nil;
    NSString* query1 = [NSString stringWithFormat:@" select resource from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where  buddy_name=?  "];
    NSArray* params = @[contact ];
    NSArray* resources = [self executeReader:query1 andArguments:params];
    return resources;
}


-(void) setOnlineBuddy:(ParsePresence*) presenceObj forAccount:(NSString *)accountNo
{
	[self beginWriteTransaction];
    [self setResourceOnline:presenceObj forAccount:accountNo];

    [self isBuddyOnline:presenceObj.user forAccount:accountNo withCompletion:^(BOOL isOnline) {
        if(!isOnline) {
            NSString* query = [NSString stringWithFormat:@"update buddylist set online=1, new=1, muc=? where account_id=? and  buddy_name=?"];
            NSArray* params = @[[NSNumber numberWithBool:presenceObj.MUC], accountNo, presenceObj.user ];
            [self executeNonQuery:query andArguments:params withCompletion:nil];
        }
    }];
    [self endWriteTransaction];
}

-(BOOL) setOfflineBuddy:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
	[self beginWriteTransaction];
    NSString* query1 = [NSString stringWithFormat:@" select buddy_id from buddylist where account_id=? and  buddy_name=?;"];
    NSArray* params=@[accountNo, presenceObj.user];
    NSString* buddyid = (NSString*)[self executeScalar:query1 andArguments:params];
    if(buddyid == nil)
	{
		[self endWriteTransaction];
		return NO;
	}

    NSString* query2 = [NSString stringWithFormat:@"delete from buddy_resources where buddy_id=? and resource=?"];
    NSArray* params2 = @[buddyid, presenceObj.resource?presenceObj.resource:@""];
    if([self executeNonQuery:query2 andArguments:params2] == NO)
	{
		[self endWriteTransaction];
		return NO;
	}

    //see how many left
    NSString* query3 = [NSString stringWithFormat:@"select count(buddy_id) from buddy_resources where buddy_id=%@;", buddyid ];
    NSString* resourceCount = (NSString*)[self executeScalar:query3 andArguments:nil];

    if([resourceCount integerValue]<1)
    {
        NSString* query = [NSString stringWithFormat:@"update buddylist set online=0, state='offline', dirty=1 where account_id=? and buddy_name=?;"];
        NSArray* params4 = @[accountNo, presenceObj.user];
		BOOL retval = [self executeNonQuery:query andArguments:params4];
		[self endWriteTransaction];
        if(retval!=NO)
        {
            return YES;
        }
        else
        {
            return NO;
        }
    }
    else
	{
		[self endWriteTransaction];
		return NO;
	}
}

-(void) setBuddyState:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
{
    NSString* toPass;
    //data length check

    if([presenceObj.show length] > 20) toPass=[presenceObj.show substringToIndex:19]; else toPass=presenceObj.show;
    if(!toPass) toPass= @"";

    NSString* query = [NSString stringWithFormat:@"update buddylist set state=?, dirty=1 where account_id=? and  buddy_name=?;"];
    [self executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.user] withCompletion:nil];
}

-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo
{

    NSString* query = [NSString stringWithFormat:@"select state from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, buddy];
    NSString* state = (NSString*)[self executeScalar:query andArguments:params];
    return state;
}

-(void) contactRequestsForAccountWithCompletion:(void (^)(NSMutableArray *))completion
{
    NSString* query = [NSString stringWithFormat:@"select account_id, buddy_name from subscriptionRequests"];

     [self executeReader:query withCompletion:^(NSMutableArray *results) {

         NSMutableArray* toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
         [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
             NSDictionary* dic = (NSDictionary *) obj;
             [toReturn addObject:[MLContact contactFromDictionary:dic]];
         }];

         if(completion) completion(toReturn);
     }];
}

-(void) addContactRequest:(MLContact *) requestor;
{
    NSString* query2 = [NSString stringWithFormat:@"insert into subscriptionRequests (buddy_name, account_id) values (?,?) "];
    [self executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId] ];
}

-(void) deleteContactRequest:(MLContact *) requestor
{
    NSString* query2 = [NSString stringWithFormat:@"delete from subscriptionRequests where buddy_name=? and account_id=? "];
    [self executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId] ];
}

-(void) setBuddyStatus:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo
{
    NSString* toPass;
    //data length check
    if([presenceObj.status length] > 200) toPass = [presenceObj.status substringToIndex:199];
    else
    {
        toPass = presenceObj.status;
    }
    if(!toPass) toPass = @"";

    NSString* query = [NSString stringWithFormat:@"update buddylist set status=?, dirty=1 where account_id=? and  buddy_name=?;"];
    [self executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.user] withCompletion:nil];
}

-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"select status from buddylist where account_id=? and buddy_name=?"];
    NSString* iconname =  (NSString *)[self executeScalar:query andArguments:@[accountNo, buddy]];
    return iconname;
}

-(NSString *) getRosterVersionForAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"SELECT rosterVersion from account where account_id=?"];
    NSArray* params = @[ accountNo];
    NSString * version=(NSString*)[self executeScalar:query andArguments:params];
    return version;
}

-(void) setRosterVersion:(NSString *) version forAccount: (NSString*) accountNo
{
    if(!accountNo || !version) return;
    NSString* query = [NSString stringWithFormat:@"update account set rosterVersion=? where account_id=?"];
    NSArray* params = @[version , accountNo];
    [self executeNonQuery:query  andArguments:params withCompletion:nil];
}

-(NSDictionary *) getSubscriptionForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    if(!contact || !accountNo) return nil;
    NSString* query = [NSString stringWithFormat:@"SELECT subscription, ask from buddylist where buddy_name=? and account_id=?"];
    NSArray* params = @[contact, accountNo];
    NSArray* version=[self executeReader:query andArguments:params];
    return version.firstObject;
}

-(void) setSubscription:(NSString *)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    if(!contact || !accountNo || !sub) return;
    NSString* query = [NSString stringWithFormat:@"update buddylist set subscription=?, ask=? where account_id=? and buddy_name=?"];
    NSArray* params = @[sub, ask?ask:@"", accountNo, contact];
    [self executeNonQuery:query  andArguments:params withCompletion:nil];
}



#pragma mark Contact info

-(void) setFullName:(NSString*) fullName forContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    NSString* toPass;
    //data length check

    NSString *cleanFullName =[fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if([cleanFullName length]>50) toPass=[cleanFullName substringToIndex:49]; else toPass=cleanFullName;

    if(!toPass) return;

    NSString* query = [NSString stringWithFormat:@"update buddylist set full_name=?, dirty=1 where account_id=? and  buddy_name=?"];
    NSArray* params = @[toPass , accountNo, contact];
    [self executeNonQuery:query  andArguments:params withCompletion:nil];
}

-(void) setNickName:(NSString*) nickName forContact:(NSString*) buddy andAccount:(NSString*) accountNo
{
    if(!nickName || !buddy) return;
    NSString* toPass;
    //data length check

    if([nickName length]>50) toPass=[nickName substringToIndex:49]; else toPass=nickName;
    NSString* query = [NSString stringWithFormat:@"update buddylist set nick_name=?, dirty=1 where account_id=? and  buddy_name=?"];
    NSArray* params = @[toPass, accountNo, buddy];

    [self executeNonQuery:query andArguments:params withCompletion:nil];
}

-(NSString*) nickName:(NSString*) buddy forAccount:(NSString*) accountNo;
{
    if(!accountNo  || !buddy) return nil;
    NSString* query = [NSString stringWithFormat:@"select nick_name from buddylist where account_id=? and buddy_name=?"];
    NSArray * params=@[accountNo, buddy];
    NSString* fullname= (NSString*)[self executeScalar:query andArguments:params];
    return fullname;
}

-(void) fullNameForContact:(NSString*) contact inAccount:(NSString*) accountNo withCompeltion: (void (^)(NSString *))completion;
{
    if(!accountNo  || !contact) return ;
    NSString* query = [NSString stringWithFormat:@"select full_name from buddylist where account_id=? and buddy_name=?"];
    NSArray * params=@[accountNo, contact];
    [self executeScalar:query andArguments:params withCompletion:^(NSObject *name) {
        if(completion) completion((NSString *)name);
    }];
}

-(void) setContactHash:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo
{
    NSString* hash=presenceObj.photoHash;
    if(!hash) hash= @"";
    //data length check
    NSString* query = [NSString stringWithFormat:@"update buddylist set iconhash=?, dirty=1 where account_id=? and buddy_name=?;"];
    NSArray* params = @[hash, accountNo, presenceObj.user];
    [self executeNonQuery:query  andArguments:params withCompletion:nil];

}

-(void) contactHash:(NSString*) buddy forAccount:(NSString*) accountNo withCompeltion: (void (^)(NSString *))completion
{
    NSString* query = [NSString stringWithFormat:@"select iconhash from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, buddy];
    [self executeScalar:query andArguments:params withCompletion:^(NSObject *iconHash) {
        if(completion)
        {
            completion((NSString *)iconHash);
        }
    }];
}

-(void) isContactInList:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=? and buddy_name=? "];
    NSArray* params = @[accountNo, buddy];

    [self executeScalar:query andArguments:params withCompletion:^(NSObject *value) {

        NSNumber* count=(NSNumber*)value;
        BOOL toreturn=NO;
        if(count!=nil)
        {
            NSInteger val=[count integerValue];
            if(val > 0) {
                toreturn= YES;
            }
        }
        if(completion)
        {
            completion(toreturn);
        }
    }];
}

-(void) isBuddyOnline:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=? and buddy_name=? and online=1 "];
    NSArray* params = @[accountNo, buddy];

    [self executeScalar:query andArguments:params withCompletion:^(NSObject *value) {

        NSNumber* count=(NSNumber*)value;
        BOOL toreturn=NO;
        if(count!=nil)
        {
            NSInteger val=[count integerValue];
            if(val>0) {
                toreturn= YES;
            }
        }
        if(completion)
        {
            completion(toreturn);
        }
    }];
}

-(void) saveMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo withComment:(NSString*) comment withCompletion:(void (^)(BOOL))completion
{
   [self beginWriteTransaction];
    NSString* query = [NSString stringWithFormat:@"update buddylist set messageDraft=? where account_id=? and buddy_name=?"];
    NSArray* params = @[comment, accountNo, buddy];
    [self executeNonQuery:query andArguments:params  withCompletion:^(BOOL success) {
        [self endWriteTransaction];
        if(completion) {
                completion(success);
            }
    }];
}

-(void) loadMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion:(void (^)(NSString*))completion
{
    NSString* query = [NSString stringWithFormat:@"SELECT messageDraft from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, buddy];
    [self executeScalar:query andArguments:params withCompletion:^(NSObject* messageDraft) {
        if(completion) {
            completion((NSString *)messageDraft);
        }
    }];
}

#pragma mark MUC

-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"SELECT Muc from buddylist where account_id=?  and buddy_name=? "];
    NSArray* params = @[ accountNo, buddy];
    NSNumber* status=(NSNumber*)[self executeScalar:query andArguments:params];
    return [status boolValue];
}

-(NSString *) ownNickNameforMuc:(NSString*) room andServer:(NSString*) server forAccount:(NSString*) accountNo
{
    NSString *combinedRoom = room;
    if([combinedRoom componentsSeparatedByString:@"@"].count == 1) {
        combinedRoom = [NSString stringWithFormat:@"%@@%@", room, server];
    }

    NSString* query = [NSString stringWithFormat:@"SELECT muc_nick from buddylist where account_id=?  and buddy_name=? "];
    NSArray* params = @[ accountNo, combinedRoom];
    NSString * nick=(NSString*)[self executeScalar:query andArguments:params];
    if(nick.length==0) {
        NSString* query2= [NSString stringWithFormat:@"SELECT nick from muc_favorites where account_id=?  and room=? "];
        NSArray *params2=@[ accountNo, combinedRoom];
        nick=(NSString*)[self executeScalar:query2 andArguments:params2];
    }
    return nick;
}

-(void) updateOwnNickName:(NSString *) nick forMuc:(NSString*) room andServer:(NSString*) server forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    NSString *combinedRoom = room;
    if([combinedRoom componentsSeparatedByString:@"@"].count == 1) {
        combinedRoom = [NSString stringWithFormat:@"%@@%@", room, server];
    }

    NSString* query = [NSString stringWithFormat:@"update buddylist set muc_nick=?, muc=1 where account_id=? and buddy_name=?"];
    NSArray* params = @[nick, accountNo, combinedRoom];
    DDLogVerbose(@"%@", query);

    [self executeNonQuery:query andArguments:params  withCompletion:completion];
}


-(void) addMucFavoriteForAccount:(NSString*) accountNo withRoom:(NSString *) room nick:(NSString *)nick autoJoin:(BOOL) autoJoin andCompletion:(void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"insert into muc_favorites (room, nick, autojoin, account_id) values(?, ?, ?, ?)"];
    NSArray* params = @[room, nick, [NSNumber numberWithBool:autoJoin], accountNo];
    DDLogVerbose(@"%@", query);

    [self executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {
        if(completion) {
            completion(success);
        }

    }];
}

-(void) updateMucFavorite:(NSNumber *) mucid forAccountId:(NSInteger) accountNo autoJoin:(BOOL) autoJoin andCompletion:(void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"update muc_favorites set autojoin=? where mucid=? and account_id=?"];
    NSArray* params = @[[NSNumber numberWithBool:autoJoin], mucid, [NSNumber numberWithInteger:accountNo]];
    DDLogVerbose(@"%@", query);

    [self executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {
        if(completion) {
            completion(success);
        }
    }];
}

-(void) deleteMucFavorite:(NSNumber *) mucid forAccountId:(NSInteger) accountNo withCompletion:(void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"delete from muc_favorites where mucid=? and account_id=?"];
    NSArray* params = @[mucid, [NSNumber numberWithInteger:accountNo]];
    DDLogVerbose(@"%@", query);

    [self executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {
        if(completion) {
            completion(success);
        }
    }];
}

-(void) mucFavoritesForAccount:(NSString*) accountNo withCompletion:(void (^)(NSMutableArray *))completion
{
    NSString* query = [NSString stringWithFormat:@"select * from muc_favorites where account_id=%@", accountNo];
    DDLogVerbose(@"%@", query);
    [self executeReader:query withCompletion:^(NSMutableArray *favorites) {
        if(favorites!=nil) {
            DDLogVerbose(@"fetched muc favorites");
        }
        else{
            DDLogVerbose(@"could not fetch  muc favorites");

        }

        if(completion) {
            completion(favorites);
        }
    }];
}

-(void) updateMucSubject:(NSString *) subject forAccount:(NSString*) accountNo andRoom:(NSString *) room  withCompletion:(void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"update buddylist set muc_subject=? where account_id=? and buddy_name=?"];
    NSArray* params = @[subject, accountNo, room];
    DDLogVerbose(@"%@", query);

    [self executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {

        if(completion) {
            completion(success);
        }

    }];
}

-(void) mucSubjectforAccount:(NSString*) accountNo andRoom:(NSString *) room  withCompletion:(void (^)(NSString* ))completion
{
    NSString* query = [NSString stringWithFormat:@"select muc_subject from buddylist where account_id=? and buddy_name=?"];

    NSArray* params = @[accountNo, room];
    DDLogVerbose(@"%@", query);

    [self executeScalar:query andArguments:params withCompletion:^(NSObject *result) {
        if(completion) completion((NSString *)result);
    }];

}

#pragma mark message Commands

-(NSArray *) messageForHistoryID:(NSInteger) historyID
{
    NSString* query = [NSString stringWithFormat:@"select message, messageid from message_history  where message_history_id=%ld", (long)historyID];
    NSArray* messageArray= [self executeReader:query andArguments:nil];
    return messageArray;
}

-(void) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom delivered:(BOOL) delivered unread:(BOOL) unread messageId:(NSString *) messageid serverMessageId:(NSString *) stanzaid messageType:(NSString *) messageType andOverrideDate:(NSDate *) messageDate encrypted:(BOOL) encrypted  withCompletion: (void (^)(BOOL, NSString*))completion
{
    if(!from || !to || !message) {
        if(completion) completion(NO, nil);
        return;
    }

    NSString *idToUse=stanzaid?stanzaid:messageid; //just ensures stanzaid is not null

    NSString* typeToUse=messageType;
	if(!typeToUse) typeToUse=kMessageTypeText; //default to insert

    [self beginWriteTransaction];
    [self hasMessageForStanzaId:idToUse orMessageID:messageid toContact:actualfrom onAccount:accountNo andCompletion:^(BOOL exists) {
        if(!exists)
        {
            //this is always from a contact
            NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            NSDate* sourceDate=[NSDate date];
            NSDate* destinationDate;
            if(messageDate) {
                //already GMT no need for conversion

                destinationDate= messageDate;
                [formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
            }
            else {
                NSTimeZone* sourceTimeZone = [NSTimeZone systemTimeZone];
                NSTimeZone* destinationTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];

                NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
                NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
                NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;

                destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
            }
            // note: if it isnt the same day we want to show the full  day

            NSString* dateString = [formatter stringFromDate:destinationDate];
            
          //do not do this in MUC
            if(!messageType && [actualfrom isEqualToString:from]) {
				[self messageTypeForMessage:message withKeepThread:YES andCompletion:^(NSString *foundMessageType) {
						NSString* query = [NSString stringWithFormat:@"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, delivered, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"];
						NSArray* params = @[accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithInteger:unread], [NSNumber numberWithInteger:delivered], messageid?messageid:@"", foundMessageType, [NSNumber numberWithInteger:encrypted], stanzaid?stanzaid:@""];
						DDLogVerbose(@"%@", query);
						[self executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {

							if(success) {
								[self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo withCompletion:^(BOOL innerSuccess) {
									[self endWriteTransaction];
									if(completion) {
										completion(success, messageType);
									}
								}];
							}
							else {
								[self endWriteTransaction];
								if(completion) {
									completion(success, messageType);
								}
							}
						}];
				}];
            } else  {
                NSString* query = [NSString stringWithFormat:@"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, delivered, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"];
                NSArray* params = @[accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithInteger:unread], [NSNumber numberWithInteger:delivered], messageid?messageid:@"", typeToUse, [NSNumber numberWithInteger:encrypted], stanzaid?stanzaid:@"" ];
                DDLogVerbose(@"%@", query);
				[self executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {

					if(success) {
						[self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo withCompletion:^(BOOL innerSuccess) {
							[self endWriteTransaction];
							if(completion) {
								completion(success, messageType);
							}
						}];
					}
					else {
						[self endWriteTransaction];
						if(completion) {
							completion(success, messageType);
						}
					}
                }];
            }
        }
        else {
			[self endWriteTransaction];
            if(completion) completion(NO, nil);
            DDLogError(@"Message %@ or stanza Id %@ duplicated,, id in use %@", messageid, stanzaid,  idToUse);
        }
    }];
}

-(void) hasMessageForStanzaId:(NSString *) stanzaId orMessageID:(NSString *) messageId toContact:(NSString *) contact onAccount:(NSString *) accountNo andCompletion: (void (^)(BOOL))completion
{
    if(!accountNo || !contact) return;
    NSString* query = [NSString stringWithFormat:@"select messageid from message_history where account_id=? and message_from=? and (stanzaid=? or messageid=?) limit 1"];
    NSArray* params = @[accountNo, contact, stanzaId, messageId];

    [self executeScalar:query andArguments:params withCompletion:^(NSObject* result) {

        BOOL exists=NO;
        if(result)
        {
            exists=YES;
        }

        if(completion)
        {
            completion(exists);
        }
    }];
}

-(void) hasMessageForId:(NSString*) messageid onAccount:(NSString *) accountNo andCompletion: (void (^)(BOOL))completion
{
    if(!accountNo ) return;
    NSString* query = [NSString stringWithFormat:@"select messageid from message_history where account_id=? and messageid=? limit 1"];
    NSArray* params = @[accountNo, messageid?messageid:@""];

    [self executeScalar:query andArguments:params withCompletion:^(NSObject* result) {

        BOOL exists=NO;
        if(result)
        {
            exists=YES;
        }

        if(completion)
        {
            completion(exists);
        }
    }];
}

-(void) setMessageId:(NSString*) messageid delivered:(BOOL) delivered
{
    NSString* query = [NSString stringWithFormat:@"update message_history set delivered=? where messageid=?"];
    DDLogVerbose(@" setting delivered %@", query);
    [self executeNonQuery:query  andArguments:@[[NSNumber numberWithBool:delivered], messageid]  withCompletion:nil];
}

-(void) setMessageId:(NSString*) messageid received:(BOOL) received
{
    NSString* query = [NSString stringWithFormat:@"update message_history set received=? where messageid=?"];
    DDLogVerbose(@" setting received confrmed %@", query);
    [self executeNonQuery:query andArguments:@[[NSNumber numberWithBool:received], messageid]  withCompletion:nil];
}

-(void) setMessageId:(NSString*) messageid errorType:(NSString *) errorType errorReason:(NSString *)errorReason
{
    NSString* query = [NSString stringWithFormat:@"update message_history set errorType=?, errorReason=? where messageid=?"];
    DDLogVerbose(@" setting message Error %@", query);
    [self executeNonQuery:query  andArguments:@[errorType, errorReason, messageid]  withCompletion:nil];
}

-(void) setMessageId:(NSString*) messageid messageType:(NSString *) messageType
{
    NSString* query = [NSString stringWithFormat:@"update message_history set messageType=? where messageid=?"];
    DDLogVerbose(@" setting message type %@", query);
    [self executeNonQuery:query  andArguments:@[messageType, messageid]  withCompletion:nil];
}

-(void) setMessageId:(NSString*) messageid previewText:(NSString *) text andPreviewImage:(NSString *) image
{
    if(!messageid) return;
    NSString* query = [NSString stringWithFormat:@"update message_history set previewText=?,  previewImage=? where messageid=?"];
    DDLogVerbose(@" setting previews type %@", query);
    [self executeNonQuery:query  andArguments:@[text?text:@"", image?image:@"", messageid]  withCompletion:nil];
}

-(void) setMessageId:(NSString*) messageid stanzaId:(NSString *) stanzaId
{
    NSString* query = [NSString stringWithFormat:@"update message_history set stanzaid=? where messageid=?"];
    DDLogVerbose(@" setting message stanzaid %@", query);
    [self executeNonQuery:query  andArguments:@[stanzaId, messageid]  withCompletion:nil];
}

-(void) clearMessages:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"delete from message_history where account_id=%@", accountNo];
    [self executeNonQuery:query withCompletion:nil];
}

-(void) deleteMessageHistory:(NSNumber*) messageNo
{
    NSString* query = [NSString stringWithFormat:@"delete from message_history where message_history_id=%@", messageNo];
    [self executeNonQuery:query withCompletion:nil];
}

-(NSArray*) messageHistoryListDates:(NSString*) buddy forAccount: (NSString*) accountNo
{
    //returns a list of  buddy's with message history

    NSString* query1 = [NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
    //DDLogVerbose(query);
    NSArray* user = [self executeReader:query1 andArguments:nil ];

    if(user!=nil)
    {
        NSString* query = [NSString stringWithFormat:@"select distinct date(timestamp) as the_date from message_history where account_id=? and message_from=? or message_to=? order by timestamp desc"];
        NSArray  *params=@[accountNo, buddy, buddy  ];
        //DDLogVerbose(query);
        NSArray* toReturn = [self executeReader:query andArguments:params];

        if(toReturn!=nil)
        {

            DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count]);

            return toReturn; //[toReturn autorelease];
        }
        else
        {
            DDLogError(@"message history buddy date list is empty or failed to read");

            return nil;
        }

    } else return nil;
}

-(NSArray*) messageHistoryDate:(NSString*) buddy forAccount:(NSString*) accountNo forDate:(NSString*) date
{
    NSString* query = [NSString stringWithFormat:@"select af, message_from, message_to, message, thetime, delivered, message_history_id from (select ifnull(actual_from, message_from) as af, message_from, message_to, message, delivered, timestamp  as thetime, message_history_id, previewImage, previewText from message_history where account_id=? and (message_from=? or message_to=?) and date(timestamp)=? order by message_history_id desc) order by message_history_id asc"];
    NSArray* params = @[accountNo, buddy, buddy, date];

    DDLogVerbose(@"%@", query);
    NSArray* results = [self executeReader:query andArguments:params];

    NSDateFormatter* formatter = self.dbFormatter;

    NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *dic = (NSDictionary *) obj;
        [toReturn addObject:[MLMessage messageFromDictionary:dic withDateFormatter:formatter]];
    }];

    if(toReturn!=nil)
    {

        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count]);

        return toReturn; //[toReturn autorelease];
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
        return nil;
    }
}

-(NSArray*) allMessagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo
{
    //returns a buddy's message history

    NSString* query = [NSString stringWithFormat:@"select message_from, message, thetime from (select message_from, message, timestamp as thetime, message_history_id, previewImage, previewText from message_history where account_id=? and (message_from=? or message_to=?) order by message_history_id desc) order by message_history_id asc "];
    NSArray* params = @[accountNo, buddy, buddy];
    //DDLogVerbose(query);
    NSArray* toReturn = [self executeReader:query andArguments:params];

    if(toReturn!=nil)
    {

        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count]);
        return toReturn; //[toReturn autorelease];
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
        return nil;
    }
}

-(BOOL) messageHistoryClean:(NSString*) buddy :(NSString*) accountNo
{
    //returns a buddy's message history

    NSString* query = [NSString stringWithFormat:@"delete from message_history where account_id=? and (message_from=? or message_to=?) "];
    NSArray* params = @[accountNo, buddy, buddy];
    //DDLogVerbose(query);
    if( [self executeNonQuery:query andArguments:params])

    {
        DDLogVerbose(@" cleaned messages for %@",  buddy );
        return YES;
    }
    else
    {
        DDLogError(@"message history failed to clean");
        return NO;
    }
}


-(BOOL) messageHistoryCleanAll
{
    //cleans a buddy's message history
    NSString* query = [NSString stringWithFormat:@"delete from message_history "];
    if( [self executeNonQuery:query andArguments:nil])
    {
        DDLogVerbose(@" cleaned messages " );
        return YES;
    }
    else
    {
        DDLogError(@"message history failed to clean all");
        return NO;
    }

}

-(NSMutableArray *) messageHistoryContacts:(NSString*) accountNo
{
    //returns a list of  buddy's with message history

    NSString* query1 = [NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
    //DDLogVerbose(query);
    NSArray* user = [self executeReader:query1 andArguments:nil];

    if([user count]>0)
    {

        NSString* query = [NSString stringWithFormat:@"select x.* from(select distinct buddy_name as thename ,'', nick_name, message_from as buddy_name, filename, a.account_id from message_history as a left outer join buddylist as b on a.message_from=b.buddy_name and a.account_id=b.account_id where a.account_id=?  union select distinct message_to as thename ,'',  nick_name, message_to as buddy_name,  filename, a.account_id from message_history as a left outer join buddylist as b on a.message_to=b.buddy_name and a.account_id=b.account_id where a.account_id=?  and message_to!=\"(null)\" )  as x where buddy_name!=?  order by thename COLLATE NOCASE "];
        NSArray* params = @[accountNo, accountNo,
                          ((NSString *)[[user objectAtIndex:0] objectForKey:@"username"]),
                          // ((NSString *)[[user objectAtIndex:0] objectForKey:@"username"]),
                          ((NSString *)[[user objectAtIndex:0] objectForKey:@"domain"])  ];
        //DDLogVerbose(query);
        NSArray* results = [self executeReader:query andArguments:params];

        NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
        [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic = (NSDictionary *) obj;
            [toReturn addObject:[MLContact contactFromDictionary:dic]];
        }];

        if(toReturn!=nil)
        {

            DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count]);
            return toReturn; //[toReturn autorelease];
        }
        else
        {
            DDLogError(@"message history buddy list is empty or failed to read");
            return nil;
        }

    } else return nil;
}


//message history
-(void) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion:(void (^)(NSMutableArray *))completion
{
    if(!accountNo ||! buddy) {
        if(completion) completion(nil);
        return;
    };
    NSString* query = [NSString stringWithFormat:@"select af, message_from, message_to, account_id, message, thetime, message_history_id, delivered, messageid, messageType, received, encrypted, previewImage, previewText, unread, errorType, errorReason from (select ifnull(actual_from, message_from) as af, message_from, message_to, account_id,   message, received, encrypted, timestamp  as thetime, message_history_id, delivered,messageid, messageType, previewImage, previewText, unread, errorType, errorReason from message_history where account_id=? and (message_from=? or message_to=?) order by message_history_id desc limit 250) order by thetime asc"];
    NSArray* params = @[accountNo, buddy, buddy];
    [self executeReader:query andArguments:params withCompletion:^(NSMutableArray *rawArray) {
        NSDateFormatter* formatter = self.dbFormatter;

        NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:rawArray.count];
        [rawArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic = (NSDictionary *) obj;
            [toReturn addObject:[MLMessage messageFromDictionary:dic withDateFormatter:formatter]];
        }];

        if(toReturn!=nil)
        {
            DDLogVerbose(@" message history count: %lu",  (unsigned long)[toReturn count]);
        }
        else
        {
            DDLogError(@"message history is empty or failed to read");
        }

        if(completion) completion(toReturn);
    }];
}

-(void) lastMessageForContact:(NSString*) contact forAccount:(NSString*) accountNo withCompletion:(void (^)(NSMutableArray *))completion
{
    if(!accountNo ||! contact) return;
    NSString* query = [NSString stringWithFormat:@"SELECT message, thetime, messageType FROM (SELECT 1 as messagePrio, bl.messageDraft as message, ac.lastMessageTime as thetime, 'MessageDraft' as messageType FROM buddylist AS bl INNER JOIN activechats AS ac where bl.account_id = ac.account_id and bl.buddy_name = ac.buddy_name and ac.account_id = ? and ac.buddy_name = ? and messageDraft is not NULL and messageDraft != '' UNION SELECT 2 as messagePrio, message, timestamp, messageType from (select message, timestamp, messageType FROM message_history where account_id=? and (message_from =? or message_to=?) ORDER BY message_history_id DESC LIMIT 1) ORDER BY messagePrio ASC LIMIT 1)"];
    NSArray* params = @[accountNo, contact, accountNo, contact, contact];

    [self executeReader:query andArguments:params withCompletion:^(NSMutableArray *results) {
        NSDateFormatter* formatter = self.dbFormatter;

        NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
        [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic = (NSDictionary *) obj;
            [toReturn addObject:[MLMessage messageFromDictionary:dic withDateFormatter:formatter]];
        }];

        if(toReturn!=nil)
        {
            DDLogVerbose(@" message history count: %lu",  (unsigned long)[toReturn count]);
        }
        else
        {
            DDLogError(@"message history is empty or failed to read");
        }

        if(completion) completion(toReturn);
    }];
}

-(void) markAsReadBuddy:(NSString*) buddy forAccount:(NSString*) accountNo
{
    if(!buddy || !accountNo) return;
    NSString* query2 = [NSString stringWithFormat:@"  update message_history set unread=0 where account_id=? and message_from=? or message_to=?"];
    [self executeNonQuery:query2 andArguments:@[accountNo, buddy, buddy] withCompletion:nil];
}


-(void) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString *)messageId encrypted:(BOOL) encrypted withCompletion:(void (^)(BOOL, NSString *))completion
{
    //Message_history going out, from is always the local user. always read, default to  delivered (will be reset by timer if needed)

    NSString *cleanedActualFrom = actualfrom;

    if([actualfrom isEqualToString:@"(null)"])
    {
        //handle null dictionary string
        cleanedActualFrom = from;
    }

    [self messageTypeForMessage:message withKeepThread:YES andCompletion:^(NSString *messageType) {

        NSArray* parts = [[[NSDate date] description] componentsSeparatedByString:@" "];
        NSString* dateTime = [NSString stringWithFormat:@"%@ %@", [parts objectAtIndex:0],[parts objectAtIndex:1]];
        NSString* query = [NSString stringWithFormat:@"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, delivered, messageid, messageType, encrypted) values (?,?,?,?,?,?,?,?,?,?,?);"];
        NSArray* params = @[accountNo, from, to, dateTime, message, cleanedActualFrom,[NSNumber numberWithInteger:0], [NSNumber numberWithInteger:1], messageId, messageType, [NSNumber numberWithInteger:encrypted]];
		[self beginWriteTransaction];
        DDLogVerbose(@"%@", query);
        [self executeNonQuery:query andArguments:params  withCompletion:^(BOOL result) {
			[self updateActiveBuddy:to setTime:dateTime forAccount:accountNo withCompletion:^(BOOL innerSuccess) {
				[self endWriteTransaction];
				if (completion) {
					completion(result, messageType);
				}
			}];
        }];
    }];
}

//count unread
-(void) countUnreadMessagesWithCompletion: (void (^)(NSNumber *))completion
{
    // count # of meaages in message table
    NSString* query = [NSString stringWithFormat:@"select count(message_history_id) from  message_history where unread=1"];

    [self executeScalar:query withCompletion:^(NSObject *result) {
        NSNumber* count = (NSNumber *) result;

        if(completion)
        {
            completion(count);
        }
    }];
}

//set all unread messages to read
-(void) setAllMessagesAsRead
{
    NSString* query = [NSString stringWithFormat:@"update message_history set unread=0 where unread=1"];

    [self executeNonQuery:query andArguments:nil withCompletion:nil];
}

-(void)setSynchpointforAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"update buddylist set synchpoint=?  where account_id=?"];

    NSDateFormatter* dateFromatter = [[NSDateFormatter alloc] init];
    NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

    [dateFromatter setLocale:enUSPOSIXLocale];
    [dateFromatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss"];
    [dateFromatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSString* synchPoint =[dateFromatter stringFromDate:[NSDate date]];

    [self executeNonQuery:query andArguments:@[synchPoint, accountNo] withCompletion:nil];
}

-(void) synchPointforAccount:(NSString*) accountNo withCompletion: (void (^)(NSDate *))completion
{
    NSString* query = [NSString stringWithFormat:@"select synchpoint from buddylist  where account_id=? order by synchpoint  desc limit 1"];

    [self executeScalar:query andArguments:@[accountNo] withCompletion:^(NSObject* result) {
        if(completion)
        {
            NSDateFormatter* dateFromatter = [[NSDateFormatter alloc] init];
            NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

            [dateFromatter setLocale:enUSPOSIXLocale];
            [dateFromatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss"];
            [dateFromatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

            NSDate* datetoReturn = [dateFromatter dateFromString:(NSString *)result];

            completion(datetoReturn);
        }
    }];
}

-(void) lastMessageDateForContact:(NSString*) contact andAccount:(NSString*) accountNo withCompletion: (void (^)(NSDate *))completion
{
    NSString* query = [NSString stringWithFormat:@"select timestamp from  message_history where account_id=? and (message_from=? or (message_to=? and delivered=1)) order by timestamp desc limit 1"];

    [self executeScalar:query andArguments:@[accountNo, contact, contact] withCompletion:^(NSObject* result) {
        if(completion)
        {
            NSDateFormatter *dateFromatter = [[NSDateFormatter alloc] init];
            NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

            [dateFromatter setLocale:enUSPOSIXLocale];
            [dateFromatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss"];
            [dateFromatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

            NSDate* datetoReturn = [dateFromatter dateFromString:(NSString *)result];

            completion(datetoReturn);
        }
    }];
}

-(void) lastMessageSanzaForAccount:(NSString*) accountNo andJid:(NSString*) jid withCompletion: (void (^)(NSString *))completion
{
    NSString* query = [NSString stringWithFormat:@"select stanzaid from  message_history where account_id=? and message_from!=? and stanzaid not null and stanzaid!='' order by timestamp desc limit 1"];

    [self executeScalar:query andArguments:@[accountNo, jid] withCompletion:^(NSObject* result) {
        if(completion)
        {
            completion((NSString *) result);
        }
    }];
}

-(void) lastMessageDateAccount:(NSString*) accountNo withCompletion: (void (^)(NSDate *))completion
{
    NSString* query = [NSString stringWithFormat:@"select timestamp from  message_history where account_id=? order by timestamp desc limit 1"];

    [self executeScalar:query andArguments:@[accountNo] withCompletion:^(NSObject* result) {
        if(completion)
        {
            NSDateFormatter* dateFromatter = [[NSDateFormatter alloc] init];
            NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

            [dateFromatter setLocale:enUSPOSIXLocale];
            [dateFromatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss"];
            [dateFromatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

            NSDate* datetoReturn = [dateFromatter dateFromString:(NSString *)result];

            completion(datetoReturn);
        }
    }];
}


#pragma mark active chats
-(void) activeContactsWithCompletion: (void (^)(NSMutableArray *))completion
{
    NSString* query = [NSString stringWithFormat:@"select  distinct a.buddy_name,  state, status,  filename, ifnull(b.full_name, a.buddy_name) AS full_name, nick_name, muc_subject, muc_nick, a.account_id,lastMessageTime, 0 AS 'count', subscription, ask from activechats as a LEFT OUTER JOIN buddylist AS b ON a.buddy_name = b.buddy_name  AND a.account_id = b.account_id order by lastMessageTime desc"];

    NSDateFormatter* dateFromatter = [[NSDateFormatter alloc] init];
    NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

    [dateFromatter setLocale:enUSPOSIXLocale];
    [dateFromatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss"];
    [dateFromatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    [self executeReader:query withCompletion:^(NSMutableArray *results) {

        NSMutableArray* toReturn = [[NSMutableArray alloc] initWithCapacity:results.count];
        [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary* dic = (NSDictionary *) obj;
            [toReturn addObject:[MLContact contactFromDictionary:dic withDateFormatter:dateFromatter]];
        }];

        if(completion) completion(toReturn);
    }];
}

-(void) activeContactDictWithCompletion: (void (^)(NSMutableArray *))completion
{
    NSString* query = [NSString stringWithFormat:@"select  distinct a.buddy_name, ifnull(b.full_name, a.buddy_name) AS full_name, nick_name, a.account_id from activechats as a LEFT OUTER JOIN buddylist AS b ON a.buddy_name = b.buddy_name  AND a.account_id = b.account_id order by lastMessageTime desc"];

    [self executeReader:query withCompletion:^(NSMutableArray *results) {

        NSMutableArray* toReturn = [[NSMutableArray alloc] initWithCapacity:results.count];
        [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary* dic = (NSDictionary *) obj;
            [toReturn addObject:dic];
        }];

        if(completion) completion(toReturn);
    }];
}

-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo
{
	[self beginWriteTransaction];
    //mark messages as read
    [self markAsReadBuddy:buddyname forAccount:accountNo];

    NSString* query = [NSString stringWithFormat:@"delete from activechats where buddy_name=? and account_id=? "];
    //	DDLogVerbose(query);
    [self executeNonQuery:query andArguments:@[buddyname, accountNo] withCompletion:nil];
	[self endWriteTransaction];
}

-(void) removeAllActiveBuddies
{

    NSString* query = [NSString stringWithFormat:@"delete from activechats " ];
    //	DDLogVerbose(query);
    [self executeNonQuery:query withCompletion:nil];
}

-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    if(!buddyname)
    {
        if (completion) {
            completion(NO);
        }
        return;
    }
    [self beginWriteTransaction];
    NSString* query = [NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=? and buddy_name=? "];
    [self executeScalar:query  andArguments:@[accountNo, buddyname] withCompletion:^(NSObject * count) {
        if(count != nil)
        {
            NSInteger val=[((NSNumber *)count) integerValue];
            if(val > 0) {
				[self endWriteTransaction];
                if (completion) {
                    completion(NO);
                }
            } else
            {
                //no
                NSString* query2 = [NSString stringWithFormat:@"insert into activechats (buddy_name, account_id, lastMessageTime) values (?,?, current_timestamp) "];
                [self executeNonQuery:query2 andArguments:@[buddyname, accountNo] withCompletion:^(BOOL result) {
					[self endWriteTransaction];
                    if (completion) {
                        completion(result);
                    }
                }];
            }
        }
    }];
}


-(void) isActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=? and buddy_name=? "];
    [self executeScalar:query andArguments:@[accountNo, buddyname] withCompletion:^(NSObject * count) {
        BOOL toReturn=NO;
        if(count!=nil)
        {
            NSInteger val = [((NSNumber*)count) integerValue];
            if(val > 0) {
                toReturn=YES;
            }
        }

        if (completion) {
            completion(toReturn);
        }
    }];
}

-(void) updateActiveBuddy:(NSString*) buddyname setTime:(NSString *)timestamp forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"select lastMessageTime from  activechats where account_id=? and buddy_name=?"];
    [self beginWriteTransaction];
    [self executeScalar:query andArguments:@[accountNo, buddyname] withCompletion:^(NSObject *result) {
        NSString* lastTime = (NSString *) result;

        NSDate* lastDate = [self.dbFormatter dateFromString:lastTime];
        NSDate* newDate = [self.dbFormatter dateFromString:timestamp];

        if(lastDate.timeIntervalSince1970<newDate.timeIntervalSince1970) {
            NSString* query = [NSString stringWithFormat:@"update activechats set lastMessageTime=? where account_id=? and buddy_name=? "];
            [self executeNonQuery:query andArguments:@[timestamp, accountNo, buddyname] withCompletion:^(BOOL success) {
				[self endWriteTransaction];
                if(completion) completion(success);
            }];
        } else {
			[self endWriteTransaction];
			if(completion) completion(NO);
		}
    }];
}





#pragma mark chat properties
-(void) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion:(void (^)(NSNumber *))completion
{
    // count # messages from a specific user in messages table
    NSString* query = [NSString stringWithFormat:@"select count(message_history_id) from  message_history where unread=1 and account_id=? and message_from=?"];

    [self executeScalar:query andArguments:@[accountNo, buddy] withCompletion:^(NSObject* result) {
        if(completion)
        {
            completion((NSNumber *)result);
        }
    }];
}


-(void) countUserMessages:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion:(void (^)(NSNumber *))completion
{
    // count # messages from a specific user in messages table
    NSString* query = [NSString stringWithFormat:@"select count(message_history_id) from  message_history where account_id=? and message_from=? or message_to=? "];

    [self executeScalar:query andArguments:@[accountNo, buddy, buddy] withCompletion:^(NSObject* result) {
        if(completion)
        {
            completion((NSNumber *)result);
        }
    }];
}

#pragma db Commands

-(void) openDB
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *dbPath = [documentsDirectory stringByAppendingPathComponent:@"sworim.sqlite"];
    DDLogInfo(@"db path %@", dbPath);

    if(sqlite3_open_v2([dbPath UTF8String], &(self->database), SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
    {
        DDLogVerbose(@"Database opened");
    }
    else
    {
        //database error message
        DDLogError(@"Error opening database");
    }
    [self executeNonQuery:@"pragma journal_mode=WAL;" andArguments:nil];
    [self executeNonQuery:@"pragma synchronous=NORMAL;" andArguments:nil];

    //truncate faster than del
    [self executeNonQuery:@"pragma truncate;" andArguments:nil];

    self.dbFormatter = [[NSDateFormatter alloc] init];
    [self.dbFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    [self.dbFormatter  setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    if(!_version_check_done)
        [self version];
}

-(void) version
{
    [self beginWriteTransaction];

#if TARGET_OS_IPHONE
    // checking db version and upgrading if necessary
    DDLogVerbose(@"Database version check");

    NSNumber* dbversion=(NSNumber*)[self executeScalar:@"select dbversion from dbversion;" andArguments:nil];
    DDLogVerbose(@"Got db version %@", dbversion);

    if([dbversion doubleValue] < 1.07)
    {
        DDLogVerbose(@"Database version <1.07 detected. Performing upgrade");
        [self executeNonQuery:@"create table buddylistOnline (buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null,buddy_name varchar(50), group_name varchar(100));" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='1.07';" andArguments:nil];

        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IdleAlert"];

        DDLogVerbose(@"Upgrade to 1.07 success");
    }

    if([dbversion doubleValue] < 1.071)
    {
        DDLogVerbose(@"Database version <1.071 detected. Performing upgrade");
        [self executeNonQuery:@"drop table buddylistOnline;" andArguments:nil];

        [self executeNonQuery:@"drop table buddylist;" andArguments:nil];
        [self executeNonQuery:@"drop table messages;" andArguments:nil];
        [self executeNonQuery:@"drop table message_history;" andArguments:nil];
        [self executeNonQuery:@"drop table buddyicon;" andArguments:nil];

        [self executeNonQuery:@"create table buddylist(buddy_id integer not null primary key AUTOINCREMENT,account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50),nick_name varchar(50), group_name varchar(50),iconhash varchar(200),filename varchar(100),state varchar(20), status varchar(200),online bool, dirty bool, new bool);" andArguments:nil];

        [self executeNonQuery:@"create table messages(message_id integer not null primary key AUTOINCREMENT,account_id integer, message_from varchar(50) collate nocase,message_to varchar(50) collate nocase, timestamp datetime, message blob,notice integer,actual_from varchar(50) collate nocase);" andArguments:nil];

        [self executeNonQuery:@"create table message_history(message_history_id integer not null primary key AUTOINCREMENT,account_id integer, message_from varchar(50) collate nocase,message_to varchar(50) collate nocase,timestamp datetime , message blob,actual_from varchar(50) collate nocase);" andArguments:nil];

        [self executeNonQuery:@"create table activechats(account_id integer not null, buddy_name varchar(50) collate nocase);" andArguments:nil];


        [self executeNonQuery:@"update dbversion set dbversion='1.071';" andArguments:nil];

        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IdleAlert"];

        DDLogVerbose(@"Upgrade to 1.071 success");
    }


    if([dbversion doubleValue] < 1.072)
    {
        DDLogVerbose(@"Database version <1.072 detected. Performing upgrade on passwords. ");
        [self executeReader:@"select account_id, password from account" andArguments:nil];

        [self executeNonQuery:@"update account set password='';" andArguments:nil];
    }


    if([dbversion doubleValue] < 1.073)
    {
        DDLogVerbose(@"Database version <1.073 detected. Performing upgrade on passwords. ");

        //set defaults on upgrade
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"OfflineContact"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MessagePreview"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Logging"];

        [self executeNonQuery:@"update dbversion set dbversion='1.073';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 1.073 success");
    }

    if([dbversion doubleValue] < 1.074)
    {
        DDLogVerbose(@"Database version <1.074 detected. Performing upgrade on protocols. ");

        [self executeNonQuery:@"delete from protocol where protocol_id=3 " andArguments:nil];
        [self executeNonQuery:@"delete from protocol where protocol_id=4 " andArguments:nil];
        [self executeNonQuery:@" create table legacy_caps(capid integer not null primary key ,captext  varchar(20))" andArguments:nil];

        [self executeNonQuery:@" insert into legacy_caps values (1,'pmuc-v1');" andArguments:nil];
        [self executeNonQuery:@" insert into legacy_caps values (2,'voice-v1');" andArguments:nil];
        [self executeNonQuery:@" insert into legacy_caps values (3,'camera-v1');" andArguments:nil];
        [self executeNonQuery:@" insert into legacy_caps values (4, 'video-v1');" andArguments:nil];

        [self executeNonQuery:@"create table buddy_resources(buddy_id integer,resource varchar(255),ver varchar(20))" andArguments:nil];

        [self executeNonQuery:@"create table ver_info(ver varchar(20),cap varchar(255), primary key (ver,cap))" andArguments:nil];

        [self executeNonQuery:@"create table buddy_resources_legacy_caps (buddy_id integer,resource varchar(255),capid  integer);" andArguments:nil];

        [self executeNonQuery:@"update dbversion set dbversion='1.074';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 1.074 success");
    }

    if([dbversion doubleValue] < 1.1)
    {
        DDLogVerbose(@"Database version <1.1 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"alter table account add column selfsigned bool;" andArguments:nil];
        [self executeNonQuery:@"alter table account add column oldstyleSSL bool;" andArguments:nil];

        [self executeNonQuery:@"update dbversion set dbversion='1.1';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 1.1 success");
    }

    if([dbversion doubleValue] < 1.2)
    {
        DDLogVerbose(@"Database version <1.2 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"update  buddylist set iconhash=NULL;" andArguments:nil];
        [self executeNonQuery:@"alter table message_history  add column unread bool;" andArguments:nil];
        [self executeNonQuery:@" insert into message_history (account_id,message_from, message_to, timestamp, message, actual_from,unread) select account_id,message_from, message_to, timestamp, message, actual_from, 1  from messages ;" andArguments:nil];
        [self executeNonQuery:@"" andArguments:nil];

        [self executeNonQuery:@"update dbversion set dbversion='1.2';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 1.2 success");
    }

    //going to from 2.1 beta to final
    if([dbversion doubleValue] < 1.3)
    {
        DDLogVerbose(@"Database version <1.3 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"update  buddylist set iconhash=NULL;" andArguments:nil];

        [self executeNonQuery:@"update dbversion set dbversion='1.3';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 1.3 success");
    }

    if([dbversion doubleValue] < 1.31)
    {
        DDLogVerbose(@"Database version <1.31 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"alter table buddylist add column  Muc bool;" andArguments:nil];

        [self executeNonQuery:@"update dbversion set dbversion='1.31';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 1.31 success");
    }

    if([dbversion doubleValue] < 1.41)
    {
        DDLogVerbose(@"Database version <1.41 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"alter table message_history add column  delivered bool;" andArguments:nil];
        [self executeNonQuery:@"alter table message_history add column  messageid varchar(255);" andArguments:nil];
        [self executeNonQuery:@"update message_history set delivered=1;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='1.41';" andArguments:nil];

        DDLogVerbose(@"Upgrade to 1.41 success");
    }


    if([dbversion doubleValue] < 1.42)
    {
        DDLogVerbose(@"Database version <1.42 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"delete from protocol where protocol_id=5;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='1.42';" andArguments:nil];

        DDLogVerbose(@"Upgrade to 1.41 success");
    }
#else
    NSNumber* dbversion= (NSNumber*)[self executeScalar:@"select dbversion from dbversion" andArguments:nil];
    DDLogVerbose(@"Got db version %@", dbversion);
#endif

    if([dbversion doubleValue] < 1.5)
    {
        DDLogVerbose(@"Database version <1.5 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"alter table account add column oauth bool;" andArguments:nil withCompletion:nil];
        [self executeNonQuery:@"update dbversion set dbversion='1.5';" andArguments:nil withCompletion:nil];

        DDLogVerbose(@"Upgrade to 1.5 success");
    }

    if([dbversion doubleValue] < 1.6)
    {
        DDLogVerbose(@"Database version <1.6 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"alter table message_history add column messageType varchar(255);"  withCompletion:nil];
        [self executeNonQuery:@"update dbversion set dbversion='1.6';" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 1.6 success");
    }
    
    // this point forward OSX might have legacy issues

    if([dbversion doubleValue] < 2.0)
    {
        DDLogVerbose(@"Database version <2.0 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"drop table muc_favorites" withCompletion:nil];
        [self executeNonQuery:@"CREATE TABLE IF NOT EXISTS \"muc_favorites\" (\"mucid\" integer NOT NULL primary key autoincrement,\"room\" varchar(255,0),\"nick\" varchar(255,0),\"autojoin\" bool, account_id int);" withCompletion:nil];
        [self executeNonQuery:@"update dbversion set dbversion='2.0';" withCompletion:nil];
        [self executeNonQuery:@"alter table buddy_resources add column muc_role varchar(255);" withCompletion:nil];
        [self executeNonQuery:@"alter table buddylist add column muc_subject varchar(255);" withCompletion:nil];
        [self executeNonQuery:@"alter table buddylist add column muc_nick varchar(255);" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 2.0 success");
    }

    if([dbversion doubleValue] < 2.1)
    {
        DDLogVerbose(@"Database version <2.1 detected. Performing upgrade on accounts.");


        [self executeNonQuery:@"alter table message_history add column received bool;" withCompletion:nil];
        [self executeNonQuery:@"update dbversion set dbversion='2.1';" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 2.1 success");
    }

    if([dbversion doubleValue] < 2.2)
    {
        DDLogVerbose(@"Database version <2.2 detected. Performing upgrade.");

        [self executeNonQuery:@"alter table buddylist add column synchPoint datetime;" withCompletion:nil];
        [self executeNonQuery:@"update dbversion set dbversion='2.2';" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 2.2 success");
    }

    if([dbversion doubleValue] < 2.3)
    {
        DDLogVerbose(@"Database version <2.3 detected. Performing upgrade.");

        NSString* resourceQuery = [NSString stringWithFormat:@"update account set resource='%@';", [HelperTools encodeRandomResource]];

        [self executeNonQuery:resourceQuery withCompletion:nil];
        [self executeNonQuery:@"update dbversion set dbversion='2.3';" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 2.3 success");
    }

    //OMEMO begins below
    if([dbversion doubleValue] < 3.1)
    {
        DDLogVerbose(@"Database version <3.1 detected. Performing upgrade.");

        [self executeNonQuery:@"CREATE TABLE signalIdentity (deviceid int NOT NULL PRIMARY KEY, account_id int NOT NULL unique,identityPublicKey BLOB,identityPrivateKey BLOB)" withCompletion:nil];
        [self executeNonQuery:@"CREATE TABLE signalSignedPreKey (account_id int NOT NULL,signedPreKeyId int not null,signedPreKey BLOB);" withCompletion:nil];

        [self executeNonQuery:@"CREATE TABLE signalPreKey (account_id int NOT NULL,prekeyid int not null,preKey BLOB);" withCompletion:nil];

        [self executeNonQuery:@"CREATE TABLE signalContactIdentity ( account_id int NOT NULL,contactName text,contactDeviceId int not null,identity BLOB,trusted boolean);" withCompletion:nil];

        [self executeNonQuery:@"CREATE TABLE signalContactKey (account_id int NOT NULL,contactName text,contactDeviceId int not null, groupId text,senderKey BLOB);" withCompletion:nil];

        [self executeNonQuery:@"  CREATE TABLE signalContactSession (account_id int NOT NULL, contactName text, contactDeviceId int not null, recordData BLOB)" withCompletion:nil];
        [self executeNonQuery:@"alter table message_history add column encrypted bool;" withCompletion:nil];

        [self executeNonQuery:@"alter table message_history add column previewText text;" withCompletion:nil];
        [self executeNonQuery:@"alter table message_history add column previewImage text;" withCompletion:nil];

        [self executeNonQuery:@"alter table buddylist add column backgroundImage text;" withCompletion:nil];

        [self executeNonQuery:@"update dbversion set dbversion='3.1';" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 3.1 success");
    }


    if([dbversion doubleValue] < 3.2)
    {
        DDLogVerbose(@"Database version <3.2 detected. Performing upgrade.");

        [self executeNonQuery:@"update dbversion set dbversion='3.2';" withCompletion:nil];

        [self executeNonQuery:@"CREATE TABLE muteList (jid varchar(50));" withCompletion:nil];
        [self executeNonQuery:@"CREATE TABLE blockList (jid varchar(50));" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 3.2 success");
    }

    if([dbversion doubleValue] < 3.3)
    {
        DDLogVerbose(@"Database version <3.3 detected. Performing upgrade.");
        [self executeNonQuery:@"update dbversion set dbversion='3.3';" withCompletion:nil];

        [self executeNonQuery:@"alter table buddylist add column encrypt bool;" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 3.3 success");
    }

    if([dbversion doubleValue] < 3.4)
    {
        DDLogVerbose(@"Database version <3.4 detected. Performing upgrade.");
        [self executeNonQuery:@"update dbversion set dbversion='3.4';" withCompletion:nil];

        [self executeNonQuery:@" alter table activechats add COLUMN lastMessageTime datetime " withCompletion:nil];

        //iterate current active and set their times
        NSArray* active = [self executeReader:@"select distinct buddy_name, account_id from activeChats" andArguments:nil];
        [active enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary* row = (NSDictionary*)obj;
            //get max
            NSNumber* max = (NSNumber *)[self executeScalar:@"select max(TIMESTAMP) from message_history where (message_to=? or message_from=?) and account_id=?" andArguments:@[[row objectForKey:@"buddy_name"],[row objectForKey:@"buddy_name"], [row objectForKey:@"account_id"]]];
            if(max != nil) {
                [self executeNonQuery:@"update activechats set lastMessageTime=? where buddy_name=? and account_id=?" andArguments:@[max,[row objectForKey:@"buddy_name"], [row objectForKey:@"account_id"]]];
            } else  {

            }
        }];

        DDLogVerbose(@"Upgrade to 3.4 success");
    }

    if([dbversion doubleValue] < 3.5)
    {
        DDLogVerbose(@"Database version <3.5 detected. Performing upgrade.");
        [self executeNonQuery:@"update dbversion set dbversion='3.5';" withCompletion:nil];

        [self executeNonQuery:@"CREATE UNIQUE INDEX uniqueContact on buddylist (buddy_name, account_id);" withCompletion:nil];
        [self executeNonQuery:@"delete from buddy_resources" withCompletion:nil];
        [self executeNonQuery:@"CREATE UNIQUE INDEX uniqueResource on buddy_resources (buddy_id, resource);" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 3.5 success ");
    }


    if([dbversion doubleValue] < 3.6)
    {
        DDLogVerbose(@"Database version <3.6 detected. Performing upgrade.");
        [self executeNonQuery:@"update dbversion set dbversion='3.6';" withCompletion:nil];

        [self executeNonQuery:@"CREATE TABLE imageCache (url varchar(255), path varchar(255) );" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 3.6 success");
    }

    if([dbversion doubleValue] < 3.7)
    {

        DDLogVerbose(@"Database version <3.7 detected. Performing upgrade.");
        [self executeNonQuery:@"update dbversion set dbversion='3.7';" withCompletion:nil];

        [self executeNonQuery:@"alter table message_history add column stanzaid text;" withCompletion:nil];

        DDLogVerbose(@"Upgrade to 3.7 success");
    }

    if([dbversion doubleValue] < 3.8)
    {
        DDLogVerbose(@"Database version <3.8 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"alter table account add column airdrop bool;" andArguments:nil];

        [self executeNonQuery:@"update dbversion set dbversion='3.8';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 3.8 success");
    }

    if([dbversion doubleValue] < 3.9)
    {
        DDLogVerbose(@"Database version <3.9 detected. Performing upgrade on accounts.");

        [self executeNonQuery:@"alter table account add column rosterVersion varchar(50);" andArguments:nil];

        [self executeNonQuery:@"update dbversion set dbversion='3.9';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 3.9 success");
    }

    if([dbversion doubleValue] < 4.0)
     {
         DDLogVerbose(@"Database version <4.0 detected. Performing upgrade on accounts.");

         [self executeNonQuery:@"alter table message_history add column errorType varchar(50);" andArguments:nil];
         [self executeNonQuery:@"alter table message_history add column errorReason varchar(50);" andArguments:nil];

         [self executeNonQuery:@"update dbversion set dbversion='4.0';" andArguments:nil];
         DDLogVerbose(@"Upgrade to 4.0 success");
     }

    if([dbversion doubleValue] < 4.1)
     {
         DDLogVerbose(@"Database version <4.1 detected. Performing upgrade on accounts.");

         [self executeNonQuery:@"CREATE TABLE subscriptionRequests(requestid integer not null primary key AUTOINCREMENT,account_id integer not null,buddy_name varchar(50) collate nocase, UNIQUE(account_id,buddy_name))" andArguments:nil];

         [self executeNonQuery:@"update dbversion set dbversion='4.1';" andArguments:nil];
         DDLogVerbose(@"Upgrade to 4.1 success");
     }

    if([dbversion doubleValue] < 4.2)
     {
         DDLogVerbose(@"Database version <4.2 detected. Performing upgrade on accounts.");

         NSArray* contacts = [self executeReader:@"select distinct account_id, buddy_name, lastMessageTime from activechats;" andArguments:nil];
          [self executeNonQuery:@"delete from activechats;" andArguments:nil];
         [contacts enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
             [self executeNonQuery:@"insert into activechats (account_id, buddy_name, lastMessageTime) values (?,?,?);"
                      andArguments:@[
                      [obj objectForKey:@"account_id"],
                       [obj objectForKey:@"buddy_name"],
                       [obj objectForKey:@"lastMessageTime"]
                      ]];
         }];

          NSArray *dupeMessageids= [self executeReader:@"select * from (select messageid, count(messageid) as c from message_history   group by messageid) where c>1" andArguments:nil];


         [dupeMessageids enumerateObjectsUsingBlock:^(NSDictionary *  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                 NSArray* dupeMessages = [self executeReader:@"select * from message_history where messageid=? order by message_history_id asc " andArguments:@[[obj objectForKey:@"messageid"]]];
            //hopefully this is quick and doesnt grow..
             [dupeMessages enumerateObjectsUsingBlock:^(NSDictionary *  _Nonnull message, NSUInteger idx, BOOL * _Nonnull stop) {
                 //keep first one
                 if(idx > 0) {
                      [self executeNonQuery:@"delete from message_history where message_history_id=?" andArguments:@[[message objectForKey:@"message_history_id"]]];
                 }
             }];
         }];

         [self executeNonQuery:@"CREATE UNIQUE INDEX ux_account_messageid ON message_history(account_id, messageid)" andArguments:nil];

         [self executeNonQuery:@"alter table activechats add column lastMesssage blob;" andArguments:nil];
         [self executeNonQuery:@"CREATE UNIQUE INDEX ux_account_buddy ON activechats(account_id, buddy_name)" andArguments:nil];

         [self executeNonQuery:@"update dbversion set dbversion='4.2';" andArguments:nil];
         DDLogVerbose(@"Upgrade to 4.2 success");
     }

    if([dbversion doubleValue] < 4.3)
    {
        DDLogVerbose(@"Database version <4.3 detected. Performing upgrade on accounts.");
        [self executeNonQuery:@"alter table buddylist add column subscription varchar(50)" andArguments:nil];
        [self executeNonQuery:@"alter table buddylist add column ask varchar(50)" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.3';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.3 success");
    }

    if([dbversion doubleValue] < 4.4)
    {
        DDLogVerbose(@"Database version <4.4 detected. Performing upgrade on accounts.");
        [self executeNonQuery:@"update account set rosterVersion='0';" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.4';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.4 success");
    }

    if([dbversion doubleValue] < 4.5)
    {
        DDLogVerbose(@"Database version <4.5 detected. Performing upgrade on accounts.");
        [self executeNonQuery:@"alter table account add column state blob;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.5';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.5 success");
    }

    if([dbversion doubleValue] < 4.6)
    {
        DDLogVerbose(@"Database version <4.6 detected. Performing upgrade on accounts.");
        [self executeNonQuery:@"alter table buddylist add column messageDraft text;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.6';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.6 success");
    }

    if([dbversion doubleValue] < 4.7)
    {
        DDLogVerbose(@"Database version <4.7 detected. Performing upgrade on accounts.");
        // Delete column password,account_name from account, set default value for rosterVersion to 0, increased varchar size
        [self executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:nil];
        [self executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'protocol_id' integer NOT NULL, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:nil];
        [self executeNonQuery:@"INSERT INTO account (account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"UPDATE account SET rosterVersion='0' WHERE rosterVersion is NULL;" andArguments:nil];
        [self executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.7';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.7 success");
    }

    if([dbversion doubleValue] < 4.71)
    {
        DDLogVerbose(@"Database version <4.71 detected. Performing upgrade on accounts.");
        // Only reset server to '' when server == domain
        [self executeNonQuery:@"UPDATE account SET server='' where server=domain;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.71';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.71 success");
    }
    
    if([dbversion doubleValue] < 4.72)
    {
        DDLogVerbose(@"Database version <4.72 detected. Performing upgrade on accounts.");
        // Delete column protocol_id from account and drop protocol table
        [self executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:nil];
        [self executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:nil];
        [self executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:nil];
        [self executeNonQuery:@"DROP TABLE protocol;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.72';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.72 success");
    }
    
    if([dbversion doubleValue] < 4.73)
    {
        DDLogVerbose(@"Database version <4.73 detected. Performing upgrade on accounts.");
        // Delete column oauth from account
        [self executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:nil];
        [self executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:nil];
        [self executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.73';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.73 success");
    }
    
    if([dbversion doubleValue] < 4.74)
    {
        DDLogVerbose(@"Database version <4.74 detected. Performing upgrade on accounts.");
        // Rename column oldstyleSSL to directTLS
        [self executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:nil];
        [self executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:nil];
        [self executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.74';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.74 success");
    }
    
    if([dbversion doubleValue] < 4.75)
    {
        DDLogVerbose(@"Database version <4.75 detected. Performing upgrade on accounts.");
        // Delete column secure from account
        [self executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:nil];
        [self executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:nil];
        [self executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state from _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.75';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.75 success");
    }
    
    if([dbversion doubleValue] < 4.76)
    {
        DDLogVerbose(@"Database version <4.76 detected. Performing upgrade on accounts.");
        // Add column for the last interaction of a contact
        [self executeNonQuery:@"alter table buddylist add column lastInteraction INTEGER NOT NULL DEFAULT 0;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.76';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.76 success");
    }
    
    if([dbversion doubleValue] < 4.77)
    {
        DDLogVerbose(@"Database version <4.77 detected. Performing upgrade on accounts.");
        // drop legacy caps tables
        [self executeNonQuery:@"DROP TABLE IF EXISTS legacy_caps;" andArguments:nil];
        [self executeNonQuery:@"DROP TABLE IF EXISTS buddy_resources_legacy_caps;" andArguments:nil];
        //recreate capabilities cache to make a fresh start
        [self executeNonQuery:@"DROP IF EXISTS TABLE ver_info;" andArguments:nil];
        [self executeNonQuery:@"CREATE TABLE ver_info(ver VARCHAR(32), cap VARCHAR(255), PRIMARY KEY (ver,cap));" andArguments:nil];
        [self executeNonQuery:@"CREATE TABLE ver_timestamp (ver VARCHAR(32), timestamp INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (ver));" andArguments:nil];
        [self executeNonQuery:@"CREATE INDEX timeindex ON ver_timestamp(timestamp);"  andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.77';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.77 success");
    }
    
    if([dbversion doubleValue] < 4.78)
    {
        DDLogVerbose(@"Database version <4.78 detected. Performing upgrade on accounts.");
        // drop airdrop column
        [self executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:nil];
        [self executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:nil];
        [self executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state from _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:nil];
        [self executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:nil];
        [self executeNonQuery:@"update dbversion set dbversion='4.78';" andArguments:nil];
        DDLogVerbose(@"Upgrade to 4.78 success");
    }
    
    [self endWriteTransaction];
    _version_check_done = YES;
    return;
}

-(void) dealloc
{
    DDLogVerbose(@"Closing database");
    sqlite3_close(self->database);
}


#pragma mark determine message type

-(void) messageTypeForMessage:(NSString *) messageString withKeepThread:(BOOL) keepThread andCompletion:(void(^)(NSString *messageType)) completion
{
	dispatch_semaphore_t semaphore;
    __block NSString* messageType = kMessageTypeText;
    if([messageString rangeOfString:@" "].location != NSNotFound) {
        if(completion) {
            completion(messageType);
        }
        return;
    }

    if ([messageString hasPrefix:@"xmpp:"]) {
           messageType=kMessageTypeUrl;
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey: @"ShowImages"] &&
        ([messageString hasPrefix:@"HTTPS://"] || [messageString hasPrefix:@"https://"] || [messageString hasPrefix:@"aesgcm://"])) {
            NSString *cleaned = [messageString stringByReplacingOccurrencesOfString:@"aesgcm://" withString:@"https://"];
            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:cleaned]];
            request.HTTPMethod = @"HEAD";
            request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;

			if(keepThread && completion)
				semaphore = dispatch_semaphore_create(0);
            NSURLSession *session = [NSURLSession sharedSession];
            [[session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError* _Nullable error) {
                NSDictionary* headers = ((NSHTTPURLResponse*)response).allHeaderFields;
                NSString* contentType = [headers objectForKey:@"Content-Type"];
                if([contentType hasPrefix:@"image/"])
                {
                    messageType = kMessageTypeImage;
                }
                else  {
                    messageType = kMessageTypeUrl;
                }

                if(completion)
				{
					if(keepThread)
						dispatch_semaphore_signal(semaphore);
					else
						completion(messageType);
				}
            }] resume];

			if(keepThread && completion)
			{
				dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
				completion(messageType);
			}
    } else if ([messageString hasPrefix:@"geo:"]) {
        messageType = kMessageTypeGeo;

        if(completion) {
            completion(messageType);
        }
    } else
        if(completion) {
            completion(messageType);
        }
}


#pragma mark mute and block
-(void) muteJid:(NSString*) jid
{
    if(!jid) return;
    NSString* query = [NSString stringWithFormat:@"insert into muteList(jid) values(?)"];
    NSArray* params = @[jid];
    [self executeNonQuery:query andArguments:params];
}

-(void) unMuteJid:(NSString*) jid
{
    if(!jid) return;
    NSString* query = [NSString stringWithFormat:@"delete from muteList where jid=?"];
    NSArray* params = @[jid];
    [self executeNonQuery:query andArguments:params];
}

-(void) isMutedJid:(NSString*) jid withCompletion: (void (^)(BOOL))completion
{
    if(!jid) return;
    NSString* query = [NSString stringWithFormat:@"select count(jid) from muteList where jid=?"];
    NSArray* params = @[jid];
    [self executeScalar:query andArguments:params withCompletion:^(NSObject *val) {
        NSNumber* count = (NSNumber *) val;
        BOOL toreturn=NO;
        if(count.integerValue > 0)
        {
            toreturn=YES;
        }
        if(completion) completion(toreturn);
    }];
}


-(void) blockJid:(NSString*) jid
{
    if(!jid ) return;
    NSString* query = [NSString stringWithFormat:@"insert into blockList(jid) values(?)"];
    NSArray* params = @[jid];
    [self executeNonQuery:query andArguments:params];
}

-(void) unBlockJid:(NSString*) jid
{
    if(!jid ) return;
    NSString* query = [NSString stringWithFormat:@"delete from blockList where jid=?"];
    NSArray* params = @[jid];
    [self executeNonQuery:query andArguments:params];
}

-(void) isBlockedJid:(NSString*) jid withCompletion: (void (^)(BOOL))completion
{
    if(!jid) return completion(NO);
    NSString* query = [NSString stringWithFormat:@"select count(jid) from blockList where jid=?"];
    NSArray* params = @[jid];
    [self executeScalar:query andArguments:params withCompletion:^(NSObject *val) {
        NSNumber *count= (NSNumber *) val;
        BOOL toreturn=NO;
        if(count.integerValue>0)
        {
            toreturn=YES;
        }
        if(completion) completion(toreturn);
    }];
}

#pragma mark - Images

-(void) createImageCache:(NSString *) path forUrl:(NSString*) url
{
    NSString* query = [NSString stringWithFormat:@"insert into imageCache(url, path) values(?, ?)"];
    NSArray* params = @[url, path];
    [self executeNonQuery:query andArguments:params];
}

-(void) deleteImageCacheForUrl:(NSString*) url
{
    NSString* query = [NSString stringWithFormat:@"delete from imageCache where url=?"];
    NSArray* params = @[url];
    [self executeNonQuery:query andArguments:params];
}

-(void) imageCacheForUrl:(NSString*) url withCompletion: (void (^)(NSString *path))completion
{
    if(!url) return;
    NSString* query = [NSString stringWithFormat:@"select path from imageCache where url=?"];
    NSArray* params = @[url];
    [self executeScalar:query andArguments:params withCompletion:^(NSObject *val) {
        NSString *path= (NSString *) val;
        if(completion) completion(path);
    }];
}

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSString*) accountNo
{
    if(!accountNo ||! contact) return nil;
    NSString* query = [NSString stringWithFormat:@"select distinct A.* from imageCache as A inner join  message_history as B on message = a.url where account_id=? and actual_from=? order by message_history_id desc"];
    NSArray* params = @[accountNo, contact];
    NSMutableArray* toReturn = [[self executeReader:query andArguments:params] mutableCopy];

    if(toReturn!=nil)
    {
        DDLogVerbose(@"attachment  count: %lu",  (unsigned long)[toReturn count]);
        return toReturn;
    }
    else
    {
        DDLogError(@"attachment list  is empty or failed to read");
        return nil;
    }

}

-(NSDate*) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountNo:(NSString* _Nonnull) accountNo
{
    NSAssert(jid, @"jid should not be null");
    NSAssert(accountNo != NULL, @"accountNo should not be null");

    NSString* query = [NSString stringWithFormat:@"SELECT lastInteraction from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, jid];
    NSNumber* lastInteractionTime = (NSNumber*)[self executeScalar:query andArguments:params];

    //return NSDate object or NSNull, if last interaction is zero
    if(![lastInteractionTime integerValue])
        return nil;
    return [NSDate dateWithTimeIntervalSince1970:[lastInteractionTime integerValue]];
}

-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andAccountNo:(NSString* _Nonnull) accountNo
{
    NSAssert(jid, @"jid should not be null");
    NSAssert(accountNo != NULL, @"accountNo should not be null");

    NSNumber* timestamp = @0;       //default value for "online" or "unknown"
    if(lastInteractionTime)
        timestamp = [NSNumber numberWithInt:lastInteractionTime.timeIntervalSince1970];

    NSString* query = [NSString stringWithFormat:@"UPDATE buddylist SET lastInteraction=? WHERE account_id=? and buddy_name=?"];
    NSArray* params = @[timestamp, accountNo, jid];
    [self executeNonQuery:query andArguments:params];
}

#pragma mark -  encryption

-(BOOL) shouldEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return NO;
    NSString* query = [NSString stringWithFormat:@"SELECT encrypt from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, jid];
    NSNumber* status=(NSNumber*)[self executeScalar:query andArguments:params];
    return [status boolValue];
}


-(void) encryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return;
    NSString* query = [NSString stringWithFormat:@"update buddylist set encrypt=1 where account_id=?  and buddy_name=?"];
    NSArray* params = @[ accountNo, jid];
    [self executeNonQuery:query andArguments:params];
    return;
}

-(void) disableEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return ;
    NSString* query = [NSString stringWithFormat:@"update buddylist set encrypt=0 where account_id=?  and buddy_name=?"];
    NSArray* params = @[ accountNo, jid];
    [self executeNonQuery:query andArguments:params];
    return;
}

@end
