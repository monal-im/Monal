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

@interface DataLayer()
@property (readonly, strong) MLSQLite* db;
@end

@implementation DataLayer

NSString* const kAccountID = @"account_id";
NSString* const kAccountState = @"account_state";

//used for account rows
NSString *const kDomain = @"domain";
NSString *const kEnabled = @"enabled";

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
    NSError* error;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    NSString* writableDBPath = [[containerUrl path] stringByAppendingPathComponent:@"sworim.sqlite"];
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* oldDBPath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"sworim.sqlite"];
    
    //database move is incomplete --> start from scratch
    //this can happen if the notification extension was run after the app upgrade but before the main app was opened
    //in this scenario the db doesn't get copyed but created from the default file (e.g. it is empty)
    if([fileManager fileExistsAtPath:oldDBPath] && [fileManager fileExistsAtPath:writableDBPath])
    {
        DDLogInfo(@"initialize: old AND new db files present, delete new one and start from scratch");
        [fileManager removeItemAtPath:writableDBPath error:&error];
        if(error)
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    }
    
    //old install is being upgraded --> copy old database to new app group path
    if([fileManager fileExistsAtPath:oldDBPath] && ![fileManager fileExistsAtPath:writableDBPath])
    {
        DDLogInfo(@"initialize: copying existing DB from OLD path to new app group one: %@ --> %@", oldDBPath, writableDBPath);
        [fileManager copyItemAtPath:oldDBPath toPath:writableDBPath error:&error];
        if(error)
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
        DDLogInfo(@"initialize: removing old DB at: %@", oldDBPath);
        [fileManager removeItemAtPath:oldDBPath error:&error];
        if(error)
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    }
    
    //the file still does not exist (e.g. fresh install) --> copy default database to app group path
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
    dbFormatter = [[NSDateFormatter alloc] init];
    [dbFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    [dbFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
}

//we are a singleton (compatible with old code), but conceptually we could also be a static class instead
+(id) sharedInstance
{
    static DataLayer* newInstance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        newInstance = [[self alloc] init];
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

-(BOOL) isAccountEnabled:(NSString*) accountNo
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

-(NSMutableDictionary*) detailsForAccount:(NSString*) accountNo
{
    if(!accountNo)
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

-(NSString*) jidOfAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT username, domain FROM account WHERE account_id=?;";
        NSMutableArray* accountDetails = [self.db executeReader:query andArguments:@[accountNo]];
        
        if(accountDetails == nil)
            return (NSString*)nil;
        
        NSString* accountJid = nil;
        if(accountDetails.count > 0) {
            NSDictionary* firstRow = [accountDetails objectAtIndex:0];
            accountJid = [NSString stringWithFormat:@"%@@%@", [firstRow objectForKey:kUsername], [firstRow objectForKey:kDomain]];
        }
        return accountJid;
    }];
}

-(BOOL) updateAccounWithDictionary:(NSDictionary *) dictionary
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"UPDATE account SET server=?, other_port=?, username=?, resource=?, domain=?, enabled=?, directTLS=?, rosterName=?, statusMessage=? WHERE account_id=?;";
        NSString* server = (NSString *) [dictionary objectForKey:kServer];
        NSString* port = (NSString *)[dictionary objectForKey:kPort];
        NSArray* params = @[server == nil ? @"" : server,
                        port == nil ? @"5222" : port,
                        ((NSString*)[dictionary objectForKey:kUsername]),
                        ((NSString*)[dictionary objectForKey:kResource]),
                        ((NSString*)[dictionary objectForKey:kDomain]),
                        [dictionary objectForKey:kEnabled],
                        [dictionary objectForKey:kDirectTLS],
                        [dictionary objectForKey:kRosterName] ? ((NSString*)[dictionary objectForKey:kRosterName]) : @"",
                        [dictionary objectForKey:@"statusMessage"] ? ((NSString*)[dictionary objectForKey:@"statusMessage"]) : @"",
                        [dictionary objectForKey:kAccountID]
        ];
        return [self.db executeNonQuery:query andArguments:params];
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
        if(result) {
            NSNumber* accountID = [self.db lastInsertId];

            // insert self chat for omemo foreign key
            [self.db executeNonQuery:@"INSERT OR IGNORE INTO buddylist ('account_id', 'buddy_name', 'muc') SELECT account_id, (username || '@' || domain), 0 FROM account WHERE account_id=?;" andArguments:@[accountID]];

            return accountID;
        } else {
            return (NSNumber*)nil;
        }
    }];
}

-(BOOL) removeAccount:(NSString*) accountNo
{
    // remove all other traces of the account_id in one transaction
    return [self.db boolWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM buddylist WHERE account_id=?;" andArguments:@[accountNo]];
        
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=?;" andArguments:@[kMessageTypeFiletransfer, accountNo]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=?;" andArguments:@[accountNo]];
        
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE account_id=?;" andArguments:@[accountNo]];
        // delete omemo related entries
        [self.db executeNonQuery:@"DELETE FROM signalContactIdentity WHERE account_id=?;" andArguments:@[accountNo]];
        [self.db executeNonQuery:@"DELETE FROM signalContactKey WHERE account_id=?;" andArguments:@[accountNo]];
        [self.db executeNonQuery:@"DELETE FROM signalIdentity WHERE account_id=?;" andArguments:@[accountNo]];
        [self.db executeNonQuery:@"DELETE FROM signalPreKey WHERE account_id=?;" andArguments:@[accountNo]];
        [self.db executeNonQuery:@"DELETE FROM signalSignedPreKey WHERE account_id=?;" andArguments:@[accountNo]];

        return [self.db executeNonQuery:@"DELETE FROM account WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(BOOL) disableEnabledAccount:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        return [self.db executeNonQuery:@"UPDATE account SET enabled=0 WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(NSMutableDictionary*) readStateForAccount:(NSString*) accountNo
{
    if(!accountNo)
        return nil;
    NSString* query = @"SELECT state from account where account_id=?";
    NSArray* params = @[accountNo];
    NSData* data = (NSData*)[self.db idReadTransaction:^{
        return [self.db executeScalar:query andArguments:params];
    }];
    if(data)
    {
        NSError* error;
        NSMutableDictionary* dic = (NSMutableDictionary*)[NSKeyedUnarchiver unarchivedObjectOfClasses:[[NSSet alloc] initWithArray:@[
            [NSMutableDictionary class],
            [NSDictionary class],
            [NSMutableSet class],
            [NSSet class],
            [NSMutableArray class],
            [NSArray class],
            [NSNumber class],
            [NSString class],
            [NSDate class],
            [MLHandler class],
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
        return dic;
    }
    return nil;
}

-(void) persistState:(NSDictionary*) state forAccount:(NSString*) accountNo
{
    if(!accountNo || !state)
        return;
    NSError* error;
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:state requiringSecureCoding:YES error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE account SET state=? WHERE account_id=?;";
        NSArray* params = @[data, accountNo];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

#pragma mark contact Commands

-(BOOL) addContact:(NSString*) contact forAccount:(NSString*) accountNo nickname:(NSString*) nickName andMucNick:(NSString* _Nullable) mucNick
{
    if(!accountNo || !contact)
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
        
        //make this a muc again if it existed as muc already (an reuse the nickname from the old buddylist entry or muc_favorites entry)
        NSString* mucNickToUse = mucNick;
        if(!mucNickToUse)
            mucNickToUse = [self ownNickNameforMuc:contact forAccount:accountNo];
        
        return [self.db executeNonQuery:@"INSERT INTO buddylist ('account_id', 'buddy_name', 'full_name', 'nick_name', 'muc', 'muc_nick') VALUES(?, ?, ?, ?, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET nick_name=?;" andArguments:@[accountNo, contact, @"", toPass, mucNickToUse ? @1 : @0, mucNickToUse ? mucNickToUse : @"", toPass]];
    }];
}

-(void) removeBuddy:(NSString*) buddy forAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        //clean up logs...
        [self messageHistoryClean:buddy forAccount:accountNo];
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

-(BOOL) resetContactsForAccount:(NSString*) accountNo
{
    if(!accountNo)
        return NO;
    return [self.db boolWriteTransaction:^{
        NSString* query2 = @"DELETE FROM buddy_resources WHERE buddy_id IN (SELECT buddy_id FROM buddylist WHERE account_id=?);";
        NSArray* params = @[accountNo];
        [self.db executeNonQuery:query2 andArguments:params];
        NSString* query = @"UPDATE buddylist SET state='offline', status='' WHERE account_id=?;";
        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(NSDictionary* _Nullable) contactDictionaryForUsername:(NSString*) username forAccount:(NSString*) accountNo
{
    if(!username || !accountNo)
        return nil;

    return [self.db idReadTransaction:^{
        NSArray* results = [self.db executeReader:@"SELECT b.buddy_name, state, status, b.full_name, b.nick_name, Muc, muc_subject, muc_type, muc_nick, b.account_id, lastMessageTime, 0 AS 'count', subscription, ask, IFNULL(pinned, 0) AS 'pinned', blocked, encrypt, muted, \
            CASE \
                WHEN a.buddy_name IS NOT NULL THEN 1 \
                ELSE 0 \
            END AS 'isActiveChat' \
            FROM buddylist AS b LEFT JOIN activechats AS a \
            ON a.buddy_name = b.buddy_name AND a.account_id = b.account_id \
            WHERE b.buddy_name=? AND b.account_id=?;" andArguments:@[username, accountNo]];
        if(results == nil || [results count] > 1)
            @throw [NSException exceptionWithName:@"DataLayerError" reason:@"unexpected contact count" userInfo:@{
                @"username": username,
                @"accountNo": accountNo,
                @"count": [NSNumber numberWithInteger:[results count]],
                @"results": results ? results : @"(null)"
            }];

        if([results count] == 0)
        {
            return (NSMutableDictionary*)nil;
        }
        else
        {
            assert([results count] == 1);
            // add unread message count to contact dict
            NSMutableDictionary* contact = [results[0] mutableCopy];
            contact[@"count"] = [self countUserUnreadMessages:username forAccount:accountNo];
            //correctly extract timestamp
            if(contact[@"lastMessageTime"])
                contact[@"lastMessageTime"] = [dbFormatter dateFromString:contact[@"lastMessageTime"]];
            return contact;
        }
    }];
}


-(NSMutableArray<MLContact*>*) searchContactsWithString:(NSString*) search
{
    return [self.db idReadTransaction:^{
        NSString* likeString = [NSString stringWithFormat:@"%%%@%%", search];
        NSString* query = @"SELECT buddy_name, A.account_id FROM buddylist AS B INNER JOIN account AS A ON A.account_id=B.account_id WHERE A.enabled=1 AND (A.username || '@' || A.domain)!=buddy_name AND buddy_name LIKE ? OR full_name LIKE ? OR nick_name LIKE ? ORDER BY full_name, nick_name, buddy_name COLLATE NOCASE ASC;";
        NSArray* params = @[likeString, likeString, likeString];
        NSMutableArray<MLContact*>* toReturn = [[NSMutableArray alloc] init];
        for(NSDictionary* dic in [self.db executeReader:query andArguments:params])
            [toReturn addObject: [MLContact createContactFromJid:dic[@"buddy_name"] andAccountNo:dic[@"account_id"]]];
        return toReturn;
    }];
}

-(NSMutableArray<MLContact*>*) contactList
{
    return [self.db idReadTransaction:^{
        //list all contacts and group chats
        NSString* query = @"SELECT B.buddy_name, B.account_id, IFNULL(IFNULL(NULLIF(B.nick_name, ''), NULLIF(B.full_name, '')), B.buddy_name) AS 'sortkey' FROM buddylist AS B INNER JOIN account AS A ON A.account_id=B.account_id WHERE A.enabled=1 AND (A.username || '@' || A.domain)!=buddy_name ORDER BY sortkey COLLATE NOCASE ASC;";
        NSMutableArray* toReturn = [[NSMutableArray alloc] init];
        for(NSDictionary* dic in [self.db executeReader:query])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountNo:dic[@"account_id"]]];
        return toReturn;
    }];
}

#pragma mark entity capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andAccountNo:(NSString*) acctNo
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(*) FROM buddylist AS a INNER JOIN buddy_resources AS b ON a.buddy_id=b.buddy_id INNER JOIN ver_info AS c ON b.ver=c.ver WHERE buddy_name=? AND account_id=? AND cap=?;";
        NSArray *params = @[user, acctNo, cap];
        NSNumber* count = (NSNumber*) [self.db executeScalar:query andArguments:params];
        return (BOOL)([count integerValue]>0);
    }];
}

-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT ver FROM buddy_resources AS A INNER JOIN buddylist AS B ON a.buddy_id=b.buddy_id WHERE resource=? AND buddy_name=?;";
        NSArray * params = @[resource, user];
        NSString* ver = (NSString*) [self.db executeScalar:query andArguments:params];
        return ver;
    }];
}

-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource
{
    NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
    [self.db voidWriteTransaction:^{
        //set ver for user and resource
        NSString* query = @"UPDATE buddy_resources SET ver=? WHERE EXISTS(SELECT * FROM buddylist WHERE buddy_resources.buddy_id=buddylist.buddy_id AND resource=? AND buddy_name=?)";
        NSArray * params = @[ver, resource, user];
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
            NSMutableSet* retval = [[NSMutableSet alloc] init];
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
    NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
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

-(void) setResourceOnline:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
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


-(NSArray*) resourcesForContact:(NSString*) contact
{
    if(!contact)
        return nil;
    return [self.db idReadTransaction:^{
        NSString* query1 = @"select resource from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where  buddy_name=?;";
        NSArray* params = @[contact ];
        NSArray* resources = [self.db executeReader:query1 andArguments:params];
        return resources;
    }];
}

-(NSArray*) getSoftwareVersionInfoForContact:(NSString*)contact resource:(NSString*)resource andAccount:(NSString*)account
{
    if(!account)
        return nil;
    return [self.db idReadTransaction:^{
        NSString* query1 = @"select platform_App_Name, platform_App_Version, platform_OS from buddy_resources where buddy_id in (select buddy_id from buddylist where account_id=? and buddy_name=?) and resource=?";
        NSArray* params = @[account, contact, resource];
        NSArray* resources = [self.db executeReader:query1 andArguments:params];
        return resources;
    }];
}

-(void) setSoftwareVersionInfoForContact:(NSString*)contact
                                resource:(NSString*)resource
                              andAccount:(NSString*)account
                             withAppName:(NSString*)appName
                              appVersion:(NSString*)appVersion
                           andPlatformOS:(NSString*)platformOS
{
    [self.db voidWriteTransaction:^{
        NSString* query = @"update buddy_resources set platform_App_Name=?, platform_App_Version=?, platform_OS=? where buddy_id in (select buddy_id from buddylist where account_id=? and buddy_name=?) and resource=?";
        NSArray* params = @[appName, appVersion, platformOS, account, contact, resource];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

-(void) setOnlineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self setResourceOnline:presenceObj forAccount:accountNo];
        NSString* query = @"UPDATE buddylist SET state='' WHERE account_id=? AND buddy_name=? AND state='offline';";
        NSArray* params = @[accountNo, presenceObj.fromUser];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

-(BOOL) setOfflineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSString* query1 = @"SELECT buddy_id FROM buddylist WHERE account_id=? AND buddy_name=?;";
        NSArray* params=@[accountNo, presenceObj.fromUser];
        NSString* buddyid = (NSString*)[self.db executeScalar:query1 andArguments:params];
        if(buddyid == nil)
            return NO;

        NSString* query2 = @"DELETE FROM buddy_resources WHERE buddy_id=? AND resource=?;";
        NSArray* params2 = @[buddyid, presenceObj.fromResource ? presenceObj.fromResource : @""];
        if([self.db executeNonQuery:query2 andArguments:params2] == NO)
            return NO;

        //see how many left
        NSString* resourceCount = [self.db executeScalar:@"SELECT COUNT(buddy_id) FROM buddy_resources WHERE buddy_id=?;" andArguments:@[buddyid]];

        if([resourceCount integerValue] < 1)
        {
            NSString* query = @"UPDATE buddylist SET state='offline' WHERE account_id=? AND buddy_name=?;";
            NSArray* params4 = @[accountNo, presenceObj.fromUser];
            BOOL retval = [self.db executeNonQuery:query andArguments:params4];
            return retval;
        }
        else
            return NO;
    }];
}

-(void) setBuddyState:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo;
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

-(BOOL) hasContactRequestForAccount:(NSString*) accountNo andBuddyName:(NSString*) buddy
{
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT COUNT(*) FROM subscriptionRequests WHERE account_id=? AND buddy_name=?";
        NSNumber* result = (NSNumber*)[self.db executeScalar:query andArguments:@[accountNo, buddy]];
        return (BOOL)(result.intValue == 1);
    }];
}

-(NSMutableArray*) contactRequestsForAccount
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT account_id, buddy_name FROM subscriptionRequests;";
        NSMutableArray* toReturn = [[NSMutableArray alloc] init];
        for(NSDictionary* dic in [self.db executeReader:query])
            [toReturn addObject:[MLContact createContactFromJid:dic[@"buddy_name"] andAccountNo:dic[@"account_id"]]];
        return toReturn;
    }];
}

-(void) addContactRequest:(MLContact *) requestor;
{
    [self.db voidWriteTransaction:^{
        NSString* query2 = @"INSERT OR IGNORE INTO subscriptionRequests (buddy_name, account_id) VALUES (?,?)";
        [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId]];
    }];
}

-(void) deleteContactRequest:(MLContact *) requestor
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

-(void) setRosterVersion:(NSString *) version forAccount: (NSString*) accountNo
{
    if(!accountNo || !version)
        return;
    [self.db voidWriteTransaction:^{
        NSString* query = @"update account set rosterVersion=? where account_id=?";
        NSArray* params = @[version , accountNo];
        [self.db executeNonQuery:query  andArguments:params];
    }];
}

-(NSDictionary*) getSubscriptionForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    if(!contact || !accountNo)
        return nil;
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT subscription, ask from buddylist where buddy_name=? and account_id=?";
        NSArray* params = @[contact, accountNo];
        NSArray* version=[self.db executeReader:query andArguments:params];
        return version.firstObject;
    }];
}

-(void) setSubscription:(NSString *)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    if(!contact || !accountNo || !sub)
        return;
    [self.db voidWriteTransaction:^{
        NSString* query = @"update buddylist set subscription=?, ask=? where account_id=? and buddy_name=?";
        NSArray* params = @[sub, ask?ask:@"", accountNo, contact];
        [self.db executeNonQuery:query  andArguments:params];
    }];
}



#pragma mark Contact info

-(void) setFullName:(NSString*) fullName forContact:(NSString*) contact andAccount:(NSString*) accountNo
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

-(void) setAvatarHash:(NSString*) hash forContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE account SET iconhash=? WHERE account_id=? AND printf('%s@%s', username, domain)=?;" andArguments:@[hash, accountNo, contact]];
        [self.db executeNonQuery:@"UPDATE buddylist SET iconhash=? WHERE account_id=? AND buddy_name=?;" andArguments:@[hash, accountNo, contact]];
    }];
}

-(NSString*) getAvatarHashForContact:(NSString*) buddy andAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* hash = [self.db executeScalar:@"SELECT iconhash FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
        if(!hash)       //try to get the hash of our own account
            hash = [self.db executeScalar:@"SELECT iconhash FROM account WHERE account_id=? AND printf('%s@%s', username, domain)=?;" andArguments:@[accountNo, buddy]];
        return hash;
    }];
}

-(BOOL) isContactInList:(NSString*) buddy forAccount:(NSString*) accountNo
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

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo withComment:(NSString*) comment
{
    return [self.db boolWriteTransaction:^{
        return [self.db executeNonQuery:@"UPDATE buddylist SET messageDraft=? WHERE account_id=? AND buddy_name=?;" andArguments:@[comment, accountNo, buddy]];
    }];
}

-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT messageDraft FROM buddylist WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[accountNo, buddy];
        return [self.db executeScalar:query andArguments:params];
    }];
}

#pragma mark MUC

-(BOOL) initMuc:(NSString*) room forAccountId:(NSString*) accountNo andMucNick:(NSString* _Nullable) mucNick
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
        NSAssert(nick, @"Could not determine muc nick when adding muc");
        
        [self cleanupMembersAndParticipantsListFor:room forAccountId:accountNo];
        return [self.db executeNonQuery:@"INSERT INTO buddylist ('account_id', 'buddy_name', 'muc', 'muc_nick') VALUES(?, ?, 1, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET muc=1, muc_nick=?;" andArguments:@[accountNo, room, mucNick ? mucNick : @"", mucNick ? mucNick : @""]];
    }];
}

-(void) cleanupMembersAndParticipantsListFor:(NSString*) room forAccountId:(NSString*) accountNo
{
    //clean up old muc data (will be refilled by incoming presences and/or disco queries)
    [self.db executeNonQuery:@"DELETE FROM muc_participants WHERE account_id=? AND room=?;" andArguments:@[accountNo, room]];
    [self.db executeNonQuery:@"DELETE FROM muc_members WHERE account_id=? AND room=?;" andArguments:@[accountNo, room]];
}

-(void) addParticipant:(NSDictionary*) participant toMuc:(NSString*) room forAccountId:(NSString*) accountNo
{
    if(!participant || !participant[@"nick"] || !room || !accountNo)
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

-(void) removeParticipant:(NSDictionary*) participant fromMuc:(NSString*) room forAccountId:(NSString*) accountNo
{
    if(!participant || !participant[@"nick"] || !room || !accountNo)
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

-(void) removeMember:(NSDictionary*) member fromMuc:(NSString*) room forAccountId:(NSString*) accountNo
{
    if(!member || !member[@"jid"] || !room || !accountNo)
        return;
    
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DELETE FROM muc_members WHERE account_id=? AND room=? AND member_jid=?;" andArguments:@[accountNo, room, member[@"jid"]]];
    }];
}

-(NSString* _Nullable) getParticipantForNick:(NSString*) nick inRoom:(NSString*) room forAccountId:(NSString*) accountNo
{
    if(!nick || !room || !accountNo)
        return nil;
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT participant_jid FROM muc_participants WHERE account_id=? AND room=? AND room_nick=?;" andArguments:@[accountNo, room, nick]];
    }];
}

-(NSArray<NSDictionary<NSString*, id>*>*) getMembersAndParticipantsOfMuc:(NSString*) room forAccountId:(NSString*) accountNo
{
    if(!room || !accountNo)
        return [[NSMutableArray<NSDictionary<NSString*, id>*> alloc] init];
    return [self.db idReadTransaction:^{
        NSMutableArray<NSDictionary<NSString*, id>*>* toReturn = [[NSMutableArray<NSDictionary<NSString*, id>*> alloc] init];
        
        [toReturn addObjectsFromArray:[self.db executeReader:@"SELECT *, 1 as 'online' FROM muc_participants WHERE account_id=? AND room=?;" andArguments:@[accountNo, room]]];
        [toReturn addObjectsFromArray:[self.db executeReader:@"SELECT *, 0 as 'online' FROM muc_members WHERE account_id=? AND room=? AND NOT EXISTS(SELECT * FROM muc_participants WHERE muc_members.account_id=muc_participants.account_id AND muc_members.room=muc_participants.room AND muc_members.member_jid=muc_participants.participant_jid);" andArguments:@[accountNo, room]]];
        
        return toReturn;
    }];
}

-(void) addMucFavorite:(NSString*) room forAccountId:(NSString*) accountNo andMucNick:(NSString* _Nullable) mucNick
{
    [self.db voidWriteTransaction:^{
        NSString* nick = mucNick;
        if(!nick)
            nick = [self ownNickNameforMuc:room forAccount:accountNo];
        NSAssert(nick, @"Could not determine muc nick when adding muc");
        
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


-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo
{
    return [self.db boolReadTransaction:^{
        NSNumber* status = (NSNumber*)[self.db executeScalar:@"SELECT Muc FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
        if(status == nil)
            return NO;
        else
            return [status boolValue];
    }];
}

-(NSString* _Nullable) ownNickNameforMuc:(NSString*) room forAccount:(NSString*) accountNo
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

-(BOOL) updateOwnNickName:(NSString*) nick forMuc:(NSString*) room forAccount:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET muc_nick=? WHERE account_id=? AND buddy_name=? AND muc=1;";
        NSArray* params = @[nick, accountNo, room];
        DDLogVerbose(@"%@", query);

        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(BOOL) deleteMuc:(NSString*) room forAccountId:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"DELETE FROM muc_favorites WHERE room=? AND account_id=?;";
        NSArray* params = @[room, accountNo];
        DDLogVerbose(@"%@", query);

        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(NSMutableArray*) listMucsForAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        return [self.db executeReader:@"SELECT * FROM muc_favorites WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(BOOL) updateMucSubject:(NSString *) subject forAccount:(NSString*) accountNo andRoom:(NSString *) room
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET muc_subject=? WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[subject, accountNo, room];
        DDLogVerbose(@"%@", query);
        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(NSString*) mucSubjectforAccount:(NSString*) accountNo andRoom:(NSString*) room
{
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT muc_subject FROM buddylist WHERE account_id=? AND buddy_name=?;";

        NSArray* params = @[accountNo, room];
        DDLogVerbose(@"%@", query);

        return [self.db executeScalar:query andArguments:params];
    }];
}

-(void) updateMucTypeTo:(NSString*) type forRoom:(NSString*) room andAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET muc_type=? WHERE account_id=? AND buddy_name=?;" andArguments:@[type, accountNo, room]];
    }];
}

-(NSString*) getMucTypeOfRoom:(NSString*) room andAccount:(NSString*) accountNo
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

-(NSNumber*) addMessageToChatBuddy:(NSString*) buddyName withInboundDir:(BOOL) inbound forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom participantJid:(NSString*) participantJid sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString*) messageid serverMessageId:(NSString*) stanzaid messageType:(NSString*) messageType andOverrideDate:(NSDate*) messageDate encrypted:(BOOL) encrypted displayMarkerWanted:(BOOL) displayMarkerWanted usingHistoryId:(NSNumber* _Nullable) historyId checkForDuplicates:(BOOL) checkForDuplicates
{
    if(!buddyName || !message)
        return nil;
    
    return [self.db idWriteTransaction:^{
        if(!checkForDuplicates || ![self hasMessageForStanzaId:stanzaid orMessageID:messageid onChatBuddy:buddyName withInboundDir:inbound onAccount:accountNo])
        {
            //this is always from a contact
            NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
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

-(BOOL) hasMessageForStanzaId:(NSString*) stanzaId orMessageID:(NSString*) messageId onChatBuddy:(NSString*) buddyName withInboundDir:(BOOL) inbound onAccount:(NSString*) accountNo
{
    if(!accountNo)
        return NO;
    
    return [self.db boolWriteTransaction:^{
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
        
        //we check message ids per contact to increase uniqueness and abort here if no contact was provided
        if(!buddyName)
        {
            DDLogVerbose(@"no contact given --> message not found");
            return NO;
        }
        
        NSNumber* historyId = (NSNumber*)[self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND buddy_name=? AND inbound=? AND messageid=?;" andArguments:@[accountNo, buddyName, [NSNumber numberWithBool:inbound], messageId]];
        if(historyId != nil)
        {
            DDLogVerbose(@"found by origin-id or messageid");
            if(stanzaId)
            {
                DDLogDebug(@"Updating stanzaid of message_history_id %@ to %@ for (account=%@, messageid=%@, contact=%@, inbound=%d)...", historyId, stanzaId, accountNo, messageId, buddyName, inbound);
                //this entry needs an update of its stanzaid
                [self.db executeNonQuery:@"UPDATE message_history SET stanzaid=? WHERE message_history_id=?" andArguments:@[stanzaId, historyId]];
            }
            return YES;
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

-(void) setMessageId:( NSString* _Nonnull ) messageid received:(BOOL) received
{
    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE message_history SET received=?, sent=? WHERE messageid=?;";
        DDLogVerbose(@"setting received confrmed %@", messageid);
        [self.db executeNonQuery:query andArguments:@[[NSNumber numberWithBool:received], [NSNumber numberWithBool:YES], messageid]];
    }];
}

-(void) setMessageId:( NSString* _Nonnull ) messageid errorType:( NSString* _Nonnull ) errorType errorReason:( NSString* _Nonnull ) errorReason
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

-(void) clearMessages:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=?;" andArguments:@[kMessageTypeFiletransfer, accountNo]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=?;" andArguments:@[accountNo]];
        
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(void) deleteMessageHistory:(NSNumber*) messageNo
{
    [self.db voidWriteTransaction:^{
        MLMessage* msg = [self messageForHistoryID:messageNo];
        if([msg.messageType isEqualToString:kMessageTypeFiletransfer])
            [MLFiletransfer deleteFileForMessage:msg];
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE message_history_id=?;" andArguments:@[messageNo]];
    }];
}

-(void) updateMessageHistory:(NSNumber*) messageNo withText:(NSString*) newText
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE message_history SET message=? WHERE message_history_id=?;" andArguments:@[newText, messageNo]];
    }];
}

-(NSNumber*) getHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from andAccount:(NSString*) accountNo
{
    return [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT M.message_history_id FROM message_history AS M INNER JOIN account AS A ON M.account_id=A.account_id WHERE messageid=? AND ((M.buddy_name=? AND M.inbound=1) OR ((A.username || '@' || A.domain)=? AND M.inbound=0)) AND M.account_id=?;" andArguments:@[messageid, from, from, accountNo]];
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

-(BOOL) messageHistoryClean:(NSString*) buddy forAccount:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=? AND buddy_name=?;" andArguments:@[kMessageTypeFiletransfer, accountNo, buddy]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];
        return [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
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
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo
{
    if(!accountNo || !buddy)
        return nil;
    return [self.db idReadTransaction:^{
        NSNumber* lastMsgHistID = [self lastMessageHistoryIdForContact:buddy forAccount:accountNo];
        // Increment msgHistId -> all messages <= msgHistId are feteched
        lastMsgHistID = [NSNumber numberWithInt:[lastMsgHistID intValue] + 1];
        return [self messagesForContact:buddy forAccount:accountNo beforeMsgHistoryID:lastMsgHistID];
    }];
}

//message history
-(NSMutableArray<MLMessage*>*) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo beforeMsgHistoryID:(NSNumber* _Nullable) msgHistoryID
{
    if(!accountNo || !buddy)
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
                [self.db executeNonQuery:@"UPDATE message_history SET unread=0 WHERE message_history_id=?;" andArguments:@[historyIDEntry]];
        }
        
        //return NSArray of all updated MLMessages
        return (NSArray*)[self messagesForHistoryIDs:messageArray];
    }];
}

-(NSNumber*) addMessageHistoryTo:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString*) messageId encrypted:(BOOL) encrypted messageType:(NSString*) messageType mimeType:(NSString*) mimeType size:(NSNumber*) size
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
        // count # of msgs in message table
        return [self.db executeScalar:@"SELECT COUNT(M.message_history_id) FROM message_history AS M INNER JOIN buddylist AS B ON M.account_id=B.account_id AND M.buddy_name=B.buddy_name WHERE M.unread=1 AND M.inbound=1 AND B.muted=0;"];
    }];
}

//set all unread messages to read
-(void) setAllMessagesAsRead
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE message_history SET unread=0 WHERE unread=1;"];
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
        NSString* query = @"SELECT a.buddy_name, a.account_id FROM activechats AS a JOIN buddylist AS b ON (a.buddy_name = b.buddy_name AND a.account_id = b.account_id) JOIN account ON a.account_id = account.account_id WHERE (account.username || '@' || account.domain) != a.buddy_name AND a.pinned=? ORDER BY lastMessageTime DESC;";
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
        //remove contact from active chats list
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE buddy_name=? AND account_id=?;" andArguments:@[buddyname, accountNo]];
    }];
}

-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    if(!buddyname || !accountNo)
        return;
    
    [self.db voidWriteTransaction:^{
        NSString* accountJid = [self jidOfAccount:accountNo];
        if(!accountJid)
            return;
#ifdef DEBUG
        MLAssert(![accountJid isEqualToString:buddyname], @"We should never try to create a chat with our own jid", (@{
            @"buddyname": buddyname,
            @"accountNo": accountNo,
            @"accountJid": accountJid
        }));
#endif
        if([accountJid isEqualToString:buddyname])
        {
            // Something is broken
            DDLogWarn(@"We should never try to create a chat with our own jid");
            return;
        }
        else
        {
            //add contact if possible (ignore already existing contacts)
            [self addContact:buddyname forAccount:accountNo nickname:nil andMucNick:nil];
            
            // insert or update
            NSString* query = @"INSERT INTO activechats (buddy_name, account_id, lastMessageTime) VALUES(?, ?, current_timestamp) ON CONFLICT(buddy_name, account_id) DO UPDATE SET lastMessageTime=current_timestamp;";
            [self.db executeNonQuery:query andArguments:@[buddyname, accountNo]];
            return;
        }
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

-(BOOL) updateActiveBuddy:(NSString*) buddyname setTime:(NSString*) timestamp forAccount:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"SELECT lastMessageTime FROM activechats WHERE account_id=? AND buddy_name=?;";
        NSObject* result = [self.db executeScalar:query andArguments:@[accountNo, buddyname]];
        NSString* lastTime = (NSString *) result;

        NSDate* lastDate = [dbFormatter dateFromString:lastTime];
        NSDate* newDate = [dbFormatter dateFromString:timestamp];

        if(lastDate.timeIntervalSince1970<newDate.timeIntervalSince1970)
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

-(NSNumber*) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo
{
    if(!buddy || !accountNo)
        return @0;
    return [self.db idReadTransaction:^{
        // count # messages from a specific user in messages table
        return [self.db executeScalar:@"SELECT COUNT(message_history_id) FROM message_history WHERE unread=1 AND account_id=? AND buddy_name=? AND inbound=1;" andArguments:@[accountNo, buddy]];
    }];
}

#pragma db Commands

-(BOOL) updateDBTo:(double) version withBlock:(monal_void_block_t) block
{
    static BOOL accountStateInvalidated = NO;
    if([(NSNumber*)[self.db executeScalar:@"SELECT dbversion FROM dbversion;"] doubleValue] < version)
    {
        DDLogVerbose(@"Database version <%@ detected. Performing upgrade.", [NSNumber numberWithDouble:version]);
        block();
        if(!accountStateInvalidated)
            [self invalidateAllAccountStates];
        accountStateInvalidated = YES;
        [self.db executeNonQuery:@"UPDATE dbversion SET dbversion=?;" andArguments:@[[NSNumber numberWithDouble:version]]];
        DDLogDebug(@"Upgrade to %@ success", [NSNumber numberWithDouble:version]);
        return YES;
    }
    return NO;
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
    
    //update db in one single write transaction
    __block NSNumber* dbversion = nil;
    [self.db voidWriteTransaction:^{
        dbversion = (NSNumber*)[self.db executeScalar:@"SELECT dbversion FROM dbversion;"];
        DDLogInfo(@"Got db version %@", dbversion);

        [self updateDBTo:2.0 withBlock:^{
            [self.db executeNonQuery:@"drop table muc_favorites"];
            [self.db executeNonQuery:@"CREATE TABLE IF NOT EXISTS \"muc_favorites\" (\"mucid\" integer NOT NULL primary key autoincrement,\"room\" varchar(255,0),\"nick\" varchar(255,0),\"autojoin\" bool, account_id int);"];
        }];

        [self updateDBTo:2.1 withBlock:^{
            [self.db executeNonQuery:@"alter table message_history add column received bool;"];
        }];

        [self updateDBTo:2.2 withBlock:^{
            [self.db executeNonQuery:@"alter table buddylist add column synchPoint datetime;"];
        }];

        [self updateDBTo:2.3 withBlock:^{
            [self.db executeNonQuery:@"UPDATE account SET resource=?;" andArguments:@[[HelperTools encodeRandomResource]]];
        }];

        //OMEMO begins below
        [self updateDBTo:3.1 withBlock:^{
            [self.db executeNonQuery:@"CREATE TABLE signalIdentity (deviceid int NOT NULL PRIMARY KEY, account_id int NOT NULL unique,identityPublicKey BLOB,identityPrivateKey BLOB)"];
            [self.db executeNonQuery:@"CREATE TABLE signalSignedPreKey (account_id int NOT NULL,signedPreKeyId int not null,signedPreKey BLOB);"];

            [self.db executeNonQuery:@"CREATE TABLE signalPreKey (account_id int NOT NULL,prekeyid int not null,preKey BLOB);"];

            [self.db executeNonQuery:@"CREATE TABLE signalContactIdentity ( account_id int NOT NULL,contactName text,contactDeviceId int not null,identity BLOB,trusted boolean);"];

            [self.db executeNonQuery:@"CREATE TABLE signalContactKey (account_id int NOT NULL,contactName text,contactDeviceId int not null, groupId text,senderKey BLOB);"];

            [self.db executeNonQuery:@"  CREATE TABLE signalContactSession (account_id int NOT NULL, contactName text, contactDeviceId int not null, recordData BLOB)"];
            [self.db executeNonQuery:@"alter table message_history add column encrypted bool;"];

            [self.db executeNonQuery:@"alter table message_history add column previewText text;"];
            [self.db executeNonQuery:@"alter table message_history add column previewImage text;"];

            [self.db executeNonQuery:@"alter table buddylist add column backgroundImage text;"];
        }];


        [self updateDBTo:3.2 withBlock:^{
            [self.db executeNonQuery:@"CREATE TABLE muteList (jid varchar(50));"];
            [self.db executeNonQuery:@"CREATE TABLE blockList (jid varchar(50));"];
        }];

        [self updateDBTo:3.3 withBlock:^{
            [self.db executeNonQuery:@"alter table buddylist add column encrypt bool;"];
        }];

        [self updateDBTo:3.4 withBlock:^{
            [self.db executeNonQuery:@"alter table activechats add COLUMN lastMessageTime datetime "];

            //iterate current active and set their times
            NSArray* active = [self.db executeReader:@"select distinct buddy_name, account_id from activeChats"];
            [active enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSDictionary* row = (NSDictionary*)obj;
                //get max
                NSNumber* max = (NSNumber *)[self.db executeScalar:@"select max(TIMESTAMP) from message_history where (message_to=? or message_from=?) and account_id=?" andArguments:@[[row objectForKey:@"buddy_name"],[row objectForKey:@"buddy_name"], [row objectForKey:@"account_id"]]];
                if(max != nil) {
                    [self.db executeNonQuery:@"update activechats set lastMessageTime=? where buddy_name=? and account_id=?" andArguments:@[max,[row objectForKey:@"buddy_name"], [row objectForKey:@"account_id"]]];
                } else  {

                }
            }];
        }];

        [self updateDBTo:3.5 withBlock:^{
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX uniqueContact on buddylist (buddy_name, account_id);"];
            [self.db executeNonQuery:@"delete from buddy_resources"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX uniqueResource on buddy_resources (buddy_id, resource);"];
        }];


        [self updateDBTo:3.6 withBlock:^{
            [self.db executeNonQuery:@"CREATE TABLE imageCache (url varchar(255), path varchar(255) );"];
        }];

        [self updateDBTo:3.7 withBlock:^{
            [self.db executeNonQuery:@"alter table message_history add column stanzaid text;"];
        }];

        [self updateDBTo:3.8 withBlock:^{
            [self.db executeNonQuery:@"alter table account add column airdrop bool;"];
        }];

        [self updateDBTo:3.9 withBlock:^{
            [self.db executeNonQuery:@"alter table account add column rosterVersion varchar(50);"];
        }];

        [self updateDBTo:4.0 withBlock:^{
            [self.db executeNonQuery:@"alter table message_history add column errorType varchar(50);"];
            [self.db executeNonQuery:@"alter table message_history add column errorReason varchar(50);"];
        }];

        [self updateDBTo:4.1 withBlock:^{
            [self.db executeNonQuery:@"CREATE TABLE subscriptionRequests(requestid integer not null primary key AUTOINCREMENT,account_id integer not null,buddy_name varchar(50) collate nocase, UNIQUE(account_id,buddy_name))"];
        }];

        [self updateDBTo:4.2 withBlock:^{
            NSArray* contacts = [self.db executeReader:@"select distinct account_id, buddy_name, lastMessageTime from activechats;"];
            [self.db executeNonQuery:@"delete from activechats;"];
            [contacts enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                [self.db executeNonQuery:@"insert into activechats (account_id, buddy_name, lastMessageTime) values (?,?,?);"
                        andArguments:@[
                        [obj objectForKey:@"account_id"],
                        [obj objectForKey:@"buddy_name"],
                        [obj objectForKey:@"lastMessageTime"]
                        ]];
            }];
            NSArray *dupeMessageids= [self.db executeReader:@"select * from (select messageid, count(messageid) as c from message_history   group by messageid) where c>1"];

            [dupeMessageids enumerateObjectsUsingBlock:^(NSDictionary *  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    NSArray* dupeMessages = [self.db executeReader:@"select * from message_history where messageid=? order by message_history_id asc " andArguments:@[[obj objectForKey:@"messageid"]]];
                //hopefully this is quick and doesnt grow..
                [dupeMessages enumerateObjectsUsingBlock:^(NSDictionary *  _Nonnull message, NSUInteger idx, BOOL * _Nonnull stop) {
                    //keep first one
                    if(idx > 0) {
                        [self.db executeNonQuery:@"delete from message_history where message_history_id=?" andArguments:@[[message objectForKey:@"message_history_id"]]];
                    }
                }];
            }];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX ux_account_messageid ON message_history(account_id, messageid)"];

            [self.db executeNonQuery:@"alter table activechats add column lastMesssage blob;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX ux_account_buddy ON activechats(account_id, buddy_name)"];
        }];

        [self updateDBTo:4.3 withBlock:^{

            [self.db executeNonQuery:@"alter table buddylist add column subscription varchar(50)"];
            [self.db executeNonQuery:@"alter table buddylist add column ask varchar(50)"];
        }];

        [self updateDBTo:4.4 withBlock:^{

            [self.db executeNonQuery:@"update account set rosterVersion='0';"];
        }];

        [self updateDBTo:4.5 withBlock:^{

            [self.db executeNonQuery:@"alter table account add column state blob;"];
        }];

        [self updateDBTo:4.6 withBlock:^{

            [self.db executeNonQuery:@"alter table buddylist add column messageDraft text;"];
        }];

        [self updateDBTo:4.7 withBlock:^{

            // Delete column password,account_name from account, set default value for rosterVersion to 0, increased varchar size
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'protocol_id' integer NOT NULL, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"UPDATE account SET rosterVersion='0' WHERE rosterVersion is NULL;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];

        [self updateDBTo:4.71 withBlock:^{

            // Only reset server to '' when server == domain
            [self.db executeNonQuery:@"UPDATE account SET server='' where server=domain;"];
        }];
        
        [self updateDBTo:4.72 withBlock:^{

            // Delete column protocol_id from account and drop protocol table
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE protocol;"];
        }];
        
        [self updateDBTo:4.73 withBlock:^{

            // Delete column oauth from account
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];
        
        [self updateDBTo:4.74 withBlock:^{
            // Rename column oldstyleSSL to directTLS
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];
        
        [self updateDBTo:4.75 withBlock:^{
            // Delete column secure from account
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];
        
        [self updateDBTo:4.76 withBlock:^{
            // Add column for the last interaction of a contact
            [self.db executeNonQuery:@"alter table buddylist add column lastInteraction INTEGER NOT NULL DEFAULT 0;"];
        }];
        
        [self updateDBTo:4.77 withBlock:^{
            // drop legacy caps tables
            [self.db executeNonQuery:@"DROP TABLE IF EXISTS legacy_caps;"];
            [self.db executeNonQuery:@"DROP TABLE IF EXISTS buddy_resources_legacy_caps;"];
            //recreate capabilities cache to make a fresh start
            [self.db executeNonQuery:@"DROP TABLE IF EXISTS ver_info;"];
            [self.db executeNonQuery:@"CREATE TABLE ver_info(ver VARCHAR(32), cap VARCHAR(255), PRIMARY KEY (ver,cap));"];
            [self.db executeNonQuery:@"CREATE TABLE ver_timestamp (ver VARCHAR(32), timestamp INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (ver));"];
            [self.db executeNonQuery:@"CREATE INDEX timeindex ON ver_timestamp(timestamp);" ];
        }];
        
        [self updateDBTo:4.78 withBlock:^{
            // drop airdrop column
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];
        
        [self updateDBTo:4.80 withBlock:^{
            [self.db executeNonQuery:@"CREATE TABLE ipc(id integer NOT NULL PRIMARY KEY AUTOINCREMENT, name VARCHAR(255), destination VARCHAR(255), data BLOB, timeout INTEGER NOT NULL DEFAULT 0);"];
        }];
        
        [self updateDBTo:4.81 withBlock:^{
            // Remove silly chats
            NSMutableArray* results = [self.db executeReader:@"select account_id, username, domain from account"];
            for(NSDictionary* row in results) {
                NSString* accountJid = [NSString stringWithFormat:@"%@@%@", [row objectForKey:kUsername], [row objectForKey:kDomain]];
                NSString* accountNo = [row objectForKey:kAccountID];

                // delete chats with accountJid == buddy_name
                [self.db executeNonQuery:@"delete from activechats where account_id=? and buddy_name=?" andArguments:@[accountNo, accountJid]];
            }
        }];
        
        [self updateDBTo:4.82 withBlock:^{
            //use the more appropriate name "sent" for the "delivered" column of message_history
            [self.db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'message_history' (message_history_id integer not null primary key AUTOINCREMENT, account_id integer, message_from text collate nocase, message_to text collate nocase, timestamp datetime, message blob, actual_from text collate nocase, messageid text, messageType text, sent bool, received bool, unread bool, encrypted bool, previewText text, previewImage text, stanzaid text, errorType text, errorReason text);"];
            [self.db executeNonQuery:@"INSERT INTO message_history (message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, sent, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason) SELECT message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, delivered, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason from _message_historyTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
        }];
        
        [self updateDBTo:4.83 withBlock:^{
            [self.db executeNonQuery:@"alter table activechats add column pinned bool DEFAULT FALSE;"];
        }];
        
        [self updateDBTo:4.84 withBlock:^{
            [self.db executeNonQuery:@"DROP TABLE IF EXISTS ipc;"];
            //remove synchPoint from db
            [self.db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50), nick_name varchar(50), group_name varchar(50), iconhash varchar(200), filename varchar(100), state varchar(20), status varchar(200), online bool, dirty bool, new bool, Muc bool, muc_subject varchar(255), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0);"];
            [self.db executeNonQuery:@"INSERT INTO buddylist (buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, online, dirty, new, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction) SELECT buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, online, dirty, new, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction FROM _buddylistTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact on buddylist(buddy_name, account_id);"];
            //make stanzaid, messageid and errorType caseinsensitive and create indixes for stanzaid and messageid
            [self.db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE message_history (message_history_id integer not null primary key AUTOINCREMENT, account_id integer, message_from text collate nocase, message_to text collate nocase, timestamp datetime, message blob, actual_from text collate nocase, messageid text collate nocase, messageType text, sent bool, received bool, unread bool, encrypted bool, previewText text, previewImage text, stanzaid text collate nocase, errorType text collate nocase, errorReason text);"];
            [self.db executeNonQuery:@"INSERT INTO message_history (message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, sent, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason) SELECT message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, sent, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason FROM _message_historyTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
            [self.db executeNonQuery:@"CREATE INDEX stanzaidIndex on message_history(stanzaid collate nocase);"];
            [self.db executeNonQuery:@"CREATE INDEX messageidIndex on message_history(messageid collate nocase);"];
        }];
        
        [self updateDBTo:4.85 withBlock:^{
            //Performing upgrade on buddy_resources.
            [self.db executeNonQuery:@"ALTER TABLE buddy_resources ADD platform_App_Name text;"];
            [self.db executeNonQuery:@"ALTER TABLE buddy_resources ADD platform_App_Version text;"];
            [self.db executeNonQuery:@"ALTER TABLE buddy_resources ADD platform_OS text;"];

            //drop and recreate in 4.77 was faulty (wrong drop syntax), do it right this time
            [self.db executeNonQuery:@"DROP TABLE IF EXISTS ver_info;"];
            [self.db executeNonQuery:@"CREATE TABLE ver_info(ver VARCHAR(32), cap VARCHAR(255), PRIMARY KEY (ver,cap));"];
        }];
        
        [self updateDBTo:4.86 withBlock:^{
            //add new stanzaid field to account table that always points to the last received stanzaid (even if that does not have a body)
            [self.db executeNonQuery:@"ALTER TABLE account ADD lastStanzaId text;"];
        }];
        
        [self updateDBTo:4.87 withBlock:^{
            //populate new stanzaid field in account table from message_history table
            NSString* stanzaId = (NSString*)[self.db executeScalar:@"SELECT stanzaid FROM message_history WHERE stanzaid!='' ORDER BY message_history_id DESC LIMIT 1;"];
            DDLogVerbose(@"Populating lastStanzaId with id %@ from history table", stanzaId);
            if(stanzaId && [stanzaId length])
                [self.db executeNonQuery:@"UPDATE account SET lastStanzaId=?;" andArguments:@[stanzaId]];
            //remove all old and most probably *wrong* stanzaids from history table
            [self.db executeNonQuery:@"UPDATE message_history SET stanzaid='';"];
        }];

        [self updateDBTo:4.9 withBlock:^{
            // add timestamps to omemo prekeys
            [self.db executeNonQuery:@"ALTER TABLE signalPreKey RENAME TO _signalPreKeyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'signalPreKey' ('account_id' int NOT NULL, 'prekeyid' int NOT NULL, 'preKey' BLOB, 'creationTimestamp' INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, 'pubSubRemovalTimestamp' INTEGER DEFAULT NULL, 'keyUsed' INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (account_id, prekeyid, preKey));"];
            [self.db executeNonQuery:@"INSERT INTO signalPreKey (account_id, prekeyid, preKey) SELECT account_id, prekeyid, preKey FROM _signalPreKeyTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _signalPreKeyTMP;"];
        }];
        
        [self updateDBTo:4.91 withBlock:^{
            //not needed anymore (better handled by 4.97)
        }];
        
        [self updateDBTo:4.92 withBlock:^{
            //add displayed and displayMarkerWanted fields
            [self.db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN displayed BOOL DEFAULT FALSE;"];
            [self.db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN displayMarkerWanted BOOL DEFAULT FALSE;"];
        }];
        
        [self updateDBTo:4.93 withBlock:^{
            //full_name should not be buddy_name anymore, but the user provided XEP-0172 nickname
            //and nick_name will be the roster name, if given
            //if none of these two are given, the local part of the jid (called node in prosody and in jidSplit:) will be used, like in other clients
            //see also https://docs.modernxmpp.org/client/design/#contexts
            [self.db executeNonQuery:@"UPDATE buddylist SET full_name='' WHERE full_name=buddy_name;"];
            [self.db executeNonQuery:@"UPDATE account SET rosterVersion=?;" andArguments:@[@""]];
        }];
        
        [self updateDBTo:4.94 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE account ADD COLUMN rosterName TEXT;"];
        }];
        
        [self updateDBTo:4.95 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE account ADD COLUMN iconhash VARCHAR(200);"];
        }];
        
        [self updateDBTo:4.96 withBlock:^{
            //not needed anymore (better handled by 4.97)
        }];
        
        [self updateDBTo:4.97 withBlock:^{
            [self invalidateAllAccountStates];
        }];
        
        [self updateDBTo:4.98 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN filetransferMimeType VARCHAR(32) DEFAULT 'application/octet-stream';"];
            [self.db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN filetransferSize INTEGER DEFAULT 0;"];
        }];

        [self updateDBTo:4.990 withBlock:^{
            // remove dupl entries from activechats && budylist
            [self.db executeNonQuery:@"DELETE FROM activechats \
                WHERE ROWID NOT IN \
                    (SELECT tmpID FROM \
                        (SELECT ROWID as tmpID, account_id, buddy_name FROM activechats WHERE \
                        ROWID IN \
                            (SELECT ROWID FROM activechats ORDER BY lastMessageTime DESC) \
                        GROUP BY account_id, buddy_name) \
                    )"];
            [self.db executeNonQuery:@"DELETE FROM buddylist WHERE ROWID NOT IN \
                    (SELECT tmpID FROM \
                        (SELECT ROWID as tmpID, account_id, buddy_name FROM buddylist GROUP BY account_id, buddy_name) \
                    )"];
        }];
        
        [self updateDBTo:4.991 withBlock:^{
            //remove dirty, online, new from db
            [self.db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50), nick_name varchar(50), group_name varchar(50), iconhash varchar(200), filename varchar(100), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(255), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0);"];
            [self.db executeNonQuery:@"INSERT INTO buddylist (buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction) SELECT buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction FROM _buddylistTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact on buddylist(buddy_name, account_id);"];
        }];
        
        [self updateDBTo:4.992 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE account ADD COLUMN statusMessage TEXT;"];
        }];
        
        [self updateDBTo:4.993 withBlock:^{
            //make filetransferMimeType and filetransferSize have NULL as default value
            //(this makes it possible to distinguish unknown values from known ones)
            [self.db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE message_history (message_history_id integer not null primary key AUTOINCREMENT, account_id integer, message_from text collate nocase, message_to text collate nocase, timestamp datetime, message blob, actual_from text collate nocase, messageid text collate nocase, messageType text, sent bool, received bool, unread bool, encrypted bool, previewText text, previewImage text, stanzaid text collate nocase, errorType text collate nocase, errorReason text, displayed BOOL DEFAULT FALSE, displayMarkerWanted BOOL DEFAULT FALSE, filetransferMimeType VARCHAR(32) DEFAULT NULL, filetransferSize INTEGER DEFAULT NULL);"];
            [self.db executeNonQuery:@"INSERT INTO message_history SELECT * FROM _message_historyTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
            [self.db executeNonQuery:@"CREATE INDEX stanzaidIndex on message_history(stanzaid collate nocase);"];
            [self.db executeNonQuery:@"CREATE INDEX messageidIndex on message_history(messageid collate nocase);"];
        }];

        // skipping 4.994 due to invalid command

        [self updateDBTo:4.995 withBlock:^{
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueActiveChat ON activechats(buddy_name, account_id);"];
        }];

        [self updateDBTo:4.996 withBlock:^{
            //remove all icon hashes to reload all icons on next app/nse start
            //(the db upgrade mechanism will make sure that no smacks resume will take place and pep pushes come in for all avatars)
            [self.db executeNonQuery:@"UPDATE account SET iconhash='';"];
            [self.db executeNonQuery:@"UPDATE buddylist SET iconhash='';"];
        }];
        
        [self updateDBTo:4.997 withBlock:^{
            //create unique constraint for (account_id, buddy_name) on activechats table
            [self.db executeNonQuery:@"ALTER TABLE activechats RENAME TO _activechatsTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE activechats (account_id integer not null, buddy_name varchar(50) collate nocase, lastMessageTime datetime, lastMesssage blob, pinned bool DEFAULT FALSE, UNIQUE(account_id, buddy_name));"];
            [self.db executeNonQuery:@"INSERT INTO activechats SELECT * FROM _activechatsTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _activechatsTMP;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueActiveChat ON activechats(buddy_name, account_id);"];
            
            //create unique constraint for (buddy_name, account_id) on buddylist table
            [self.db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50), nick_name varchar(50), group_name varchar(50), iconhash varchar(200), filename varchar(100), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(255), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0, UNIQUE(account_id, buddy_name));"];
            [self.db executeNonQuery:@"INSERT INTO buddylist SELECT * FROM _buddylistTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact on buddylist(buddy_name, account_id);"];
        }];

        [self updateDBTo:5.000 withBlock:^{
            // cleanup omemo tables
            [self.db executeNonQuery:@"DELETE FROM signalContactIdentity WHERE account_id NOT IN (SELECT account_id FROM account);"];
            [self.db executeNonQuery:@"DELETE FROM signalContactKey WHERE account_id NOT IN (SELECT account_id FROM account);"];
            [self.db executeNonQuery:@"DELETE FROM signalIdentity WHERE account_id NOT IN (SELECT account_id FROM account);"];
            [self.db executeNonQuery:@"DELETE FROM signalPreKey WHERE account_id NOT IN (SELECT account_id FROM account);"];
            [self.db executeNonQuery:@"DELETE FROM signalSignedPreKey WHERE account_id NOT IN (SELECT account_id FROM account);"];
        }];
        
        [self updateDBTo:5.001 withBlock:^{
            //do this in 5.0 branch as well
            
            //create unique constraint for (account_id, buddy_name) on activechats table
            [self.db executeNonQuery:@"ALTER TABLE activechats RENAME TO _activechatsTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE activechats (account_id integer not null, buddy_name varchar(50) collate nocase, lastMessageTime datetime, lastMesssage blob, pinned bool DEFAULT FALSE, UNIQUE(account_id, buddy_name));"];
            [self.db executeNonQuery:@"INSERT INTO activechats SELECT * FROM _activechatsTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _activechatsTMP;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueActiveChat ON activechats(buddy_name, account_id);"];
            
            //create unique constraint for (buddy_name, account_id) on buddylist table
            [self.db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50), nick_name varchar(50), group_name varchar(50), iconhash varchar(200), filename varchar(100), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(255), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0, UNIQUE(account_id, buddy_name));"];
            [self.db executeNonQuery:@"INSERT INTO buddylist SELECT * FROM _buddylistTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact on buddylist(buddy_name, account_id);"];
        }];

        [self updateDBTo:5.002 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE buddylist ADD COLUMN blocked BOOL DEFAULT FALSE;"];
            [self.db executeNonQuery:@"DROP TABLE blockList;"];
        }];

        [self updateDBTo:5.003 withBlock:^{
            [self.db executeNonQuery:@"CREATE TABLE 'blocklistCache' (\
                'account_id' TEXT NOT NULL, \
                'node' TEXT, \
                'host' TEXT, \
                'resource' TEXT, \
                UNIQUE('account_id','node','host','resource'), \
                CHECK( \
                (LENGTH('node') > 0 AND LENGTH('host') > 0 AND LENGTH('resource') > 0) \
                OR \
                (LENGTH('node') > 0 AND LENGTH('host') > 0) \
                OR \
                (LENGTH('host') > 0 AND LENGTH('resource') > 0) \
                OR \
                (LENGTH('host') > 0) \
                ), \
                FOREIGN KEY('account_id') REFERENCES 'account'('account_id') \
            );"];
        }];
        
        /*
         * OMEMO trust levels:
         * 0: no trust
         * 1: ToFU
         * 2: trust
         */
        [self updateDBTo:5.004 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE signalContactIdentity RENAME TO _signalContactIdentityTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'signalContactIdentity' ( \
                 'account_id' INTEGER NOT NULL, \
                 'contactName' TEXT NOT NULL, \
                 'contactDeviceId' INTEGER NOT NULL, \
                 'identity' BLOB, \
                 'lastReceivedMsg' INTEGER DEFAULT NULL, \
                 'removedFromDeviceList' INTEGER DEFAULT NULL, \
                 'trustLevel' INTEGER NOT NULL DEFAULT 1, \
                 FOREIGN KEY('contactName') REFERENCES 'buddylist'('buddy_name'), \
                 PRIMARY KEY('account_id', 'contactName', 'contactDeviceId'), \
                 FOREIGN KEY('account_id') REFERENCES 'account'('account_id') \
             );"];
            [self.db executeNonQuery:@"INSERT INTO signalContactIdentity \
                ( \
                    account_id, contactName, contactDeviceId, identity, trustLevel \
                ) \
                SELECT \
                    account_id, contactName, contactDeviceId, identity, \
                    CASE \
                        WHEN trusted=1 THEN 1 \
                        ELSE 0 \
                    END \
                FROM _signalContactIdentityTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _signalContactIdentityTMP;"];
        }];
        
        [self updateDBTo:5.005 withBlock:^{
            //remove group_name and filename columns from buddylist, resize buddy_name, full_name, nick_name and muc_subject columns and add lastStanzaId column (only used for mucs)
            [self.db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(255) collate nocase, full_name varchar(255), nick_name varchar(255), iconhash varchar(200), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(1024), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0, blocked BOOL DEFAULT FALSE, muc_type VARCHAR(10) DEFAULT 'channel', lastMucStanzaId text DEFAULT NULL, UNIQUE(account_id, buddy_name));"];
            [self.db executeNonQuery:@"INSERT INTO buddylist SELECT buddy_id, account_id, buddy_name, full_name, nick_name, iconhash, state, status, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction, blocked, 'channel', NULL FROM _buddylistTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact ON buddylist(buddy_name, account_id);"];
            [self.db executeNonQuery:@"UPDATE buddylist SET muc_type='channel' WHERE Muc = true;"];     //muc default type
            
            //create new muc favorites table
            [self.db executeNonQuery:@"DROP TABLE muc_favorites;"];
            [self.db executeNonQuery:@"CREATE TABLE muc_favorites (room VARCHAR(255) PRIMARY KEY, nick varchar(255), account_id INTEGER, UNIQUE(room, account_id));"];
        }];
        
        [self updateDBTo:5.006 withBlock:^{
            // recreate blocklistCache - fixes foreign key
            [self.db executeNonQuery:@"ALTER TABLE blocklistCache RENAME TO _blocklistCacheTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'blocklistCache' (\
                'account_id' TEXT NOT NULL, \
                'node' TEXT, \
                'host' TEXT, \
                'resource' TEXT, \
                UNIQUE('account_id','node','host','resource'), \
                CHECK( \
                (LENGTH('node') > 0 AND LENGTH('host') > 0 AND LENGTH('resource') > 0) \
                OR \
                (LENGTH('node') > 0 AND LENGTH('host') > 0) \
                OR \
                (LENGTH('host') > 0 AND LENGTH('resource') > 0) \
                OR \
                (LENGTH('host') > 0) \
                ), \
                FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE \
            );"];
            [self.db executeNonQuery:@"DELETE FROM _blocklistCacheTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [self.db executeNonQuery:@"INSERT INTO blocklistCache SELECT * FROM _blocklistCacheTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _blocklistCacheTMP;"];

            // recreate signalContactIdentity - fixes foreign key
            [self.db executeNonQuery:@"ALTER TABLE signalContactIdentity RENAME TO _signalContactIdentityTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'signalContactIdentity' ( \
                 'account_id' INTEGER NOT NULL, \
                 'contactName' TEXT NOT NULL, \
                 'contactDeviceId' INTEGER NOT NULL, \
                 'identity' BLOB, \
                 'lastReceivedMsg' INTEGER DEFAULT NULL, \
                 'removedFromDeviceList' INTEGER DEFAULT NULL, \
                 'trustLevel' INTEGER NOT NULL DEFAULT 1, \
                 FOREIGN KEY('account_id','contactName') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE, \
                 PRIMARY KEY('account_id', 'contactName', 'contactDeviceId'), \
                 FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE \
             );"];
            [self.db executeNonQuery:@"DELETE FROM _signalContactIdentityTMP WHERE account_id NOT IN (SELECT account_id FROM account) OR (account_id, contactName) NOT IN (SELECT account_id, buddy_name FROM buddylist);"];
            [self.db executeNonQuery:@"INSERT INTO signalContactIdentity SELECT * FROM _signalContactIdentityTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _signalContactIdentityTMP;"];
            // add self chats for omemo
            [self.db executeNonQuery:@"INSERT OR IGNORE INTO buddylist ('account_id', 'buddy_name', 'muc') SELECT account_id, (username || '@' || domain), 0 FROM account;"];
        }];

        [self updateDBTo:5.007 withBlock:^{
            // remove broken omemo sessions
            [self.db executeNonQuery:@"DELETE FROM signalContactIdentity WHERE (account_id, contactName) NOT IN (SELECT account_id, contactName FROM signalContactSession);"];
            [self.db executeNonQuery:@"DELETE FROM signalContactSession WHERE (account_id, contactName) NOT IN (SELECT account_id, contactName FROM signalContactIdentity);"];
        }];

        [self updateDBTo:5.008 withBlock:^{
            [self.db executeNonQuery:@"DROP TABLE muc_favorites;"];
            [self.db executeNonQuery:@"CREATE TABLE 'muc_favorites' ( \
                 'account_id' INTEGER NOT NULL, \
                 'room' VARCHAR(255) NOT NULL, \
                 'nick' varchar(255), \
                 'autojoin' BOOL NOT NULL DEFAULT 0, \
                 FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                 UNIQUE('room', 'account_id'), \
                 PRIMARY KEY('account_id', 'room') \
             );"];
        }];

        [self updateDBTo:5.009 withBlock:^{
            // add foreign key to signalContactSession
            [self.db executeNonQuery:@"ALTER TABLE signalContactSession RENAME TO _signalContactSessionTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'signalContactSession' ( \
                     'account_id' int NOT NULL, \
                     'contactName' text, \
                     'contactDeviceId' int NOT NULL, \
                     'recordData' BLOB, \
                     PRIMARY KEY('account_id','contactName','contactDeviceId'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                     FOREIGN KEY('account_id', 'contactName') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
                 );"];
            [self.db executeNonQuery:@"DELETE FROM _signalContactSessionTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [self.db executeNonQuery:@"DELETE FROM _signalContactSessionTMP WHERE (account_id, contactName) NOT IN (SELECT account_id, buddy_name FROM buddylist)"];
            [self.db executeNonQuery:@"INSERT INTO signalContactSession SELECT * FROM _signalContactSessionTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _signalContactSessionTMP;"];

            // add foreign key to signalIdentity
            [self.db executeNonQuery:@"ALTER TABLE signalIdentity RENAME TO _signalIdentityTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'signalIdentity' ( \
                     'account_id' int NOT NULL, \
                     'deviceid' int NOT NULL, \
                     'identityPublicKey' BLOB NOT NULL, \
                     'identityPrivateKey' BLOB NOT NULL, \
                     PRIMARY KEY('account_id', 'deviceid'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE \
                 );"];
            [self.db executeNonQuery:@"DELETE FROM _signalIdentityTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [self.db executeNonQuery:@"INSERT INTO signalIdentity (account_id, deviceid, identityPublicKey, identityPrivateKey) SELECT account_id, deviceid, identityPublicKey, identityPrivateKey FROM _signalIdentityTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _signalIdentityTMP;"];

            // add foreign key to signalPreKey
            [self.db executeNonQuery:@"ALTER TABLE signalPreKey RENAME TO _signalPreKeyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'signalPreKey' ( \
                     'account_id' int NOT NULL, \
                     'prekeyid' int NOT NULL, \
                     'preKey' BLOB, \
                     'creationTimestamp' INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, \
                     'pubSubRemovalTimestamp' INTEGER DEFAULT NULL, \
                     'keyUsed' INTEGER NOT NULL DEFAULT 0, \
                     PRIMARY KEY('account_id', 'prekeyid'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE \
                 );"];
            [self.db executeNonQuery:@"DELETE FROM _signalPreKeyTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [self.db executeNonQuery:@"INSERT INTO signalPreKey SELECT * FROM _signalPreKeyTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _signalPreKeyTMP;"];

            // add foreign key to signalSignedPreKey
            [self.db executeNonQuery:@"ALTER TABLE signalSignedPreKey RENAME TO _signalSignedPreKeyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'signalSignedPreKey' ( \
                     'account_id' int NOT NULL, \
                     'signedPreKeyId' int NOT NULL, \
                     'signedPreKey' BLOB, \
                     PRIMARY KEY('account_id', 'signedPreKeyId'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE \
                 );"];
            [self.db executeNonQuery:@"DELETE FROM _signalSignedPreKeyTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [self.db executeNonQuery:@"DELETE FROM _signalSignedPreKeyTMP WHERE (ROWID, account_id, signedPreKeyId, signedPreKey) NOT IN (SELECT ROWID, account_id, signedPreKeyId, signedPreKey FROM _signalSignedPreKeyTMP GROUP BY account_id);"];
            [self.db executeNonQuery:@"INSERT INTO signalSignedPreKey SELECT * FROM _signalSignedPreKeyTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _signalSignedPreKeyTMP;"];
        }];

        [self updateDBTo:5.010 withBlock:^{
            // add foreign key to activechats
            [self.db executeNonQuery:@"ALTER TABLE activechats RENAME TO _activechatsTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'activechats' ( \
                     'account_id' integer NOT NULL, \
                     'buddy_name' varchar(50) NOT NULL COLLATE nocase, \
                     'lastMessageTime' datetime, \
                     'lastMesssage' blob, \
                     'pinned' bool NOT NULL DEFAULT FALSE, \
                     PRIMARY KEY('account_id', 'buddy_name'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                     FOREIGN KEY('account_id', 'buddy_name') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
                 );"];
            [self.db executeNonQuery:@"DELETE FROM _activechatsTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [self.db executeNonQuery:@"DELETE FROM _activechatsTMP WHERE (account_id, buddy_name) NOT IN (SELECT account_id, buddy_name FROM buddylist)"];
            [self.db executeNonQuery:@"INSERT INTO activechats SELECT * FROM _activechatsTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _activechatsTMP;"];

            // add foreign key to activechats
            [self.db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'buddylist' ( \
                     'buddy_id' integer NOT NULL, \
                     'account_id' integer NOT NULL, \
                     'buddy_name' varchar(255) COLLATE nocase, \
                     'full_name' varchar(255), \
                     'nick_name' varchar(255), \
                     'iconhash' varchar(200), \
                     'state' varchar(20), \
                     'status' varchar(200), \
                     'Muc' bool, \
                     'muc_subject' varchar(1024), \
                     'muc_nick' varchar(255), \
                     'backgroundImage' text, \
                     'encrypt' bool, \
                     'subscription' varchar(50), \
                     'ask' varchar(50), \
                     'messageDraft' text, \
                     'lastInteraction' INTEGER NOT NULL DEFAULT 0, \
                     'blocked' BOOL DEFAULT FALSE, \
                     'muc_type' VARCHAR(10) DEFAULT 'channel', \
                     'lastMucStanzaId' text DEFAULT NULL, \
                     UNIQUE('account_id', 'buddy_name'), \
                     PRIMARY KEY('buddy_id' AUTOINCREMENT), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE \
                 );"];
            [self.db executeNonQuery:@"DELETE FROM _buddylistTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [self.db executeNonQuery:@"INSERT INTO buddylist SELECT * FROM _buddylistTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _buddylistTMP;"];

            // add foreign key to buddy_resources
            [self.db executeNonQuery:@"ALTER TABLE buddy_resources RENAME TO _buddy_resourcesTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'buddy_resources' ( \
                     'buddy_id' integer NOT NULL, \
                     'resource' varchar(255, 0) NOT NULL, \
                     'ver' varchar(20, 0), \
                     'platform_App_Name' text, \
                     'platform_App_Version' text, \
                     'platform_OS' text, \
                     PRIMARY KEY('buddy_id','resource'), \
                     FOREIGN KEY('buddy_id') REFERENCES 'buddylist'('buddy_id') ON DELETE CASCADE \
                 );"];
            [self.db executeNonQuery:@"DELETE FROM _buddy_resourcesTMP WHERE buddy_id NOT IN (SELECT buddy_id FROM buddylist)"];
            [self.db executeNonQuery:@"DELETE FROM _buddy_resourcesTMP WHERE (ROWID, buddy_id, resource) NOT IN (SELECT ROWID, buddy_id, resource FROM _buddy_resourcesTMP GROUP BY buddy_id, resource);"];
            [self.db executeNonQuery:@"INSERT INTO buddy_resources (buddy_id, resource, ver, platform_App_Name, platform_App_Version, platform_OS) SELECT buddy_id, resource, ver, platform_App_Name, platform_App_Version, platform_OS FROM _buddy_resourcesTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _buddy_resourcesTMP;"];
        }];
        
        [self updateDBTo:5.011 withBlock:^{
            [self.db executeNonQuery:@"CREATE TABLE 'muc_participants' ( \
                     'account_id' INTEGER NOT NULL, \
                     'room' VARCHAR(255) NOT NULL, \
                     'room_nick' VARCHAR(255) NOT NULL, \
                     'participant_jid' VARCHAR(255), \
                     'affiliation' VARCHAR(255), \
                     'role' VARCHAR(255), \
                     PRIMARY KEY('account_id','room','room_nick'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                     FOREIGN KEY('account_id', 'room') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
            );"];
        }];

        [self updateDBTo:5.012 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE buddylist ADD COLUMN muted BOOL DEFAULT FALSE"];
        }];

        [self updateDBTo:5.013 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE signalContactIdentity ADD COLUMN brokenSession BOOL DEFAULT FALSE"];
        }];

        [self updateDBTo:5.014 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            // Create a backup before changing a lot of the table style
            [self.db executeNonQuery:@"CREATE TABLE message_history_backup AS SELECT * FROM _message_historyTMP WHERE 0"];
            [self.db executeNonQuery:@"INSERT INTO message_history_backup SELECT * FROM _message_historyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'message_history' ( \
                     'message_history_id' integer NOT NULL, \
                     'account_id' integer NOT NULL, \
                     'buddy_name' TEXT NOT NULL, \
                     'inbound' BOOL NOT NULL DEFAULT 0, \
                     'timestamp' datetime NOT NULL, \
                     'message' blob NOT NULL, \
                     'actual_from' text COLLATE nocase, \
                     'messageid' text COLLATE nocase, \
                     'messageType' text, \
                     'sent' bool, \
                     'received' bool, \
                     'unread' bool, \
                     'encrypted' bool DEFAULT FALSE, \
                     'previewText' text, \
                     'previewImage' text, \
                     'stanzaid' text COLLATE nocase, \
                     'errorType' text COLLATE nocase, \
                     'errorReason' text, \
                     'displayed' BOOL DEFAULT FALSE, \
                     'displayMarkerWanted' BOOL DEFAULT FALSE, \
                     'filetransferMimeType' VARCHAR(32) DEFAULT NULL, \
                     'filetransferSize' INTEGER DEFAULT NULL, \
                     PRIMARY KEY('message_history_id' AUTOINCREMENT), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                     FOREIGN KEY('account_id', 'buddy_name') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
                 );"];
            [self.db executeNonQuery:@"DELETE FROM _message_historyTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            // delete all group chats and all chats that don't have a valid buddy
            [self.db executeNonQuery:@"DELETE FROM _message_historyTMP WHERE message_history_id IN (\
                SELECT message_history_id \
                FROM _message_historyTMP AS M INNER JOIN account AS A \
                    ON M.account_id=A.account_id \
                    WHERE (M.message_from!=(A.username || '@' || A.domain) AND M.message_to!=(A.username || '@' || A.domain))\
                )\
            "];
            [self.db executeNonQuery:@"INSERT INTO message_history \
                (message_history_id, account_id, buddy_name, inbound, timestamp, message, actual_from, messageid, messageType, sent, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason, displayed, displayMarkerWanted, filetransferMimeType, filetransferSize) \
                SELECT \
                    M.message_history_id, M.account_id, \
                    CASE \
                        WHEN M.message_from=(A.username || '@' || A.domain) THEN M.message_to \
                        ELSE M.message_from \
                    END AS buddy_name, \
                    CASE \
                        WHEN M.message_from=(A.username || '@' || A.domain) THEN 0 \
                        ELSE 1 \
                    END AS inbound, \
                    M.timestamp, M.message, M.actual_from, M.messageid, M.messageType, M.sent, M.received, M.unread, M.encrypted, M.previewText, M.previewImage, M.stanzaid, M.errorType, M.errorReason, M.displayed, M.displayMarkerWanted, M.filetransferMimeType, M.filetransferSize \
                FROM _message_historyTMP AS M INNER JOIN account AS A ON M.account_id=A.account_id;\
             "];
            // delete muc messages
            [self.db executeNonQuery:@"DELETE FROM message_history WHERE message_history_id IN (\
                SELECT message_history_id \
                FROM message_history AS M INNER JOIN buddylist AS B\
                ON M.account_id=B.account_id AND M.buddy_name=B.buddy_name \
                WHERE B.Muc=1) \
            "];
            [self.db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
        }];
        
        [self updateDBTo:5.015 withBlock:^{
            [self.db executeNonQuery:@"CREATE TABLE 'muc_members' ( \
                'account_id' INTEGER NOT NULL, \
                'room' VARCHAR(255) NOT NULL, \
                'member_jid' VARCHAR(255), \
                'affiliation' VARCHAR(255), \
                PRIMARY KEY('account_id','room','member_jid'), \
                FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                FOREIGN KEY('account_id', 'room') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
            );"];
        }];
        
        // Migrate muteList to new format and delete old table
        [self updateDBTo:5.016 withBlock:^{
            [self.db executeNonQuery:@"UPDATE buddylist SET muted=1 \
                WHERE buddy_name IN ( \
                    SELECT DISTINCT jid FROM muteList \
             );"];
            [self.db executeNonQuery:@"DROP TABLE muteList;"];
        }];
        
        // Delete all muc's
        [self updateDBTo:5.017 withBlock:^{
            [self.db executeNonQuery:@"DELETE FROM buddylist WHERE Muc=1;"];
            [self.db executeNonQuery:@"DELETE FROM muc_participants;"];
            [self.db executeNonQuery:@"DELETE FROM muc_members;"];
            [self.db executeNonQuery:@"DELETE FROM muc_favorites;"];
        }];
        
        [self updateDBTo:5.018 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN participant_jid TEXT DEFAULT NULL"];
        }];
        
        // delete message_history backup table
        [self updateDBTo:5.019 withBlock:^{
            [self.db executeNonQuery:@"DROP TABLE message_history_backup;"];
        }];
        
        //update muc favorites to have the autojoin flag set
        [self updateDBTo:5.020 withBlock:^{
            [self.db executeNonQuery:@"UPDATE muc_favorites SET autojoin=1;"];
        }];

        // jid's should be lower only
        [self updateDBTo:5.021 withBlock:^{
            [self.db executeNonQuery:@"UPDATE account SET username=LOWER(username), domain=LOWER(domain);"];
            [self.db executeNonQuery:@"UPDATE activechats SET buddy_name=lower(buddy_name);"];
            [self.db executeNonQuery:@"UPDATE buddylist SET buddy_name=LOWER(buddy_name);"];
            [self.db executeNonQuery:@"UPDATE message_history SET buddy_name=LOWER(buddy_name), actual_from=LOWER(actual_from), participant_jid=LOWER(participant_jid);"];
            [self.db executeNonQuery:@"UPDATE muc_members SET room=LOWER(room);"];
            [self.db executeNonQuery:@"UPDATE muc_participants SET room=LOWER(room);"];
            [self.db executeNonQuery:@"UPDATE muc_participants SET room=LOWER(room);"];
            [self.db executeNonQuery:@"UPDATE signalContactIdentity SET contactName=LOWER(contactName);"];
            [self.db executeNonQuery:@"UPDATE signalContactSession SET contactName=LOWER(contactName);"];
            [self.db executeNonQuery:@"UPDATE subscriptionRequests SET buddy_name=LOWER(buddy_name);"];
        }];

        [self updateDBTo:5.022 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE subscriptionRequests RENAME TO _subscriptionRequestsTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'subscriptionRequests' ( \
                'account_id' integer NOT NULL, \
                'buddy_name' varchar(255) NOT NULL, \
                FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                PRIMARY KEY('account_id','buddy_name') \
            );"];
            [self.db executeNonQuery:@"DELETE FROM _subscriptionRequestsTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [self.db executeNonQuery:@"INSERT INTO subscriptionRequests (account_id, buddy_name) SELECT account_id, buddy_name FROM _subscriptionRequestsTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _subscriptionRequestsTMP;"];
        }];
        
        [self updateDBTo:5.023 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE muc_favorites RENAME TO _muc_favoritesTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'muc_favorites' ( \
                'account_id' INTEGER NOT NULL, \
                'room' VARCHAR(255) NOT NULL, \
                'nick' varchar(255), \
                FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                UNIQUE('room', 'account_id'), \
                PRIMARY KEY('account_id', 'room') \
            );"];
            [self.db executeNonQuery:@"INSERT INTO muc_favorites (account_id, room, nick) SELECT account_id, room, nick FROM _muc_favoritesTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _muc_favoritesTMP;"];
        }];
        
        [self updateDBTo:5.024 withBlock:^{
            //nicknames should be compared case sensitive --> change collation
            //we don't need to migrate our table data because the db upgrade triggers a xmpp reconnect and this in turn triggers
            //a new muc join which does clear this table anyways
            [self.db executeNonQuery:@"DROP TABLE muc_participants;"];
            [self.db executeNonQuery:@"CREATE TABLE 'muc_participants' ( \
                     'account_id' INTEGER NOT NULL, \
                     'room' VARCHAR(255) NOT NULL, \
                     'room_nick' VARCHAR(255) NOT NULL COLLATE binary, \
                     'participant_jid' VARCHAR(255), \
                     'affiliation' VARCHAR(255), \
                     'role' VARCHAR(255), \
                     PRIMARY KEY('account_id','room','room_nick'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                     FOREIGN KEY('account_id', 'room') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
            );"];
        }];

        [self updateDBTo:5.025 withBlock:^{
            // delete all old shareSheet outbox messages
            NSArray<NSDictionary*>* newOutbox = [[NSArray alloc] init];
            [[HelperTools defaultsDB] setObject:newOutbox forKey:@"outbox"];
            [[HelperTools defaultsDB] synchronize];
        }];
    }];
    
    // Vacuum after db updates
    NSNumber* newdbversion = [self.db idReadTransaction:^{
        return [self.db executeScalar:@"SELECT dbversion FROM dbversion;"];
    }];
    if(![newdbversion isEqual:dbversion])
    {
        [self.db vacuum];
        [self cleanUpShareSheetOutbox];
    }
    
    //turn foreign keys on again
    //needed for sqlite >= 3.26.0 (see https://sqlite.org/lang_altertable.html point 2)
    [self.db executeNonQuery:@"PRAGMA legacy_alter_table=off;"];
    [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
    
    DDLogInfo(@"Database version check complete, old version %@ was updated to version %@", dbversion, newdbversion);
    return;
}

-(void) cleanUpShareSheetOutbox
{
    NSArray<NSDictionary*>* outbox = [[[HelperTools defaultsDB] objectForKey:@"outbox"] mutableCopy];
    NSMutableArray<NSDictionary*>* outboxClean = [[[HelperTools defaultsDB] objectForKey:@"outbox"] mutableCopy];
    NSMutableSet<NSString*>* accountList = [[NSMutableSet alloc] init];
    for(NSDictionary* account in [self accountList]) {
        [accountList addObject:[account objectForKey:@"account_id"]];
    }

    for(NSDictionary* row in outbox)
    {
        NSString* outAccountNo = [row objectForKey:@"accountNo"];
        NSString* recipient = [row objectForKey:@"recipient"];
        if(outAccountNo == nil || recipient == nil) {
            // remove element
            [outboxClean removeObject:row];
            continue;
        }
        if([accountList containsObject:outAccountNo] == NO) {
            [outboxClean removeObject:row];
            continue;
        }
    }
    [[HelperTools defaultsDB] setObject:outboxClean forKey:@"outbox"];
    [[HelperTools defaultsDB] synchronize];
}

#pragma mark mute and block
-(void) muteJid:(NSString*) jid onAccount:(NSString*) accountNo
{
    if(!jid || !accountNo)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET muted=1 WHERE account_id=? AND buddy_name=?" andArguments:@[accountNo, jid]];
    }];
}

-(void) unMuteJid:(NSString*) jid onAccount:(NSString*) accountNo
{
    if(!jid || !accountNo)
    {
        unreachable();
        return;
    }
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET muted=0 WHERE account_id=? AND buddy_name=?" andArguments:@[accountNo, jid]];
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

-(void) blockJid:(NSString*) jid withAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo)
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

-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids forAccountNo:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        // remove blocked state for all buddies of account
        [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=?;" andArguments:@[accountNo]];
        // set blocking
        for(NSString* blockedJid in blockedJids)
            [self blockJid:blockedJid withAccountNo:accountNo];
    }];
}

-(void) unBlockJid:(NSString*) jid withAccountNo:(NSString*) accountNo
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

-(u_int8_t) isBlockedJid:(NSString*) jid withAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo)
        return NO;

    return [[self.db idReadTransaction:^{
        NSDictionary<NSString*, NSString*>* parsedJid = [HelperTools splitJid:jid];
        NSNumber* blocked;
        u_int8_t ruleId = kBlockingNoMatch;
        if(parsedJid[@"node"] && parsedJid[@"host"] && parsedJid[@"resource"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource=?;" andArguments:@[accountNo, parsedJid[@"node"], parsedJid[@"host"], parsedJid[@"resource"]]];
            ruleId = kBlockingMatchedNodeHostResource;
        }
        else if(parsedJid[@"node"] && parsedJid[@"host"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node=? AND host=? AND resource IS NULL;" andArguments:@[accountNo, parsedJid[@"node"], parsedJid[@"host"]]];
            ruleId = kBlockingMatchedNodeHost;
        }
        else if(parsedJid[@"host"] && parsedJid[@"resource"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource=?;" andArguments:@[accountNo, parsedJid[@"host"], parsedJid[@"resource"]]];
            ruleId = kBlockingMatchedHostResource;
        }
        else if(parsedJid[@"host"])
        {
            blocked = [self.db executeScalar:@"SELECT COUNT(*) FROM blocklistCache WHERE account_id=? AND node IS NULL AND host=? AND resource IS NULL;" andArguments:@[accountNo, parsedJid[@"host"]]];
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
        NSMutableArray* blockedJids = [[NSMutableArray alloc] init];
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
-(NSArray*) getAllCachedImages
{
    return [self.db idReadTransaction:^{
        return [self.db executeReader:@"SELECT DISTINCT * FROM imageCache;"];
    }];
}

// (deprecated) should only be used to upgrade to new table format
-(void) removeImageCacheTables
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"DROP TABLE imageCache;"];
    }];
}

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSString*) accountNo
{
    if(!accountNo ||! contact)
        return nil;
    
    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=? AND buddy_name=? GROUP BY message ORDER BY message_history_id ASC;";
        NSArray* params = @[kMessageTypeFiletransfer, accountNo, contact];
        
        NSMutableArray* retval = [[NSMutableArray alloc] init];
        for(MLMessage* msg in [self messagesForHistoryIDs:[self.db executeScalarReader:query andArguments:params]])
            [retval addObject:[MLFiletransfer getFileInfoForMessage:msg]];
        return retval;
    }];
}

#pragma mark - last interaction

-(NSDate*) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountNo:(NSString* _Nonnull) accountNo
{
    NSAssert(jid, @"jid should not be null");
    NSAssert(accountNo != NULL, @"accountNo should not be null");

    return [self.db idReadTransaction:^{
        NSString* query = @"SELECT lastInteraction FROM buddylist WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[accountNo, jid];
        NSNumber* lastInteractionTime = (NSNumber*)[self.db executeScalar:query andArguments:params];

        //return NSDate object or 1970, if last interaction is zero
        if(![lastInteractionTime integerValue])
            return [[NSDate date] initWithTimeIntervalSince1970:0] ;
        return [NSDate dateWithTimeIntervalSince1970:[lastInteractionTime integerValue]];
    }];
}

-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andAccountNo:(NSString* _Nonnull) accountNo
{
    NSAssert(jid, @"jid should not be null");
    NSAssert(accountNo != NULL, @"accountNo should not be null");

    NSNumber* timestamp = @0;       //default value for "online" or "unknown"
    if(lastInteractionTime)
        timestamp = [NSNumber numberWithInt:lastInteractionTime.timeIntervalSince1970];

    [self.db voidWriteTransaction:^{
        NSString* query = @"UPDATE buddylist SET lastInteraction=? WHERE account_id=? AND buddy_name=?;";
        NSArray* params = @[timestamp, accountNo, jid];
        [self.db executeNonQuery:query andArguments:params];
    }];
}

#pragma mark - encryption

-(BOOL) shouldEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo)
        return NO;
    return [self.db boolReadTransaction:^{
        NSString* query = @"SELECT encrypt from buddylist where account_id=? and buddy_name=?";
        NSArray* params = @[accountNo, jid];
        NSNumber* status=(NSNumber*)[self.db executeScalar:query andArguments:params];
        return [status boolValue];
    }];
}


-(void) encryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET encrypt=1 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, jid]];
    }];
    return;
}

-(void) disableEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo)
        return;
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE buddylist SET encrypt=0 WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, jid]];
    }];
    return;
}

#pragma mark History Message Search (search keyword in message, buddy_name, messageType)

-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword accountNo:(NSString*) accountNo
{
    if(!keyword || !accountNo)
        return nil;
    return [self.db idReadTransaction:^{
        NSString *likeString = [NSString stringWithFormat:@"%%%@%%", keyword];
        NSString* query = @"SELECT message_history_id FROM message_history WHERE account_id = ? AND (message like ? OR buddy_name LIKE ? OR messageType LIKE ?) ORDER BY timestamp ASC;";
        NSArray* params = @[accountNo, likeString, likeString, likeString];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}

-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword accountNo:(NSString*) accountNo betweenBuddy:(NSString* _Nonnull) contactJid
{
    if(!keyword || !accountNo)
        return nil;
    return [self.db idReadTransaction:^{
        NSString *likeString = [NSString stringWithFormat:@"%%%@%%", keyword];
        NSString* query = @"SELECT message_history_id FROM message_history WHERE account_id=? AND message LIKE ? AND buddy_name=? ORDER BY timestamp ASC;";
        NSArray* params = @[accountNo, likeString, contactJid];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}
@end
