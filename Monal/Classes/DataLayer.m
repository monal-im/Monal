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
NSString *const kPlainActivated = @"plain_activated";

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
    self = [super init];
    
    //checking db version and upgrading if necessary
    DDLogInfo(@"Database version check");

    //set wal mode (this setting is permanent): https://www.sqlite.org/pragma.html#pragma_journal_mode
    //this is a special case because it can not be done while in a transaction!!!
    [self.db enableWAL];
    [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];
    
    //needed for sqlite >= 3.26.0 (see https://sqlite.org/lang_altertable.html point 2)
    [self.db executeNonQuery:@"PRAGMA legacy_alter_table=on;"];
    [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];

    //do db upgrades and vacuum db afterwards
    if([DataLayerMigrations migrateDB:self.db withDataLayer:self])
        [self.db vacuum];

    //turn foreign keys on again
    //needed for sqlite >= 3.26.0 (see https://sqlite.org/lang_altertable.html point 2)
    [self.db executeNonQuery:@"PRAGMA legacy_alter_table=off;"];
    [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
    
    DDLogInfo(@"Database version check completed");
    
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
    NSString* temporaryFilename = [NSString stringWithFormat:@"sworim_%@.db", [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString* temporaryFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:temporaryFilename];
    
    //checkpoint db before copying db file
    [self.db checkpointWal];
    
    //this transaction creates a new wal log and makes sure the file copy is atomic/consistent
    BOOL success = [self.db boolWriteTransaction:^{
        //copy db file to temp file
        NSError* error;
        [fileManager copyItemAtPath:dbPath toPath:temporaryFilePath error:&error];
        if(error)
        {
            DDLogError(@"Could not copy database to export location!");
            return NO;
        }
        return YES;
    }];
    
    if(success)
        return temporaryFilePath;
    return nil;
}

-(void) createTransaction:(monal_void_block_t) block
{
    [self.db voidWriteTransaction:block];
}

-(void) vacuum
{
    return [self.db vacuum];
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

-(BOOL) isAccountEnabled:(NSNumber*) accountID
{
    return [self.db boolReadTransaction:^{
        return [[self.db executeScalar:@"SELECT enabled FROM account WHERE account_id=?;" andArguments:@[accountID]] boolValue];
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

-(NSMutableDictionary*) detailsForAccount:(NSNumber*) accountID
{
    if(accountID == nil)
        return nil;
    return [self.db idReadTransaction:^{
        NSArray* result = [self.db executeReader:@"SELECT * FROM account WHERE account_id=?;" andArguments:@[accountID]];
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
        NSString* query = @"UPDATE account SET server=?, other_port=?, username=?, resource=?, domain=?, enabled=?, directTLS=?, rosterName=?, statusMessage=?, needs_password_migration=? WHERE account_id=?;";
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
            [dictionary objectForKey:kAccountID],
        ];
        BOOL retval = [self.db executeNonQuery:query andArguments:params];
        [self addSelfChatForAccount:dictionary[kAccountID]];
        return retval;
    }];
}

-(NSNumber*) addAccountWithDictionary:(NSDictionary*) dictionary
{
    return [self.db idWriteTransaction:^{
        NSString* query = @"INSERT INTO account (server, other_port, resource, domain, enabled, directTLS, username, rosterName, statusMessage, plain_activated) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
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
            [dictionary objectForKey:@"statusMessage"] ? ((NSString*)[dictionary objectForKey:@"statusMessage"]) : @"",
            [dictionary objectForKey:kPlainActivated] != nil ? [dictionary objectForKey:kPlainActivated] : [NSNumber numberWithBool:NO],
        ];
        BOOL result = [self.db executeNonQuery:query andArguments:params];
        // return the accountID
        if(result == YES) {
            NSNumber* accountID = [self.db lastInsertId];
            DDLogInfo(@"Added account %@ to account table with accountID %@", [dictionary objectForKey:kUsername], accountID);
            [self addSelfChatForAccount:accountID];
            return accountID;
        } else {
            return (NSNumber*)nil;
        }
    }];
}

-(BOOL) removeAccount:(NSNumber*) accountID
{
    // remove all other traces of the account_id in one transaction
    return [self.db boolWriteTransaction:^{
        // enable secure delete
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];

        // delete transfered files from local device
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=?;" andArguments:@[kMessageTypeFiletransfer, accountID]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];

        // delete account and all entries with the same account_id (CASCADE DELETE)
        BOOL accountDeleted = [self.db executeNonQuery:@"DELETE FROM account WHERE account_id=?;" andArguments:@[accountID]];

        // disable secure delete again
        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
        return accountDeleted;
    }];
}

-(BOOL) disableAccountForPasswordMigration:(NSNumber*) accountID
{
    return [self.db boolWriteTransaction:^{
        [self persistState:[xmpp invalidateState:[self readStateForAccount:accountID]] forAccount:accountID];
        return [self.db executeNonQuery:@"UPDATE account SET enabled=0, needs_password_migration=1, resource=? WHERE account_id=?;" andArguments:@[[HelperTools encodeRandomResource], accountID]];
    }];
}

-(NSArray*) accountListNeedingPasswordMigration
{
    return [self.db idReadTransaction:^{
        return [self.db executeReader:@"SELECT * FROM account WHERE NOT enabled AND needs_password_migration ORDER BY account_id ASC;"];
    }];
}

-(BOOL) isPlainActivatedForAccount:(NSNumber*) accountID
{
    return [self.db boolReadTransaction:^{
        NSNumber* plainActivated = (NSNumber*)[self.db executeScalar:@"SELECT plain_activated FROM account WHERE account_id=?;" andArguments:@[accountID]];
        if(plainActivated == nil)
            return NO;
        else
            return [plainActivated boolValue];
    }];
}

-(BOOL) deactivatePlainForAccount:(NSNumber*) accountID
{
    return [self.db boolReadTransaction:^{
        return [self.db executeNonQuery:@"UPDATE account SET plain_activated=0 WHERE account_id=?;" andArguments:@[accountID]];
    }];
}

-(NSMutableDictionary*) readStateForAccount:(NSNumber*) accountID
{
    if(accountID == nil)
        return nil;
    NSString* query = @"SELECT state from account where account_id=?";
    NSArray* params = @[accountID];
    NSData* data = (NSData*)[self.db idReadTransaction:^{
        return [self.db executeScalar:query andArguments:params];
    }];
    if(data)
        return [HelperTools unserializeData:data];
    return nil;
}

-(void) persistState:(NSDictionary*) state forAccount:(NSNumber*) accountID
{
    if(accountID == nil || !state)
        return;
    NSData* data = [HelperTools serializeObject:state];
    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE account SET state=? WHERE account_id=?;";
        NSArray* params = @[data, accountID];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

#pragma mark contact Commands

-(BOOL) addSelfChatForAccount:(NSNumber*) accountID
{
    BOOL encrypt = NO;
#ifndef DISABLE_OMEMO
        encrypt = [[HelperTools defaultsDB] boolForKey:@"OMEMODefaultOn"];
#endif// DISABLE_OMEMO
    NSDictionary* accountDetails = [self detailsForAccount:accountID];
    return [self.db executeNonQuery:@"INSERT INTO buddylist ('account_id', 'buddy_name', 'full_name', 'nick_name', 'muc', 'muc_nick', 'encrypt') VALUES(?, ?, ?, ?, ?, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET subscription='both';" andArguments:@[accountID, [NSString stringWithFormat:@"%@@%@", accountDetails[kUsername], accountDetails[kDomain]], @"", @"", @0, @"", @(encrypt)]];
}

-(BOOL) addContact:(NSString*) contact forAccount:(NSNumber*) accountID nickname:(NSString*) nickName
{
    if(accountID == nil || !contact)
        return NO;
    
    return [self.db boolWriteTransaction:^{
        //data length check
        NSString* toPass;
        NSString* cleanNickName;
        if(!nickName)
        {
            //use already existing nickname, if none was given
            cleanNickName = [self.db executeScalar:@"SELECT nick_name FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, contact]];
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
        
        return [self.db executeNonQuery:@"INSERT INTO buddylist ('account_id', 'buddy_name', 'full_name', 'nick_name', 'muc', 'muc_nick', 'encrypt') VALUES(?, ?, ?, ?, ?, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET nick_name=?;" andArguments:@[accountID, contact, @"", toPass, @0, @"", @(encrypt), toPass]];
    }];
}

-(void) removeBuddy:(NSString*) buddy forAccount:(NSNumber*) accountID
{
    [self.db voidWriteTransaction:^{
        //clean up logs...
        [self clearMessagesWithBuddy:buddy onAccount:accountID];
        //...and delete contact
        [self.db executeNonQuery:@"DELETE FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, buddy]];
    }];
}

-(BOOL) clearBuddies:(NSString*) accountID
{
    return [self.db boolWriteTransaction:^{
        return [self.db executeNonQuery:@"DELETE FROM buddylist WHERE account_id=?;" andArguments:@[accountID]];
    }];
}

#pragma mark Buddy Property commands

-(BOOL) resetContactsForAccount:(NSNumber*) accountID
{
    if(accountID == nil)
        return NO;
    return [self.db boolWriteTransaction:^{
        NSString* query2 = @"DELETE FROM buddy_resources WHERE buddy_id IN (SELECT buddy_id FROM buddylist WHERE account_id=?);";
        NSArray* params = @[accountID];
        [self.db executeNonQuery:query2 andArguments:params];
        NSString* query = @"UPDATE buddylist SET state='offline', status='' WHERE account_id=?;";
        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(NSDictionary* _Nullable) contactDictionaryForUsername:(NSString*) username forAccount:(NSNumber*) accountID
{
    if(!username || accountID == nil)
        return nil;

    return [self.db idReadTransaction:^{
        NSArray* results = [self.db executeReader:@"SELECT b.buddy_name, state, status, b.full_name, b.nick_name, Muc, muc_subject, muc_type, muc_nick, mentionOnly, b.account_id, 0 AS 'count', subscription, ask, IFNULL(pinned, 0) AS 'pinned', blocked, encrypt, muted, \
            CASE \
                WHEN a.buddy_name IS NOT NULL THEN 1 \
                ELSE 0 \
            END AS 'isActiveChat' \
            FROM buddylist AS b LEFT JOIN activechats AS a \
            ON a.buddy_name = b.buddy_name AND a.account_id = b.account_id \
            WHERE b.buddy_name=? AND b.account_id=?;" andArguments:@[username, accountID]];
        
        MLAssert(results != nil && [results count] <= 1, @"Unexpected contact count", (@{
            @"username": username,
            @"accountID": accountID,
            @"count": [NSNumber numberWithInteger:[results count]],
            @"results": results ? results : @"(null)"
        }));

        if([results count] == 0)
            return (NSMutableDictionary*)nil;
        else
        {
            NSMutableDictionary* contact = [results[0] mutableCopy];
            //correctly extract NSDate object or 1970, if last interaction is zero
            contact[@"lastInteraction"] = nilWrapper([self lastInteractionOfJid:username forAccountID:accountID]);
            //if we have this muc in our favorites table, this muc is "subscribed"
            if([self.db executeScalar:@"SELECT room FROM muc_favorites WHERE room=? AND account_id=?;" andArguments:@[username, accountID]] != nil)
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
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountID:dic[@"account_id"]]];
        return toReturn;
    }];
}

-(NSArray<MLContact*>*) contactList
{
    return [self contactListWithJid:@""];
}

-(NSArray<MLContact*>*) possibleGroupMembersForAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        //list all contacts without groupchats and self contact
        NSString* query = @"SELECT B.buddy_name, B.account_id, IFNULL(IFNULL(NULLIF(B.nick_name, ''), NULLIF(B.full_name, '')), B.buddy_name) FROM buddylist as B INNER JOIN account AS A ON A.account_id=B.account_id WHERE B.account_id=? AND B.muc=0 AND B.buddy_name != (A.username || '@' || A.domain)";
        NSMutableArray* toReturn = [NSMutableArray new];
        for(NSDictionary* dic in [self.db executeReader:query andArguments:@[accountID]])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountID:dic[@"account_id"]]];
        return toReturn;
    }];
}

-(NSArray<MLContact*>*) contactListWithJid:(NSString*) jid
{
    return [self.db idReadTransaction:^{
        //list all contacts and group chats
        NSString* query = @"SELECT B.buddy_name, B.account_id, IFNULL(IFNULL(NULLIF(B.nick_name, ''), NULLIF(B.full_name, '')), B.buddy_name) AS 'sortkey' FROM buddylist AS B INNER JOIN account AS A ON A.account_id=B.account_id WHERE A.enabled=1 AND (B.buddy_name=? OR ?='') ORDER BY sortkey COLLATE NOCASE ASC;";
        NSMutableArray* toReturn = [NSMutableArray new];
        for(NSDictionary* dic in [self.db executeReader:query andArguments:@[jid, jid]])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountID:dic[@"account_id"]]];
        return toReturn;
    }];
}

#pragma mark entity capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user onAccountID:(NSNumber*) accountID
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(*) FROM buddylist AS a INNER JOIN buddy_resources AS b ON a.buddy_id=b.buddy_id INNER JOIN ver_info AS c ON b.ver=c.ver WHERE a.buddy_name=? AND a.account_id=? AND c.cap=? AND c.account_id=?;";
        NSArray *params = @[user, accountID, cap, accountID];
        NSNumber* count = (NSNumber*) [self.db executeScalar:query andArguments:params];
        return (BOOL)([count integerValue]>0);
    }];
}

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andResource:(NSString*) resource onAccountID:(NSNumber*) accountID
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(*) FROM buddylist AS a INNER JOIN buddy_resources AS b ON a.buddy_id=b.buddy_id INNER JOIN ver_info AS c ON b.ver=c.ver WHERE a.buddy_name=? AND b.resource=? AND a.account_id=? AND c.cap=? AND c.account_id=?;";
        NSNumber* count = (NSNumber*) [self.db executeScalar:query andArguments:@[user, resource, accountID, cap, accountID]];
        return (BOOL)([count integerValue]>0);
    }];
}

-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource onAccountID:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT ver FROM buddy_resources AS A INNER JOIN buddylist AS B ON a.buddy_id=b.buddy_id WHERE resource=? AND buddy_name=? AND account_id=? LIMIT 1;";
        NSArray * params = @[resource, user, accountID];
        NSString* ver = (NSString*) [self.db executeScalar:query andArguments:params];
        return ver;
    }];
}

-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource onAccountID:(NSNumber*) accountID
{
    NSNumber* timestamp = [HelperTools currentTimestampInSeconds];
    [self.db voidWriteTransaction:^{
        //set ver for user and resource
        NSString* query = @"UPDATE buddy_resources SET ver=? WHERE EXISTS(SELECT * FROM buddylist WHERE buddy_resources.buddy_id=buddylist.buddy_id AND resource=? AND buddy_name=? AND account_id=?)";
        NSArray * params = @[ver, resource, user, accountID];
        [self.db executeNonQuery:query andArguments:params];
        
        //update timestamp for this ver string to make it not timeout (old ver strings and features are removed from feature cache after 28 days)
        NSString* query2 = @"UPDATE ver_info SET timestamp=? WHERE ver=? AND account_id=?;";
        NSArray * params2 = @[timestamp, ver, accountID];
        [self.db executeNonQuery:query2 andArguments:params2];
    }];
}

-(NSSet*) getCapsforVer:(NSString*) ver onAccountID:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        NSSet* result = [NSSet setWithArray:[self.db executeScalarReader:@"SELECT cap FROM ver_info WHERE ver=? AND account_id=?;" andArguments:@[ver, accountID]]];
        
        DDLogVerbose(@"caps count: %lu", (unsigned long)[result count]);
        if([result count] == 0)
            return (NSSet*)nil;
        return result;
    }];
}

-(void) setCaps:(NSSet*) caps forVer:(NSString*) ver onAccountID:(NSNumber*) accountID
{
    NSNumber* timestamp = [HelperTools currentTimestampInSeconds];
    [self.db voidWriteTransaction:^{
        //remove old caps for this ver
        [self.db executeNonQuery:@"DELETE FROM ver_info WHERE ver=? AND account_id=?;" andArguments:@[ver, accountID]];
        
        //insert new caps
        for(NSString* feature in caps)
            [self.db executeNonQuery:@"INSERT INTO ver_info (ver, cap, account_id, timestamp) VALUES (?, ?, ?, ?);" andArguments:@[ver, feature, accountID, timestamp]];
                
        //cleanup old entries of *all* accounts
        [self.db executeNonQuery:@"DELETE FROM ver_info WHERE timestamp<?;" andArguments:@[[NSNumber numberWithInteger:[timestamp integerValue] - (86400 * 28)]]];      //cache timeout is 28 days
    }];
}

#pragma mark presence functions

-(void) setResourceOnline:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID
{
    if(!presenceObj.fromResource)
        return;
    [self.db voidWriteTransaction:^{
        //get buddyid for name and account
        NSString* query1 = @"select buddy_id from buddylist where account_id=? and buddy_name=?;";
        NSObject* buddyid = [self.db executeScalar:query1 andArguments:@[accountID, presenceObj.fromUser]];
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

-(MLContactSoftwareVersionInfo* _Nullable) getSoftwareVersionInfoForContact:(NSString*) contact resource:(NSString*) resource andAccount:(NSNumber*) accountID
{
    if(accountID == nil)
        return nil;
    NSArray<NSDictionary*>* versionInfoArr = [self.db idReadTransaction:^{
        NSArray<NSDictionary*>* resources = [self.db executeReader:@"SELECT platform_App_Name, platform_App_Version, platform_OS FROM buddy_resources WHERE buddy_id IN (SELECT buddy_id FROM buddylist WHERE account_id=? AND buddy_name=?) AND resource=?" andArguments:@[accountID, contact, resource]];
        return resources;
    }];
    if(versionInfoArr == nil || versionInfoArr.count == 0) {
        return nil;
    } else {
        NSDictionary* versionInfo = versionInfoArr.firstObject;
        NSDate* lastInteraction = [self lastInteractionOfJid:contact andResource:resource forAccountID:accountID];
        return [[MLContactSoftwareVersionInfo alloc] initWithJid:contact andRessource:resource andAppName:versionInfo[@"platform_App_Name"] andAppVersion:versionInfo[@"platform_App_Version"] andPlatformOS:versionInfo[@"platform_OS"] andLastInteraction:lastInteraction];
    }
}

-(void) setSoftwareVersionInfoForContact:(NSString*) contact
                                resource:(NSString*) resource
                              andAccount:(NSNumber*) account
                        withSoftwareInfo:(MLContactSoftwareVersionInfo*) newSoftwareInfo
{
    [self.db voidWriteTransaction:^{
        NSString* query = @"update buddy_resources set platform_App_Name=?, platform_App_Version=?, platform_OS=? where buddy_id in (select buddy_id from buddylist where account_id=? and buddy_name=?) and resource=?";
        NSArray* params = @[nilWrapper(newSoftwareInfo.appName), nilWrapper(newSoftwareInfo.appVersion), nilWrapper(newSoftwareInfo.platformOs), account, contact, resource];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

-(void) setOnlineBuddy:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID
{
    [self.db voidWriteTransaction:^{
        [self setResourceOnline:presenceObj forAccount:accountID];
        NSString* query = @"UPDATE buddylist SET state='' WHERE account_id=? AND buddy_name=? AND state='offline';";
        NSArray* params = @[accountID, presenceObj.fromUser];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

-(void) setOfflineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountID
{
    return [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM buddy_resources AS R WHERE resource=? AND EXISTS(SELECT * FROM buddylist AS B WHERE B.buddy_id=R.buddy_id AND B.account_id=? AND B.buddy_name=?);" andArguments:@[presenceObj.fromResource ? presenceObj.fromResource : @"", accountID, presenceObj.fromUser]];
        [self.db executeNonQuery:@"UPDATE buddylist AS B SET state='offline' WHERE account_id=? AND buddy_name=? AND NOT EXISTS(SELECT * FROM buddy_resources AS R WHERE B.buddy_id=R.buddy_id);" andArguments:@[accountID, presenceObj.fromUser]];
    }];
}

-(void) setBuddyState:(XMPPPresence*) presenceObj forAccount:(NSNumber*) accountID;
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
        [self.db executeNonQuery:query andArguments:@[toPass, accountID, presenceObj.fromUser]];
    }];
}

-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountID
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT state FROM buddylist WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[accountID, buddy];
        NSString* state = (NSString*)[self.db executeScalar:query andArguments:params];
        return state;
    }];
}

-(BOOL) hasContactRequestForContact:(MLContact*) contact
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(*) FROM subscriptionRequests WHERE account_id=? AND buddy_name=?";
        NSNumber* result = (NSNumber*)[self.db executeScalar:query andArguments:@[contact.accountID, contact.contactJid]];
        return (BOOL)(result.intValue == 1);
    }];
}

-(NSMutableArray*) allContactRequests
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT subscriptionRequests.account_id, subscriptionRequests.buddy_name FROM subscriptionRequests, account WHERE subscriptionRequests.account_id = account.account_id AND account.enabled;";
        NSMutableArray* toReturn = [NSMutableArray new];
        for(NSDictionary* dic in [self.db executeReader:query])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountID:dic[@"account_id"]]];
        return toReturn;
    }];
}

-(void) addContactRequest:(MLContact*) requestor;
{
    [self.db voidWriteTransaction:^{
        NSString* query2 = @"INSERT OR IGNORE INTO subscriptionRequests (buddy_name, account_id) VALUES (?,?)";
        [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountID]];
    }];
}

-(void) deleteContactRequest:(MLContact*) requestor
{
    [self.db voidWriteTransaction:^{
        NSString* query2 = @"delete from subscriptionRequests where buddy_name=? and account_id=? ";
        [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountID]];
    }];
}

-(void) setBuddyStatus:(XMPPPresence*) presenceObj forAccount:(NSString*) accountID
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
        [self.db executeNonQuery:query andArguments:@[toPass, accountID, presenceObj.fromUser]];
    }];
}

-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountID
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT status FROM buddylist WHERE account_id=? AND buddy_name=?;";
        NSString* iconname =  (NSString *)[self.db executeScalar:query andArguments:@[accountID, buddy]];
        return iconname;
    }];
}

-(NSString *) getRosterVersionForAccount:(NSString*) accountID
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT rosterVersion FROM account WHERE account_id=?;";
        NSArray* params = @[ accountID];
        NSString * version=(NSString*)[self.db executeScalar:query andArguments:params];
        return version;
    }];
}

-(void) setRosterVersion:(NSString*) version forAccount:(NSNumber*) accountID
{
    if(accountID == nil || !version)
        return;
    [self.db voidWriteTransaction:^{
        NSString* query = @"update account set rosterVersion=? where account_id=?";
        NSArray* params = @[version , accountID];
        [self.db executeNonQuery:query  andArguments:params];
    }];
}

-(NSDictionary*) getSubscriptionForContact:(NSString*) contact andAccount:(NSNumber*) accountID
{
    if(!contact || accountID == nil)
        return nil;
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT subscription, ask from buddylist where buddy_name=? and account_id=?";
        NSArray* params = @[contact, accountID];
        NSArray* version = [self.db executeReader:query andArguments:params];
        return version.firstObject;
    }];
}

-(void) setSubscription:(NSString*)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSNumber*) accountID
{
    if(!contact || accountID == nil || !sub)
        return;
    [self.db voidWriteTransaction:^{
        NSString* query = @"update buddylist set subscription=?, ask=? where account_id=? and buddy_name=?";
        NSArray* params = @[sub, ask?ask:@"", accountID, contact];
        [self.db executeNonQuery:query  andArguments:params];
    }];
}



#pragma mark Contact info

-(void) setFullName:(NSString*) fullName forContact:(NSString*) contact andAccount:(NSNumber*) accountID
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
        NSArray* params = @[toPass , accountID, contact];
        [self.db executeNonQuery:query  andArguments:params];
    }];
}

-(void) setAvatarHash:(NSString*) hash forContact:(NSString*) contact andAccount:(NSNumber*) accountID
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE account SET iconhash=? WHERE account_id=? AND printf('%s@%s', username, domain)=?;" andArguments:@[hash, accountID, contact]];
        [self.db executeNonQuery:@"UPDATE buddylist SET iconhash=? WHERE account_id=? AND buddy_name=?;" andArguments:@[hash, accountID, contact]];
    }];
}

-(NSString*) getAvatarHashForContact:(NSString*) buddy andAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        NSString* hash = [self.db executeScalar:@"SELECT iconhash FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, buddy]];
        if(!hash)           //try to get the hash of our own account
            hash = [self.db executeScalar:@"SELECT iconhash FROM account WHERE account_id=? AND printf('%s@%s', username, domain)=?;" andArguments:@[accountID, buddy]];
        if(!hash)
            hash = @"";     //hashes should never be nil
        return hash;
    }];
}

-(BOOL) isContactInList:(NSString*) buddy forAccount:(NSNumber*) accountID
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"select count(buddy_id) from buddylist where account_id=? and buddy_name=? ";
        NSArray* params = @[accountID, buddy];

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

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountID withComment:(NSString*) comment
{
    return [self.db boolWriteTransaction:^{
        return [self.db executeNonQuery:@"UPDATE buddylist SET messageDraft=? WHERE account_id=? AND buddy_name=?;" andArguments:@[comment, accountID, buddy]];
    }];
}

-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT messageDraft FROM buddylist WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[accountID, buddy];
        return [self.db executeScalar:query andArguments:params];
    }];
}

#pragma mark MUC

-(BOOL) initMuc:(NSString*) room forAccountID:(NSNumber*) accountID andMucNick:(NSString* _Nullable) mucNick
{
    return [self.db boolWriteTransaction:^{
        BOOL isMuc = [self isBuddyMuc:room forAccount:accountID];
        if(!isMuc)
        {
            // remove old buddy and add new one (this changes "normal" buddys to muc buddys if the aren't already tagged as mucs)
            // this will clean up associated buddylist data, too (foreign keys etc.)
            [self.db executeNonQuery:@"DELETE FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, room]];
        }
        
        NSString* nick = mucNick;
        if(!nick)
            nick = [self ownNickNameforMuc:room forAccount:accountID];
        MLAssert(nick != nil, @"Could not determine muc nick when adding muc");
        
        for(NSString* type in @[kMucAffiliationMember, kMucAffiliationAdmin, kMucAffiliationOwner])
        {
            [self cleanupParticipantsListFor:room andType:type onAccountID:accountID];
            [self cleanupMembersListFor:room andType:type onAccountID:accountID];
        }
        
        BOOL encrypt = NO;
#ifndef DISABLE_OMEMO
        // omemo for non group MUCs is disabled once the type of the muc is set
        // (for channel type mucs this will be disabled while creating the muc shortly after this function is called)
        encrypt = [[HelperTools defaultsDB] boolForKey:@"OMEMODefaultOn"];
#endif// DISABLE_OMEMO
        
        return [self.db executeNonQuery:@"INSERT INTO buddylist ('account_id', 'buddy_name', 'muc', 'muc_nick', 'encrypt') VALUES(?, ?, 1, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET muc=1, muc_nick=?;" andArguments:@[accountID, room, mucNick ? mucNick : @"", @(encrypt), mucNick ? mucNick : @""]];
    }];
}

-(void) cleanupParticipantsListFor:(NSString*) room andType:(NSString*) type onAccountID:(NSNumber*) accountID
{
    //clean up old muc data (will be refilled by incoming presences and/or disco queries)
    [self.db executeNonQuery:@"DELETE FROM muc_participants WHERE account_id=? AND room=? AND affiliation=?;" andArguments:@[accountID, room, type]];
}

-(void) cleanupMembersListFor:(NSString*) room andType:(NSString*) type onAccountID:(NSNumber*) accountID
{
    //clean up old muc data (will be refilled by incoming presences and/or disco queries)
    [self.db executeNonQuery:@"DELETE FROM muc_members WHERE account_id=? AND room=? AND affiliation=?;" andArguments:@[accountID, room, type]];
}

-(void) addParticipant:(NSDictionary*) participant toMuc:(NSString*) room forAccountID:(NSNumber*) accountID
{
    if(!participant || !participant[@"nick"] || !room || accountID == nil)
        return;
    
    [self.db voidWriteTransaction:^{
        //create entry if not already existing
        [self.db executeNonQuery:@"INSERT OR IGNORE INTO muc_participants ('account_id', 'room', 'room_nick', 'occupant_id') VALUES(?, ?, ?, ?);" andArguments:@[accountID, room, participant[@"nick"], nilWrapper(participant[@"occupant_id"])]];
        
        //update entry with optional fields (the first two fields are for members that are not just participants)
        if(participant[@"jid"])
            [self.db executeNonQuery:@"UPDATE muc_participants SET participant_jid=? WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[participant[@"jid"], accountID, room, participant[@"nick"]]];
        if(participant[@"affiliation"])
            [self.db executeNonQuery:@"UPDATE muc_participants SET affiliation=? WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[participant[@"affiliation"], accountID, room, participant[@"nick"]]];
        if(participant[@"role"])
            [self.db executeNonQuery:@"UPDATE muc_participants SET role=? WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[participant[@"role"], accountID, room, participant[@"nick"]]];
    }];
}

-(void) removeParticipant:(NSDictionary*) participant fromMuc:(NSString*) room forAccountID:(NSNumber*) accountID
{
    if(!participant || !participant[@"nick"] || !room || accountID == nil)
        return;
    
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM muc_participants WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[accountID, room, participant[@"nick"]]];
    }];
}

-(void) addMember:(NSDictionary*) member toMuc:(NSString*) room forAccountID:(NSString*) accountID
{
    if(!member || !member[@"jid"] || !room || !accountID)
        return;
    
    [self.db voidWriteTransaction:^{
        //create entry if not already existing
        [self.db executeNonQuery:@"INSERT OR IGNORE INTO muc_members ('account_id', 'room', 'member_jid') VALUES(?, ?, ?);" andArguments:@[accountID, room, member[@"jid"]]];
        
        //update entry with optional fields
        if(member[@"affiliation"])
            [self.db executeNonQuery:@"UPDATE muc_members SET affiliation=? WHERE account_id=? AND room=? AND member_jid=?;" andArguments:@[member[@"affiliation"], accountID, room, member[@"jid"]]];
    }];
}

-(void) removeMember:(NSDictionary*) member fromMuc:(NSString*) room forAccountID:(NSNumber*) accountID
{
    if(!member || !member[@"jid"] || !room || accountID == nil)
        return;
    
    DDLogDebug(@"Removing member '%@' from muc '%@'...", member[@"jid"], room);
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM muc_members WHERE account_id=? AND room=? AND member_jid=?;" andArguments:@[accountID, room, member[@"jid"]]];
    }];
}

-(NSDictionary* _Nullable) getParticipantForNick:(NSString*) nick inRoom:(NSString*) room forAccountID:(NSNumber*) accountID
{
    if(!nick || !room || accountID == nil)
        return nil;
    return [self.db idReadTransaction:^{
        NSArray* result = [self.db executeReader:@"SELECT * FROM muc_participants WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[accountID, room, nick]];
        return result.count > 0 ? result[0] : nil;
    }];
}

-(NSDictionary* _Nullable) getParticipantForOccupant:(NSString*) occupant inRoom:(NSString*) room forAccountID:(NSNumber*) accountID
{
    if(!occupant || !occupant || accountID == nil)
        return nil;
    return [self.db idReadTransaction:^{
        NSArray* result = [self.db executeReader:@"SELECT * FROM muc_participants WHERE account_id=? AND room=? AND occupant_id=?;" andArguments:@[accountID, room, occupant]];
        return result.count > 0 ? result[0] : nil;
    }];
}

-(NSArray<NSDictionary<NSString*, id>*>*) getMembersAndParticipantsOfMuc:(NSString*) room forAccountID:(NSNumber*) accountID
{
    if(!room || accountID == nil)
        return [[NSMutableArray<NSDictionary<NSString*, id>*> alloc] init];
    return [self.db idReadTransaction:^{
        NSMutableArray<NSDictionary<NSString*, id>*>* toReturn = [[NSMutableArray<NSDictionary<NSString*, id>*> alloc] init];
        
        [toReturn addObjectsFromArray:[self.db executeReader:@"SELECT *, 1 as 'online' FROM muc_participants WHERE account_id=? AND room=? ORDER BY affiliation, room_nick;" andArguments:@[accountID, room]]];
        [toReturn addObjectsFromArray:[self.db executeReader:@"SELECT *, 0 as 'online' FROM muc_members WHERE account_id=? AND room=? AND NOT EXISTS(SELECT * FROM muc_participants WHERE muc_members.account_id=muc_participants.account_id AND muc_members.room=muc_participants.room AND muc_members.member_jid=muc_participants.participant_jid) ORDER BY affiliation;" andArguments:@[accountID, room]]];
        
        return toReturn;
    }];
}

-(NSString* _Nullable) getOwnAffiliationInGroupOrChannel:(MLContact*) contact
{
    MLAssert(contact.isMuc, @"Function should only be called on a group contact");
    return [self.db idReadTransaction:^{
        NSString* retval = [self.db executeScalar:@"SELECT M.affiliation FROM muc_participants AS M INNER JOIN account AS A ON M.account_id=A.account_id WHERE M.room=? AND A.account_id=? AND (A.username || '@' || A.domain) == M.participant_jid" andArguments:@[contact.contactJid, contact.accountID]];
        if(retval == nil)
            retval = [self.db executeScalar:@"SELECT M.affiliation FROM muc_members AS M INNER JOIN account AS A ON M.account_id=A.account_id WHERE M.room=? AND A.account_id=? AND (A.username || '@' || A.domain) == M.member_jid" andArguments:@[contact.contactJid, contact.accountID]];
        return retval;
    }];
}

-(NSString*  _Nullable) getOwnRoleInGroupOrChannel:(MLContact*) contact
{
    MLAssert(contact.isMuc, @"Function should only be called on a group contact");
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT M.role FROM muc_participants AS M INNER JOIN account AS A ON M.account_id=A.account_id WHERE M.room=? AND A.account_id=? AND (A.username || '@' || A.domain) == M.participant_jid" andArguments:@[contact.contactJid, contact.accountID]];
    }];
}

-(void) addMucFavorite:(NSString*) room forAccountID:(NSNumber*) accountID andMucNick:(NSString* _Nullable) mucNick
{
    [self.db voidWriteTransaction:^{
        NSString* nick = mucNick;
        if(!nick)
            nick = [self ownNickNameforMuc:room forAccount:accountID];
        MLAssert(nick != nil, @"Could not determine muc nick when adding muc");
        
        [self.db executeNonQuery:@"INSERT INTO muc_favorites (room, nick, account_id) VALUES(?, ?, ?) ON CONFLICT(room, account_id) DO UPDATE SET nick=?;" andArguments:@[room, nick, accountID, nick]];
    }];
}

-(NSString*) lastStanzaIdForMuc:(NSString* _Nonnull) room andAccount:(NSString* _Nonnull) accountID
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT lastMucStanzaId FROM buddylist WHERE muc=1 AND account_id=? AND buddy_name=?;" andArguments:@[accountID, room]];
    }];
}

-(void) setLastStanzaId:(NSString*) lastStanzaId forMuc:(NSString* _Nonnull) room andAccount:(NSString* _Nonnull) accountID
{
    [self.db voidWriteTransaction:^{
        if(lastStanzaId && [lastStanzaId length])
            [self.db executeNonQuery:@"UPDATE buddylist SET lastMucStanzaId=? WHERE muc=1 AND account_id=? AND buddy_name=?;" andArguments:@[lastStanzaId, accountID, room]];
    }];
}


-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSNumber*) accountID
{
    return [self.db boolReadTransaction:^{
        NSNumber* status = (NSNumber*)[self.db executeScalar:@"SELECT Muc FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, buddy]];
        if(status == nil)
            return NO;
        else
            return [status boolValue];
    }];
}

-(NSString* _Nullable) ownNickNameforMuc:(NSString*) room forAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        NSString* nick = (NSString*)[self.db executeScalar:@"SELECT muc_nick FROM buddylist WHERE account_id=? AND buddy_name=? and muc=1;" andArguments:@[accountID, room]];
        // fallback to nick in muc_favorites
        if(!nick || nick.length == 0)
            nick = (NSString*)[self.db executeScalar:@"SELECT nick FROM muc_favorites WHERE account_id=? AND room=?;" andArguments:@[accountID, room]];
        if(!nick || nick.length == 0)
            return (NSString*)nil;
        return nick;
    }];
}

-(BOOL) updateOwnNickName:(NSString*) nick forMuc:(NSString*) room forAccount:(NSNumber*) accountID
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET muc_nick=? WHERE account_id=? AND buddy_name=? AND muc=1;";
        NSArray* params = @[nick, accountID, room];
        DDLogVerbose(@"%@", query);

        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(BOOL) deleteMuc:(NSString*) room forAccountID:(NSNumber*) accountID
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"DELETE FROM muc_favorites WHERE room=? AND account_id=?;";
        NSArray* params = @[room, accountID];
        DDLogVerbose(@"%@", query);

        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(NSSet*) listMucsForAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        NSMutableSet* retval = [NSMutableSet new];
        for(NSDictionary* entry in [self.db executeReader:@"SELECT * FROM muc_favorites WHERE account_id=?;" andArguments:@[accountID]])
            [retval addObject:[entry[@"room"] lowercaseString]];
        return retval;
    }];
}

-(BOOL) updateMucSubject:(NSString *) subject forAccount:(NSNumber*) accountID andRoom:(NSString *) room
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET muc_subject=? WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[subject, accountID, room];
        DDLogVerbose(@"%@", query);
        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(NSString*) mucSubjectforAccount:(NSNumber*) accountID andRoom:(NSString*) room
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT muc_subject FROM buddylist WHERE account_id=? AND buddy_name=?;";

        NSArray* params = @[accountID, room];
        DDLogVerbose(@"%@", query);

        return [self.db executeScalar:query andArguments:params];
    }];
}

-(void) updateMucTypeTo:(NSString*) type forRoom:(NSString*) room andAccount:(NSNumber*) accountID
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET muc_type=? WHERE account_id=? AND buddy_name=?;" andArguments:@[type, accountID, room]];
        if([type isEqualToString:kMucTypeGroup] == NO)
        {
            // non group type MUCs do not support encryption
            [self.db executeNonQuery:@"UPDATE buddylist SET encrypt=0 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, room]];
        }
    }];
}

-(NSString*) getMucTypeOfRoom:(NSString*) room andAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT muc_type FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, room]];
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

-(NSNumber*) getBiggestHistoryId
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT MAX(message_history_id) FROM message_history;"];
    }];
}

-(NSNumber*) addMessageToChatBuddy:(NSString*) buddyName withInboundDir:(BOOL) inbound forAccount:(NSNumber*) accountID withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom occupantId:(NSString* _Nullable) occupantId participantJid:(NSString*_Nullable) participantJid sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString*) messageid serverMessageId:(NSString*) stanzaid messageType:(NSString*) messageType andOverrideDate:(NSDate*) messageDate encrypted:(BOOL) encrypted displayMarkerWanted:(BOOL) displayMarkerWanted usingHistoryId:(NSNumber* _Nullable) historyId checkForDuplicates:(BOOL) checkForDuplicates;
{
    if(!buddyName || !message)
        return nil;
    
    return [self.db idWriteTransaction:^{
        if(!checkForDuplicates || [self hasMessageForStanzaId:stanzaid orMessageID:messageid withInboundDir:inbound occupantId:occupantId andJid:buddyName onAccount:accountID] == nil)
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
                query = @"insert into message_history (message_history_id, account_id, buddy_name, inbound, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid, participant_jid, occupant_id) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
                params = @[historyId, accountID, buddyName, [NSNumber numberWithBool:inbound], dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", messageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@"", nilWrapper(participantJid), nilWrapper(occupantId)];
            }
            else
            {
                //we use autoincrement here instead of MAX(message_history_id) + 1 to be a little bit faster (but at the cost of "duplicated code")
                query = @"insert into message_history (account_id, buddy_name, inbound, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid, participant_jid, occupant_id) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
                params = @[accountID, buddyName, [NSNumber numberWithBool:inbound], dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", messageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@"", nilWrapper(participantJid), nilWrapper(occupantId)];
            }
            DDLogVerbose(@"%@ params:%@", query, params);
            BOOL success = [self.db executeNonQuery:query andArguments:params];
            if(!success)
                return (NSNumber*)nil;
            NSNumber* historyId = [self.db lastInsertId];
            [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountID];
            return historyId;
        }
        else
        {
            DDLogWarn(@"Message(%@) %@ with stanzaid %@ already existing, ignoring history update: %@", accountID, messageid, stanzaid, message);
            return (NSNumber*)nil;
        }
    }];
}

-(NSNumber* _Nullable) hasMessageForStanzaId:(NSString*) stanzaId orMessageID:(NSString*) messageId withInboundDir:(BOOL) inbound occupantId:(NSString* _Nullable) occupantId andJid:(NSString*) jid onAccount:(NSNumber*) accountID
{
    if(accountID == nil)
        return (NSNumber*)nil;
    
    return (NSNumber*)[self.db idWriteTransaction:^{
        //if the stanzaid was given, this is conclusive for dedup, we don't need to check any other ids (EXCEPTION BELOW)
        if(stanzaId)
        {
            DDLogVerbose(@"stanzaid provided");
            NSArray<NSNumber*>* found = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? AND stanzaid!='' AND stanzaid=?;" andArguments:@[accountID, jid, stanzaId]];
            if([found count])
            {
                DDLogVerbose(@"stanzaid provided and could be found: %@", found);
                return found[0];
            }
        }
        
        //EXCEPT: outbound messages coming from this very client (we don't know their stanzaids)
        //NOTE: the MAM XEP does not mandate full jids in from-attribute of the wrapped message stanza
        //      --> we can't use that to figure out if the message came from this very client or only from another client using this account
        //=> if the stanzaid does not match and we process an outbound message, only dedup using origin-id (that should be unique and monal sets them)
        //   the check, if an origin-id was given, lives in MLMessageProcessor.m (it only triggers a dedup for messages either having a stanzaid or an origin-id)
        if(inbound == NO)
        {
            NSNumber* historyId = (NSNumber*)[self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? AND inbound=0 AND messageid=?;" andArguments:@[accountID, jid, messageId]];
            if(historyId != nil)
            {
                DDLogVerbose(@"found by origin-id or messageid");
                if(stanzaId!=nil)
                {
                    DDLogDebug(@"Updating stanzaid of message_history_id %@ to %@ for (account=%@, messageid=%@, inbound=%d)...", historyId, stanzaId, accountID, messageId, inbound);
                    //this entry needs an update of its stanzaid
                    [self.db executeNonQuery:@"UPDATE message_history SET stanzaid=? WHERE message_history_id=?" andArguments:@[stanzaId, historyId]];
                }
                if(occupantId!=nil)
                {
                    DDLogDebug(@"Updating occupant_id of message_history_id %@ to %@ for (account=%@, messageid=%@, inbound=%d)...", historyId, occupantId, accountID, messageId, inbound);
                    //only update occupant id if not set yet
                    [self.db executeNonQuery:@"UPDATE message_history SET occupant_id=? WHERE occupant_id IS NULL AND message_history_id=?" andArguments:@[nilWrapper(occupantId), historyId]];
                }
                return historyId;
            }
        }
        
        DDLogVerbose(@"nothing worked --> message not found");
        return (NSNumber*)nil;
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

-(void) clearMessages:(NSNumber*) accountID
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=?;" andArguments:@[kMessageTypeFiletransfer, accountID]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=?;" andArguments:@[accountID]];
        
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE account_id=?;" andArguments:@[accountID]];
        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
    }];
}

-(void) clearMessagesWithBuddy:(NSString*) buddy onAccount:(NSNumber*) accountID
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=? AND buddy_name=?;" andArguments:@[kMessageTypeFiletransfer, accountID, buddy]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, buddy]];
        
        //better UX without deleting the active chat
        //[self.db executeNonQuery:@"DELETE FROM activechats WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, buddy]];
        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
    }];
}

-(NSNumber*) autoDeleteMessagesAfterInterval:(NSTimeInterval) interval
{
    return [self.db idWriteTransaction:^{
        [self.db executeNonQuery:@"PRAGMA secure_delete=on;"];
        //interval before now
        NSDate* pastDate = [NSDate dateWithTimeIntervalSinceNow: -interval];
        NSString* pastDateString = [dbFormatter stringFromDate:pastDate];

        //select message history IDs of inbound read messages or outgoing messages being old enough
        //if they are filetransfers and delete those files
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE (inbound=0 OR unread=0) AND timestamp<? AND messageType=?;" andArguments:@[pastDateString, kMessageTypeFiletransfer]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];

        //delete inbound read messages or outgoing messages being old enough
        NSNumber* deletionCount = [self.db executeScalar:@"SELECT COUNT(*) FROM message_history WHERE (inbound=0 OR unread=0) AND timestamp<?;" andArguments:@[pastDateString]];
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE (inbound=0 OR unread=0) AND timestamp<?;" andArguments:@[pastDateString]];

        //delete all chats with empty history from active chats list
        [self.db executeNonQuery:@"DELETE FROM activechats AS AC WHERE NOT EXISTS (SELECT 1 FROM message_history AS MH WHERE MH.account_id=AC.account_id AND MH.buddy_name=AC.buddy_name);"];

        [self.db executeNonQuery:@"PRAGMA secure_delete=off;"];
        
        return deletionCount;
    }];
}

-(void) retractMessageHistory:(NSNumber*) messageNo
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

-(NSNumber* _Nullable) getLMCHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from occupantId:(NSString* _Nullable) occupantId participantJid:(NSString* _Nullable) participantJid andAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT M.message_history_id FROM message_history AS M INNER JOIN account AS A ON M.account_id=A.account_id INNER JOIN buddylist AS B on M.buddy_name = B.buddy_name AND M.account_id = B.account_id WHERE messageid=? AND M.account_id=? AND (\
            (B.Muc=0 AND ((M.buddy_name=? AND M.inbound=1) OR ((A.username || '@' || A.domain)=? AND M.inbound=0))) OR \
            (B.Muc=1 AND M.buddy_name=? AND (\
                    (M.occupant_id=? AND M.occupant_id IS NOT NULL) OR \
                    (M.participant_jid=? AND M.participant_jid IS NOT NULL) \
                ) AND ( \
                    (M.actual_from=B.muc_nick AND M.inbound=0) OR \
                    (M.actual_from!=B.muc_nick AND M.inbound=1) \
                ) \
            ) \
        );" andArguments:@[messageid, accountID, from, from, from, nilWrapper(occupantId), nilWrapper(participantJid)]];
    }];
}

-(NSNumber* _Nullable) getRetractionHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from participantJid:(NSString* _Nullable) participantJid occupantId:(NSString* _Nullable) occupantId andAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT M.message_history_id FROM message_history AS M INNER JOIN account AS A ON M.account_id=A.account_id INNER JOIN buddylist AS B on M.buddy_name = B.buddy_name AND M.account_id = B.account_id WHERE M.account_id=? AND ( \
            (B.Muc=0 AND M.messageid=? AND ((M.buddy_name=? AND M.inbound=1) OR ((A.username || '@' || A.domain)=? AND M.inbound=0))) OR \
            (B.Muc=1 AND M.stanzaid=? AND M.buddy_name=? AND ( \
                (M.participant_jid=? AND M.participant_jid IS NOT NULL) OR (M.occupant_id=? AND M.occupant_id IS NOT NULL)) \
            ) \
        );" andArguments:@[accountID, messageid, from, from, messageid, from, nilWrapper(participantJid), nilWrapper(occupantId)]];
    }];
}

-(NSNumber* _Nullable) getRetractionHistoryIDForModeratedStanzaId:(NSString*) stanzaId from:(NSString*) from andAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT M.message_history_id FROM message_history AS M INNER JOIN account AS A ON M.account_id=A.account_id INNER JOIN buddylist AS B on M.buddy_name = B.buddy_name AND M.account_id = B.account_id \
            WHERE M.account_id=? AND B.Muc=1 AND M.stanzaid=? AND M.buddy_name=?;"
            andArguments:@[accountID, stanzaId, from]];
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
            " andArguments:@[msg.accountID, msg.buddyName, historyID]];
        
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
        
        //only allow LMC if the correction message has the same encryption or better state as the original message
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
                    (SELECT message_history_id, inbound, encrypted, messageType FROM message_history WHERE account_id=? AND buddy_name=? AND message_history_id<? ORDER BY message_history_id ASC) \
                WHERE \
                    message_history_id=? LIMIT 1; \
                " andArguments:@[@(encrypted), @(encrypted), msg.accountID, msg.buddyName, historyBaseID, historyID]];
        }
        else
        {
            //only allow LMC if the correction message has the same encryption or better state as the original message
            editAllowed = (NSNumber*)[self.db executeScalar:@"\
                SELECT \
                    CASE \
                        WHEN (encrypted=? OR 1=?) THEN 1 \
                        ELSE 0 \
                    END \
                FROM \
                    (SELECT message_history_id, inbound, encrypted, messageType FROM message_history WHERE account_id=? AND buddy_name=? ORDER BY message_history_id DESC) \
                WHERE \
                    message_history_id=? LIMIT 1; \
                " andArguments:@[@(encrypted), @(encrypted), msg.accountID, msg.buddyName, historyID]];
        }
        BOOL eligible = YES;
        eligible &= editAllowed.intValue == 1;
        eligible &= [msg.messageType isEqualToString:kMessageTypeText];
        return eligible;
    }];
}

//message history
-(NSNumber*) lastMessageHistoryIdForContact:(NSString*) buddy forAccount:(NSString*) accountID
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? ORDER BY message_history_id DESC LIMIT 1" andArguments:@[ accountID, buddy]];
    }];
}

//message history
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountID
{
    if(accountID == nil || !buddy)
        return nil;
    return [self.db idReadTransaction:^{
        NSNumber* lastMsgHistID = [self lastMessageHistoryIdForContact:buddy forAccount:accountID];
        // Increment msgHistId -> all messages <= msgHistId are feteched
        lastMsgHistID = [NSNumber numberWithInt:[lastMsgHistID intValue] + 1];
        return [self messagesForContact:buddy forAccount:accountID beforeMsgHistoryID:lastMsgHistID];
    }];
}

//message history
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSNumber*) accountID beforeMsgHistoryID:(NSNumber* _Nullable) msgHistoryID
{
    if(accountID == nil || !buddy)
        return nil;
    return [self.db idReadTransaction:^{
        NSNumber* historyIdToUse = msgHistoryID;
        //fall back to newest message in history (including this message in this case)
        if(historyIdToUse == nil)
        {
            //we are querying with < relation below, but want to include the newest message nontheless
            historyIdToUse = @([[self lastMessageHistoryIdForContact:buddy forAccount:accountID] intValue] + 1);
        }
        NSString* query = @"SELECT message_history_id FROM (SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? AND message_history_id<? ORDER BY message_history_id DESC LIMIT ?) ORDER BY message_history_id ASC;";
        NSNumber* msgLimit = @(kMonalBackscrollingMsgCount);
        NSArray* params = @[accountID, buddy, historyIdToUse, msgLimit];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}

-(MLMessage*) lastMessageForContact:(NSString*) contact forAccount:(NSString*) accountID
{
    if(!accountID || !contact)
        return nil;
    
    return [self.db idReadTransaction:^{
        //return message draft (if any)
        NSString* query = @"SELECT bl.messageDraft AS message, ac.lastMessageTime AS thetime, 'MessageDraft' AS messageType, '' AS af, '' AS filetransferMimeType, 0 AS filetransferSize, bl.Muc, bl.muc_type, bl.buddy_name FROM buddylist AS bl INNER JOIN activechats AS ac ON bl.account_id = ac.account_id AND bl.buddy_name = ac.buddy_name WHERE ac.account_id=? AND ac.buddy_name=? AND messageDraft IS NOT NULL AND messageDraft != '';";
        NSArray* params = @[accountID, contact];
        NSArray* results = [self.db executeReader:query andArguments:params];
        if([results count])
        {
            NSMutableDictionary* message = [(NSDictionary*)results[0] mutableCopy];
            if(message[@"thetime"])
                message[@"thetime"] = [dbFormatter dateFromString:message[@"thetime"]];
            return [MLMessage messageFromDictionary:message];
        }
        
        //return "real" last message
        NSNumber* historyID = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountID, contact]];
        if(historyID == nil)
            return (MLMessage*)nil;
        return [self messageForHistoryID:historyID];
    }];
}

-(NSArray<MLMessage*>*) markMessagesAsReadForBuddy:(NSString*) buddy andAccount:(NSString*) accountID tillStanzaId:(NSString*) stanzaid wasOutgoing:(BOOL) outgoing
{
    if(!buddy || !accountID)
    {
        DDLogError(@"No buddy or accountID specified!");
        return @[];
    }
    
    return (NSArray<MLMessage*>*)[self.db idWriteTransaction:^{
        NSNumber* historyId;
        
        if(stanzaid)        //stanzaid or messageid given --> return all unread / not displayed messages until (and including) this one
        {
            historyId = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND stanzaid!='' AND stanzaid=? ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountID, stanzaid]];
            
            //if stanzaid could not be found we've got a messageid instead
            if(historyId == nil)
            {
                DDLogVerbose(@"Stanzaid not found, trying messageid");
                historyId = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND messageid=? ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountID, stanzaid]];
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
            historyId = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountID, buddy]];
            
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
            messageArray = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE displayed=0 AND displayMarkerWanted=1 AND received=1 AND account_id=? AND buddy_name=? AND inbound=0 AND message_history_id<=? ORDER BY message_history_id ASC;" andArguments:@[accountID, buddy, historyId]];
        else
            messageArray = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE unread=1 AND account_id=? AND buddy_name=? AND inbound=1 AND message_history_id<=? ORDER BY message_history_id ASC;" andArguments:@[accountID, buddy, historyId]];
        
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
                [self.db executeNonQuery:@"UPDATE buddylist SET latest_read_message_history_id=? WHERE account_id=? AND buddy_name=?;" andArguments:@[historyIDEntry, accountID, buddy]];
            }
        }
        
        //return NSArray of all updated MLMessages
        return (NSArray*)[self messagesForHistoryIDs:messageArray];
    }];
}

-(NSNumber*) addMessageHistoryTo:(NSString*) to forAccount:(NSNumber*) accountID withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString*) messageId encrypted:(BOOL) encrypted messageType:(NSString*) messageType mimeType:(NSString*) mimeType size:(NSNumber*) size
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
        params = @[accountID, to, [NSNumber numberWithBool:NO], dateTime, message, actualfrom, [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], messageId, messageType, [NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:YES], mimeType, size];
    }
    else
    {
        query = @"INSERT INTO message_history (account_id, buddy_name, inbound, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, displayMarkerWanted) VALUES(?,?,?,?,?,?,?,?,?,?,?,?);";
        params = @[accountID, to, [NSNumber numberWithBool:NO], dateTime, message, actualfrom, [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], messageId, messageType, [NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:YES]];
    }
    
    return [self.db idWriteTransaction:^{
        DDLogVerbose(@"%@", query);
        BOOL result = [self.db executeNonQuery:query andArguments:params];
        if(!result)
            return (NSNumber*)nil;
        NSNumber* historyId = [self.db lastInsertId];
        [self updateActiveBuddy:to setTime:dateTime forAccount:accountID];
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

-(NSString*) lastStanzaIdForAccount:(NSString*) accountID
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT lastStanzaId FROM account WHERE account_id=?;" andArguments:@[accountID]];
    }];
}

-(void) setLastStanzaId:(NSString*) lastStanzaId forAccount:(NSString*) accountID
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE account SET lastStanzaId=? WHERE account_id=?;" andArguments:@[lastStanzaId, accountID]];
    }];
}

#pragma mark active chats

-(NSMutableArray<MLContact*>*) activeContactsWithPinned:(BOOL) pinned
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT a.buddy_name, a.account_id FROM activechats AS a JOIN buddylist AS b ON (a.buddy_name = b.buddy_name AND a.account_id = b.account_id) JOIN account ON a.account_id = account.account_id WHERE a.pinned=? AND account.enabled ORDER BY lastMessageTime DESC;";
        NSMutableArray<MLContact*>* toReturn = [[NSMutableArray<MLContact*> alloc] init];
        for(NSDictionary* dic in [self.db executeReader:query andArguments:@[[NSNumber numberWithBool:pinned]]])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountID:dic[@"account_id"]]];
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

-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountID
{
    [self.db voidWriteTransaction:^{
        //mark all messages as read
        [self.db executeNonQuery:@"UPDATE message_history SET unread=0 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, buddyname]];
        //make sure the latest_read_message_history_id field in our buddylist is updated
        //(we use the newest history entry for this buddyname here)
        [self.db executeNonQuery:@"UPDATE buddylist SET latest_read_message_history_id=COALESCE((\
            SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? AND inbound=1 ORDER BY message_history_id DESC LIMIT 1\
        ), (\
            SELECT message_history_id FROM message_history ORDER BY message_history_id DESC LIMIT 1\
        ), 0) WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, buddyname, accountID, buddyname]];
        //remove contact from active chats list
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, buddyname]];
    }];
}

-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSNumber*) accountID
{
    if(!buddyname || accountID == nil)
        return;
    
    [self.db voidWriteTransaction:^{
        //add contact if possible (ignore already existing contacts)
        [self addContact:buddyname forAccount:accountID nickname:nil];

        // insert or update active chat
        NSString* query = @"INSERT INTO activechats (buddy_name, account_id, lastMessageTime) VALUES(?, ?, current_timestamp) ON CONFLICT(buddy_name, account_id) DO UPDATE SET lastMessageTime=current_timestamp;";
        [self.db executeNonQuery:query andArguments:@[buddyname, accountID]];
    }];
    return;
}


-(BOOL) isActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountID
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(buddy_name) FROM activechats WHERE account_id=? AND buddy_name=?;";
        NSNumber* count = (NSNumber*)[self.db executeScalar:query andArguments:@[accountID, buddyname]];
        if(count != nil)
        {
            NSInteger val = [((NSNumber*)count) integerValue];
            return (BOOL)(val > 0);
        }
        else
            return NO;
    }];
}

-(BOOL) updateActiveBuddy:(NSString*) buddyname setTime:(NSString*) timestamp forAccount:(NSNumber*) accountID
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"SELECT lastMessageTime FROM activechats WHERE account_id=? AND buddy_name=?;";
        NSObject* result = [self.db executeScalar:query andArguments:@[accountID, buddyname]];
        NSString* lastTime = (NSString *) result;

        NSDate* lastDate = [dbFormatter dateFromString:lastTime];
        NSDate* newDate = [dbFormatter dateFromString:timestamp];

        if(lastDate.timeIntervalSince1970 < newDate.timeIntervalSince1970)
        {
            NSString* query = @"UPDATE activechats SET lastMessageTime=? WHERE account_id=? AND buddy_name=?;";
            BOOL success = [self.db executeNonQuery:query andArguments:@[timestamp, accountID, buddyname]];
            return success;
        }
        else
            return NO;
    }];
}

#pragma mark chat properties

-(NSNumber*) countUserUnreadMessages:(NSString*) buddy forAccount:(NSNumber*) accountID
{
    if(!buddy || accountID == nil)
        return @0;
    return [self.db idReadTransaction:^{
        // count # messages from a specific user in messages table
        return [self.db executeScalar:@"SELECT COALESCE(COUNT(message_history_id),0) FROM message_history AS h WHERE h.message_history_id > (SELECT COALESCE(latest_read_message_history_id, 0) FROM buddylist WHERE account_id=? AND buddy_name=?) AND h.unread=1 AND h.account_id=? AND h.buddy_name=? AND h.inbound=1;" andArguments:@[accountID, buddy, accountID, buddy]];
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

-(NSString*) lastUsedPushServerForAccount:(NSNumber*) accountID
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT registeredPushServer FROM account WHERE account_id=?;" andArguments:@[accountID]];
    }];
}

-(void) updateUsedPushServer:(NSString*) pushServer forAccount:(NSNumber*) accountID
{
    [self.db voidWriteTransaction:^{
        [self.db executeScalarReader:@"UPDATE account SET registeredPushServer=? WHERE account_id=?;" andArguments:@[pushServer, accountID]];
    }];
}

-(void) deleteDelayedMessageStanzasForAccount:(NSString*) accountID
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM delayed_message_stanzas WHERE account_id=?;" andArguments:@[accountID]];
    }];
}

-(void) addDelayedMessageStanza:(MLXMLNode*) stanza forArchiveJid:(NSString*) archiveJid andAccountID:(NSNumber*) accountID
{
    if(accountID == nil || !archiveJid || !stanza)
        return;
    NSError* error;
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:stanza requiringSecureCoding:YES error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"INSERT INTO delayed_message_stanzas (account_id, archive_jid, stanza) VALUES(?, ?, ?);" andArguments:@[accountID, archiveJid, data]];
    }];
}

-(MLXMLNode* _Nullable) getNextDelayedMessageStanzaForArchiveJid:(NSString*) archiveJid andAccountID:(NSNumber*) accountID
{
    if(accountID == nil|| !archiveJid)
        return nil;
    NSData* data = (NSData*)[self.db idWriteTransaction:^{
        NSArray* entries = [self.db executeReader:@"SELECT id, stanza FROM delayed_message_stanzas WHERE account_id=? AND archive_jid=? ORDER BY id ASC LIMIT 1;" andArguments:@[accountID, archiveJid]];
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

-(void) muteContact:(MLContact*) contact
{
    if(!contact)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET muted=1 WHERE account_id=? AND buddy_name=?;" andArguments:@[contact.accountID, contact.contactJid]];
    }];
}

-(void) unMuteContact:(MLContact*) contact
{
    if(!contact)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET muted=0 WHERE account_id=? AND buddy_name=?;" andArguments:@[contact.accountID, contact.contactJid]];
    }];
}

-(BOOL) isMutedJid:(NSString*) jid onAccount:(NSString*) accountID
{
    if(!jid || !accountID)
    {
        unreachable();
        return NO;
    }
    return [self.db boolReadTransaction:^{
        NSNumber* count = (NSNumber*)[self.db executeScalar:@"SELECT COUNT(buddy_name) FROM buddylist WHERE account_id=? AND buddy_name=? AND muted=1;" andArguments: @[accountID, jid]];
        return count.boolValue;
    }];
}

-(void) setMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSString*) accountID
{
    if(!jid || !accountID)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET mentionOnly=1 WHERE account_id=? AND buddy_name=? AND muc=1;" andArguments:@[accountID, jid]];
    }];
}

-(void) setMucAlertOnAll:(NSString*) jid onAccount:(NSString*) accountID
{
    if(!jid || !accountID)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET mentionOnly=0 WHERE account_id=? AND buddy_name=? AND muc=1;" andArguments:@[accountID, jid]];
    }];
}

-(BOOL) isMucAlertOnMentionOnly:(NSString*) jid onAccount:(NSString*) accountID
{
    if(!jid || !accountID)
    {
        unreachable();
        return NO;
    }
    return [self.db boolReadTransaction:^{
        NSNumber* count = (NSNumber*)[self.db executeScalar:@"SELECT COUNT(buddy_name) FROM buddylist WHERE account_id=? AND buddy_name=? AND mentionOnly=1 AND muc=1;" andArguments: @[accountID, jid]];
        return count.boolValue;
    }];
}

-(void) blockJid:(NSString*) jid withAccountID:(NSNumber*) accountID
{
    if(!jid || accountID == nil)
        return;
    NSDictionary<NSString*, NSString*>* parsedJid = [HelperTools splitJid:jid];
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"INSERT OR IGNORE INTO blocklistCache(account_id, node, host, resource) VALUES(?, ?, ?, ?)" andArguments:@[accountID,
                parsedJid[@"node"] ? parsedJid[@"node"] : [NSNull null],
                parsedJid[@"host"] ? parsedJid[@"host"] : [NSNull null],
                parsedJid[@"resource"] ? parsedJid[@"resource"] : [NSNull null],
        ]];
    }];
}

-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids forAccountID:(NSNumber*) accountID
{
    [self.db voidWriteTransaction:^{
        // remove blocked state for all buddies of account
        [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=?;" andArguments:@[accountID]];
        // set blocking
        for(NSString* blockedJid in blockedJids)
            [self blockJid:blockedJid withAccountID:accountID];
    }];
}

-(void) unBlockJid:(NSString*) jid withAccountID:(NSNumber*) accountID
{
    NSDictionary<NSString*, NSString*>* parsedJid = [HelperTools splitJid:jid];
    [self.db voidWriteTransaction:^{
        if(parsedJid[@"node"] && parsedJid[@"host"] && parsedJid[@"resource"])
        {
            [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource=?" andArguments:@[accountID, parsedJid[@"node"], parsedJid[@"host"], parsedJid[@"resource"]]];    }
        else if(parsedJid[@"node"] && parsedJid[@"host"])
        {
            [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource IS NULL" andArguments:@[accountID, parsedJid[@"node"], parsedJid[@"host"]]];
        }
        else if(parsedJid[@"host"] && parsedJid[@"resource"])
        {
            [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource=?" andArguments:@[accountID, parsedJid[@"host"], parsedJid[@"resource"]]];
        }
        else if(parsedJid[@"host"])
        {
            [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource IS NULL" andArguments:@[accountID, parsedJid[@"host"]]];
        }
    }];
}

-(uint8_t) isBlockedContact:(MLContact*) contact
{
    if(!contact)
        return kBlockingNoMatch;

    return (uint8_t)[[self.db idReadTransaction:^{
        NSDictionary<NSString*, NSString*>* parsedJid = [HelperTools splitJid:contact.contactJid];
        NSNumber* blocked;
        uint8_t ruleId = kBlockingNoMatch;
        if(parsedJid[@"node"] && parsedJid[@"host"] && parsedJid[@"resource"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource=?;" andArguments:@[contact.accountID, parsedJid[@"node"], parsedJid[@"host"], parsedJid[@"resource"]]];
            ruleId = kBlockingMatchedNodeHostResource;
        }
        else if(parsedJid[@"node"] && parsedJid[@"host"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource IS NULL;" andArguments:@[contact.accountID, parsedJid[@"node"], parsedJid[@"host"]]];
            ruleId = kBlockingMatchedNodeHost;
        }
        else if(parsedJid[@"host"] && parsedJid[@"resource"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource=?;" andArguments:@[contact.accountID, parsedJid[@"host"], parsedJid[@"resource"]]];
            ruleId = kBlockingMatchedHostResource;
        }
        else if(parsedJid[@"host"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource IS NULL;" andArguments:@[contact.accountID, parsedJid[@"host"]]];
            ruleId = kBlockingMatchedHost;
        }
        if(blocked.intValue >= 1)
            return [NSNumber numberWithInt:ruleId];
        else
            return [NSNumber numberWithInt:kBlockingNoMatch];
    }] intValue];
}

-(NSArray<NSDictionary<NSString*, NSString*>*>*) blockedJidsForAccount:(NSString*) accountID
{
    return [self.db idReadTransaction:^{
        NSArray* blockedJidsFromDB = [self.db executeReader:@"SELECT * FROM blocklistCache WHERE account_id=?" andArguments:@[accountID]];
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

-(BOOL) isPinnedChat:(NSString*) accountID andBuddyJid:(NSString*) buddyJid
{
    if(!accountID || !buddyJid)
        return NO;
    return [self.db boolReadTransaction:^{
        NSNumber* pinnedNum = [self.db executeScalar:@"SELECT pinned FROM activechats WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, buddyJid]];
        if(pinnedNum != nil)
            return [pinnedNum boolValue];
        else
            return NO;
    }];
}

-(void) pinChat:(NSString*) accountID andBuddyJid:(NSString*) buddyJid
{
    if(!accountID || !buddyJid)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE activechats SET pinned=1 WHERE account_id=? AND buddy_name=?" andArguments:@[accountID, buddyJid]];
    }];
}
-(void) unPinChat:(NSString*) accountID andBuddyJid:(NSString*) buddyJid
{
    if(!accountID || !buddyJid)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE activechats SET pinned=0 WHERE account_id=? AND buddy_name=?" andArguments:@[accountID, buddyJid]];
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

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSString*) accountID
{
    if(!accountID ||! contact)
        return nil;
    
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=? AND buddy_name=? GROUP BY message ORDER BY message_history_id ASC;";
        NSArray* params = @[kMessageTypeFiletransfer, accountID, contact];
        
        NSMutableArray* retval = [NSMutableArray new];
        for(MLMessage* msg in [self messagesForHistoryIDs:[self.db executeScalarReader:query andArguments:params]])
            [retval addObject:[MLFiletransfer getFileInfoForMessage:msg]];
        return retval;
    }];
}

#pragma mark - last interaction

-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountID:(NSNumber* _Nonnull) accountID
{
    MLAssert(jid != nil, @"jid should not be null");
    MLAssert(accountID != nil, @"accountID should not be null");
    return [self.db idReadTransaction:^{
        //this will only return resources supporting "urn:xmpp:idle:1" and being "online" (e.g. lastInteraction = 0)
        NSNumber* online = [self.db executeScalar:@"SELECT R.lastInteraction FROM buddy_resources AS R INNER JOIN buddylist AS B ON R.buddy_id=B.buddy_id INNER JOIN ver_info AS V ON R.ver=V.ver WHERE B.account_id=? AND B.buddy_name=? AND V.account_id=? AND V.cap='urn:xmpp:idle:1' AND R.lastInteraction=0 ORDER BY R.lastInteraction ASC LIMIT 1;" andArguments:@[accountID, jid, accountID]];
        
        //this will only return resources supporting "urn:xmpp:idle:1" and being "idle since <...>" (e.g. lastInteraction > 0)
        NSNumber* idle = [self.db executeScalar:@"SELECT R.lastInteraction FROM buddy_resources AS R INNER JOIN buddylist AS B ON R.buddy_id=B.buddy_id INNER JOIN ver_info AS V ON R.ver=V.ver WHERE B.account_id=? AND B.buddy_name=? AND V.account_id=? AND V.cap='urn:xmpp:idle:1' AND R.lastInteraction!=0 ORDER BY R.lastInteraction DESC LIMIT 1;" andArguments:@[accountID, jid, accountID]];
        
        //this will only return a value if the buddy has a last interaction not being NULL or 0
        NSNumber* globalIdle = [self.db executeScalar:@"SELECT lastInteraction FROM buddylist WHERE account_id=? AND buddy_name=? AND NOT (lastInteraction IS NULL OR lastInteraction==0);" andArguments:@[accountID, jid]];
        
        //at least one online resource means the buddy is online
        //if no online resource can be found use the newest timestamp as "idle since <...>" timestamp
        //if this can also not be found, use the global timestamp and if this is NULL then return nil
        //(meaning last interaction is unsupported and was every since we saw presences from this jid)
        DDLogDebug(@"LastInteraction of %@ online=%@, idle=%@, globalIdle=%@", jid, online, idle, globalIdle);
        if(online != nil)
            return [[NSDate date] initWithTimeIntervalSince1970:0] ;
        if(idle == nil)
        {
            if(globalIdle == nil)
                return (NSDate*)nil;
            return [NSDate dateWithTimeIntervalSince1970:[globalIdle integerValue]];
        }
        return [NSDate dateWithTimeIntervalSince1970:[idle integerValue]];
    }];
}

-(NSDate* _Nullable) lastInteractionOfJid:(NSString* _Nonnull) jid andResource:(NSString* _Nonnull) resource forAccountID:(NSNumber* _Nonnull) accountID
{
    MLAssert(jid != nil, @"jid should not be null");
    MLAssert(accountID != nil, @"accountID should not be null");
    return [self.db idReadTransaction:^{
        //this will only return resources supporting "urn:xmpp:idle:1"
        NSNumber* lastInteraction = [self.db executeScalar:@"SELECT R.lastInteraction FROM buddy_resources AS R INNER JOIN buddylist AS B ON R.buddy_id=B.buddy_id WHERE B.account_id=? AND B.buddy_name=? AND R.resource=? AND EXISTS(SELECT * FROM ver_info AS V WHERE V.ver=R.ver AND V.account_id=B.account_id AND V.cap='urn:xmpp:idle:1') LIMIT 1;" andArguments:@[accountID, jid, resource]];
        DDLogDebug(@"LastInteraction of %@/%@ lastInteraction=%@", jid, resource, lastInteraction);
        if(lastInteraction == nil)
            return (NSDate*)nil;
        return [NSDate dateWithTimeIntervalSince1970:[lastInteraction integerValue]];
    }];
}

-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andResource:(NSString*) resource onAccountID:(NSNumber* _Nonnull) accountID
{
    MLAssert(jid != nil, @"jid should not be null");
    MLAssert(accountID != nil, @"accountID should not be null");
    
    NSNumber* timestamp = @0;       //default value for "online" or "unknown" (depending on caps)
    if(lastInteractionTime != nil)
        timestamp = [HelperTools dateToNSNumberSeconds:lastInteractionTime];
    
    DDLogDebug(@"Setting lastInteraction of %@/%@ to %@...", jid, resource, timestamp);
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddy_resources AS R SET lastInteraction=? WHERE EXISTS(SELECT * FROM buddylist AS B WHERE B.buddy_id=R.buddy_id AND B.account_id=? AND B.buddy_name=?) AND R.resource=?;" andArguments:@[timestamp, accountID, jid, resource]];
        [self.db executeNonQuery:@"UPDATE buddylist SET lastInteraction=? WHERE account_id=? AND buddy_name=? AND (lastInteraction IS NULL OR lastInteraction<?);" andArguments:@[timestamp, accountID, jid, timestamp]];
    }];
}

#pragma mark - encryption

-(BOOL) shouldEncryptForJid:(NSString*) jid andAccountID:(NSNumber*) accountID
{
    if(!jid || accountID == nil)
        return NO;
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT encrypt from buddylist where account_id=? and buddy_name=?";
        NSArray* params = @[accountID, jid];
        NSNumber* status=(NSNumber*)[self.db executeScalar:query andArguments:params];
        return [status boolValue];
    }];
}


-(void) encryptForJid:(NSString*) jid andAccountID:(NSNumber*) accountID
{
    if(!jid || accountID == nil)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET encrypt=1 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, jid]];
    }];
    return;
}

-(void) disableEncryptForJid:(NSString*) jid andAccountID:(NSNumber*) accountID
{
    if(!jid || accountID == nil)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET encrypt=0 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountID, jid]];
    }];
    return;
}

-(NSNumber*) addIdleTimerWithTimeout:(NSNumber*) timeout andHandler:(MLHandler*) handler onAccountID:(NSNumber*) accountID
{
    return [self.db idWriteTransaction:^{
        [self.db executeNonQuery:@"INSERT INTO idle_timers (timeout, account_id, handler) VALUES (?, ?, ?);" andArguments:@[timeout, accountID, [HelperTools serializeObject:handler]]];
        return [self.db lastInsertId];
    }];
}

-(void) delIdleTimerWithId:(NSNumber* _Nullable) timerId
{
    DDLogVerbose(@"Trying to remove idle timer with id: %@", timerId);
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
        xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:timer[@"account_id"]];
        MLAssert(account != nil, @"Deleting an idle timer should not be done when an account is disabled!", (@{
            @"timerId": timerId,
            @"accountID": nilWrapper(timer[@"account_id"])
        }));
        $invalidate([HelperTools unserializeData:timer[@"handler"]], $ID(account));
        [self.db executeNonQuery:@"DELETE FROM idle_timers WHERE id=?;" andArguments:@[timerId]];
    }];
}

-(void) cleanupIdleTimerOnAccountID:(NSNumber*) accountID
{
    if(accountID == nil)
        return;
    return [self.db voidWriteTransaction:^{
        xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:accountID];
        MLAssert(account != nil, @"Cleaning up idle timers should not be done when an account is disabled!", (@{
            @"accountID": nilWrapper(accountID)
        }));
        [self.db executeNonQuery:@"DELETE FROM idle_timers WHERE account_id=?;" andArguments:@[accountID]];
    }];
}

//this method will only be called from our timer background thread also handling iq timeouts
-(void) decrementIdleTimersForAccount:(xmpp*) account
{
    return [self.db voidWriteTransaction:^{
        for(NSDictionary* timer in [self.db executeReader:@"SELECT * FROM idle_timers WHERE account_id=?;" andArguments:@[account.accountID]])
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

-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword accountID:(NSNumber*) accountID
{
    if(!keyword || accountID == nil)
        return nil;
    return [self.db idReadTransaction:^{
        NSString *likeString = [NSString stringWithFormat:@"%%%@%%", keyword];
        NSString* query = @"SELECT message_history_id FROM message_history WHERE account_id = ? AND (message like ? OR buddy_name LIKE ? OR messageType LIKE ?) ORDER BY timestamp ASC;";
        NSArray* params = @[accountID, likeString, likeString, likeString];
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
        NSArray* params = @[contact.accountID, likeString, contact.contactJid];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}

@end
