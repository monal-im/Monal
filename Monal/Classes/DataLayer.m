//
//  DataLayer.m
//  SworIM
//
//  Created by Anurodh Pokharel on 3/28/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "DataLayer.h"
#import "DDLog.h"


#if TARGET_OS_IPHONE
#import "PasswordManager.h"
#else

#endif

@implementation DataLayer

static const int ddLogLevel = LOG_LEVEL_INFO;

 NSString *const kAccountID= @"account_id";

//used for account rows
 NSString *const kAccountName =@"account_name";
 NSString *const kDomain =@"domain";
 NSString *const kEnabled =@"enabled";

 NSString *const kServer =@"server";
 NSString *const kPort =@"other_port";
 NSString *const kResource =@"resource";
 NSString *const kSSL =@"secure";
 NSString *const kOldSSL =@"oldstyleSSL";
 NSString *const kOauth =@"oauth";
 NSString *const kSelfSigned =@"selfsigned";

NSString *const kUsername =@"username";
NSString *const kFullName =@"full_name";


// used for contact rows
NSString *const kContactName =@"buddy_name";
NSString *const kCount =@"count";

static DataLayer *sharedInstance=nil;

+ (DataLayer* )sharedInstance
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sharedInstance = [DataLayer alloc] ;
        [sharedInstance initDB];
    });
    return sharedInstance;
    
}

#pragma mark  -- V1 low level
-(NSObject*) executeScalar:(NSString*) query
{
    if(!query) return nil;
    NSObject* __block toReturn;
    dispatch_sync(_dbQueue, ^{
        sqlite3_stmt *statement;
        if (sqlite3_prepare_v2(database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
            if (sqlite3_step(statement) == SQLITE_ROW)
            {
                switch(sqlite3_column_type(statement,0))
                {
                        // SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
                    case (SQLITE_INTEGER):
                    {
                        NSNumber* returnInt= [NSNumber numberWithInt:sqlite3_column_int(statement,0)];
                        while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        toReturn= returnInt;
                        break;
                    }
                        
                    case (SQLITE_FLOAT):
                    {
                        NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement,0)];
                        while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        toReturn= returnInt;
                        break;
                    }
                        
                    case (SQLITE_TEXT):
                    {
                        NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,0)];
                        //	DDLogVerbose(@"got %@", returnString);
                        while(sqlite3_step(statement)== SQLITE_ROW ){} //clear
                        toReturn= [returnString  stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
                        break;
                        
                    }
                        
                    case (SQLITE_BLOB):
                    {
                        //trat as string for now
                        NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,0)];
                        while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        toReturn= [returnString  stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
                        toReturn= nil;
                        break;
                    }
                        
                    case (SQLITE_NULL):
                    {
                        DDLogVerbose(@"return nil with sql null");
                        while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        toReturn= nil;
                        break;
                    }
                        
                }
                
            } else
            {DDLogVerbose(@"return nil with no row");
                toReturn= nil;};
        }
        else{
            //if noting else
            DDLogVerbose(@"returning nil with out OK %@", query);
            toReturn= nil;
        }
    });
    
    return toReturn;
}

-(NSArray*) executeReader:(NSString*) query
{
    if(!query) return nil;
    NSMutableArray* __block toReturn =  [[NSMutableArray alloc] init] ;
    dispatch_sync(_dbQueue, ^{
        sqlite3_stmt *statement;
        if (sqlite3_prepare_v2(database, [query cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
            
            while (sqlite3_step(statement) == SQLITE_ROW) {
                NSMutableDictionary* row= [[NSMutableDictionary alloc] init];
                int counter=0;
                while(counter< sqlite3_column_count(statement) )
                {
                    NSString* columnName=[NSString stringWithUTF8String:sqlite3_column_name(statement,counter)];
                    
                    switch(sqlite3_column_type(statement,counter))
                    {
                            // SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
                        case (SQLITE_INTEGER):
                        {
                            NSNumber* returnInt= [NSNumber numberWithInt:sqlite3_column_int(statement,counter)];
                            [row setObject:returnInt forKey:columnName];
                            break;
                        }
                            
                        case (SQLITE_FLOAT):
                        {
                            NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement,counter)];
                            [row setObject:returnInt forKey:columnName];
                            break;
                        }
                            
                        case (SQLITE_TEXT):
                        {
                            NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,counter)];
                            [row setObject:[returnString stringByReplacingOccurrencesOfString:@"''" withString:@"'"] forKey:columnName];
                            break;
                            
                        }
                            
                        case (SQLITE_BLOB):
                        {
                            //trat as string for now
                            NSString* returnblob = [NSString stringWithUTF8String:sqlite3_column_text(statement,counter)];
                            [row setObject:[returnblob stringByReplacingOccurrencesOfString:@"''" withString:@"'"] forKey:columnName];
                            break;
                            
                            
                            //Note: add blob support  as nsdata later
                            
                            //char* data= sqlite3_value_text(statement);
                            ///NSData* returnData =[NSData dataWithBytes:]
                            
                        }
                            
                        case (SQLITE_NULL):
                        {
                            DDLogVerbose(@"return nil with sql null");
                            
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
    });
    
    return toReturn;
}

-(BOOL) executeNonQuery:(NSString*) query
{
     if(!query) return NO;
    BOOL __block toReturn;
    dispatch_sync(_dbQueue, ^{
        sqlite3_stmt *statement;
        if (sqlite3_prepare_v2(database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK)
        {
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
    });
    
    return toReturn;
}




#pragma mark -- V2 low level
-(void) executeScalar:(NSString*) query withCompletion: (void (^)(NSObject *))completion
{
    if(!query)
    {
        if(completion) {
            completion(nil);
        }
    }
    
    dispatch_async(_dbQueue, ^{
        NSObject* toReturn;
        sqlite3_stmt *statement;
        if (sqlite3_prepare_v2(database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
            if (sqlite3_step(statement) == SQLITE_ROW)
            {
                switch(sqlite3_column_type(statement,0))
                {
                        // SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
                    case (SQLITE_INTEGER):
                    {
                        NSNumber* returnInt= [NSNumber numberWithInt:sqlite3_column_int(statement,0)];
                        while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        toReturn= returnInt;
                        break;
                    }
                        
                    case (SQLITE_FLOAT):
                    {
                        NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement,0)];
                        while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        toReturn= returnInt;
                        break;
                    }
                        
                    case (SQLITE_TEXT):
                    {
                        NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,0)];
                        //	DDLogVerbose(@"got %@", returnString);
                        while(sqlite3_step(statement)== SQLITE_ROW ){} //clear
                        toReturn= [returnString  stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
                        break;
                        
                    }
                        
                    case (SQLITE_BLOB):
                    {
                        //trat as string for now
                        NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,0)];
                        while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        toReturn= [returnString  stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
                        toReturn= nil;
                        break;
                    }
                        
                    case (SQLITE_NULL):
                    {
                        DDLogVerbose(@"return nil with sql null");
                        while(sqlite3_step(statement)== SQLITE_ROW) {} //clear
                        toReturn= nil;
                        break;
                    }
                        
                }
                
            } else
            {DDLogVerbose(@"return nil with no row");
                toReturn= nil;};
        }
        else{
            //if noting else
            DDLogVerbose(@"returning nil with out OK %@", query);
            toReturn= nil;
        }
        
        if(completion) {
            completion(toReturn);
        }
    });

}

-(void) executeReader:(NSString*) query withCompletion: (void (^)(NSArray *))completion;
{
    if(!query)
    {
        if(completion) {
            completion(nil);
        }
    }
   
    dispatch_async(_dbQueue, ^{
        
        NSMutableArray*  toReturn =  [[NSMutableArray alloc] init] ;
        
        sqlite3_stmt *statement;
        if (sqlite3_prepare_v2(database, [query cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK) {
            
            while (sqlite3_step(statement) == SQLITE_ROW) {
                NSMutableDictionary* row= [[NSMutableDictionary alloc] init];
                int counter=0;
                while(counter< sqlite3_column_count(statement) )
                {
                    NSString* columnName=[NSString stringWithUTF8String:sqlite3_column_name(statement,counter)];
                    
                    switch(sqlite3_column_type(statement,counter))
                    {
                            // SQLITE_INTEGER, SQLITE_FLOAT, SQLITE_TEXT, SQLITE_BLOB, or SQLITE_NULL
                        case (SQLITE_INTEGER):
                        {
                            NSNumber* returnInt= [NSNumber numberWithInt:sqlite3_column_int(statement,counter)];
                            [row setObject:returnInt forKey:columnName];
                            break;
                        }
                            
                        case (SQLITE_FLOAT):
                        {
                            NSNumber* returnInt= [NSNumber numberWithDouble:sqlite3_column_double(statement,counter)];
                            [row setObject:returnInt forKey:columnName];
                            break;
                        }
                            
                        case (SQLITE_TEXT):
                        {
                            NSString* returnString = [NSString stringWithUTF8String:sqlite3_column_text(statement,counter)];
                            [row setObject:[returnString stringByReplacingOccurrencesOfString:@"''" withString:@"'"] forKey:columnName];
                            break;
                            
                        }
                            
                        case (SQLITE_BLOB):
                        {
                            //trat as string for now
                            NSString* returnblob = [NSString stringWithUTF8String:sqlite3_column_text(statement,counter)];
                            [row setObject:[returnblob stringByReplacingOccurrencesOfString:@"''" withString:@"'"] forKey:columnName];
                            break;
                            
                            
                            //Note: add blob support  as nsdata later
                            
                            //char* data= sqlite3_value_text(statement);
                            ///NSData* returnData =[NSData dataWithBytes:]
                            
                        }
                            
                        case (SQLITE_NULL):
                        {
                            DDLogVerbose(@"return nil with sql null");
                            
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
        
        if(completion) {
            completion(toReturn);
        }
    });
    
}

-(void) executeNonQuery:(NSString*) query withCompletion: (void (^)(BOOL))completion
{
    if(!query)
    {
        if(completion) {
            completion(NO);
        }
    }
    
    BOOL __block toReturn;
    dispatch_async(_dbQueue, ^{
        sqlite3_stmt *statement;
        if (sqlite3_prepare_v2(database, [query  cStringUsingEncoding:NSUTF8StringEncoding], -1, &statement, NULL) == SQLITE_OK)
        {
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
        if (completion)
        {
            completion(toReturn);
        }
    });
    

}

#pragma mark account commands

-(NSArray*) protocolList
{
    NSString* query=[NSString stringWithFormat:@"select * from protocol where protocol_id<=3 or protocol_id=5 order by protocol_id asc"];
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        
        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count] );
        return toReturn;
    }
    else
    {
        DDLogError(@"protocol list  is empty or failed to read");
        return nil;
    }
}

-(NSArray*) accountList
{
    NSString* query=[NSString stringWithFormat:@"select * from account order by account_id asc "];
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        
        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count] );
        
        return toReturn;
    }
    else
    {
        DDLogError(@"account list  is empty or failed to read");
        
        return nil;
    }
    
}

-(NSArray*) enabledAccountList
{
    NSString* query=[NSString stringWithFormat:@"select * from account where enabled=1 order by account_id asc "];
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        
        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count] );
        
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

-(NSArray*) accountVals:(NSString*) accountNo
{
    NSString* query=[NSString stringWithFormat:@"select * from account where  account_id=%@ ", accountNo];
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        
        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count] );
        return toReturn;
    }
    else
    {
        DDLogError(@"account list  is empty or failed to read");
        return nil;
    }
    
}


-(void) updateAccounWithDictionary:(NSDictionary *) dictionary andCompletion:(void (^)(BOOL))completion;
{
    NSString* query=
    [NSString stringWithFormat:@"update account  set account_name='%@', protocol_id=%@, server='%@', other_port='%@', username='%@', password='%@', secure=%d, resource='%@', domain='%@', enabled=%d, selfsigned=%d, oldstyleSSL=%d, oauth=%d  where account_id=%@",
     ((NSString *)[dictionary objectForKey:kUsername]).escapeForSql,
     @"1",
     ((NSString *)[dictionary objectForKey:kServer]).escapeForSql,
     ((NSString *)[dictionary objectForKey:kPort]),
     ((NSString *)[dictionary objectForKey:kUsername]).escapeForSql,
     @"",
     [[dictionary objectForKey:kSSL] boolValue],
     ((NSString *)[dictionary objectForKey:kResource]).escapeForSql,
     ((NSString *)[dictionary objectForKey:kDomain]).escapeForSql,
     [[dictionary objectForKey:kEnabled] boolValue],
     [[dictionary objectForKey:kSelfSigned] boolValue],
     [[dictionary objectForKey:kOldSSL] boolValue],
     [[dictionary objectForKey:kOauth] boolValue],
     [dictionary objectForKey:kAccountID]
     
     ];
    
    [self executeNonQuery:query withCompletion:completion];
}

-(void) addAccountWithDictionary:(NSDictionary *) dictionary andCompletion: (void (^)(BOOL))completion
{
    NSString* query= [NSString stringWithFormat:@"insert into account values(null, '%@', %@, '%@', '%@', '%@', '%@', %d, '%@', '%@', %d, %d, %d, %d) ",
                      ((NSString *)[dictionary objectForKey:kUsername]).escapeForSql,
                      @"1",
                      ((NSString *) [dictionary objectForKey:kServer]).escapeForSql,
                      ((NSString *)[dictionary objectForKey:kPort]).escapeForSql,
                      ((NSString *)[dictionary objectForKey:kUsername]).escapeForSql,
                      @"", [[dictionary objectForKey:kSSL] boolValue],
                      ((NSString *)[dictionary objectForKey:kResource]).escapeForSql,
                      ((NSString *)[dictionary objectForKey:kDomain]).escapeForSql,
                      [[dictionary objectForKey:kEnabled] boolValue],
                      [[dictionary objectForKey:kSelfSigned] boolValue],
                      [[dictionary objectForKey:kOldSSL] boolValue],
                      [[dictionary objectForKey:kOauth] boolValue]
                      ];
    
    [self executeNonQuery:query withCompletion:completion];
   
}


-(BOOL) removeAccount:(NSString*) accountNo
{
    // remove all other traces of the account_id
    NSString* query1=[NSString stringWithFormat:@"delete from buddylist  where account_id=%@ ;", accountNo];
    [self executeNonQuery:query1];
    
    NSString* query3=[NSString stringWithFormat:@"delete from message_history  where account_id=%@ ;", accountNo];
    [self executeNonQuery:query3];
    
    NSString* query4=[NSString stringWithFormat:@"delete from activechats  where account_id=%@ ;", accountNo];
    [self executeNonQuery:query4];
    
    NSString* query=[NSString stringWithFormat:@"delete from account  where account_id=%@ ;", accountNo];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}


-(BOOL) disableEnabledAccount:(NSString*) accountNo
{
    
    NSString* query=[NSString stringWithFormat:@"update account set enabled=0 where account_id=%@  ", accountNo];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}








#pragma mark Buddy Commands


-(BOOL) addBuddy:(NSString*) buddy  forAccount:(NSString*) accountNo fullname:(NSString*) fullName nickname:(NSString*) nickName
{
    __block BOOL toReturn=NO;
    //this needs to be one atomic operation
    dispatch_sync(_contactQueue, ^{
        if(![self isBuddyInList:buddy forAccount:accountNo]) {
            
            // no blank full names
            NSString* actualfull;
            if([[fullName  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]==0) {
                actualfull=buddy;
            }
            else {
                actualfull=fullName;
            }
            
            NSString* query=[NSString stringWithFormat:@"insert into buddylist values(null, %@, '%@', '%@','%@','','','','','',0, 0, 1,0);", accountNo, buddy.escapeForSql, actualfull.escapeForSql, nickName.escapeForSql];
            if([self executeNonQuery:query]!=NO)
            {
                toReturn= YES;
            }
            else
            {
                
            }
        }
    });
    
    return toReturn;
    
}

-(BOOL) removeBuddy:(NSString*) buddy forAccount:(NSString*) accountNo
{
    
    //clean up logs
    [self messageHistoryClean:buddy :accountNo];
    
    NSString* query=[NSString stringWithFormat:@"delete from buddylist  where account_id=%@ and buddy_name='%@';", accountNo, buddy.escapeForSql];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}
-(BOOL) clearBuddies:(NSString*) accountNo
{
    
    NSString* query=[NSString stringWithFormat:@"delete from buddylist  where account_id=%@ ;", accountNo];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}


#pragma mark Buddy Property commands

-(BOOL) resetContacts
{
    NSString* query2=[NSString stringWithFormat:@"delete from  buddy_resources ;   "];
    [self executeNonQuery:query2];
    
    
    NSString* query=[NSString stringWithFormat:@"update buddylist set dirty=0, new=0, online=0, state='offline', status='';   "];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
    
}

-(BOOL) resetContactsForAccount:(NSString*) accountNo
{
    NSString* query2=[NSString stringWithFormat:@"delete from  buddy_resources  where buddy_id in (select buddy_id from  buddylist where account_id=%@);   ", accountNo];
    [self executeNonQuery:query2];
    
    
    NSString* query=[NSString stringWithFormat:@"update buddylist set dirty=0, new=0, online=0, state='offline', status='' where account_id=%@;   ", accountNo];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
    
}

-(void) contactForUsername:(NSString*) username forAccount: (NSString*) accountNo withCompletion: (void (^)(NSArray *))completion
{
    NSString* query= query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0, ifnull(full_name, buddy_name) as full_name, account_id from buddylist where buddy_name='%@' and account_id=%@", username.escapeForSql, accountNo];
    
    //DDLogVerbose(query);
    [self executeReader:query withCompletion:^(NSArray * toReturn) {
        if(toReturn!=nil)
        {
            DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count] );
            
        }
        else
        {
            DDLogError(@"buddylist is empty or failed to read");
        }
        
        if(completion) {
            completion(toReturn);
        }
    }];
     
}


-(NSArray*) searchContactsWithString:(NSString*) search
{
    NSString* query=@"";
    
    
    query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0 as 'count' , ifnull(full_name, buddy_name) as full_name, account_id, online from buddylist where buddy_name like '%%%@%%' or full_name like '%%%@%%'  order by full_name COLLATE NOCASE asc ", search, search];
    
    
    //DDLogVerbose(query);
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count] );
        return toReturn;
    }
    else
    {
        DDLogError(@"buddylist is empty or failed to read");
        return nil;
    }
    
}

-(NSArray*) onlineContactsSortedBy:(NSString*) sort
{
    NSString* query=@"";
    
    if([sort isEqualToString:@"Name"])
    {
        query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0 as 'count' , ifnull(full_name, buddy_name) as full_name, account_id from buddylist where online=1    order by full_name COLLATE NOCASE asc "];
    }
    
    if([sort isEqualToString:@"Status"])
    {
        query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0 as 'count', ifnull(full_name, buddy_name) as full_name, account_id from buddylist where   online=1   order by state,full_name COLLATE NOCASE  asc "];
    }
    
    //DDLogVerbose(query);
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count] );
        return toReturn;
    }
    else
    {
        DDLogError(@"buddylist is empty or failed to read");
        return nil;
    }
    
}

-(NSArray*) offlineContacts
{
    
    NSString* query=[NSString stringWithFormat:@"select buddy_name,state,status,filename,0, ifnull(full_name, buddy_name) as full_name, a.account_id from buddylist  as A inner join account as b  on a.account_id=b.account_id  where  online=0 and enabled=1 order by full_name COLLATE NOCASE "];
    //DDLogVerbose(query);
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count] );
        return toReturn;
    }
    else
    {
        DDLogError(@"buddylist is empty or failed to read");
        return nil;
    }
    
    
}



#pragma mark Ver string and Capabilities

//-(BOOL) setResourceVer:(presence*)presenceObj: (NSString*) accountNo
//{
//
//    //get buddyid for name and account
//
//    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user ];
//
//    NSString* buddyid = [self executeScalar:query1];
//
//    if(buddyid==nil) return NO;
//
//
//
//    NSString* query=[NSString stringWithFormat:@"update buddy_resources set ver='%@' where buddy_id=%@ and resource='%@'", presenceObj.ver, buddyid, presenceObj.resource ];
//	if([self executeNonQuery:query]!=NO)
//	{
//
//		;
//		return YES;
//	}
//	else
//	{
//        ;
//		return NO;
//	}
//}

-(BOOL) checkCap:(NSString*)cap forUser:(NSString*) user accountNo:(NSString*) acctNo
{
    NSString* query=[NSString stringWithFormat:@"select count(*) from buddylist as a inner join buddy_resources as b on a.buddy_id=b.buddy_id  inner join ver_info as c  on  b.ver=c.ver where buddy_name='%@' and account_id=%@ and cap='%@'", user.escapeForSql, acctNo,cap.escapeForSql ];
    
    //DDLogVerbose(@"%@", query);
    NSNumber* count = (NSNumber*) [self executeScalar:query];
    
    if([count integerValue]>0) return YES; else return NO;
}

-(NSArray*) capsforVer:(NSString*) verString
{
    
    
    NSString* query=[NSString stringWithFormat:@"select cap from ver_info where ver='%@'", verString.escapeForSql];
    
    //DDLogVerbose(query);
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        
        if([toReturn count]==0) return nil;
        
        DDLogVerbose(@" caps  count: %lu",  (unsigned long)[toReturn count] );
        return toReturn; //[toReturn autorelease];
    }
    else
    {
        DDLogError(@"caps list is empty");
        return nil;
    }
    
}

-(NSString*)getVerForUser:(NSString*)user Resource:(NSString*) resource
{
    NSString* query1=[NSString stringWithFormat:@" select ver from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where resource='%@' and buddy_name='%@'", resource.escapeForSql, user.escapeForSql ];
    
    NSString* ver = (NSString*) [self executeScalar:query1];
    
    return ver;
    
}

-(BOOL)setFeature:(NSString*)feature  forVer:(NSString*) ver
{
    NSString* query=[NSString stringWithFormat:@"insert into ver_info values ('%@', '%@')", ver.escapeForSql,feature.escapeForSql];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

#pragma mark legacy caps

-(void) clearLegacyCaps
{
    NSString* query=[NSString stringWithFormat:@"delete from buddy_resources_legacy_caps"];
    
    //DDLogVerbose(@"%@", query);
    [self executeNonQuery:query];
    
    return;
}

//-(BOOL) setLegacyCap:(NSString*)cap forUser:(presence*)presenceObj accountNo:(NSString*) acctNo
//{
//    if (presenceObj.resource==nil) return NO;
//
//    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", acctNo, presenceObj.user ];
//
//    NSString* buddyid = [self executeScalar:query1];
//
//    if(buddyid==nil) return NO;
//
//
//    NSString* query2=[NSString stringWithFormat:@" select capid  from legacy_caps  where captext='%@';", cap ];
//
//    NSString* capid = [self executeScalar:query2];
//
//    if(capid==nil) return NO;
//
//
//    NSString* query=[NSString stringWithFormat:@"insert into buddy_resources_legacy_caps values (%@,'%@',%@)", buddyid, presenceObj.resource, capid ];
//	if([self executeNonQuery:query]!=NO)
//	{
//
//		;
//		return YES;
//	}
//	else
//	{
//        ;
//		return NO;
//	}
//
//
//}

-(BOOL) checkLegacyCap:(NSString*)cap forUser:(NSString*) user accountNo:(NSString*) acctNo
{
    NSString* query=[NSString stringWithFormat:@"select count(*) from buddylist as a inner join buddy_resources_legacy_caps as b on a.buddy_id=b.buddy_id  inner join legacy_caps as c on c.capid=b.capid where buddy_name='%@' and account_id=%@ and captext='%@'", user.escapeForSql, acctNo,cap.escapeForSql ];
    
    //DDLogVerbose(@"%@", query);
    NSNumber* count = (NSNumber *) [self executeScalar:query];
    
    if([count integerValue]>0) return YES; else return NO;
}

#pragma mark presence functions

-(void) setResourceOnline:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
    //get buddyid for name and account
    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user.escapeForSql ];
    [self executeScalar:query1 withCompletion:^(NSObject *buddyid) {
        if(buddyid)  {
            NSString* query3=[NSString stringWithFormat:@" select count(buddy_id) from buddy_resources where buddy_id=%@ and resource='%@';", buddyid, presenceObj.resource.escapeForSql ];
                [self executeScalar:query3 withCompletion:^(NSObject * resourceCount) {
                //do not duplicate resource
                 if([(NSNumber *)resourceCount integerValue] ==0) {
                     NSString* query=[NSString stringWithFormat:@"insert into buddy_resources values (%@, '%@', '')", buddyid, presenceObj.resource.escapeForSql ];
                     [self executeNonQuery:query withCompletion:nil];
                 }
            }];
    
        }
    }];
}


-(NSArray*)resourcesForContact:(NSString*)contact
{
    NSString* query1=[NSString stringWithFormat:@" select resource from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where  buddy_name='%@'  ", contact.escapeForSql ];
    NSArray* resources = [self executeReader:query1];
    return resources;
    
}


-(void) setOnlineBuddy:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
    [self setResourceOnline:presenceObj forAccount:accountNo];
    
    [self isBuddyOnline:presenceObj.user forAccount:accountNo withCompletion:^(BOOL isOnline) {
        if(!isOnline) {
            NSString* query=[NSString stringWithFormat:@"update buddylist set online=1, new=1, muc=%d where account_id=%@ and  buddy_name='%@';",presenceObj.MUC, accountNo, presenceObj.user.escapeForSql ];
            [self executeNonQuery:query withCompletion:nil];
        }
    }];

}

-(BOOL) setOfflineBuddy:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
    
    NSString* query1=[NSString stringWithFormat:@" select buddy_id from buddylist where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user.escapeForSql ];
    NSString* buddyid = (NSString*)[self executeScalar:query1];
    if(buddyid==nil) return NO;
    
    NSString* query2=[NSString stringWithFormat:@"delete from   buddy_resources where buddy_id=%@ and resource='%@'", buddyid, presenceObj.resource.escapeForSql ];
    if([self executeNonQuery:query2]==NO) return NO;
    
    NSString* query4=[NSString stringWithFormat:@"delete from   buddy_resources_legacy_caps where buddy_id=%@ and resource='%@'",
                      buddyid, presenceObj.resource.escapeForSql ];
    if([self executeNonQuery:query4]==NO) return NO;
    
    //see how many left
    NSString* query3=[NSString stringWithFormat:@" select count(buddy_id) from buddy_resources where buddy_id=%@;", buddyid ];
    NSString* resourceCount = (NSString*)[self executeScalar:query3];
    
    if([resourceCount integerValue]<1)
    {
        NSString* query=[NSString stringWithFormat:@"update buddylist set online=0, state='offline', dirty=1  where account_id=%@ and  buddy_name='%@';", accountNo, presenceObj.user.escapeForSql];
        if([self executeNonQuery:query]!=NO)
        {
            return YES;
        }
        else
        {
            return NO;
        }
    }
    else return NO;
    
}


-(void) setBuddyState:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
{
    NSString* toPass;
    //data length check
    
    if([presenceObj.show length]>20) toPass=[presenceObj.show substringToIndex:19]; else toPass=presenceObj.show;
    NSString* query=[NSString stringWithFormat:@"update buddylist set state='%@', dirty=1 where account_id=%@ and  buddy_name='%@';",toPass, accountNo, presenceObj.user.escapeForSql];
    [self executeNonQuery:query withCompletion:nil];
    
}

-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo
{
    
    NSString* query=[NSString stringWithFormat:@"select state from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy.escapeForSql];
    NSString* state= (NSString*)[self executeScalar:query];
    return state;
}


-(void) setBuddyStatus:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo
{
    NSString* toPass;
    //data length check
    if([presenceObj.status length]>200) toPass=[[presenceObj.status substringToIndex:199] stringByReplacingOccurrencesOfString:@"'"
                                                                                                                    withString:@"''"];
    else toPass=[presenceObj.status  stringByReplacingOccurrencesOfString:@"'"
                                                               withString:@"''"];;
    NSString* query=[NSString stringWithFormat:@"update buddylist set status='%@', dirty=1 where account_id=%@ and  buddy_name='%@';",[toPass stringByReplacingOccurrencesOfString:@"'" withString:@"''"], accountNo, presenceObj.user.escapeForSql];
    [self executeNonQuery:query withCompletion:nil];

}

-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query=[NSString stringWithFormat:@"select status from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy.escapeForSql];
    NSString* iconname= [self executeScalar:query];
    return iconname;
}



#pragma mark Contact info

-(BOOL) setFullName:(NSString*) fullName forBuddy:(NSString*) buddy andAccount:(NSString*) accountNo
{
    
    NSString* toPass;
    //data length check
    
    if([fullName length]>50) toPass=[fullName substringToIndex:49]; else toPass=fullName;
    // sometimes the buddyname comes from a roster so it might not be in the list yet, add first and if that fails (ie already there) then set fullname
    
    if(![self addBuddy:buddy forAccount: accountNo fullname:fullName nickname:@""])
    {
        NSString* query=[NSString stringWithFormat:@"update buddylist set full_name='%@',dirty=1 where account_id=%@ and  buddy_name='%@';",[toPass stringByReplacingOccurrencesOfString:@"'" withString:@"''"], accountNo, buddy.escapeForSql];
        if([self executeNonQuery:query]!=NO)
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
        return YES;
    }
}

-(BOOL) setNickName:(NSString*) nickName forBuddy:(NSString*) buddy andAccount:(NSString*) accountNo
{
    NSString* toPass;
    //data length check
    
    if([nickName length]>50) toPass=[nickName substringToIndex:49]; else toPass=nickName;
    NSString* query=[NSString stringWithFormat:@"update buddylist set nick_name='%@',dirty=1 where account_id=%@ and  buddy_name='%@';",toPass.escapeForSql, accountNo, buddy.escapeForSql];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

-(NSString*) fullName:(NSString*) buddy forAccount:(NSString*) accountNo;
{
    NSString* query=[NSString stringWithFormat:@"select full_name from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy.escapeForSql];
    NSString* fullname= (NSString*)[self executeScalar:query];
    return fullname;
}


-(BOOL) setBuddyHash:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
{
    NSString* hash=presenceObj.photoHash;
    if(!hash) hash=@"";
    //data length check
    NSString* query=[NSString stringWithFormat:@"update buddylist set iconhash='%@', dirty=1 where account_id=%@ and  buddy_name='%@';",hash,
                     accountNo, presenceObj.user.escapeForSql];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

-(NSString*) buddyHash:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query=[NSString stringWithFormat:@"select iconhash from buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy.escapeForSql];
    NSString* iconhash= (NSString*)[self executeScalar:query];
    return iconhash;
}


-(bool) isBuddyInList:(NSString*) buddy forAccount:(NSString*) accountNo
{
    
    NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' ", accountNo, buddy.escapeForSql];
    
    NSNumber* count=(NSNumber*)[self executeScalar:query];
    if(count!=nil)
    {
        int val=[count integerValue];
        if(val>0) {
            return YES;
        }
        else
        {
            return NO;
        }
    }
    else
    {
        return NO;
    }
    
    
}

-(void) isBuddyOnline:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' and online=1 ", accountNo, buddy.escapeForSql];
    
    [self executeScalar:query withCompletion:^(NSObject *value) {
        
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

-(bool) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query=[NSString stringWithFormat:@"SELECT Muc from buddylist where account_id=%@  and buddy_name='%@' ", accountNo, buddy.escapeForSql];
    NSNumber* status=(NSNumber*)[self executeScalar:query];
    return [status boolValue];
}

-(bool) isBuddyAdded:(NSString*) buddy forAccount:(NSString*) accountNo
{
    // count # of meaages in message table
    NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' and online=1 and new=1", accountNo, buddy.escapeForSql];
    NSNumber* count=(NSNumber*)[self executeScalar:query];
    if(count!=nil)
    {
        int val=[count integerValue];
        if(val>0) {
            
            return YES; } else
            {
                
                return NO;
            }
    }
    else
    {
        return NO;
    }
    
    
}

-(bool) isBuddyRemoved:(NSString*) buddy forAccount:(NSString*) accountNo
{
    // count # of meaages in message table
    NSString* query=[NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=%@ and buddy_name='%@' and online=0 and dirty=1", accountNo, buddy.escapeForSql];
    
    NSNumber* count=(NSNumber*)[self executeScalar:query];
    if(count!=nil)
    {
        int val=[count integerValue];
        if(val>0) {
            
            return YES; } else
            {
                
                return NO;
            }
        
    }
    else
    {
        ;
        return NO;
    }
    
    
}


#pragma mark icon Commands


-(BOOL) setIconName:(NSString*) icon forBuddy:(NSString*) buddy inAccount:(NSString*) accountNo
{
    
    NSString* query=[NSString stringWithFormat:@"update buddylist set filename='%@',dirty=1 where account_id=%@ and  buddy_name='%@';",icon, accountNo, buddy.escapeForSql];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

-(NSString*) iconName:(NSString*) buddy forAccount:(NSString*) accountNo;
{
    NSString* query=[NSString stringWithFormat:@"select filename from  buddylist where account_id=%@ and buddy_name='%@'", accountNo, buddy.escapeForSql];
    NSString* iconname= (NSString*)[self executeScalar:query];
    return iconname;
}





#pragma mark message Commands

-(NSArray *) messageForHistoryID:(NSInteger) historyID
{
    NSString* query=[NSString stringWithFormat:@"select message, messageid from message_history  where message_history_id=%ld", (long)historyID];
    NSArray* messageArray= [self executeReader:query];
    return messageArray;
}

-(BOOL) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom delivered:(BOOL) delivered unread:(BOOL) unread
{
    //this is always from a contact
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSDate* sourceDate=[NSDate date];
    
    NSTimeZone* sourceTimeZone = [NSTimeZone systemTimeZone];
    NSTimeZone* destinationTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    
    NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
    NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
    NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;
    
    NSDate* destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
    
    // note: if it isnt the same day we want to show the full  day
    
    NSString* dateString = [formatter stringFromDate:destinationDate];
    // in the event it is a message from the room
    
    //all messages default to unread
    NSString* query=[NSString stringWithFormat:@"insert into message_history values (null, %@, '%@',  '%@', '%@', '%@', '%@',%d,%d,'');", accountNo, from.escapeForSql, to.escapeForSql, 	dateString, message.escapeForSql, actualfrom.escapeForSql,unread, delivered];
    DDLogVerbose(@"%@",query);
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        DDLogError(@"failed to insert ");
        return NO;
    }
    
}

-(void) setMessageId:(NSString*) messageid delivered:(BOOL) delivered
{
    NSString* query=[NSString stringWithFormat:@"update message_history set delivered=%d where messageid='%@';",delivered, messageid];
    DDLogInfo(@" setting delivered %@",query);
    [self executeNonQuery:query withCompletion:nil];
 
}



-(BOOL) clearMessages:(NSString*) accountNo
{
    NSString* query=[NSString stringWithFormat:@"delete from message_history where account_id=%@", accountNo];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}



-(BOOL) deleteMessageHistory:(NSString*) messageNo
{
    NSString* query=[NSString stringWithFormat:@"delete from message_history where message_history_id=%@", messageNo];
    if([self executeNonQuery:query]!=NO)
    {
        return YES;
    }
    else
    {
        return NO;
    }
}

-(NSArray*) messageHistoryListDates:(NSString*) buddy forAccount: (NSString*) accountNo
{
    //returns a list of  buddy's with message history
    
    NSString* query1=[NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
    //DDLogVerbose(query);
    NSArray* user = [self executeReader:query1];
    
    if(user!=nil)
    {
        
        NSString* query=[NSString stringWithFormat:@"select distinct date(timestamp) as the_date from message_history where account_id=%@ and  message_from='%@' or  message_to='%@'   order by timestamp desc", accountNo, buddy.escapeForSql, buddy.escapeForSql  ];
        //DDLogVerbose(query);
        NSArray* toReturn = [self executeReader:query];
        
        if(toReturn!=nil)
        {
            
            DDLogVerbose(@" count: %d",  [toReturn count] );
            
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
    
    NSString* query=[NSString stringWithFormat:@"select af, message, thetime, message_history_id from (select ifnull(actual_from, message_from) as af, message,     timestamp  as thetime, message_history_id from message_history where account_id=%@ and (message_from='%@' or message_to='%@') and date(timestamp)='%@' order by message_history_id desc) order by message_history_id asc",accountNo, buddy.escapeForSql, buddy.escapeForSql, date];
    
    DDLogVerbose(@"%@",query);
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        
        DDLogVerbose(@" count: %d",  [toReturn count] );
        
        return toReturn; //[toReturn autorelease];
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
        return nil;
    }
    
}



-(NSArray*) messageHistoryAll:(NSString*) buddy forAccount:(NSString*) accountNo
{
    //returns a buddy's message history
    
    NSString* query=[NSString stringWithFormat:@"select message_from, message, thetime from (select message_from, message, timestamp as thetime, message_history_id from message_history where account_id=%@ and (message_from='%@' or message_to='%@') order by message_history_id desc) order by message_history_id asc ", accountNo, buddy.escapeForSql, buddy.escapeForSql];
    //DDLogVerbose(query);
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        
        DDLogVerbose(@" count: %d",  [toReturn count] );
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
    
    
    
    NSString* query=[NSString stringWithFormat:@"delete from message_history where account_id=%@ and (message_from='%@' or message_to='%@') ",accountNo, buddy.escapeForSql, buddy.escapeForSql];
    //DDLogVerbose(query);
    if( [self executeNonQuery:query])
        
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
    NSString* query=[NSString stringWithFormat:@"delete from message_history "];
    if( [self executeNonQuery:query])
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

-(NSArray*) messageHistoryBuddies:(NSString*) accountNo
{
    //returns a list of  buddy's with message history
    
    NSString* query1=[NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
    //DDLogVerbose(query);
    NSArray* user = [self executeReader:query1];
    
    if([user count]>0)
    {
        
        NSString* query=[NSString stringWithFormat:@"select x.* from(select distinct message_from,'', ifnull(full_name, message_from) as full_name, filename from message_history as a left outer join buddylist as b on a.message_from=b.buddy_name and a.account_id=b.account_id where a.account_id=%@  union select distinct message_to  ,'', ifnull(full_name, message_to) as full_name, filename from message_history as a left outer join buddylist as b on a.message_to=b.buddy_name and a.account_id=b.account_id where a.account_id=%@  )  as x where message_from!='%@' and message_from!='%@@%@'  order by full_name COLLATE NOCASE ", accountNo, accountNo,((NSString *)[[user objectAtIndex:0] objectForKey:@"username"]).escapeForSql, ((NSString *)[[user objectAtIndex:0] objectForKey:@"username"]).escapeForSql,  ((NSString *)[[user objectAtIndex:0] objectForKey:@"domain"]).escapeForSql  ];
        //DDLogVerbose(query);
        NSArray* toReturn = [self executeReader:query];
        
        if(toReturn!=nil)
        {
            
            DDLogVerbose(@" count: %d",  [toReturn count] );
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
-(NSMutableArray*) messageHistory:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query=[NSString stringWithFormat:@"select af, message, thetime, message_history_id, delivered, messageid from (select ifnull(actual_from, message_from) as af, message,     timestamp  as thetime, message_history_id, delivered,messageid from message_history where account_id=%@ and (message_from='%@' or message_to='%@') order by message_history_id desc limit 30) order by message_history_id asc",accountNo, buddy.escapeForSql, buddy.escapeForSql];
    DDLogVerbose(@"%@", query);
    NSMutableArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        
        DDLogVerbose(@" message history count: %d",  [toReturn count] );
        return toReturn; //[toReturn autorelease];
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
        return nil;
    }
    
}

-(void) markAsReadBuddy:(NSString*) buddy forAccount:(NSString*) accountNo
{
    
    NSString* query2=[NSString stringWithFormat:@"  update message_history set unread=0 where account_id=%@ and message_from='%@';", accountNo, buddy.escapeForSql];
    [self executeNonQuery:query2 withCompletion:nil];

}

-(void) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString *)messageId withCompletion:(void (^)(BOOL))completion
{
    //MEssaes_history ging out, from is always the local user. always read, default to  delivered (will be reset by timer if needed)
    
    NSArray* parts=[[[NSDate date] description] componentsSeparatedByString:@" "];
    NSString* query=[NSString stringWithFormat:@"insert into message_history values (null, %@, '%@',  '%@', '%@ %@', '%@', '%@',0,1,'%@');", accountNo, from.escapeForSql, to.escapeForSql,
                     [parts objectAtIndex:0],[parts objectAtIndex:1], message.escapeForSql, actualfrom.escapeForSql, messageId.escapeForSql];
    
    [self executeNonQuery:query withCompletion:^(BOOL result) {
        if (completion) {
            completion(result);
        }
        
    }];
}


//count unread
-(void) countUnreadMessagesWithCompletion: (void (^)(NSNumber *))completion
{
    // count # of meaages in message table
    NSString* query=[NSString stringWithFormat:@"select count(message_history_id) from  message_history where unread=1"];
    
    [self executeScalar:query withCompletion:^(NSObject *result) {
        NSNumber *count= (NSNumber *) result;
        
        if(completion)
        {
            completion(count);
        }
    }];
}

#pragma mark active chats
-(NSArray*) activeBuddies
{
    
    NSString* query=[NSString stringWithFormat:@"select X.*, 0 as 'count' from (select distinct a.buddy_name,state,status,filename, ifnull(b.full_name, a.buddy_name) as full_name, a.account_id from activechats as a left outer  join buddylist as b on a.buddy_name=b.buddy_name and a.account_id=b.account_id ) as X left outer join (select account_id, message_from, max(timestamp) as max_time from  message_history group by account_id, message_from) as Y on X.account_id=Y.account_id and X.buddy_name=Y.message_from order by Y.max_time desc, X.full_name COLLATE NOCASE asc" ];
    //	DDLogVerbose(query);
    NSArray* toReturn = [self executeReader:query];
    
    if(toReturn!=nil)
    {
        DDLogVerbose(@" count: %d",  [toReturn count] );
        return toReturn;
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
        return nil;
    }
    
}

-(bool) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    //mark messages as read
    [self markAsReadBuddy:buddyname forAccount:accountNo];
    
    NSString* query=[NSString stringWithFormat:@"delete from activechats where buddy_name='%@' and account_id=%@ ", buddyname.escapeForSql, accountNo ];
    //	DDLogVerbose(query);
    BOOL result=[self executeNonQuery:query];
    
    return result;
}

-(bool) removeAllActiveBuddies
{
    
    NSString* query=[NSString stringWithFormat:@"delete from activechats " ];
    //	DDLogVerbose(query);
    BOOL result=[self executeNonQuery:query];
    return result;
    
}



-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    NSString* query=[NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=%@ and buddy_name='%@' ", accountNo, buddyname.escapeForSql];
   [self executeScalar:query withCompletion:^(NSObject * count) {
        if(count!=nil)
        {
            NSInteger val=[((NSNumber *)count) integerValue];
            if(val>0) {
                if (completion) {
                    completion(NO);
                }
            } else
            {
                //no
                NSString* query2=[NSString stringWithFormat:@"insert into activechats values ( %@,'%@') ",  accountNo,buddyname.escapeForSql ];
                [self executeNonQuery:query2 withCompletion:^(BOOL result) {
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
    NSString* query=[NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=%@ and buddy_name='%@' ", accountNo, buddyname.escapeForSql];
    [self executeScalar:query withCompletion:^(NSObject * count) {
        BOOL toReturn=NO;
        if(count!=nil)
        {
            NSInteger val=[((NSNumber *)count) integerValue];
            if(val>0) {
                toReturn=YES;
            }
        }
        
        if (completion) {
            completion(toReturn);
        }
    }];
    
}


#pragma mark chat properties



-(void) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion:(void (^)(NSNumber *))completion
{
    // count # messages from a specific user in messages table
    NSString* query=[NSString stringWithFormat:@"select count(message_history_id) from  message_history where unread=1 and account_id=%@ and message_from='%@'", accountNo, buddy.escapeForSql];
    
    [self executeScalar:query withCompletion:^(NSObject* result) {
        if(completion)
        {
            completion((NSNumber *)result);
        }
    }];
    
}


-(void) countUserMessages:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion:(void (^)(NSNumber *))completion
{
    // count # messages from a specific user in messages table
    NSString* query=[NSString stringWithFormat:@"select count(message_history_id) from  message_history where account_id=%@ and message_from='%@' or message_to='%@' ", accountNo, buddy.escapeForSql, buddy.escapeForSql];
    
    [self executeScalar:query withCompletion:^(NSObject* result) {
        if(completion)
        {
            completion((NSNumber *)result);
        }
    }];
    
}

#pragma db Commands

-(void) initDB
{
    _dbQueue = dispatch_queue_create(kMonalDBQueue, DISPATCH_QUEUE_SERIAL);
    _contactQueue = dispatch_queue_create(kMonalContactQueue, DISPATCH_QUEUE_SERIAL);
    
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *writableDBPath = [documentsDirectory stringByAppendingPathComponent:@"sworim.sqlite"];
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
    if (sqlite3_config(SQLITE_CONFIG_SERIALIZED) == SQLITE_OK) {
        DDLogVerbose(@"Database configured ok");
    } else DDLogVerbose(@"Database not configured ok");
    
    sqlite3_initialize();
    
    dbPath = writableDBPath; //[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"sworim.sqlite"];
    if (sqlite3_open([dbPath UTF8String], &database) == SQLITE_OK) {
        DDLogVerbose(@"Database opened");
    }
    else
    {
        //database error message
        DDLogError(@"Error opening database");
    }
    //truncate faster than del
    [self executeNonQuery:@"pragma truncate;"];
    
    dbversionCheck=[NSLock new];
    [self version];
    
    
}

-(void) version
{
    [dbversionCheck lock];
    
    
#if TARGET_OS_IPHONE
    // checking db version and upgrading if necessary
    DDLogVerbose(@"Database version check");
    
    //<1.02 has no db version table but gtalk port is 443 . this is an identifier
    NSNumber* gtalkport= (NSNumber*)[self executeScalar:@"select default_port from  protocol   where protocol_name='GTalk';"];
    if([gtalkport intValue]==443)
    {
        DDLogVerbose(@"Database version <1.02 detected. Performing upgrade");
        [self executeNonQuery:@"drop table account;"];
        [self executeNonQuery:@"create table account( account_id integer not null primary key AUTOINCREMENT,account_name varchar(20) not null, protocol_id integer not null, server varchar(50) not null, other_port integer, username varchar(30), password varchar(30), secure bool,resource varchar(30), domain varchar(50), enabled bool);"];
        [self executeNonQuery:@"update protocol set default_port=5223 where protocol_name='GTalk';"];
        [self executeNonQuery:@"create table dbversion(dbversion varchar(10) );"];
        [self executeNonQuery:@"insert into dbversion values('1.02');"];
        
        
        DDLogVerbose(@"Upgrade to 1.02 success importing default account");
        NSString* importAcc= [NSString stringWithFormat:@"insert into account values(null, '%@', 0, '%@', %@, '%@', '%@', %@, '%@', '%@', 1); ",
                              [[NSUserDefaults standardUserDefaults] stringForKey:@"username"] ,
                              [ [NSUserDefaults standardUserDefaults] stringForKey:@"server"] ,
                              [ [NSUserDefaults standardUserDefaults] stringForKey:@"portno"] ,
                              [ [NSUserDefaults standardUserDefaults] stringForKey:@"username"] ,
                              [ [NSUserDefaults standardUserDefaults] stringForKey:@"password"] ,
                              [ [NSUserDefaults standardUserDefaults] stringForKey:@"SSL"] ,
                              [[NSUserDefaults standardUserDefaults] stringForKey:@"resource"] ,
                              [[NSUserDefaults standardUserDefaults] stringForKey:@"thedomain"]
                              
                              ];
        
        [self executeNonQuery:importAcc];
        
        
        
        DDLogVerbose(@"Done");
        
        
    }
    
    
    
    // < 1.04 has google talk on 5223 or 443
    
    if( ([gtalkport intValue]==5223) || ([gtalkport intValue]==443))
    {
        DDLogVerbose(@"Database version <1.04 detected. Performing upgrade");
        [self executeNonQuery:@"update protocol set default_port=5222 where protocol_name='GTalk';"];
        [self executeNonQuery:@"insert into protocol values (null,'Facebook',5222); "];
        
        [self executeNonQuery:@"drop table buddylist; "];
        [self executeNonQuery:@"drop table buddyicon; "];
        [self executeNonQuery:@"create table buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50), full_name varchar(50), nick_name varchar(50)); "];
        [self executeNonQuery:@"create table buddyicon(buddyicon_id integer null primary key AUTOINCREMENT,buddy_id integer not null,hash varchar(255),  filename varchar(50)); "];
        
        [self executeNonQuery:@"drop table dbversion;"];
        [self executeNonQuery:@"create table dbversion(dbversion real);"];
        [self executeNonQuery:@"insert into dbversion values(1.04);"];
        DDLogVerbose(@"Upgrade to 1.04 success ");
        
        
    }
    
    
    NSNumber* dbversion= (NSNumber*)[self executeScalar:@"select dbversion from dbversion"];
    DDLogVerbose(@"Got db version %@", dbversion);
    
    
    if([dbversion doubleValue]<1.07)
    {
        DDLogVerbose(@"Database version <1.07 detected. Performing upgrade");
        [self executeNonQuery:@"create table buddylistOnline (buddy_id integer not null primary key AUTOINCREMENT,account_id integer not null,buddy_name varchar(50), group_name varchar(100)); "];
        [self executeNonQuery:@"update dbversion set dbversion='1.07'; "];
        
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IdleAlert"];
        
        DDLogVerbose(@"Upgrade to 1.07 success ");
        
    }
    
    if([dbversion doubleValue]<1.071)
    {
        DDLogVerbose(@"Database version <1.071 detected. Performing upgrade");
        [self executeNonQuery:@"drop table buddylistOnline;  "];
        
        [self executeNonQuery:@"drop table buddylist;  "];
        [self executeNonQuery:@"drop table messages;  "];
        [self executeNonQuery:@"drop table message_history;  "];
        [self executeNonQuery:@"drop table buddyicon;  "];
        
        
        
        [self executeNonQuery:@"create table buddylist(buddy_id integer not null primary key AUTOINCREMENT,account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50),nick_name varchar(50), group_name varchar(50),iconhash varchar(200),filename varchar(100),state varchar(20), status varchar(200),online bool, dirty bool, new bool); "];
        
        
        
        
        [self executeNonQuery:@"create table messages(message_id integer not null primary key AUTOINCREMENT,account_id integer, message_from varchar(50) collate nocase,message_to varchar(50) collate nocase, timestamp datetime, message blob,notice integer,actual_from varchar(50) collate nocase);"];
        
        
        
        [self executeNonQuery:@"create table message_history(message_history_id integer not null primary key AUTOINCREMENT,account_id integer, message_from varchar(50) collate nocase,message_to varchar(50) collate nocase,timestamp datetime , message blob,actual_from varchar(50) collate nocase);"];
        
        
        
        
        [self executeNonQuery:@"create table activechats(account_id integer not null, buddy_name varchar(50) collate nocase); "];
        
        
        [self executeNonQuery:@"update dbversion set dbversion='1.071'; "];
        
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"IdleAlert"];
        
        DDLogVerbose(@"Upgrade to 1.071 success ");
        
    }

    
    if([dbversion doubleValue]<1.072)
    {
        DDLogVerbose(@"Database version <1.072 detected. Performing upgrade on passwords. ");
        NSArray* rows = [self executeReader:@"select account_id, password from account"];
        int counter=0;
        PasswordManager* pass;
        while(counter<[rows count])
        {
            //DDLogVerbose(@" %@ %@",[[rows objectAtIndex:counter] objectAtIndex:0], [[rows objectAtIndex:counter] objectAtIndex:1] );
            pass=[[PasswordManager alloc]  init:[NSString stringWithFormat:@"%@",[[rows objectAtIndex:counter] objectAtIndex:0]]];
            [pass setPassword:[[rows objectAtIndex:counter] objectAtIndex:1]] ;
            //DDLogVerbose(@"got:%@", [pass getPassword] );
            
            counter++;
        }
        
        
        //wipe passwords
        
        [self executeNonQuery:@"update account set password=''; "];
        
    }
    
    
    if([dbversion doubleValue]<1.073)
    {
        DDLogVerbose(@"Database version <1.073 detected. Performing upgrade on passwords. ");
        
        //set defaults on upgrade
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"OfflineContact"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MessagePreview"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Logging"];
        
        [self executeNonQuery:@"update dbversion set dbversion='1.073'; "];
        DDLogVerbose(@"Upgrade to 1.073 success ");
        
    }
    
    
    
    if([dbversion doubleValue]<1.074)
    {
        DDLogVerbose(@"Database version <1.074 detected. Performing upgrade on protocols. ");
        
        
        [self executeNonQuery:@"delete from protocol where protocol_id=3 "];
        [self executeNonQuery:@"delete from protocol where protocol_id=4 "];
        [self executeNonQuery:@" create table legacy_caps(capid integer not null primary key ,captext  varchar(20))"];
        
        [self executeNonQuery:@" insert into legacy_caps values (1,'pmuc-v1');"];
        [self executeNonQuery:@" insert into legacy_caps values (2,'voice-v1');"];
        [self executeNonQuery:@" insert into legacy_caps values (3,'camera-v1');"];
        [self executeNonQuery:@" insert into legacy_caps values (4, 'video-v1');"];
        
        
        
        [self executeNonQuery:@"create table buddy_resources(buddy_id integer,resource varchar(255),ver varchar(20))"];
        
        [self executeNonQuery:@"create table ver_info(ver varchar(20),cap varchar(255), primary key (ver,cap))"];
        
        [self executeNonQuery:@"create table buddy_resources_legacy_caps (buddy_id integer,resource varchar(255),capid  integer);"];
        
        [self executeNonQuery:@"update dbversion set dbversion='1.074'; "];
        DDLogVerbose(@"Upgrade to 1.074 success ");
        
    }
    
    if([dbversion doubleValue]<1.1)
    {
        DDLogVerbose(@"Database version <1.1 detected. Performing upgrade on accounts. ");
        
        [self executeNonQuery:@"alter table account add column selfsigned bool;"];
        [self executeNonQuery:@"alter table account add column oldstyleSSL bool; "];
        
        [self executeNonQuery:@"update dbversion set dbversion='1.1'; "];
        DDLogVerbose(@"Upgrade to 1.1 success ");
        
    }
    
    
    if([dbversion doubleValue]<1.2)
    {
        DDLogVerbose(@"Database version <1.2 detected. Performing upgrade on accounts. ");
        
        [self executeNonQuery:@"update  buddylist set iconhash=NULL;"];
        [self executeNonQuery:@"alter table message_history  add column unread bool;"];
        [self executeNonQuery:@" insert into message_history (account_id,message_from, message_to, timestamp, message, actual_from,unread) select account_id,message_from, message_to, timestamp, message, actual_from, 1  from messages ;"];
        [self executeNonQuery:@""];
        
        
        [self executeNonQuery:@"update dbversion set dbversion='1.2'; "];
        DDLogVerbose(@"Upgrade to 1.2 success ");
        
    }
    
    //going to from 2.1 beta to final
    if([dbversion doubleValue]<1.3)
    {
        DDLogVerbose(@"Database version <1.3 detected. Performing upgrade on accounts. ");
        
        [self executeNonQuery:@"update  buddylist set iconhash=NULL;"];
        
        [self executeNonQuery:@"update dbversion set dbversion='1.3'; "];
        DDLogVerbose(@"Upgrade to 1.3 success ");
        
    }
    
    
    if([dbversion doubleValue]<1.31)
    {
        DDLogVerbose(@"Database version <1.31 detected. Performing upgrade on accounts. ");
        
        [self executeNonQuery:@"alter table buddylist add column  Muc bool;"];
        
        [self executeNonQuery:@"update dbversion set dbversion='1.31'; "];
        DDLogVerbose(@"Upgrade to 1.31 success ");
        
    }
    
    if([dbversion doubleValue]<1.41)
    {
        DDLogVerbose(@"Database version <1.41 detected. Performing upgrade on accounts. ");
        
        [self executeNonQuery:@"alter table message_history add column  delivered bool;"];
        [self executeNonQuery:@"alter table message_history add column  messageid varchar(255);"];
        [self executeNonQuery:@"update message_history set delivered=1;"];
        [self executeNonQuery:@"update dbversion set dbversion='1.41'; "];
        
        
        DDLogVerbose(@"Upgrade to 1.41 success ");
        
    }
    
    
    if([dbversion doubleValue]<1.42)
    {
        DDLogVerbose(@"Database version <1.42 detected. Performing upgrade on accounts. ");
        
        [self executeNonQuery:@"delete from protocol where protocol_id=5;"];
        [self executeNonQuery:@"update dbversion set dbversion='1.42'; "];
        
        
        DDLogVerbose(@"Upgrade to 1.41 success ");
        
    }
#else 
    NSNumber* dbversion= (NSNumber*)[self executeScalar:@"select dbversion from dbversion"];
    DDLogVerbose(@"Got db version %@", dbversion);
#endif
    
    if([dbversion doubleValue]<1.5)
    {
        DDLogVerbose(@"Database version <1.5 detected. Performing upgrade on accounts. ");
        
        [self executeNonQuery:@"alter table account add column oauth bool;"];
        [self executeNonQuery:@"update dbversion set dbversion='1.5'; "];
        
        DDLogVerbose(@"Upgrade to 1.5 success ");
        
    }
    
    // this point forward OSX might have legacy issues
    
    
    [dbversionCheck unlock];
    [self resetContacts];
    return;
    
}

-(void) dealloc
{
    sqlite3_close(database);
}



@end