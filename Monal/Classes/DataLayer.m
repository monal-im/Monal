//
//  DataLayer.m
//  SworIM
//
//  Created by Anurodh Pokharel on 3/28/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "DataLayer.h"
#import "xmpp.h"
#import "MLSQLite.h"
#import "HelperTools.h"
#import "MLXMLNode.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"
#import "XMPPIQ.h"
#import "XMPPDataForm.h"
#import "MLFiletransfer.h"
#import "DataLayerMigrations.h"
#import "MLContactSoftwareVersionInfo.h"
#import "MLXMPPManager.h"

@interface DataLayer()
@property (readonly, strong) MLSQLite* db;
@end

@implementation DataLayer

NSString* const kAccountID = @"account_id";
NSString* const kAccountState = @"account_state";

//used for account rows
NSString *const kDomain = @"domain";
NSString *const kEnabled = @"enabled";
NSString *const kNeedsPasswordMigration = @"needs_password_migration";
NSString *const kSupportsSasl2 = @"supports_sasl2";

NSString *const kServer = @"server";
NSString *const kPort = @"other_port";
NSString *const kResource = @"resource";
NSString *const kDirectTLS = @"directTLS";
NSString *const kRosterName = @"rosterName";

NSString *const kUsername = @"username";

NSString *const kMessageTypeStatus = @"Status";
NSString *const kMessageTypeMessageDraft = @"MessageDraft";
NSString *const kMessageTypeText = @"Text";
NSString *const kMessageTypeGeo = @"Geo";
NSString *const kMessageTypeUrl = @"Url";
NSString *const kMessageTypeFiletransfer = @"Filetransfer";

static NSString* dbPath;
static NSDateFormatter* dbFormatter;

+(void) initialize
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* writableDBPath = [[HelperTools getContainerURLForPathComponents:@[@"sworim.sqlite"]] path];
    
    //the file does not exist (e.g. fresh install) --> copy default database to app group path
    if(![fileManager fileExistsAtPath:writableDBPath])
    {
        DDLogInfo(@"initialize: copying default DB to: %@", writableDBPath);
        NSString* defaultDBPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"sworim.sqlite"];
        NSError* error;
        [fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:&error];
        if(error)
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    }
    
    //init global state
    dbPath = writableDBPath;
    dbFormatter = [NSDateFormatter new];
    [dbFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    [dbFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
}

//we are a singleton (compatible with old code), but conceptually we could also be a static class instead
+(id) sharedInstance
{
    static DataLayer* newInstance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        newInstance = [self new];
    });
    return newInstance;
}

-(id) init
{
    //check db version on first db open only
    [self version];
    return self;
}

//this is the getter of our readonly "db" property always returning the thread-local instance of the MLSQLite class
-(MLSQLite*) db
{
    //always return thread-local instance of sqlite class (this is important for performance!)
    return [MLSQLite sharedInstanceForFile:dbPath];
}

-(NSString* _Nullable) exportDB
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* temporaryFilename = [NSString stringWithFormat:@"%@.db", [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString* temporaryFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:temporaryFilename];
    
    //checkpoint db before copying db file
    [self.db checkpointWal];
    
    //copy db file to temp file
    NSError* error;
    [fileManager copyItemAtPath:dbPath toPath:temporaryFilePath error:&error];
    if(error)
        return nil;
    
    return temporaryFilePath;
}

-(void) createTransaction:(monal_void_block_t) block
{
    [self.db voidWriteTransaction:block];
}

-(void) version
{
    // checking db version and upgrading if necessary
    DDLogInfo(@"Database version check");

    //set wal mode (this setting is permanent): https://www.sqlite.org/pragma.html#pragma_journal_mode
    //this is a special case because it can not be done while in a transaction!!!
    [self.db enableWAL];

    //needed for sqlite >= 3.26.0 (see https://sqlite.org/lang_altertable.html point 2)
    [self.db executeNonQuery:@"PRAGMA legacy_alter_table=on;"];
    [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
    [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];

    // Vacuum after db updates
    if([DataLayerMigrations migrateDB:self.db withDataLayer:self])
    {
        [self.db vacuum];
        DDLogInfo(@"Database Vacuum complete");
    }

    //turn foreign keys on again
    //needed for sqlite >= 3.26.0 (see https://sqlite.org/lang_altertable.html point 2)
    [self.db executeNonQuery:@"PRAGMA legacy_alter_table=off;"];
    [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
    
    DDLogInfo(@"Database version check completed");
    return;
}

#pragma mark account commands

-(NSArray*) accountList
{
    return [self.db idReadTransaction:^{
        return [self.db executeReader:@"SELECT * FROM account ORDER BY account_id ASC;"];
    }];
}

-(NSNumber*) enabledAccountCnts
{
    return [self.db idReadTransaction:^{
        return (NSNumber*)[self.db executeScalar:@"SELECT COUNT(*) FROM account WHERE enabled=1;"];
    }];
}

-(NSArray*) enabledAccountList
{
    return [self.db idReadTransaction:^{
        return [self.db executeReader:@"SELECT * FROM account WHERE enabled=1 ORDER BY account_id ASC;"];
    }];
}

-(BOOL) isAccountEnabled:(NSNumber*) accountNo
{
    return [self.db boolReadTransaction:^{
        return [[self.db executeScalar:@"SELECT enabled FROM account WHERE account_id=?;" andArguments:@[accountNo]] boolValue];
    }];
}

-(NSNumber*) accountIDForUser:(NSString*) user andDomain:(NSString*) domain
{
    if(!user && !domain)
        return nil;

    NSString* cleanUser = user;
    NSString* cleanDomain = domain;

    if(!cleanDomain)
        cleanDomain= @"";
    if(!cleanUser)
        cleanUser= @"";

    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT account_id FROM account WHERE domain=? and username=?;";
        NSArray* result = [self.db executeReader:query andArguments:@[cleanDomain, cleanUser]];
        if(result.count > 0) {
            return (NSNumber*)[result[0] objectForKey:@"account_id"];
        }
        return (NSNumber*)nil;
    }];
}

-(BOOL) doesAccountExistUser:(NSString*) user andDomain:(NSString *) domain
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT * FROM account WHERE domain=? AND username=?;";
        NSArray* result = [self.db executeReader:query andArguments:@[domain, user]];
        return (BOOL)(result.count > 0);
    }];
}

-(NSMutableDictionary*) detailsForAccount:(NSNumber*) accountNo
{
    if(accountNo == nil)
        return nil;
    return [self.db idReadTransaction:^{
        NSArray* result = [self.db executeReader:@"SELECT * FROM account WHERE account_id=?;" andArguments:@[accountNo]];
        if(result != nil && [result count])
        {
            DDLogVerbose(@"count: %lu", (unsigned long)[result count]);
            return (NSMutableDictionary*)result[0];
        }
        else
            DDLogError(@"account list is empty or failed to read");
        return (NSMutableDictionary*)nil;
    }];
}

-(BOOL) updateAccounWithDictionary:(NSDictionary*) dictionary
{
    return [self.db boolWriteTransaction:^{
        DDLogVerbose(@"Updating account with: %@", dictionary);
        NSString* query = @"UPDATE account SET server=?, other_port=?, username=?, resource=?, domain=?, enabled=?, directTLS=?, rosterName=?, statusMessage=?, needs_password_migration=?, supports_sasl2=? WHERE account_id=?;";
        NSString* server = (NSString*)[dictionary objectForKey:kServer];
        NSString* port = (NSString*)[dictionary objectForKey:kPort];
        NSArray* params = @[
            server == nil ? @"" : server,
            port == nil ? @"5222" : port,
            ((NSString*)[dictionary objectForKey:kUsername]),
            ((NSString*)[dictionary objectForKey:kResource]),
            ((NSString*)[dictionary objectForKey:kDomain]),
            [dictionary objectForKey:kEnabled],
            [dictionary objectForKey:kDirectTLS],
            [dictionary objectForKey:kRosterName] ? ((NSString*)[dictionary objectForKey:kRosterName]) : @"",
            [dictionary objectForKey:@"statusMessage"] ? ((NSString*)[dictionary objectForKey:@"statusMessage"]) : @"",
            [dictionary objectForKey:kNeedsPasswordMigration],
            [dictionary objectForKey:kSupportsSasl2],
            [dictionary objectForKey:kAccountID],
        ];
        BOOL retval = [self.db executeNonQuery:query andArguments:params];
        //add self-chat
        [self addContact:[NSString stringWithFormat:@"%@@%@", dictionary[kUsername], dictionary[kDomain]] forAccount:dictionary[kAccountID] nickname:nil];
        return retval;
    }];
}

-(NSNumber*) addAccountWithDictionary:(NSDictionary*) dictionary
{
    return [self.db idWriteTransaction:^{
        NSString* query = @"INSERT INTO account (server, other_port, resource, domain, enabled, directTLS, username, rosterName, statusMessage) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);";
        NSString* server = (NSString*) [dictionary objectForKey:kServer];
        NSString* port = (NSString*)[dictionary objectForKey:kPort];
        NSArray* params = @[
            server == nil ? @"" : server,
            port == nil ? @"5222" : port,
            ((NSString *)[dictionary objectForKey:kResource]),
            ((NSString *)[dictionary objectForKey:kDomain]),
            [dictionary objectForKey:kEnabled] ,
            [dictionary objectForKey:kDirectTLS],
            ((NSString *)[dictionary objectForKey:kUsername]),
            [dictionary objectForKey:kRosterName] ? ((NSString*)[dictionary objectForKey:kRosterName]) : @"",
            [dictionary objectForKey:@"statusMessage"] ? ((NSString*)[dictionary objectForKey:@"statusMessage"]) : @""
        ];
        BOOL result = [self.db executeNonQuery:query andArguments:params];
        // return the accountID
        if(result == YES) {
            NSNumber* accountID = [self.db lastInsertId];
            DDLogInfo(@"Added account %@ to account table with accountNo %@", [dictionary objectForKey:kUsername], accountID);
            //add self-chat
            [self addContact:[NSString stringWithFormat:@"%@@%@", dictionary[kUsername], dictionary[kDomain]] forAccount:accountID nickname:nil];
            return accountID;
        } else {
            return (NSNumber*)nil;
        }
    }];
}

-(BOOL) removeAccount:(NSNumber*) accountNo
{
    // remove all other traces of the account_id in one transaction
    return [self.db boolWriteTransaction:^{
        // enable secure delete
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];

        // delete transfered files from local device
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=?;" andArguments:@[kMessageTypeFiletransfer, accountNo]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];

        // delete account and all entries with the same account_id (CASCADE DELETE)
        BOOL accountDeleted = [self.db executeNonQuery:@"DELETE FROM account WHERE account_id=?;" andArguments:@[accountNo]];

        // disable secure delete again
        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
        return accountDeleted;
    }];
}

-(BOOL) disableAccountForPasswordMigration:(NSNumber*) accountNo
{
    return [self.db boolWriteTransaction:^{
        [self persistState:[xmpp invalidateState:[self readStateForAccount:accountNo]] forAccount:accountNo];
        return [self.db executeNonQuery:@"UPDATE account SET enabled=0, needs_password_migration=1, resource=? WHERE account_id=?;" andArguments:@[[HelperTools encodeRandomResource], accountNo]];
    }];
}

-(NSArray*) accountListNeedingPasswordMigration
{
    return [self.db idReadTransaction:^{
        return [self.db executeReader:@"SELECT * FROM account WHERE NOT enabled AND needs_password_migration ORDER BY account_id ASC;"];
    }];
}

-(BOOL) pinSasl2ForAccount:(NSNumber*) accountNo
{
    return [self.db boolWriteTransaction:^{
        return [self.db executeNonQuery:@"UPDATE account SET supports_sasl2=1 WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(BOOL) isSasl2PinnedForAccount:(NSNumber*) accountNo
{
    return [self.db boolReadTransaction:^{
        NSNumber* sasl2Pinned = (NSNumber*)[self.db executeScalar:@"SELECT supports_sasl2 FROM account WHERE account_id=?;" andArguments:@[accountNo]];
        if(sasl2Pinned == nil)
            return NO;
        else
            return [sasl2Pinned boolValue];
    }];
}

-(NSMutableDictionary*) readStateForAccount:(NSNumber*) accountNo
{
    if(accountNo == nil)
        return nil;
    NSString* query = @"SELECT state from account where account_id=?";
    NSArray* params = @[accountNo];
    NSData* data = (NSData*)[self.db idReadTransaction:^{
        return [self.db executeScalar:query andArguments:params];
    }];
    if(data)
        return [HelperTools unserializeData:data];
    return nil;
}

-(void) persistState:(NSDictionary*) state forAccount:(NSNumber*) accountNo
{
    if(accountNo == nil || !state)
        return;
    NSData* data = [HelperTools serializeObject:state];
    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE account SET state=? WHERE account_id=?;";
        NSArray* params = @[data, accountNo];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

#pragma mark contact Commands

-(BOOL) addContact:(NSString*) contact forAccount:(NSNumber*) accountNo nickname:(NSString*) nickName
{
    if(accountNo == nil || !contact)
        return NO;
    
    return [self.db boolWriteTransaction:^{
        //data length check
        NSString* toPass;
        NSString* cleanNickName;
        if(!nickName)
        {
            //use already existing nickname, if none was given
            cleanNickName = [self.db executeScalar:@"SELECT nick_name FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, contact]];
            //fall back to an empty one if this contact is not already in our db
            if(!cleanNickName)
                cleanNickName = @"";
        }
        else
            cleanNickName = [nickName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if([cleanNickName length] > 50)
            toPass = [cleanNickName substringToIndex:49];
        else
            toPass = cleanNickName;
        
        BOOL encrypt = NO;
#ifndef DISABLE_OMEMO
        encrypt = [[HelperTools defaultsDB] boolForKey:@"OMEMODefaultOn"];
#endif// DISABLE_OMEMO
        
        return [self.db executeNonQuery:@"INSERT INTO buddylist ('account_id', 'buddy_name', 'full_name', 'nick_name', 'muc', 'muc_nick', 'encrypt') VALUES(?, ?, ?, ?, ?, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET nick_name=?;" andArguments:@[accountNo, contact, @"", toPass, @0, @"", @(encrypt), toPass]];
    }];
}

-(void) removeBuddy:(NSString*) buddy forAccount:(NSNumber*) accountNo
{
    [self.db voidWriteTransaction:^{
        //clean up logs...
        [self clearMessagesWithBuddy:buddy onAccount:accountNo];
        //...and delete contact
        [self.db executeNonQuery:@"DELETE FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
    }];
}

-(BOOL) clearBuddies:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        return [self.db executeNonQuery:@"DELETE FROM buddylist WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

#pragma mark Buddy Property commands

-(BOOL) resetContactsForAccount:(NSNumber*) accountNo
{
    if(accountNo == nil)
        return NO;
    return [self.db boolWriteTransaction:^{
        NSString* query2 = @"DELETE FROM buddy_resources WHERE buddy_id IN (SELECT buddy_id FROM buddylist WHERE account_id=?);";
        NSArray* params = @[accountNo];
        [self.db executeNonQuery:query2 andArguments:params];
        NSString* query = @"UPDATE buddylist SET state='offline', status='' WHERE account_id=?;";
        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(NSDictionary* _Nullable) contactDictionaryForUsername:(NSString*) username forAccount:(NSNumber*) accountNo
{
    if(!username || accountNo == nil)
        return nil;

    return [self.db idReadTransaction:^{
        NSArray* results = [self.db executeReader:@"SELECT b.buddy_name, state, status, b.full_name, b.nick_name, Muc, muc_subject, muc_type, muc_nick, mentionOnly, b.account_id, 0 AS 'count', subscription, ask, IFNULL(pinned, 0) AS 'pinned', blocked, encrypt, muted, \
            CASE \
                WHEN a.buddy_name IS NOT NULL THEN 1 \
                ELSE 0 \
            END AS 'isActiveChat' \
            FROM buddylist AS b LEFT JOIN activechats AS a \
            ON a.buddy_name = b.buddy_name AND a.account_id = b.account_id \
            WHERE b.buddy_name=? AND b.account_id=?;" andArguments:@[username, accountNo]];
        
        MLAssert(results != nil && [results count] <= 1, @"Unexpected contact count", (@{
            @"username": username,
            @"accountNo": accountNo,
            @"count": [NSNumber numberWithInteger:[results count]],
            @"results": results ? results : @"(null)"
        }));

        if([results count] == 0)
            return (NSMutableDictionary*)nil;
        else
        {
            NSMutableDictionary* contact = [results[0] mutableCopy];
            //correctly extract NSDate object or 1970, if last interaction is zero
            contact[@"lastInteraction"] = [self lastInteractionOfJid:username forAccountNo:accountNo];
            //if we have this muc in our favorites table, this muc is "subscribed"
            if([self.db executeScalar:@"SELECT room FROM muc_favorites WHERE room=? AND account_id=?;" andArguments:@[username, accountNo]] != nil)
                contact[@"subscription"] = @"both";
            return contact;
        }
    }];
}


-(NSMutableArray<MLContact*>*) searchContactsWithString:(NSString*) search
{
    return [self.db idReadTransaction:^{
        NSString* likeString = [NSString stringWithFormat:@"%%%@%%", search];
        NSString* query = @"SELECT B.buddy_name, B.account_id, IFNULL(IFNULL(NULLIF(B.nick_name, ''), NULLIF(B.full_name, '')), B.buddy_name) AS 'sortkey' FROM buddylist AS B INNER JOIN account AS A ON A.account_id=B.account_id WHERE A.enabled=1 AND (B.buddy_name LIKE ? OR B.full_name LIKE ? OR B.nick_name LIKE ?) ORDER BY sortkey COLLATE NOCASE ASC;";
        NSArray* params = @[likeString, likeString, likeString];
        NSMutableArray<MLContact*>* toReturn = [NSMutableArray new];
        for(NSDictionary* dic in [self.db executeReader:query andArguments:params])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountNo:dic[@"account_id"]]];
        return toReturn;
    }];
}

-(NSMutableArray<MLContact*>*) contactList
{
    return [self contactListWithJid:@""];
}

-(NSMutableArray<MLContact*>*) contactListWithJid:(NSString*) jid
{
    return [self.db idReadTransaction:^{
        //list all contacts and group chats
        NSString* query = @"SELECT B.buddy_name, B.account_id, IFNULL(IFNULL(NULLIF(B.nick_name, ''), NULLIF(B.full_name, '')), B.buddy_name) AS 'sortkey' FROM buddylist AS B INNER JOIN account AS A ON A.account_id=B.account_id WHERE A.enabled=1 AND (B.buddy_name=? OR ?='') ORDER BY sortkey COLLATE NOCASE ASC;";
        NSMutableArray* toReturn = [NSMutableArray new];
        for(NSDictionary* dic in [self.db executeReader:query andArguments:@[jid, jid]])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountNo:dic[@"account_id"]]];
        return toReturn;
    }];
}

#pragma mark entity capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user onAccountNo:(NSNumber*) accountNo
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(*) FROM buddylist AS a INNER JOIN buddy_resources AS b ON a.buddy_id=b.buddy_id INNER JOIN ver_info AS c ON b.ver=c.ver WHERE buddy_name=? AND account_id=? AND cap=?;";
        NSArray *params = @[user, accountNo, cap];
        NSNumber* count = (NSNumber*) [self.db executeScalar:query andArguments:params];
        return (BOOL)([count integerValue]>0);
    }];
}

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andResource:(NSString*) resource onAccountNo:(NSNumber*) accountNo
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(*) FROM buddylist AS a INNER JOIN buddy_resources AS b ON a.buddy_id=b.buddy_id INNER JOIN ver_info AS c ON b.ver=c.ver WHERE buddy_name=? AND resource=? AND account_id=? AND cap=?;";
        NSNumber* count = (NSNumber*) [self.db executeScalar:query andArguments:@[user, resource, accountNo, cap]];
        return (BOOL)([count integerValue]>0);
    }];
}

-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource onAccountNo:(NSNumber*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT ver FROM buddy_resources AS A INNER JOIN buddylist AS B ON a.buddy_id=b.buddy_id WHERE resource=? AND buddy_name=? AND account_id=? LIMIT 1;";
        NSArray * params = @[resource, user, accountNo];
        NSString* ver = (NSString*) [self.db executeScalar:query andArguments:params];
        return ver;
    }];
}

-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource onAccountNo:(NSNumber*) accountNo
{
    NSNumber* timestamp = [HelperTools currentTimestampInSeconds];
    [self.db voidWriteTransaction:^{
        //set ver for user and resource
        NSString* query = @"UPDATE buddy_resources SET ver=? WHERE EXISTS(SELECT * FROM buddylist WHERE buddy_resources.buddy_id=buddylist.buddy_id AND resource=? AND buddy_name=? AND account_id=?)";
        NSArray * params = @[ver, resource, user, accountNo];
        [self.db executeNonQuery:query andArguments:params];
        
        //update timestamp for this ver string to make it not timeout (old ver strings and features are removed from feature cache after 28 days)
        NSString* query2 = @"INSERT INTO ver_timestamp (ver, timestamp) VALUES (?, ?) ON CONFLICT(ver) DO UPDATE SET timestamp=?;";
        NSArray * params2 = @[ver, timestamp, timestamp];
        [self.db executeNonQuery:query2 andArguments:params2];
    }];
}

-(NSSet*) getCapsforVer:(NSString*) ver
{
    return [self.db idReadTransaction:^{
        NSString* query = @"select cap from ver_info where ver=?";
        NSArray * params = @[ver];
        NSArray* resultArray = [self.db executeReader:query andArguments:params];
        
        if(resultArray != nil)
        {
            DDLogVerbose(@"caps count: %lu", (unsigned long)[resultArray count]);
            if([resultArray count] == 0)
                return (NSSet*)nil;
            NSMutableSet* retval = [NSMutableSet new];
            for(NSDictionary* row in resultArray)
                [retval addObject:row[@"cap"]];
            return (NSSet*)retval;
        }
        else
        {
            DDLogError(@"caps list is empty");
            return (NSSet*)nil;
        }
    }];
}

-(void) setCaps:(NSSet*) caps forVer:(NSString*) ver
{
    NSNumber* timestamp = [HelperTools currentTimestampInSeconds];
    [self.db voidWriteTransaction:^{
        //remove old caps for this ver
        NSString* query0 = @"DELETE FROM ver_info WHERE ver=?;";
        NSArray * params0 = @[ver];
        [self.db executeNonQuery:query0 andArguments:params0];
        
        //insert new caps
        for(NSString* feature in caps)
        {
            NSString* query1 = @"INSERT INTO ver_info (ver, cap) VALUES (?, ?);";
            NSArray * params1 = @[ver, feature];
            [self.db executeNonQuery:query1 andArguments:params1];
        }
        
        //update timestamp for this ver string
        NSString* query2 = @"INSERT INTO ver_timestamp (ver, timestamp) VALUES (?, ?) ON CONFLICT(ver) DO UPDATE SET timestamp=?;";
        NSArray * params2 = @[ver, timestamp, timestamp];
        [self.db executeNonQuery:query2 andArguments:params2];
        
        //cleanup old entries
        NSString* query3 = @"SELECT ver FROM ver_timestamp WHERE timestamp<?";
        NSArray* params3 = @[[NSNumber numberWithInteger:[timestamp integerValue] - (86400 * 28)]];     //cache timeout is 28 days
        NSArray* oldEntries = [self.db executeReader:query3 andArguments:params3];
        if(oldEntries)
            for(NSDictionary* row in oldEntries)
            {
                NSString* query4 = @"DELETE FROM ver_info WHERE ver=?;";
                NSArray * params4 = @[row[@"ver"]];
                [self.db executeNonQuery:query4 andArguments:params4];
            }
    }];
}

#pragma mark presence functions

-(void) setResourceOnline:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountNo
{
    if(!presenceObj.fromResource)
        return;
    [self.db voidWriteTransaction:^{
        //get buddyid for name and account
        NSString* query1 = @"select buddy_id from buddylist where account_id=? and buddy_name=?;";
        NSObject* buddyid = [self.db executeScalar:query1 andArguments:@[accountNo, presenceObj.fromUser]];
        if(buddyid)
        {
            NSString* query = @"insert or ignore into buddy_resources ('buddy_id', 'resource', 'ver') values (?, ?, '')";
            [self.db executeNonQuery:query andArguments:@[buddyid, presenceObj.fromResource]];
        }
    }];
}


-(NSArray<NSString*>*) resourcesForContact:(MLContact* _Nonnull) contact
{
    return [self.db idReadTransaction:^{
        NSArray<NSString*>* resources = [self.db executeScalarReader:@"SELECT resource FROM buddy_resources AS A INNER JOIN buddylist AS B ON a.buddy_id=b.buddy_id WHERE  buddy_name=?;" andArguments:@[contact.contactJid]];
        return resources;
    }];
}

-(MLContactSoftwareVersionInfo* _Nullable) getSoftwareVersionInfoForContact:(NSString*)contact resource:(NSString*)resource andAccount:(NSNumber*)accountNo
{
    if(accountNo == nil)
        return nil;
    NSArray<NSDictionary*>* versionInfoArr = [self.db idReadTransaction:^{
        NSArray<NSDictionary*>* resources = [self.db executeReader:@"SELECT platform_App_Name, platform_App_Version, platform_OS FROM buddy_resources WHERE buddy_id IN (SELECT buddy_id FROM buddylist WHERE account_id=? AND buddy_name=?) AND resource=?" andArguments:@[accountNo, contact, resource]];
        return resources;
    }];
    if(versionInfoArr == nil || versionInfoArr.count == 0) {
        return nil;
    } else {
        NSDictionary* versionInfo = versionInfoArr.firstObject;
        NSDate* lastInteraction = [self lastInteractionOfJid:contact andResource:resource forAccountNo:accountNo];
        return [[MLContactSoftwareVersionInfo alloc] initWithJid:contact andRessource:resource andAppName:versionInfo[@"platform_App_Name"] andAppVersion:versionInfo[@"platform_App_Version"] andPlatformOS:versionInfo[@"platform_OS"] andLastInteraction:lastInteraction];
    }
}

-(void) setSoftwareVersionInfoForContact:(NSString*)contact
                                resource:(NSString*)resource
                              andAccount:(NSNumber*)account
                        withSoftwareInfo:(MLContactSoftwareVersionInfo*) newSoftwareInfo
{
    [self.db voidWriteTransaction:^{
        NSString* query = @"update buddy_resources set platform_App_Name=?, platform_App_Version=?, platform_OS=? where buddy_id in (select buddy_id from buddylist where account_id=? and buddy_name=?) and resource=?";
        NSArray* params = @[newSoftwareInfo.appName, newSoftwareInfo.appVersion, newSoftwareInfo.platformOs, account, contact, resource];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

-(void) setOnlineBuddy:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self setResourceOnline:presenceObj forAccount:accountNo];
        NSString* query = @"UPDATE buddylist SET state='' WHERE account_id=? AND buddy_name=? AND state='offline';";
        NSArray* params = @[accountNo, presenceObj.fromUser];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

-(void) setOfflineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
{
    return [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM buddy_resources AS R WHERE resource=? AND EXISTS(SELECT * FROM buddylist AS B WHERE B.buddy_id=R.buddy_id AND B.account_id=? AND B.buddy_name=?);" andArguments:@[presenceObj.fromResource ? presenceObj.fromResource : @"", accountNo, presenceObj.fromUser]];
        [self.db executeNonQuery:@"UPDATE buddylist AS B SET state='offline' WHERE account_id=? AND buddy_name=? AND NOT EXISTS(SELECT * FROM buddy_resources AS R WHERE B.buddy_id=R.buddy_id);" andArguments:@[accountNo, presenceObj.fromUser]];
    }];
}

-(void) setBuddyState:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountNo;
{
    NSString* toPass = @"";
    if([presenceObj check:@"show#"])
    {
        //data length check
        if([[presenceObj findFirst:@"show#"] length] > 20)
            toPass = [[presenceObj findFirst:@"show#"] substringToIndex:19];
        else
            toPass = [presenceObj findFirst:@"show#"];
    }

    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET state=? WHERE account_id=? AND buddy_name=?;";
        [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.fromUser]];
    }];
}

-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT state FROM buddylist WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[accountNo, buddy];
        NSString* state = (NSString*)[self.db executeScalar:query andArguments:params];
        return state;
    }];
}

-(BOOL) hasContactRequestForContact:(MLContact*) contact
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(*) FROM subscriptionRequests WHERE account_id=? AND buddy_name=?";
        NSNumber* result = (NSNumber*)[self.db executeScalar:query andArguments:@[contact.accountId, contact.contactJid]];
        return (BOOL)(result.intValue == 1);
    }];
}

-(NSMutableArray*) allContactRequests
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT subscriptionRequests.account_id, subscriptionRequests.buddy_name FROM subscriptionRequests, account WHERE subscriptionRequests.account_id = account.account_id AND account.enabled;";
        NSMutableArray* toReturn = [NSMutableArray new];
        for(NSDictionary* dic in [self.db executeReader:query])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountNo:dic[@"account_id"]]];
        return toReturn;
    }];
}

-(void) addContactRequest:(MLContact*) requestor;
{
    [self.db voidWriteTransaction:^{
        NSString* query2 = @"INSERT OR IGNORE INTO subscriptionRequests (buddy_name, account_id) VALUES (?,?)";
        [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId]];
    }];
}

-(void) deleteContactRequest:(MLContact*) requestor
{
    [self.db voidWriteTransaction:^{
        NSString* query2 = @"delete from subscriptionRequests where buddy_name=? and account_id=? ";
        [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId]];
    }];
}

-(void) setBuddyStatus:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
{
    NSString* toPass = @"";
    if([presenceObj check:@"status#"])
    {
        //data length check
        if([[presenceObj findFirst:@"status#"] length] > 200)
            toPass = [[presenceObj findFirst:@"status#"] substringToIndex:199];
        else
            toPass = [presenceObj findFirst:@"status#"];
    }

    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET status=? WHERE account_id=? AND buddy_name=?;";
        [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.fromUser]];
    }];
}

-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT status FROM buddylist WHERE account_id=? AND buddy_name=?;";
        NSString* iconname =  (NSString *)[self.db executeScalar:query andArguments:@[accountNo, buddy]];
        return iconname;
    }];
}

-(NSString *) getRosterVersionForAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT rosterVersion FROM account WHERE account_id=?;";
        NSArray* params = @[ accountNo];
        NSString * version=(NSString*)[self.db executeScalar:query andArguments:params];
        return version;
    }];
}

-(void) setRosterVersion:(NSString*) version forAccount:(NSNumber*) accountNo
{
    if(accountNo == nil || !version)
        return;
    [self.db voidWriteTransaction:^{
        NSString* query = @"update account set rosterVersion=? where account_id=?";
        NSArray* params = @[version , accountNo];
        [self.db executeNonQuery:query  andArguments:params];
    }];
}

-(NSDictionary*) getSubscriptionForContact:(NSString*) contact andAccount:(NSNumber*) accountNo
{
    if(!contact || accountNo == nil)
        return nil;
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT subscription, ask from buddylist where buddy_name=? and account_id=?";
        NSArray* params = @[contact, accountNo];
        NSArray* version = [self.db executeReader:query andArguments:params];
        return version.firstObject;
    }];
}

-(void) setSubscription:(NSString*)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSNumber*) accountNo
{
    if(!contact || accountNo == nil || !sub)
        return;
    [self.db voidWriteTransaction:^{
        NSString* query = @"update buddylist set subscription=?, ask=? where account_id=? and buddy_name=?";
        NSArray* params = @[sub, ask?ask:@"", accountNo, contact];
        [self.db executeNonQuery:query  andArguments:params];
    }];
}



#pragma mark Contact info

-(void) setFullName:(NSString*) fullName forContact:(NSString*) contact andAccount:(NSNumber*) accountNo
{
    //data length check
    NSString* toPass;
    NSString* cleanFullName = [fullName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if([cleanFullName length]>50)
        toPass = [cleanFullName substringToIndex:49];
    else
        toPass = cleanFullName;

    if(!toPass)
        return;

    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET full_name=? WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[toPass , accountNo, contact];
        [self.db executeNonQuery:query  andArguments:params];
    }];
}

-(void) setAvatarHash:(NSString*) hash forContact:(NSString*) contact andAccount:(NSNumber*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE account SET iconhash=? WHERE account_id=? AND printf('%s@%s', username, domain)=?;" andArguments:@[hash, accountNo, contact]];
        [self.db executeNonQuery:@"UPDATE buddylist SET iconhash=? WHERE account_id=? AND buddy_name=?;" andArguments:@[hash, accountNo, contact]];
    }];
}

-(NSString*) getAvatarHashForContact:(NSString*) buddy andAccount:(NSNumber*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* hash = [self.db executeScalar:@"SELECT iconhash FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
        if(!hash)           //try to get the hash of our own account
            hash = [self.db executeScalar:@"SELECT iconhash FROM account WHERE account_id=? AND printf('%s@%s', username, domain)=?;" andArguments:@[accountNo, buddy]];
        if(!hash)
            hash = @"";     //hashes should never be nil
        return hash;
    }];
}

-(BOOL) isContactInList:(NSString*) buddy forAccount:(NSNumber*) accountNo
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"select count(buddy_id) from buddylist where account_id=? and buddy_name=? ";
        NSArray* params = @[accountNo, buddy];

        NSObject* value = [self.db executeScalar:query andArguments:params];

        NSNumber* count=(NSNumber*)value;
        BOOL toreturn = NO;
        if(count != nil)
        {
            NSInteger val = [count integerValue];
            if(val > 0) {
                toreturn = YES;
            }
        }
        return toreturn;
    }];
}

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountNo withComment:(NSString*) comment
{
    return [self.db boolWriteTransaction:^{
        return [self.db executeNonQuery:@"UPDATE buddylist SET messageDraft=? WHERE account_id=? AND buddy_name=?;" andArguments:@[comment, accountNo, buddy]];
    }];
}

-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT messageDraft FROM buddylist WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[accountNo, buddy];
        return [self.db executeScalar:query andArguments:params];
    }];
}

#pragma mark MUC

-(BOOL) initMuc:(NSString*) room forAccountId:(NSNumber*) accountNo andMucNick:(NSString* _Nullable) mucNick
{
    return [self.db boolWriteTransaction:^{
        BOOL isMuc = [self isBuddyMuc:room forAccount:accountNo];
        if(!isMuc)
        {
            // remove old buddy and add new one (this changes "normal" buddys to muc buddys if the aren't already tagged as mucs)
            // this will clean up associated buddylist data, too (foreign keys etc.)
            [self.db executeNonQuery:@"DELETE FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, room]];
        }
        
        NSString* nick = mucNick;
        if(!nick)
            nick = [self ownNickNameforMuc:room forAccount:accountNo];
        MLAssert(nick != nil, @"Could not determine muc nick when adding muc");
        
        [self cleanupMembersAndParticipantsListFor:room forAccountId:accountNo];
        
        BOOL encrypt = NO;
#ifndef DISABLE_OMEMO
        // omemo for non group MUCs is disabled once the type of the muc is set
        encrypt = [[HelperTools defaultsDB] boolForKey:@"OMEMODefaultOn"];
#endif// DISABLE_OMEMO
        
        return [self.db executeNonQuery:@"INSERT INTO buddylist ('account_id', 'buddy_name', 'muc', 'muc_nick', 'encrypt') VALUES(?, ?, 1, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET muc=1, muc_nick=?;" andArguments:@[accountNo, room, mucNick ? mucNick : @"", @(encrypt), mucNick ? mucNick : @""]];
    }];
}

-(void) cleanupMembersAndParticipantsListFor:(NSString*) room forAccountId:(NSNumber*) accountNo
{
    //clean up old muc data (will be refilled by incoming presences and/or disco queries)
    [self.db executeNonQuery:@"DELETE FROM muc_participants WHERE account_id=? AND room=?;" andArguments:@[accountNo, room]];
    [self.db executeNonQuery:@"DELETE FROM muc_members WHERE account_id=? AND room=?;" andArguments:@[accountNo, room]];
}

-(void) addParticipant:(NSDictionary*) participant toMuc:(NSString*) room forAccountId:(NSNumber*) accountNo
{
    if(!participant || !participant[@"nick"] || !room || accountNo == nil)
        return;
    
    [self.db voidWriteTransaction:^{
        //create entry if not already existing
        [self.db executeNonQuery:@"INSERT OR IGNORE INTO muc_participants ('account_id', 'room', 'room_nick') VALUES(?, ?, ?);" andArguments:@[accountNo, room, participant[@"nick"]]];
        
        //update entry with optional fields (the first two fields are for members that are not just participants)
        if(participant[@"jid"])
            [self.db executeNonQuery:@"UPDATE muc_participants SET participant_jid=? WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[participant[@"jid"], accountNo, room, participant[@"nick"]]];
        if(participant[@"affiliation"])
            [self.db executeNonQuery:@"UPDATE muc_participants SET affiliation=? WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[participant[@"affiliation"], accountNo, room, participant[@"nick"]]];
        if(participant[@"role"])
            [self.db executeNonQuery:@"UPDATE muc_participants SET role=? WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[participant[@"role"], accountNo, room, participant[@"nick"]]];
    }];
}

-(void) removeParticipant:(NSDictionary*) participant fromMuc:(NSString*) room forAccountId:(NSNumber*) accountNo
{
    if(!participant || !participant[@"nick"] || !room || accountNo == nil)
        return;
    
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM muc_participants WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[accountNo, room, participant[@"nick"]]];
    }];
}

-(void) addMember:(NSDictionary*) member toMuc:(NSString*) room forAccountId:(NSString*) accountNo
{
    if(!member || !member[@"jid"] || !room || !accountNo)
        return;
    
    [self.db voidWriteTransaction:^{
        //create entry if not already existing
        [self.db executeNonQuery:@"INSERT OR IGNORE INTO muc_members ('account_id', 'room', 'member_jid') VALUES(?, ?, ?);" andArguments:@[accountNo, room, member[@"jid"]]];
        
        //update entry with optional fields
        if(member[@"affiliation"])
            [self.db executeNonQuery:@"UPDATE muc_members SET affiliation=? WHERE account_id=? AND room=? AND member_jid=?;" andArguments:@[member[@"affiliation"], accountNo, room, member[@"jid"]]];
    }];
}

-(void) removeMember:(NSDictionary*) member fromMuc:(NSString*) room forAccountId:(NSNumber*) accountNo
{
    if(!member || !member[@"jid"] || !room || accountNo == nil)
        return;
    
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM muc_members WHERE account_id=? AND room=? AND member_jid=?;" andArguments:@[accountNo, room, member[@"jid"]]];
    }];
}

-(NSDictionary* _Nullable) getParticipantForNick:(NSString*) nick inRoom:(NSString*) room forAccountId:(NSString*) accountNo
{
    if(!nick || !room || accountNo == nil)
        return nil;
    return [self.db idReadTransaction:^{
        NSArray* result = [self.db executeReader:@"SELECT * FROM muc_participants WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[accountNo, room, nick]];
        return result.count > 0 ? result[0] : nil;
    }];
}

-(NSArray<NSDictionary<NSString*, id>*>*) getMembersAndParticipantsOfMuc:(NSString*) room forAccountId:(NSNumber*) accountNo
{
    if(!room || accountNo == nil)
        return [[NSMutableArray<NSDictionary<NSString*, id>*> alloc] init];
    return [self.db idReadTransaction:^{
        NSMutableArray<NSDictionary<NSString*, id>*>* toReturn = [[NSMutableArray<NSDictionary<NSString*, id>*> alloc] init];
        
        [toReturn addObjectsFromArray:[self.db executeReader:@"SELECT *, 1 as 'online' FROM muc_participants WHERE account_id=? AND room=?;" andArguments:@[accountNo, room]]];
        [toReturn addObjectsFromArray:[self.db executeReader:@"SELECT *, 0 as 'online' FROM muc_members WHERE account_id=? AND room=? AND NOT EXISTS(SELECT * FROM muc_participants WHERE muc_members.account_id=muc_participants.account_id AND muc_members.room=muc_participants.room AND muc_members.member_jid=muc_participants.participant_jid);" andArguments:@[accountNo, room]]];
        
        return toReturn;
    }];
}

-(void) addMucFavorite:(NSString*) room forAccountId:(NSNumber*) accountNo andMucNick:(NSString* _Nullable) mucNick
{
    [self.db voidWriteTransaction:^{
        NSString* nick = mucNick;
        if(!nick)
            nick = [self ownNickNameforMuc:room forAccount:accountNo];
        MLAssert(nick != nil, @"Could not determine muc nick when adding muc");
        
        [self.db executeNonQuery:@"INSERT INTO muc_favorites (room, nick, account_id) VALUES(?, ?, ?) ON CONFLICT(room, account_id) DO UPDATE SET nick=?;" andArguments:@[room, nick, accountNo, nick]];
    }];
}

-(NSString*) lastStanzaIdForMuc:(NSString* _Nonnull) room andAccount:(NSString* _Nonnull) accountNo
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT lastMucStanzaId FROM buddylist WHERE muc=1 AND account_id=? AND buddy_name=?;" andArguments:@[accountNo, room]];
    }];
}

-(void) setLastStanzaId:(NSString*) lastStanzaId forMuc:(NSString* _Nonnull) room andAccount:(NSString* _Nonnull) accountNo
{
    [self.db voidWriteTransaction:^{
        if(lastStanzaId && [lastStanzaId length])
            [self.db executeNonQuery:@"UPDATE buddylist SET lastMucStanzaId=? WHERE muc=1 AND account_id=? AND buddy_name=?;" andArguments:@[lastStanzaId, accountNo, room]];
    }];
}


-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSNumber*) accountNo
{
    return [self.db boolReadTransaction:^{
        NSNumber* status = (NSNumber*)[self.db executeScalar:@"SELECT Muc FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
        if(status == nil)
            return NO;
        else
            return [status boolValue];
    }];
}

-(NSString* _Nullable) ownNickNameforMuc:(NSString*) room forAccount:(NSNumber*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* nick = (NSString*)[self.db executeScalar:@"SELECT muc_nick FROM buddylist WHERE account_id=? AND buddy_name=? and muc=1;" andArguments:@[accountNo, room]];
        // fallback to nick in muc_favorites
        if(!nick || nick.length == 0)
            nick = (NSString*)[self.db executeScalar:@"SELECT nick FROM muc_favorites WHERE account_id=? AND room=?;" andArguments:@[accountNo, room]];
        if(!nick || nick.length == 0)
            return (NSString*)nil;
        return nick;
    }];
}

-(BOOL) updateOwnNickName:(NSString*) nick forMuc:(NSString*) room forAccount:(NSNumber*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET muc_nick=? WHERE account_id=? AND buddy_name=? AND muc=1;";
        NSArray* params = @[nick, accountNo, room];
        DDLogVerbose(@"%@", query);

        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(BOOL) deleteMuc:(NSString*) room forAccountId:(NSNumber*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"DELETE FROM muc_favorites WHERE room=? AND account_id=?;";
        NSArray* params = @[room, accountNo];
        DDLogVerbose(@"%@", query);

        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(NSMutableArray*) listMucsForAccount:(NSNumber*) accountNo
{
    return [self.db idReadTransaction:^{
        return [self.db executeReader:@"SELECT * FROM muc_favorites WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(BOOL) updateMucSubject:(NSString *) subject forAccount:(NSNumber*) accountNo andRoom:(NSString *) room
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET muc_subject=? WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[subject, accountNo, room];
        DDLogVerbose(@"%@", query);
        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(NSString*) mucSubjectforAccount:(NSNumber*) accountNo andRoom:(NSString*) room
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT muc_subject FROM buddylist WHERE account_id=? AND buddy_name=?;";

        NSArray* params = @[accountNo, room];
        DDLogVerbose(@"%@", query);

        return [self.db executeScalar:query andArguments:params];
    }];
}

-(void) updateMucTypeTo:(NSString*) type forRoom:(NSString*) room andAccount:(NSNumber*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET muc_type=? WHERE account_id=? AND buddy_name=?;" andArguments:@[type, accountNo, room]];
        if([type isEqualToString:@"group"] == NO)
        {
            // non group type MUCs do not support encryption
            [self.db executeNonQuery:@"UPDATE buddylist SET encrypt=0 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, room]];
        }
    }];
}

-(NSString*) getMucTypeOfRoom:(NSString*) room andAccount:(NSNumber*) accountNo
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT muc_type FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, room]];
    }];
}

#pragma mark message Commands

-(NSArray<MLMessage*>*) messagesForHistoryIDs:(NSArray<NSNumber*>*) historyIDs
{
    return [self.db idReadTransaction:^{
        NSString* idList = [historyIDs componentsJoinedByString:@","];
        NSString* query = [NSString stringWithFormat:@"SELECT \
            B.Muc, B.muc_type, \
            CASE \
                WHEN M.actual_from NOT NULL THEN M.actual_from \
                WHEN M.inbound=0 THEN (A.username || '@' || A.domain) \
                ELSE M.buddy_name \
            END AS af, \
            timestamp AS thetime, M.* \
            FROM message_history AS M INNER JOIN buddylist AS B \
                ON M.account_id=B.account_id AND M.buddy_name=B.buddy_name \
            INNER JOIN account AS A \
                ON M.account_id=A.account_id \
            WHERE M.message_history_id IN(%@);", idList];
        NSMutableArray<MLMessage*>* retval = [[NSMutableArray<MLMessage*> alloc] init];
        for(NSDictionary* dic in [self.db executeReader:query])
        {
            NSMutableDictionary* message = [dic mutableCopy];
            if(message[@"thetime"])
                message[@"thetime"] = [dbFormatter dateFromString:message[@"thetime"]];
            [retval addObject:[MLMessage messageFromDictionary:message]];
        }
        return retval;
    }];
}

-(MLMessage*) messageForHistoryID:(NSNumber*) historyID
{
    if(historyID == nil)
        return nil;
    NSArray<MLMessage*>* result = [self messagesForHistoryIDs:@[historyID]];
    if(![result count])
        return nil;
    return result[0];
}

-(NSNumber*) getSmallestHistoryId
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT MIN(message_history_id) FROM message_history;"];
    }];
}

-(NSNumber*) addMessageToChatBuddy:(NSString*) buddyName withInboundDir:(BOOL) inbound forAccount:(NSNumber*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom participantJid:(NSString*) participantJid sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString*) messageid serverMessageId:(NSString*) stanzaid messageType:(NSString*) messageType andOverrideDate:(NSDate*) messageDate encrypted:(BOOL) encrypted displayMarkerWanted:(BOOL) displayMarkerWanted usingHistoryId:(NSNumber* _Nullable) historyId checkForDuplicates:(BOOL) checkForDuplicates
{
    if(!buddyName || !message)
        return nil;
    
    return [self.db idWriteTransaction:^{
        if(!checkForDuplicates || ![self hasMessageForStanzaId:stanzaid orMessageID:messageid withInboundDir:inbound onAccount:accountNo])
        {
            //this is always from a contact
            NSDateFormatter* formatter = [NSDateFormatter new];
            [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            NSDate* sourceDate = [NSDate date];
            NSDate* destinationDate;
            if(messageDate)
            {
                //already GMT no need for conversion
                destinationDate = messageDate;
                [formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
            }
            else
            {
                NSTimeZone* sourceTimeZone = [NSTimeZone systemTimeZone];
                NSTimeZone* destinationTimeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];

                NSInteger sourceGMTOffset = [sourceTimeZone secondsFromGMTForDate:sourceDate];
                NSInteger destinationGMTOffset = [destinationTimeZone secondsFromGMTForDate:sourceDate];
                NSTimeInterval interval = destinationGMTOffset - sourceGMTOffset;

                destinationDate = [[NSDate alloc] initWithTimeInterval:interval sinceDate:sourceDate];
            }
            // note: if it isnt the same day we want to show the full  day
            NSString* dateString = [formatter stringFromDate:destinationDate];
            
            NSString* query;
            NSArray* params;
            if(historyId != nil)
            {
                DDLogVerbose(@"Inserting backwards with history id %@", historyId);
                query = @"insert into message_history (message_history_id, account_id, buddy_name, inbound, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid, participant_jid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
                params = @[historyId, accountNo, buddyName, [NSNumber numberWithBool:inbound], dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", messageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@"", participantJid != nil ? participantJid : [NSNull null]];
            }
            else
            {
                //we use autoincrement here instead of MAX(message_history_id) + 1 to be a little bit faster (but at the cost of "duplicated code")
                query = @"insert into message_history (account_id, buddy_name, inbound, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid, participant_jid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
                params = @[accountNo, buddyName, [NSNumber numberWithBool:inbound], dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", messageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@"", participantJid != nil ? participantJid : [NSNull null]];
            }
            DDLogVerbose(@"%@ params:%@", query, params);
            BOOL success = [self.db executeNonQuery:query andArguments:params];
            if(!success)
                return (NSNumber*)nil;
            NSNumber* historyId = [self.db lastInsertId];
            [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo];
            return historyId;
        }
        else
        {
            DDLogError(@"Message(%@) %@ with stanzaid %@ already existing, ignoring history update", accountNo, messageid, stanzaid);
            return (NSNumber*)nil;
        }
    }];
}

-(BOOL) hasMessageForStanzaId:(NSString*) stanzaId orMessageID:(NSString*) messageId withInboundDir:(BOOL) inbound onAccount:(NSNumber*) accountNo
{
    if(accountNo == nil)
        return NO;
    
    return [self.db boolWriteTransaction:^{
        //if the stanzaid was given, this is conclusive for dedup, we don't need to check any other ids (EXCEPTION BELOW)
        if(stanzaId)
        {
            DDLogVerbose(@"stanzaid provided");
            NSArray* found = [self.db executeReader:@"SELECT * FROM message_history WHERE account_id=? AND stanzaid!='' AND stanzaid=?;" andArguments:@[accountNo, stanzaId]];
            if([found count])
            {
                DDLogVerbose(@"stanzaid provided and could be found: %@", found);
                return YES;
            }
        }
        
        //EXCEPT: outbound messages coming from this very client (we don't know their stanzaids)
        //NOTE: the MAM XEP does not mandate full jids in from-attribute of the wrapped message stanza
        //      --> we can't use that to figure out if the message came from this very client or only from another client using this account
        //=> if the stanzaid does not match and we process an outbound message, only dedup using origin-id (that should be unique and monal sets them)
        //   the check, if an origin-id was given, lives in MLMessageProcessor.m (it only triggers a dedup for messages either having a stanzaid or an origin-id)
        if(inbound == NO)
        {
            NSNumber* historyId = (NSNumber*)[self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND inbound=0 AND messageid=?;" andArguments:@[accountNo, messageId]];
            if(historyId != nil)
            {
                DDLogVerbose(@"found by origin-id or messageid");
                if(stanzaId)
                {
                    DDLogDebug(@"Updating stanzaid of message_history_id %@ to %@ for (account=%@, messageid=%@, inbound=%d)...", historyId, stanzaId, accountNo, messageId, inbound);
                    //this entry needs an update of its stanzaid
                    [self.db executeNonQuery:@"UPDATE message_history SET stanzaid=? WHERE message_history_id=?" andArguments:@[stanzaId, historyId]];
                }
                return YES;
            }
        }
        
        DDLogVerbose(@"nothing worked --> message not found");
        return NO;
    }];
}

-(void) setMessageId:(NSString* _Nonnull) messageid sent:(BOOL) sent
{
    [self.db voidWriteTransaction:^{
        BOOL _sent = sent;
        //force sent YES if the message was already received
        if(!_sent)
        {
            if([self.db executeScalar:@"SELECT messageid FROM message_history WHERE messageid=? AND received;" andArguments:@[messageid]])
                _sent = YES;
        }
        NSString* query = @"UPDATE message_history SET sent=? WHERE messageid=? AND NOT sent;";
        DDLogVerbose(@"setting sent %@", messageid);
        [self.db executeNonQuery:query andArguments:@[[NSNumber numberWithBool:_sent], messageid]];
    }];
}

-(void) setMessageId:(NSString* _Nonnull ) messageid received:(BOOL) received
{
    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE message_history SET received=?, sent=? WHERE messageid=?;";
        DDLogVerbose(@"setting received confrmed %@", messageid);
        [self.db executeNonQuery:query andArguments:@[[NSNumber numberWithBool:received], [NSNumber numberWithBool:YES], messageid]];
    }];
}

-(void) setMessageId:(NSString* _Nonnull) messageid errorType:(NSString* _Nonnull) errorType errorReason:(NSString* _Nonnull) errorReason
{
    [self.db voidWriteTransaction:^{
        //ignore error if the message was already received by *some* client
        if([self.db executeScalar:@"SELECT messageid FROM message_history WHERE messageid=? AND received;" andArguments:@[messageid]])
        {
            DDLogVerbose(@"ignoring message error for %@ [%@, %@]", messageid, errorType, errorReason);
            return;
        }
        NSString* query = @"UPDATE message_history SET errorType=?, errorReason=? WHERE messageid=?;";
        DDLogVerbose(@"setting message error %@ [%@, %@]", messageid, errorType, errorReason);
        [self.db executeNonQuery:query andArguments:@[errorType, errorReason, messageid]];
    }];
}

-(void) clearErrorOfMessageId:(NSString* _Nonnull) messageid
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE message_history SET errorType='', errorReason='' WHERE messageid=?;" andArguments:@[messageid]];
    }];
}

-(void) setMessageHistoryId:(NSNumber*) historyId filetransferMimeType:(NSString*) mimeType filetransferSize:(NSNumber*) size
{
    if(historyId == nil)
        return;
    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE message_history SET messageType=?, filetransferMimeType=?, filetransferSize=? WHERE message_history_id=?;";
        DDLogVerbose(@"setting message type 'kMessageTypeFiletransfer', mime type '%@' and size %@ for history id %@", mimeType, size, historyId);
        [self.db executeNonQuery:query andArguments:@[kMessageTypeFiletransfer, mimeType, size, historyId]];
    }];
}

-(void) setMessageHistoryId:(NSNumber*) historyId messageType:(NSString*) messageType
{
    if(historyId == nil)
        return;
    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE message_history SET messageType=? WHERE message_history_id=?;";
        DDLogVerbose(@"setting message type '%@' for history id %@", messageType, historyId);
        [self.db executeNonQuery:query andArguments:@[messageType, historyId]];
    }];
}

-(void) setMessageId:(NSString*) messageid previewText:(NSString*) text andPreviewImage:(NSString*) image
{
    if(!messageid)
        return;
    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE message_history SET previewText=?, previewImage=? WHERE messageid=?;";
        DDLogVerbose(@"setting previews type %@", messageid);
        [self.db executeNonQuery:query  andArguments:@[text?text:@"", image?image:@"", messageid]];
    }];
}

-(void) setMessageId:(NSString*) messageid stanzaId:(NSString*) stanzaId
{
    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE message_history SET stanzaid=? WHERE messageid=?;";
        DDLogVerbose(@"setting message stanzaid %@", query);
        [self.db executeNonQuery:query andArguments:@[stanzaId, messageid]];
    }];
}

-(void) clearMessages:(NSNumber*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=?;" andArguments:@[kMessageTypeFiletransfer, accountNo]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=?;" andArguments:@[accountNo]];
        
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE account_id=?;" andArguments:@[accountNo]];
        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
    }];
}

-(void) clearMessagesWithBuddy:(NSString*) buddy onAccount:(NSNumber*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=? AND buddy_name=?;" andArguments:@[kMessageTypeFiletransfer, accountNo, buddy]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
        
        //better UX without deleting the active chat
        //[self.db executeNonQuery:@"DELETE FROM activechats WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
    }];
}


-(void) autodeleteAllMessagesAfter3Days
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];
        //3 days before now
        NSString* pastDate = [dbFormatter stringFromDate:[[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay value:-3 toDate:[NSDate date] options:0]];
        //delete all transferred files old enough
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND timestamp<?;" andArguments:@[kMessageTypeFiletransfer, pastDate]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];
        //delete all messages in history old enough
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE timestamp<?;" andArguments:@[pastDate]];
        //delete all chats with empty history from active chats list
        [self.db executeNonQuery:@"DELETE FROM activechats AS AC WHERE NOT EXISTS (SELECT account_id FROM message_history AS MH WHERE MH.account_id=AC.account_id AND MH.buddy_name=AC.buddy_name);"];
        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
    }];
}

-(void) deleteMessageHistory:(NSNumber*) messageNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];
        MLMessage* msg = [self messageForHistoryID:messageNo];
        if([msg.messageType isEqualToString:kMessageTypeFiletransfer])
            [MLFiletransfer deleteFileForMessage:msg];
        [self.db executeNonQuery:@"UPDATE message_history SET message='', messageType=?, filetransferMimeType='', filetransferSize=0, retracted=1 WHERE message_history_id=?;" andArguments:@[kMessageTypeText, messageNo]];
        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
    }];
}

-(void) deleteMessageHistoryLocally:(NSNumber*) messageNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];
        MLMessage* msg = [self messageForHistoryID:messageNo];
        if([msg.messageType isEqualToString:kMessageTypeFiletransfer])
            [MLFiletransfer deleteFileForMessage:msg];
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE message_history_id=?;" andArguments:@[messageNo]];
        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
    }];
}

-(void) updateMessageHistory:(NSNumber*) messageNo withText:(NSString*) newText
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE message_history SET message=? WHERE message_history_id=?;" andArguments:@[newText, messageNo]];
    }];
}

-(NSNumber*) getHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from andAccount:(NSNumber*) accountNo
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT M.message_history_id FROM message_history AS M INNER JOIN account AS A ON M.account_id=A.account_id WHERE messageid=? AND ((M.buddy_name=? AND M.inbound=1) OR ((A.username || '@' || A.domain)=? AND M.inbound=0)) AND M.account_id=?;" andArguments:@[messageid, from, from, accountNo]];
    }];
}

-(NSDate* _Nullable) returnTimestampForQuote:(NSNumber*) historyID
{
    return [self.db idReadTransaction:^{
        MLMessage* msg = [self messageForHistoryID:historyID];
        
        //timestamp not needed if we can't find the message we are quoting
        if(msg == nil)
            return (NSDate*)nil;

        //check if message is among the newest 8 exchanged with this buddy
        NSNumber*  isRecentEnough = (NSNumber*)[self.db executeScalar:@"\
            SELECT COUNT(message_history_id) \
            FROM \
                (SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? ORDER BY message_history_id DESC LIMIT 8) \
            WHERE \
                message_history_id=?; \
            " andArguments:@[msg.accountId, msg.buddyName, historyID]];
        
        if(isRecentEnough.intValue == 1)
            return (NSDate*)nil;
        //messages not among the newest 8, but received in the last 15 minutes don't need a timestamp either
        if([[NSDate date] timeIntervalSinceDate:msg.timestamp] < 900)
            return (NSDate*)nil;
        return msg.timestamp;
    }];
}

-(BOOL) checkLMCEligible:(NSNumber*) historyID encrypted:(BOOL) encrypted historyBaseID:(NSNumber* _Nullable) historyBaseID
{
    return [self.db boolReadTransaction:^{
        MLMessage* msg = [self messageForHistoryID:historyID];
        NSNumber* editAllowed;
        
        //corretion not allowed if we can't find the message the correction was for
        if(msg == nil)
            return NO;
        
        //use the oldest 3 messages, if we are processing a MLhistory mam fetch, and the newest 3, if we are going forward in time
        if(historyBaseID != nil)
        {
            //only allow LMC for the 3 newest messages of this contact (or of us)
            editAllowed = (NSNumber*)[self.db executeScalar:@"\
                SELECT \
                    CASE \
                        WHEN (encrypted=? OR 1=?) THEN 1 \
                        ELSE 0 \
                    END \
                FROM \
                    (SELECT message_history_id, inbound, encrypted, messageType FROM message_history WHERE account_id=? AND buddy_name=? AND message_history_id<? ORDER BY message_history_id ASC LIMIT 3) \
                WHERE \
                    message_history_id=?; \
                " andArguments:@[[NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:encrypted], msg.accountId, msg.buddyName, historyBaseID, historyID]];
        }
        else
        {
            //only allow LMC for the 3 newest messages of this contact (or of us)
            editAllowed = (NSNumber*)[self.db executeScalar:@"\
                SELECT \
                    CASE \
                        WHEN (encrypted=? OR 1=?) THEN 1 \
                        ELSE 0 \
                    END \
                FROM \
                    (SELECT message_history_id, inbound, encrypted, messageType FROM message_history WHERE account_id=? AND buddy_name=? ORDER BY message_history_id DESC LIMIT 3) \
                WHERE \
                    message_history_id=?; \
                " andArguments:@[[NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:encrypted], msg.accountId, msg.buddyName, historyID]];
        }
        BOOL eligible = YES;
        eligible &= editAllowed.intValue == 1;
        eligible &= [msg.messageType isEqualToString:kMessageTypeText];
        return eligible;
    }];
}

//message history
-(NSNumber*) lastMessageHistoryIdForContact:(NSString*) buddy forAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? ORDER BY message_history_id DESC LIMIT 1" andArguments:@[ accountNo, buddy]];
    }];
}

//message history
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountNo
{
    if(accountNo == nil || !buddy)
        return nil;
    return [self.db idReadTransaction:^{
        NSNumber* lastMsgHistID = [self lastMessageHistoryIdForContact:buddy forAccount:accountNo];
        // Increment msgHistId -> all messages <= msgHistId are feteched
        lastMsgHistID = [NSNumber numberWithInt:[lastMsgHistID intValue] + 1];
        return [self messagesForContact:buddy forAccount:accountNo beforeMsgHistoryID:lastMsgHistID];
    }];
}

//message history
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountNo beforeMsgHistoryID:(NSNumber* _Nullable) msgHistoryID
{
    if(accountNo == nil || !buddy)
        return nil;
    return [self.db idReadTransaction:^{
        NSNumber* historyIdToUse = msgHistoryID;
        //fall back to newest message in history (including this message in this case)
        if(historyIdToUse == nil)
        {
            //we are querying with < relation below, but want to include the newest message nontheless
            historyIdToUse = @([[self lastMessageHistoryIdForContact:buddy forAccount:accountNo] intValue] + 1);
        }
        NSString* query = @"SELECT message_history_id FROM (SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? AND message_history_id<? ORDER BY message_history_id DESC LIMIT ?) ORDER BY message_history_id ASC;";
        NSNumber* msgLimit = @(kMonalBackscrollingMsgCount);
        NSArray* params = @[accountNo, buddy, historyIdToUse, msgLimit];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}

-(MLMessage*) lastMessageForContact:(NSString*) contact forAccount:(NSString*) accountNo
{
    if(!accountNo || !contact)
        return nil;
    
    return [self.db idReadTransaction:^{
        //return message draft (if any)
        NSString* query = @"SELECT bl.messageDraft AS message, ac.lastMessageTime AS thetime, 'MessageDraft' AS messageType, '' AS af, '' AS filetransferMimeType, 0 AS filetransferSize, bl.Muc, bl.muc_type, bl.buddy_name FROM buddylist AS bl INNER JOIN activechats AS ac ON bl.account_id = ac.account_id AND bl.buddy_name = ac.buddy_name WHERE ac.account_id=? AND ac.buddy_name=? AND messageDraft IS NOT NULL AND messageDraft != '';";
        NSArray* params = @[accountNo, contact];
        NSArray* results = [self.db executeReader:query andArguments:params];
        if([results count])
        {
            NSMutableDictionary* message = [(NSDictionary*)results[0] mutableCopy];
            if(message[@"thetime"])
                message[@"thetime"] = [dbFormatter dateFromString:message[@"thetime"]];
            return [MLMessage messageFromDictionary:message];
        }
        
        //return "real" last message
        NSNumber* historyID = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountNo, contact]];
        if(historyID == nil)
            return (MLMessage*)nil;
        return [self messageForHistoryID:historyID];
    }];
}

-(NSArray<MLMessage*>*) markMessagesAsReadForBuddy:(NSString*) buddy andAccount:(NSString*) accountNo tillStanzaId:(NSString*) stanzaid wasOutgoing:(BOOL) outgoing
{
    if(!buddy || !accountNo)
    {
        DDLogError(@"No buddy or accountNo specified!");
        return @[];
    }
    
    return (NSArray<MLMessage*>*)[self.db idWriteTransaction:^{
        NSNumber* historyId;
        
        if(stanzaid)        //stanzaid or messageid given --> return all unread / not displayed messages until (and including) this one
        {
            historyId = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND stanzaid!='' AND stanzaid=? ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountNo, stanzaid]];
            
            //if stanzaid could not be found we've got a messageid instead
            if(historyId == nil)
            {
                DDLogVerbose(@"Stanzaid not found, trying messageid");
                historyId = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND messageid=? ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountNo, stanzaid]];
            }
            //messageid still not found?
            if(historyId == nil)
            {
                DDLogWarn(@"Could not get message_history_id for stanzaid/messageid %@", stanzaid);
                return @[];     //no messages with this stanzaid / messageid could be found
            }
        }
        else        //no stanzaid given --> return all unread / not displayed messages for this contact
        {
            DDLogDebug(@"Returning newest historyId (no stanzaid/messageid given)");
            historyId = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountNo, buddy]];
            
            if(historyId == nil)
            {
                DDLogWarn(@"Could not get newest message_history_id (history empty)");
                return @[];     //no messages with this stanzaid / messageid could be found
            }
        }
        
        //on outgoing messages we only allow displayed=true for markable messages that have been received properly by the other end
        //marking messages as displayed that have not been received (or marking messages that are not markable) would create false UI
        NSArray* messageArray;
        if(outgoing)
            messageArray = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE displayed=0 AND displayMarkerWanted=1 AND received=1 AND account_id=? AND buddy_name=? AND inbound=0 AND message_history_id<=? ORDER BY message_history_id ASC;" andArguments:@[accountNo, buddy, historyId]];
        else
            messageArray = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE unread=1 AND account_id=? AND buddy_name=? AND inbound=1 AND message_history_id<=? ORDER BY message_history_id ASC;" andArguments:@[accountNo, buddy, historyId]];
        
        DDLogVerbose(@"[%@:%@] messageArray=%@", outgoing ? @"OUT" : @"IN", historyId, messageArray);
        
        //mark messages as read/displayed
        for(NSNumber* historyIDEntry in messageArray)
        {
            if(outgoing)
                [self.db executeNonQuery:@"UPDATE message_history SET displayed=1 WHERE message_history_id=? AND received=1;" andArguments:@[historyIDEntry]];
            else
            {
                [self.db executeNonQuery:@"UPDATE message_history SET unread=0 WHERE message_history_id=?;" andArguments:@[historyIDEntry]];
                //make sure the latest_read_message_history_id field in our buddylist is updated
                [self.db executeNonQuery:@"UPDATE buddylist SET latest_read_message_history_id=? WHERE account_id=? AND buddy_name=?;" andArguments:@[historyIDEntry, accountNo, buddy]];
            }
        }
        
        //return NSArray of all updated MLMessages
        return (NSArray*)[self messagesForHistoryIDs:messageArray];
    }];
}

-(NSNumber*) addMessageHistoryTo:(NSString*) to forAccount:(NSNumber*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString*) messageId encrypted:(BOOL) encrypted messageType:(NSString*) messageType mimeType:(NSString*) mimeType size:(NSNumber*) size
{
    //Message_history going out, from is always the local user. always read and not sent
    NSArray* parts = [[[NSDate date] description] componentsSeparatedByString:@" "];
    NSString* dateTime = [NSString stringWithFormat:@"%@ %@", [parts objectAtIndex:0], [parts objectAtIndex:1]];
    if(mimeType && size != nil)
        size = @(0);
    NSString* query;
    NSArray* params;
    if(mimeType && size)
    {
        query = @"INSERT INTO message_history (account_id, buddy_name, inbound, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, displayMarkerWanted, filetransferMimeType, filetransferSize) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?);";
        params = @[accountNo, to, [NSNumber numberWithBool:NO], dateTime, message, actualfrom, [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], messageId, messageType, [NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:YES], mimeType, size];
    }
    else
    {
        query = @"INSERT INTO message_history (account_id, buddy_name, inbound, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, displayMarkerWanted) VALUES(?,?,?,?,?,?,?,?,?,?,?,?);";
        params = @[accountNo, to, [NSNumber numberWithBool:NO], dateTime, message, actualfrom, [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], messageId, messageType, [NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:YES]];
    }
    
    return [self.db idWriteTransaction:^{
        DDLogVerbose(@"%@", query);
        BOOL result = [self.db executeNonQuery:query andArguments:params];
        if(!result)
            return (NSNumber*)nil;
        NSNumber* historyId = [self.db lastInsertId];
        [self updateActiveBuddy:to setTime:dateTime forAccount:accountNo];
        return historyId;
    }];
}

//count unread
-(NSNumber*) countUnreadMessages
{
    return [self.db idReadTransaction:^{
        // count # of unread msgs in message table and ignore muted buddies and mentionOnly buddies without mention
        return [self.db executeScalar:@"SELECT Count(M.message_history_id) \
                                        FROM message_history AS M \
                                        LEFT JOIN buddylist AS B \
                                                    ON M.account_id = B.account_id \
                                                        AND M.buddy_name = B.buddy_name \
                                        LEFT JOIN account AS A \
                                                    ON M.account_id = A.account_id \
                                        WHERE M.message_history_id > (SELECT Min(latest_read_message_history_id) FROM buddylist) \
                                            AND A.enabled \
                                            AND B.muted = 0 \
                                            AND M.inbound = 1 \
                                            AND M.unread = 1 \
                                            AND ( \
                                                B.mentionOnly = 0 OR ( \
                                                       (B.muc_nick != '' AND M.message LIKE '%'||B.muc_nick||'%') \
                                                    OR (A.rosterName != '' AND M.message LIKE '%'||A.rosterName||'%') \
                                                    OR (A.username != '' AND M.message LIKE '%'||A.username||'%') \
                                                    OR (A.username != '' AND A.domain != '' AND M.message LIKE '%'||A.username||'@'||A.domain||'%') \
                                                ) \
                                            ) \
                                        ;"];
    }];
}

-(NSString*) lastStanzaIdForAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT lastStanzaId FROM account WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(void) setLastStanzaId:(NSString*) lastStanzaId forAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE account SET lastStanzaId=? WHERE account_id=?;" andArguments:@[lastStanzaId, accountNo]];
    }];
}

#pragma mark active chats

-(NSMutableArray<MLContact*>*) activeContactsWithPinned:(BOOL) pinned
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT a.buddy_name, a.account_id FROM activechats AS a JOIN buddylist AS b ON (a.buddy_name = b.buddy_name AND a.account_id = b.account_id) JOIN account ON a.account_id = account.account_id WHERE a.pinned=? AND account.enabled ORDER BY lastMessageTime DESC;";
        NSMutableArray<MLContact*>* toReturn = [[NSMutableArray<MLContact*> alloc] init];
        for(NSDictionary* dic in [self.db executeReader:query andArguments:@[[NSNumber numberWithBool:pinned]]])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountNo:dic[@"account_id"]]];
        return toReturn;
    }];
}

-(NSArray<MLContact*>*) activeContactDict
{
    return [self.db idReadTransaction:^{
        NSMutableArray<MLContact*>* mergedContacts = [self activeContactsWithPinned:YES];
        [mergedContacts addObjectsFromArray:[self activeContactsWithPinned:NO]];
        return mergedContacts;
    }];
}

-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        //mark all messages as read
        [self.db executeNonQuery:@"UPDATE message_history SET unread=0 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddyname]];
        //make sure the latest_read_message_history_id field in our buddylist is updated
        //(we use the newest history entry for this buddyname here)
        [self.db executeNonQuery:@"UPDATE buddylist SET latest_read_message_history_id=COALESCE((\
            SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? AND inbound=1 ORDER BY message_history_id DESC LIMIT 1\
        ), (\
            SELECT message_history_id FROM message_history ORDER BY message_history_id DESC LIMIT 1\
        ), 0) WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddyname, accountNo, buddyname]];
        //remove contact from active chats list
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddyname]];
    }];
}

-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSNumber*) accountNo
{
    if(!buddyname || accountNo == nil)
        return;
    
    [self.db voidWriteTransaction:^{
        //add contact if possible (ignore already existing contacts)
        [self addContact:buddyname forAccount:accountNo nickname:nil];

        // insert or update active chat
        NSString* query = @"INSERT INTO activechats (buddy_name, account_id, lastMessageTime) VALUES(?, ?, current_timestamp) ON CONFLICT(buddy_name, account_id) DO UPDATE SET lastMessageTime=current_timestamp;";
        [self.db executeNonQuery:query andArguments:@[buddyname, accountNo]];
    }];
    return;
}


-(BOOL) isActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(buddy_name) FROM activechats WHERE account_id=? AND buddy_name=?;";
        NSNumber* count = (NSNumber*)[self.db executeScalar:query andArguments:@[accountNo, buddyname]];
        if(count != nil)
        {
            NSInteger val = [((NSNumber*)count) integerValue];
            return (BOOL)(val > 0);
        }
        else
            return NO;
    }];
}

-(BOOL) updateActiveBuddy:(NSString*) buddyname setTime:(NSString*) timestamp forAccount:(NSNumber*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"SELECT lastMessageTime FROM activechats WHERE account_id=? AND buddy_name=?;";
        NSObject* result = [self.db executeScalar:query andArguments:@[accountNo, buddyname]];
        NSString* lastTime = (NSString *) result;

        NSDate* lastDate = [dbFormatter dateFromString:lastTime];
        NSDate* newDate = [dbFormatter dateFromString:timestamp];

        if(lastDate.timeIntervalSince1970 < newDate.timeIntervalSince1970)
        {
            NSString* query = @"UPDATE activechats SET lastMessageTime=? WHERE account_id=? AND buddy_name=?;";
            BOOL success = [self.db executeNonQuery:query andArguments:@[timestamp, accountNo, buddyname]];
            return success;
        }
        else
            return NO;
    }];
}

#pragma mark chat properties

-(NSNumber*) countUserUnreadMessages:(NSString*) buddy forAccount:(NSNumber*) accountNo
{
    if(!buddy || accountNo == nil)
        return @0;
    return [self.db idReadTransaction:^{
        // count # messages from a specific user in messages table
        return [self.db executeScalar:@"SELECT COALESCE(COUNT(message_history_id),0) FROM message_history AS h WHERE h.message_history_id > (SELECT COALESCE(latest_read_message_history_id, 0) FROM buddylist WHERE account_id=? AND buddy_name=?) AND h.unread=1 AND h.account_id=? AND h.buddy_name=? AND h.inbound=1;" andArguments:@[accountNo, buddy, accountNo, buddy]];
    }];
}

-(void) invalidateAllAccountStates
{
#ifndef IS_ALPHA
    @try {
#endif
        DDLogWarn(@"Invalidating state of all accounts...");
        [self.db voidWriteTransaction:^{
            for(NSDictionary* entry in [self.db executeReader:@"SELECT account_id FROM account;"])
                [self persistState:[xmpp invalidateState:[self readStateForAccount:entry[@"account_id"]]] forAccount:entry[@"account_id"]];
        }];
#ifndef IS_ALPHA
    } @catch (NSException* exception) {
        DDLogError(@"caught invalidate state exception: %@", exception);
    }
#endif
}

-(NSString*) lastUsedPushServerForAccount:(NSNumber*) accountNo
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT registeredPushServer FROM account WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(void) updateUsedPushServer:(NSString*) pushServer forAccount:(NSNumber*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeScalarReader:@"UPDATE account SET registeredPushServer=? WHERE account_id=?;" andArguments:@[pushServer, accountNo]];
    }];
}

-(void) deleteDelayedMessageStanzasForAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM delayed_message_stanzas WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(void) addDelayedMessageStanza:(MLXMLNode*) stanza forArchiveJid:(NSString*) archiveJid andAccountNo:(NSNumber*) accountNo
{
    if(accountNo == nil || !archiveJid || !stanza)
        return;
    NSError* error;
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:stanza requiringSecureCoding:YES error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"INSERT INTO delayed_message_stanzas (account_id, archive_jid, stanza) VALUES(?, ?, ?);" andArguments:@[accountNo, archiveJid, data]];
    }];
}

-(MLXMLNode* _Nullable) getNextDelayedMessageStanzaForArchiveJid:(NSString*) archiveJid andAccountNo:(NSNumber*) accountNo
{
    if(accountNo == nil|| !archiveJid)
        return nil;
    NSData* data = (NSData*)[self.db idWriteTransaction:^{
        NSArray* entries = [self.db executeReader:@"SELECT id, stanza FROM delayed_message_stanzas WHERE account_id=? AND archive_jid=? ORDER BY id ASC LIMIT 1;" andArguments:@[accountNo, archiveJid]];
        if(![entries count])
            return (NSData*)nil;
        [self.db executeNonQuery:@"DELETE FROM delayed_message_stanzas WHERE id=?;" andArguments:@[entries[0][@"id"]]];
        return (NSData*)entries[0][@"stanza"];
    }];
    if(data)
    {
        NSError* error;
        MLXMLNode* stanza = (MLXMLNode*)[NSKeyedUnarchiver unarchivedObjectOfClasses:[[NSSet alloc] initWithArray:@[
            [NSData class],
            [NSMutableData class],
            [NSMutableDictionary class],
            [NSDictionary class],
            [NSMutableSet class],
            [NSSet class],
            [NSMutableArray class],
            [NSArray class],
            [NSNumber class],
            [NSString class],
            [NSDate class],
            [MLXMLNode class],
            [XMPPIQ class],
            [XMPPPresence class],
            [XMPPMessage class],
            [XMPPDataForm class],
        ]] fromData:data error:&error];
        if(error)
        {
#ifdef IS_ALPHA
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
#else
            DDLogError(@"Error: %@", error);
            return nil;
#endif
        }
        return stanza;
    }
    return nil;
}

-(void) addShareSheetPayload:(NSDictionary*) payload
{
    //make sure we don't insert empty data
    if(payload[@"type"] == nil || payload[@"data"] == nil)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"INSERT INTO sharesheet_outbox (account_id, recipient, type, data) VALUES(?, ?, ?, ?);" andArguments:@[
            payload[@"account_id"],
            payload[@"recipient"],
            payload[@"type"],
            [HelperTools serializeObject:payload[@"data"]],
        ]];
    }];
}

-(NSArray*) getShareSheetPayload
{
    return [self.db idWriteTransaction:^{
        NSArray* payloadList = [self.db executeReader:@"SELECT * FROM sharesheet_outbox ORDER BY id ASC;"];
        NSMutableArray* retval = [NSMutableArray new];
        for(NSDictionary* entry_ in payloadList)
        {
            NSMutableDictionary* entry = [[NSMutableDictionary alloc] initWithDictionary:entry_];
            if(entry[@"data"])
                entry[@"data"] = [HelperTools unserializeData:entry[@"data"]];
            [retval addObject:entry];
        }
        return (NSArray*)retval;
    }];
}

-(void) deleteShareSheetPayloadWithId:(NSNumber*) payloadId
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM sharesheet_outbox WHERE id=?;" andArguments:@[payloadId]];
    }];
}

#pragma mark mute and block

-(void) muteJid:(MLContact*) contact
{
    if(!contact)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET muted=1 WHERE account_id=? AND buddy_name=?;" andArguments:@[contact.accountId, contact.contactJid]];
    }];
}

-(void) unMuteJid:(MLContact*) contact
{
    if(!contact)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET muted=0 WHERE account_id=? AND buddy_name=?;" andArguments:@[contact.accountId, contact.contactJid]];
    }];
}

-(BOOL) isMutedJid:(NSString*) jid onAccount:(NSString*) accountNo
{
    if(!jid || !accountNo)
    {
        unreachable();
        return NO;
    }
    return [self.db boolReadTransaction:^{
        NSNumber* count = (NSNumber*)[self.db executeScalar:@"SELECT COUNT(buddy_name) FROM buddylist WHERE account_id=? AND buddy_name=? AND muted=1;" andArguments: @[accountNo, jid]];
        return count.boolValue;
    }];
}

-(void) setMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSString*) accountNo
{
    if(!jid || !accountNo)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET mentionOnly=1 WHERE account_id=? AND buddy_name=? AND muc=1;" andArguments:@[accountNo, jid]];
    }];
}

-(void) setMucAlertOnAll:(NSString*) jid onAccount:(NSString*) accountNo
{
    if(!jid || !accountNo)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET mentionOnly=0 WHERE account_id=? AND buddy_name=? AND muc=1;" andArguments:@[accountNo, jid]];
    }];
}

-(BOOL) isMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSString*) accountNo
{
    if(!jid || !accountNo)
    {
        unreachable();
        return NO;
    }
    return [self.db boolReadTransaction:^{
        NSNumber* count = (NSNumber*)[self.db executeScalar:@"SELECT COUNT(buddy_name) FROM buddylist WHERE account_id=? AND buddy_name=? AND mentionOnly=1 AND muc=1;" andArguments: @[accountNo, jid]];
        return count.boolValue;
    }];
}

-(void) blockJid:(NSString*) jid withAccountNo:(NSNumber*) accountNo
{
    if(!jid || accountNo == nil)
        return;
    NSDictionary<NSString*, NSString*>* parsedJid = [HelperTools splitJid:jid];
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"INSERT OR IGNORE INTO blocklistCache(account_id, node, host, resource) VALUES(?, ?, ?, ?)" andArguments:@[accountNo,
                parsedJid[@"node"] ? parsedJid[@"node"] : [NSNull null],
                parsedJid[@"host"] ? parsedJid[@"host"] : [NSNull null],
                parsedJid[@"resource"] ? parsedJid[@"resource"] : [NSNull null],
        ]];
    }];
}

-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids forAccountNo:(NSNumber*) accountNo
{
    [self.db voidWriteTransaction:^{
        // remove blocked state for all buddies of account
        [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=?;" andArguments:@[accountNo]];
        // set blocking
        for(NSString* blockedJid in blockedJids)
            [self blockJid:blockedJid withAccountNo:accountNo];
    }];
}

-(void) unBlockJid:(NSString*) jid withAccountNo:(NSNumber*) accountNo
{
    NSDictionary<NSString*, NSString*>* parsedJid = [HelperTools splitJid:jid];
    [self.db voidWriteTransaction:^{
        if(parsedJid[@"node"] && parsedJid[@"host"] && parsedJid[@"resource"])
        {
            [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource=?" andArguments:@[accountNo, parsedJid[@"node"], parsedJid[@"host"], parsedJid[@"resource"]]];    }
        else if(parsedJid[@"node"] && parsedJid[@"host"])
        {
            [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource IS NULL" andArguments:@[accountNo, parsedJid[@"node"], parsedJid[@"host"]]];
        }
        else if(parsedJid[@"host"] && parsedJid[@"resource"])
        {
            [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource=?" andArguments:@[accountNo, parsedJid[@"host"], parsedJid[@"resource"]]];
        }
        else if(parsedJid[@"host"])
        {
            [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource IS NULL" andArguments:@[accountNo, parsedJid[@"host"]]];
        }
    }];
}

-(u_int8_t) isBlockedJid:(MLContact*) contact
{
    if(!contact)
        return NO;

    return (u_int8_t)[[self.db idReadTransaction:^{
        NSDictionary<NSString*, NSString*>* parsedJid = [HelperTools splitJid:contact.contactJid];
        NSNumber* blocked;
        u_int8_t ruleId = kBlockingNoMatch;
        if(parsedJid[@"node"] && parsedJid[@"host"] && parsedJid[@"resource"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource=?;" andArguments:@[contact.accountId, parsedJid[@"node"], parsedJid[@"host"], parsedJid[@"resource"]]];
            ruleId = kBlockingMatchedNodeHostResource;
        }
        else if(parsedJid[@"node"] && parsedJid[@"host"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource IS NULL;" andArguments:@[contact.accountId, parsedJid[@"node"], parsedJid[@"host"]]];
            ruleId = kBlockingMatchedNodeHost;
        }
        else if(parsedJid[@"host"] && parsedJid[@"resource"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource=?;" andArguments:@[contact.accountId, parsedJid[@"host"], parsedJid[@"resource"]]];
            ruleId = kBlockingMatchedHostResource;
        }
        else if(parsedJid[@"host"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource IS NULL;" andArguments:@[contact.accountId, parsedJid[@"host"]]];
            ruleId = kBlockingMatchedHost;
        }
        else
        {
            return [NSNumber numberWithInt:kBlockingNoMatch];
        }
        if(blocked.intValue == 1)
            return [NSNumber numberWithInt:ruleId];
        else
            return [NSNumber numberWithInt:kBlockingNoMatch];
    }] intValue];
}

-(NSArray<NSDictionary<NSString*, NSString*>*>*) blockedJidsForAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        NSArray* blockedJidsFromDB = [self.db executeReader:@"SELECT * FROM blocklistCache WHERE account_id=?" andArguments:@[accountNo]];
        NSMutableArray* blockedJids = [NSMutableArray new];
        for(NSDictionary* blockedJid in blockedJidsFromDB)
        {
            NSString* fullJid = @"";
            if(blockedJid[@"node"])
                fullJid = [NSString stringWithFormat:@"%@@", blockedJid[@"node"]];
            if(blockedJid[@"host"])
                fullJid = [NSString stringWithFormat:@"%@%@", fullJid, blockedJid[@"host"]];
            if(blockedJid[@"resource"])
                fullJid = [NSString stringWithFormat:@"%@/%@", fullJid, blockedJid[@"resource"]];
            NSMutableDictionary* blockedMutableJid = [[NSMutableDictionary alloc] initWithDictionary:blockedJid];
            [blockedMutableJid setValue:fullJid forKey:@"fullBlockedJid"];
            [blockedJids addObject:blockedMutableJid];
        }
        return blockedJids;
    }];
}

-(BOOL) isPinnedChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid
{
    if(!accountNo || !buddyJid)
        return NO;
    return [self.db boolReadTransaction:^{
        NSNumber* pinnedNum = [self.db executeScalar:@"SELECT pinned FROM activechats WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddyJid]];
        if(pinnedNum != nil)
            return [pinnedNum boolValue];
        else
            return NO;
    }];
}

-(void) pinChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid
{
    if(!accountNo || !buddyJid)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE activechats SET pinned=1 WHERE account_id=? AND buddy_name=?" andArguments:@[accountNo, buddyJid]];
    }];
}
-(void) unPinChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid
{
    if(!accountNo || !buddyJid)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE activechats SET pinned=0 WHERE account_id=? AND buddy_name=?" andArguments:@[accountNo, buddyJid]];
    }];
}

#pragma mark - Filetransfers

-(NSArray*) getAllMessagesForFiletransferUrl:(NSString*) url
{
    return [self.db idReadTransaction:^{
        return [self messagesForHistoryIDs:[self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE message=?;" andArguments:@[url]]];
    }];
}

-(void) upgradeImageMessagesToFiletransferMessages
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE message_history SET messageType=? WHERE messageType=?;" andArguments:@[kMessageTypeFiletransfer, @"Image"]];
    }];
}

// (deprecated) should only be used to upgrade to new table format
-(NSArray<NSDictionary*>*) getAllCachedImages
{
    return [self.db idReadTransaction:^{
        NSNumber* tableFound = [self.db executeScalar:@"SELECT count(*) FROM sqlite_master WHERE type='table' AND name='imageCache';"];
        if(tableFound.boolValue == NO)
        {
            return [[NSArray<NSDictionary*> alloc] init];
        }
        return (NSArray<NSDictionary*>*)[self.db executeReader:@"SELECT DISTINCT * FROM imageCache;"];
    }];
}

// (deprecated) should only be used to upgrade to new table format
-(void) removeImageCacheTables
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DROP TABLE IF EXISTS imageCache;"];
    }];
}

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSString*) accountNo
{
    if(!accountNo ||! contact)
        return nil;
    
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=? AND buddy_name=? GROUP BY message ORDER BY message_history_id ASC;";
        NSArray* params = @[kMessageTypeFiletransfer, accountNo, contact];
        
        NSMutableArray* retval = [NSMutableArray new];
        for(MLMessage* msg in [self messagesForHistoryIDs:[self.db executeScalarReader:query andArguments:params]])
            [retval addObject:[MLFiletransfer getFileInfoForMessage:msg]];
        return retval;
    }];
}

#pragma mark - last interaction

-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountNo:(NSNumber* _Nonnull) accountNo
{
    MLAssert(jid != nil, @"jid should not be null");
    MLAssert(accountNo != nil, @"accountNo should not be null");
    return [self.db idReadTransaction:^{
        //this will only return resources supporting "urn:xmpp:idle:1" and being "online" (e.g. lastInteraction = 0)
        NSNumber* online = [self.db executeScalar:@"SELECT lastInteraction FROM buddy_resources AS R INNER JOIN buddylist AS B ON R.buddy_id=B.buddy_id INNER JOIN ver_info AS V ON R.ver=V.ver WHERE B.account_id=? AND B.buddy_name=? AND V.cap='urn:xmpp:idle:1' AND R.lastInteraction=0 ORDER BY lastInteraction ASC LIMIT 1;" andArguments:@[accountNo, jid]];
        
        //this will only return resources supporting "urn:xmpp:idle:1" and being "idle since <...>" (e.g. lastInteraction > 0)
        NSNumber* idle = [self.db executeScalar:@"SELECT lastInteraction FROM buddy_resources AS R INNER JOIN buddylist AS B ON R.buddy_id=B.buddy_id INNER JOIN ver_info AS V ON R.ver=V.ver WHERE B.account_id=? AND B.buddy_name=? AND cap='urn:xmpp:idle:1' AND R.lastInteraction!=0 ORDER BY lastInteraction DESC LIMIT 1;" andArguments:@[accountNo, jid]];
        
        //at least one online resource means the buddy is online
        //if no online resource can be found use the newest timestamp as "idle since <...>" timestamp
        DDLogDebug(@"LastInteraction of %@ online=%@, idle=%@", jid, online, idle);
        if(online != nil)
            return [[NSDate date] initWithTimeIntervalSince1970:0] ;
        if(idle == nil)
            return (NSDate*)nil;
        return [NSDate dateWithTimeIntervalSince1970:[idle integerValue]];
    }];
}

-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid andResource:(NSString* _Nonnull) resource forAccountNo:(NSNumber* _Nonnull) accountNo
{
    MLAssert(jid != nil, @"jid should not be null");
    MLAssert(accountNo != nil, @"accountNo should not be null");
    return [self.db idReadTransaction:^{
        //this will only return resources supporting "urn:xmpp:idle:1"
        NSNumber* lastInteraction = [self.db executeScalar:@"SELECT lastInteraction FROM buddy_resources AS R INNER JOIN buddylist AS B ON R.buddy_id=B.buddy_id WHERE B.account_id=? AND B.buddy_name=? AND R.resource=? AND EXISTS(SELECT * FROM ver_info AS V WHERE V.ver=R.ver AND V.cap='urn:xmpp:idle:1') LIMIT 1;" andArguments:@[accountNo, jid, resource]];
        DDLogDebug(@"LastInteraction of %@/%@ lastInteraction=%@", jid, resource, lastInteraction);
        if(lastInteraction == nil)
            return (NSDate*)nil;
        return [NSDate dateWithTimeIntervalSince1970:[lastInteraction integerValue]];
    }];
}

-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andResource:(NSString*) resource onAccountNo:(NSNumber* _Nonnull) accountNo
{
    MLAssert(jid != nil, @"jid should not be null");
    MLAssert(accountNo != nil, @"accountNo should not be null");
    
    NSNumber* timestamp = @0;       //default value for "online" or "unknown" (depending on caps)
    if(lastInteractionTime != nil)
        timestamp = [HelperTools dateToNSNumberSeconds:lastInteractionTime];
    
    DDLogDebug(@"Setting lastInteraction timestamp of %@/%@ to %@...", jid, resource, timestamp);
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddy_resources AS R SET lastInteraction=? WHERE EXISTS(SELECT * FROM buddylist AS B WHERE B.buddy_id=R.buddy_id AND B.account_id=? AND B.buddy_name=?) AND R.resource=?;" andArguments:@[timestamp, accountNo, jid, resource]];
    }];
}

#pragma mark - encryption

-(BOOL) shouldEncryptForJid:(NSString*) jid andAccountNo:(NSNumber*) accountNo
{
    if(!jid || accountNo == nil)
        return NO;
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT encrypt from buddylist where account_id=? and buddy_name=?";
        NSArray* params = @[accountNo, jid];
        NSNumber* status=(NSNumber*)[self.db executeScalar:query andArguments:params];
        return [status boolValue];
    }];
}


-(void) encryptForJid:(NSString*) jid andAccountNo:(NSNumber*) accountNo
{
    if(!jid || accountNo == nil)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET encrypt=1 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, jid]];
    }];
    return;
}

-(void) disableEncryptForJid:(NSString*) jid andAccountNo:(NSNumber*) accountNo
{
    if(!jid || accountNo == nil)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET encrypt=0 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, jid]];
    }];
    return;
}

-(NSNumber*) addIdleTimerWithTimeout:(NSNumber*) timeout andHandler:(MLHandler*) handler onAccountNo:(NSNumber*) accountNo
{
    return [self.db idWriteTransaction:^{
        [self.db executeNonQuery:@"INSERT INTO idle_timers (timeout, account_id, handler) VALUES (?, ?, ?);" andArguments:@[timeout, accountNo, [HelperTools serializeObject:handler]]];
        return [self.db lastInsertId];
    }];
}

-(void) delIdleTimerWithId:(NSNumber* _Nullable) timerId
{
    if(timerId == nil)
        return;
    return [self.db voidWriteTransaction:^{
        NSArray* timers = [self.db executeReader:@"SELECT * FROM idle_timers WHERE id=?;" andArguments:@[timerId]];
        if(timers == nil || [timers count] != 1)
            return;         //we could not find this timerId, ignore this call
        NSDictionary* timer = timers[0];
        //call invalidation of this timer's handler (will do nothing if this handler does not have any invalidation method)
        //and delete the timer afterwards
        //thanks to foreign keys deleting an account will automatically delete it's idle timers, too.
        //therefore the following assertion only handles deactivated accounts
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:timer[@"account_id"]];
        MLAssert(account != nil, @"Deleting an idle timer should not be done when an account is disabled!", (@{
            @"timerId": timerId,
            @"accountNo": nilWrapper(timer[@"account_id"])
        }));
        $invalidate([HelperTools unserializeData:timer[@"handler"]], $ID(account));
        [self.db executeNonQuery:@"DELETE FROM idle_timers WHERE id=?;" andArguments:@[timerId]];
    }];
}

//this method will only be called from our timer background thread also handling iq timeouts
-(void) decrementIdleTimersForAccount:(xmpp*) account
{
    return [self.db voidWriteTransaction:^{
        for(NSDictionary* timer in [self.db executeReader:@"SELECT * FROM idle_timers WHERE account_id=?;" andArguments:@[account.accountNo]])
        {
            DDLogVerbose(@"Decrementing idle timer %@(%@): %@", timer[@"id"], timer[@"timeout"], [HelperTools unserializeData:timer[@"handler"]]);
            if([timer[@"timeout"] unsignedIntegerValue] == 0)
            {
                //this timer expired --> call it's handler and delete the timer afterwards
                $call([HelperTools unserializeData:timer[@"handler"]], $ID(account));
                [self.db executeNonQuery:@"DELETE FROM idle_timers WHERE id=?;" andArguments:@[timer[@"id"]]];
                continue;
            }
            //just decrease timeout of this timer (it will expire when reaching zero)
            [self.db executeNonQuery:@"UPDATE idle_timers SET timeout=timeout-1 WHERE id=?;" andArguments:@[timer[@"id"]]];
        }
    }];
}

#pragma mark History Message Search (search keyword in message, buddy_name, messageType)

-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword accountNo:(NSNumber*) accountNo
{
    if(!keyword || accountNo == nil)
        return nil;
    return [self.db idReadTransaction:^{
        NSString *likeString = [NSString stringWithFormat:@"%%%@%%", keyword];
        NSString* query = @"SELECT message_history_id FROM message_history WHERE account_id = ? AND (message like ? OR buddy_name LIKE ? OR messageType LIKE ?) ORDER BY timestamp ASC;";
        NSArray* params = @[accountNo, likeString, likeString, likeString];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}

-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword betweenContact:(MLContact* _Nonnull) contact
{
    if(!keyword)
        return nil;
    return [self.db idReadTransaction:^{
        NSString* likeString = [NSString stringWithFormat:@"%%%@%%", keyword];
        NSString* query = @"SELECT message_history_id FROM message_history WHERE account_id=? AND (message LIKE ? OR messageType LIKE ?) AND buddy_name=? ORDER BY timestamp ASC;";
        NSArray* params = @[contact.accountId, likeString, contact.contactJid];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}

@end
