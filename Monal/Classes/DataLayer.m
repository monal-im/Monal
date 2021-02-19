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

-(NSString*) exportDB
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
    return [self.db executeReader:@"SELECT * FROM account ORDER BY account_id ASC;"];
}

-(NSNumber*) enabledAccountCnts
{
    return (NSNumber*)[self.db executeScalar:@"SELECT COUNT(*) FROM account WHERE enabled=1;"];
}

-(NSArray*) enabledAccountList
{
    return [self.db executeReader:@"SELECT * FROM account WHERE enabled=1 ORDER BY account_id ASC;"] ;
}

-(BOOL) isAccountEnabled:(NSString*) accountNo
{
    return [[self.db executeScalar:@"SELECT enabled FROM account WHERE account_id=?;" andArguments:@[accountNo]] boolValue];
}

-(NSNumber*) accountIDForUser:(NSString*) user andDomain:(NSString*) domain
{
    if(!user && !domain)
        return nil;

    NSString* cleanUser = user;
    NSString* cleanDomain = domain;

    if(!cleanDomain) cleanDomain= @"";
    if(!cleanUser) cleanUser= @"";

    NSString* query = @"SELECT account_id FROM account WHERE domain=? and username=?;";
    NSArray* result = [self.db executeReader:query andArguments:@[cleanDomain, cleanUser]];
    if(result.count > 0) {
        return [result[0] objectForKey:@"account_id"];
    }
    return nil;
}

-(BOOL) doesAccountExistUser:(NSString*) user andDomain:(NSString *) domain
{
    NSString* query = @"SELECT * FROM account WHERE domain=? AND username=?;";
    NSArray* result = [self.db executeReader:query andArguments:@[domain, user]];
    return result.count > 0;
}

-(NSMutableDictionary*) detailsForAccount:(NSString*) accountNo
{
    if(!accountNo)
        return nil;
    NSArray* result = [self.db executeReader:@"SELECT * FROM account WHERE account_id=?;" andArguments:@[accountNo]];
    if(result != nil && [result count])
    {
        DDLogVerbose(@"count: %lu", (unsigned long)[result count]);
        return result[0];
    }
    else
        DDLogError(@"account list is empty or failed to read");
    return nil;
}

-(NSString*) jidOfAccount:(NSString*) accountNo
{
    NSString* query = @"SELECT username, domain FROM account WHERE account_id=?;";
    NSMutableArray* accountDetails = [self.db executeReader:query andArguments:@[accountNo]];
    
    if(accountDetails == nil)
        return nil;
    
    NSString* accountJid = nil;
    if(accountDetails.count > 0) {
        NSDictionary* firstRow = [accountDetails objectAtIndex:0];
        accountJid = [NSString stringWithFormat:@"%@@%@", [firstRow objectForKey:kUsername], [firstRow objectForKey:kDomain]];
    }
    return accountJid;
}

-(BOOL) updateAccounWithDictionary:(NSDictionary *) dictionary
{
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
}

-(NSNumber*) addAccountWithDictionary:(NSDictionary*) dictionary
{
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
        return accountID;
    } else {
        return nil;
    }
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
    return [self.db executeNonQuery:@"UPDATE account SET enabled=0 WHERE account_id=?;" andArguments:@[accountNo]] != NO;
}

-(NSMutableDictionary*) readStateForAccount:(NSString*) accountNo
{
    if(!accountNo) return nil;
    NSString* query = @"SELECT state from account where account_id=?";
    NSArray* params = @[accountNo];
    NSData* data = (NSData*)[self.db executeScalar:query andArguments:params];
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
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
        return dic;
    }
    return nil;
}

-(void) persistState:(NSDictionary*) state forAccount:(NSString*) accountNo
{
    if(!accountNo || !state) return;
    NSString* query = @"update account set state=? where account_id=?";
    NSError* error;
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:state requiringSecureCoding:YES error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    NSArray *params = @[data, accountNo];
    [self.db executeNonQuery:query andArguments:params];
}

#pragma mark contact Commands

-(BOOL) addContact:(NSString*) contact forAccount:(NSString*) accountNo nickname:(NSString*) nickName andMucNick:(NSString* _Nullable) mucNick
{
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
        } else {
            cleanNickName = [nickName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if([cleanNickName length] > 50)
            toPass = [cleanNickName substringToIndex:49];
        else
            toPass = cleanNickName;
        
        NSString* query = @"INSERT INTO buddylist ('account_id', 'buddy_name', 'full_name', 'nick_name', 'muc', 'muc_nick') VALUES(?, ?, ?, ?, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET nick_name=?;";
        if(!accountNo || !contact)
            return NO;
        else
        {
            NSArray* params = @[accountNo, contact, @"", toPass, mucNick ? @1 : @0, mucNick ? mucNick : @"", toPass];
            BOOL success = [self.db executeNonQuery:query andArguments:params];
            return success;
        }
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
    return [self.db executeNonQuery:@"DELETE FROM buddylist WHERE account_id=?;" andArguments:@[accountNo]] != NO;
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

-(MLContact*) contactForUsername:(NSString*) username forAccount:(NSString*) accountNo
{
    if(!username || !accountNo)
        return nil;
    
    NSArray* results = [self.db executeReader:@"SELECT b.buddy_name, state, status, b.full_name, b.nick_name, Muc, muc_subject, muc_type, muc_nick, b.account_id, lastMessageTime, 0 AS 'count', subscription, ask, IFNULL(pinned, 0) AS 'pinned', blocked, \
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
    
    //check if we know this contact and return a dummy one if not
    if([results count] == 0)
    {
        DDLogWarn(@"Returning dummy MLContact for %@ on accountNo %@", username, accountNo);
        return [MLContact contactFromDictionary:@{
            @"buddy_name": username,
            @"nick_name": @"",
            @"full_name": @"",
            @"subscription": kSubNone,
            @"ask": @"",
            @"account_id": accountNo,
            //@"muc_subject": nil,
            //@"muc_nick": nil,
            @"Muc": @NO,
            @"pinned": @NO,
            @"status": @"",
            @"state": @"offline",
            @"count": @0,
            @"isActiveChat": @NO
        }];
    }
    else
        return [MLContact contactFromDictionary:results[0]];
}


-(NSArray<MLContact*>*) searchContactsWithString:(NSString*) search
{
    NSString* likeString = [NSString stringWithFormat:@"%%%@%%", search];
    NSString* query = @"SELECT buddy_name, account_id FROM buddylist WHERE buddy_name LIKE ? OR full_name LIKE ? OR nick_name LIKE ? ORDER BY full_name, nick_name, buddy_name COLLATE NOCASE ASC;";
    NSArray* params = @[likeString, likeString, likeString];
    NSMutableArray<MLContact*>* toReturn = [[NSMutableArray alloc] init];
    for(NSDictionary* dic in [self.db executeReader:query andArguments:params])
        [toReturn addObject:[self contactForUsername:dic[@"buddy_name"] forAccount:dic[@"account_id"]]];
    return toReturn;
}

-(NSMutableArray*) contactList
{
    //only list contacts having a roster entry (e.g. kSubBoth, kSubTo or kSubFrom)
    NSString* query = @"SELECT buddy_name, a.account_id, IFNULL(IFNULL(NULLIF(A.nick_name, ''), NULLIF(A.full_name, '')), buddy_name) AS 'sortkey' FROM buddylist AS A INNER JOIN account AS b ON a.account_id=b.account_id WHERE (a.subscription=? OR a.subscription=? OR a.subscription=?) AND b.enabled=1 ORDER BY sortkey COLLATE NOCASE ASC;";
    NSMutableArray* toReturn = [[NSMutableArray alloc] init];
    for(NSDictionary* dic in [self.db executeReader:query andArguments:@[kSubBoth, kSubTo, kSubFrom]])
        [toReturn addObject:[self contactForUsername:dic[@"buddy_name"] forAccount:dic[@"account_id"]]];
    return toReturn;
}

#pragma mark entity capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andAccountNo:(NSString*) acctNo
{
    NSString* query = @"SELECT COUNT(*) FROM buddylist AS a INNER JOIN buddy_resources AS b ON a.buddy_id=b.buddy_id INNER JOIN ver_info AS c ON b.ver=c.ver WHERE buddy_name=? AND account_id=? AND cap=?;";
    NSArray *params = @[user, acctNo, cap];
    NSNumber* count = (NSNumber*) [self.db executeScalar:query andArguments:params];
    return [count integerValue]>0;
}

-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource
{
    NSString* query = @"SELECT ver FROM buddy_resources AS A INNER JOIN buddylist AS B ON a.buddy_id=b.buddy_id WHERE resource=? AND buddy_name=?;";
    NSArray * params = @[resource, user];
    NSString* ver = (NSString*) [self.db executeScalar:query andArguments:params];
    return ver;
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
    NSString* query = @"select cap from ver_info where ver=?";
    NSArray * params = @[ver];
    NSArray* resultArray = [self.db executeReader:query andArguments:params];
    
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
    if(!contact) return nil;
    NSString* query1 = @" select resource from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where  buddy_name=?  ";
    NSArray* params = @[contact ];
    NSArray* resources = [self.db executeReader:query1 andArguments:params];
    return resources;
}

-(NSArray*) getSoftwareVersionInfoForContact:(NSString*)contact resource:(NSString*)resource andAccount:(NSString*)account
{
    if(!account) return nil;
    NSString* query1 = @"select platform_App_Name, platform_App_Version, platform_OS from buddy_resources where buddy_id in (select buddy_id from buddylist where account_id=? and buddy_name=?) and resource=?";
    NSArray* params = @[account, contact, resource];
    NSArray* resources = [self.db executeReader:query1 andArguments:params];
    return resources;
}

-(void) setSoftwareVersionInfoForContact:(NSString*)contact
                                resource:(NSString*)resource
                              andAccount:(NSString*)account
                             withAppName:(NSString*)appName
                              appVersion:(NSString*)appVersion
                           andPlatformOS:(NSString*)platformOS
{
    NSString* query = @"update buddy_resources set platform_App_Name=?, platform_App_Version=?, platform_OS=? where buddy_id in (select buddy_id from buddylist where account_id=? and buddy_name=?) and resource=?";
    NSArray* params = @[appName, appVersion, platformOS, account, contact, resource];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) setOnlineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self setResourceOnline:presenceObj forAccount:accountNo];
        NSString* query = @"UPDATE buddylist SET state='', muc=? WHERE account_id=? AND buddy_name=? AND state='offline';";
        NSArray* params = @[@([presenceObj check:@"{http://jabber.org/protocol/muc#user}x"]), accountNo, presenceObj.fromUser];
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

    NSString* query = @"UPDATE buddylist SET state=? WHERE account_id=? AND buddy_name=?;";
    [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.fromUser]];
}

-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo
{

    NSString* query = @"SELECT state FROM buddylist WHERE account_id=? AND buddy_name=?;";
    NSArray* params = @[accountNo, buddy];
    NSString* state = (NSString*)[self.db executeScalar:query andArguments:params];
    return state;
}

-(BOOL) hasContactRequestForAccount:(NSString*) accountNo andBuddyName:(NSString*) buddy
{
    NSString* query = @"SELECT COUNT(*) FROM subscriptionRequests WHERE account_id=? AND buddy_name=?";

    NSNumber* result = (NSNumber*)[self.db executeScalar:query andArguments:@[accountNo, buddy]];

    return result.intValue == 1;
}

-(NSMutableArray*) contactRequestsForAccount
{
    NSString* query = @"SELECT account_id, buddy_name FROM subscriptionRequests;";
    NSMutableArray* toReturn = [[NSMutableArray alloc] init];
    for(NSDictionary* dic in [self.db executeReader:query])
        [toReturn addObject:[self contactForUsername:dic[@"buddy_name"] forAccount:dic[@"account_id"]]];
    return toReturn;
}

-(void) addContactRequest:(MLContact *) requestor;
{
    NSString* query2 = @"INSERT OR IGNORE INTO subscriptionRequests (buddy_name, account_id) VALUES (?,?)";
    [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId] ];
}

-(void) deleteContactRequest:(MLContact *) requestor
{
    NSString* query2 = @"delete from subscriptionRequests where buddy_name=? and account_id=? ";
    [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId] ];
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

    NSString* query = @"UPDATE buddylist SET status=? WHERE account_id=? AND buddy_name=?;";
    [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.fromUser]];
}

-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = @"SELECT status FROM buddylist WHERE account_id=? AND buddy_name=?;";
    NSString* iconname =  (NSString *)[self.db executeScalar:query andArguments:@[accountNo, buddy]];
    return iconname;
}

-(NSString *) getRosterVersionForAccount:(NSString*) accountNo
{
    NSString* query = @"SELECT rosterVersion FROM account WHERE account_id=?;";
    NSArray* params = @[ accountNo];
    NSString * version=(NSString*)[self.db executeScalar:query andArguments:params];
    return version;
}

-(void) setRosterVersion:(NSString *) version forAccount: (NSString*) accountNo
{
    if(!accountNo || !version) return;
    NSString* query = @"update account set rosterVersion=? where account_id=?";
    NSArray* params = @[version , accountNo];
    [self.db executeNonQuery:query  andArguments:params];
}

-(NSDictionary *) getSubscriptionForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    if(!contact || !accountNo) return nil;
    NSString* query = @"SELECT subscription, ask from buddylist where buddy_name=? and account_id=?";
    NSArray* params = @[contact, accountNo];
    NSArray* version=[self.db executeReader:query andArguments:params];
    return version.firstObject;
}

-(void) setSubscription:(NSString *)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    if(!contact || !accountNo || !sub) return;
    NSString* query = @"update buddylist set subscription=?, ask=? where account_id=? and buddy_name=?";
    NSArray* params = @[sub, ask?ask:@"", accountNo, contact];
    [self.db executeNonQuery:query  andArguments:params];
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

    NSString* query = @"UPDATE buddylist SET full_name=? WHERE account_id=? AND buddy_name=?;";
    NSArray* params = @[toPass , accountNo, contact];
    [self.db executeNonQuery:query  andArguments:params];
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
    return [self.db idWriteTransaction:^{
        NSString* hash = [self.db executeScalar:@"SELECT iconhash FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
        if(!hash)       //try to get the hash of our own account
            hash = [self.db executeScalar:@"SELECT iconhash FROM account WHERE account_id=? AND printf('%s@%s', username, domain)=?;" andArguments:@[accountNo, buddy]];
        return hash;
    }];
}

-(BOOL) isContactInList:(NSString*) buddy forAccount:(NSString*) accountNo
{
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
}

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo withComment:(NSString*) comment
{
    NSString* query = @"UPDATE buddylist SET messageDraft=? WHERE account_id=? AND buddy_name=?;";
    NSArray* params = @[comment, accountNo, buddy];
    BOOL success = [self.db executeNonQuery:query andArguments:params];

    return success;
}

-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = @"SELECT messageDraft FROM buddylist WHERE account_id=? AND buddy_name=?;";
    NSArray* params = @[accountNo, buddy];
    NSObject* messageDraft = [self.db executeScalar:query andArguments:params];
    return (NSString*)messageDraft;
}

#pragma mark MUC

-(BOOL) initMuc:(NSString*) room forAccountId:(NSString*) accountNo andMucNick:(NSString* _Nullable) mucNick
{
    return [self.db boolWriteTransaction:^{
        NSString* nick = mucNick;
        if(!nick)
            nick = [self ownNickNameforMuc:room forAccount:accountNo];
        NSAssert(nick, @"Could not determine muc nick when adding muc");
        
        // return old buddy and add new one (this changes "normal" buddys to muc buddys if the aren't already tagged as mucs
        [self.db executeNonQuery:@"DELETE FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, room]];
        return [self.db executeNonQuery:@"INSERT INTO buddylist ('account_id', 'buddy_name', 'muc', 'muc_nick') VALUES(?, ?, ?, ?);" andArguments:@[accountNo, room, @1, mucNick ? mucNick : @""]];
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
    return [self.db executeScalar:@"SELECT lastMucStanzaId FROM buddylist WHERE muc=1 AND account_id=? AND buddy_name=?;" andArguments:@[accountNo, room]];
}

-(void) setLastStanzaId:(NSString*) lastStanzaId forMuc:(NSString* _Nonnull) room andAccount:(NSString* _Nonnull) accountNo
{
    if(lastStanzaId && [lastStanzaId length])
        [self.db executeNonQuery:@"UPDATE buddylist SET lastMucStanzaId=? WHERE muc=1 AND account_id=? AND buddy_name=?;" andArguments:@[lastStanzaId, accountNo, room]];
}


-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSNumber* status = (NSNumber*)[self.db executeScalar:@"SELECT Muc FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddy]];
    return [status boolValue];
}

-(NSString* _Nullable) ownNickNameforMuc:(NSString*) room forAccount:(NSString*) accountNo
{
    NSString* nick = (NSString*)[self.db executeScalar:@"SELECT muc_nick FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, room]];
    // fallback to nick in muc_favorites
    if(!nick || nick.length == 0)
        nick = (NSString*)[self.db executeScalar:@"SELECT nick FROM muc_favorites WHERE account_id=? AND room=?;" andArguments:@[accountNo, room]];
    if(!nick || nick.length == 0)
        return nil;
    return nick;
}

-(BOOL) updateOwnNickName:(NSString*) nick forMuc:(NSString*) room forAccount:(NSString*) accountNo
{
    NSString* query = @"UPDATE buddylist SET muc_nick=? WHERE account_id=? AND buddy_name=? AND muc=1;";
    NSArray* params = @[nick, accountNo, room];
    DDLogVerbose(@"%@", query);

    return [self.db executeNonQuery:query andArguments:params];
}

-(BOOL) deleteMuc:(NSString*) room forAccountId:(NSString*) accountNo
{
    NSString* query = @"DELETE FROM muc_favorites WHERE room=? AND account_id=?;";
    NSArray* params = @[room, accountNo];
    DDLogVerbose(@"%@", query);

    BOOL success = [self.db executeNonQuery:query andArguments:params];
    return success;
}

-(NSMutableArray*) listMucsForAccount:(NSString*) accountNo
{
    return [self.db executeReader:@"SELECT * FROM muc_favorites WHERE account_id=?;" andArguments:@[accountNo]];
}

-(BOOL) updateMucSubject:(NSString *) subject forAccount:(NSString*) accountNo andRoom:(NSString *) room
{
    NSString* query = @"UPDATE buddylist SET muc_subject=? WHERE account_id=? AND buddy_name=?;";
    NSArray* params = @[subject, accountNo, room];
    DDLogVerbose(@"%@", query);

    BOOL success = [self.db executeNonQuery:query andArguments:params];
    return success;
}

-(NSString*) mucSubjectforAccount:(NSString*) accountNo andRoom:(NSString*) room
{
    NSString* query = @"SELECT muc_subject FROM buddylist WHERE account_id=? AND buddy_name=?;";

    NSArray* params = @[accountNo, room];
    DDLogVerbose(@"%@", query);

    NSObject* result = [self.db executeScalar:query andArguments:params];
    return (NSString*)result;
}

-(void) updateMucTypeTo:(NSString*) type forRoom:(NSString*) room andAccount:(NSString*) accountNo
{
    [self.db executeNonQuery:@"UPDATE buddylist SET muc_type=? WHERE account_id=? AND buddy_name=?;" andArguments:@[type, accountNo, room]];
}

-(NSString*) getMucTypeOfRoom:(NSString*) room andAccount:(NSString*) accountNo
{
    return [self.db executeScalar:@"SELECT muc_type FROM buddylist WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, room]];
}

#pragma mark message Commands

-(NSArray*) messagesForHistoryIDs:(NSArray*) historyIDs
{
    NSString* idList = [historyIDs componentsJoinedByString:@","];
    NSString* query = [NSString stringWithFormat:@"SELECT IFNULL(actual_from, message_from) AS af, timestamp AS thetime, * FROM message_history WHERE message_history_id IN(%@);", idList];

    NSMutableArray* retval = [[NSMutableArray alloc] init];
    for(NSDictionary* dic in [self.db executeReader:query])
        [retval addObject:[MLMessage messageFromDictionary:dic withDateFormatter:dbFormatter]];
    return retval;
}

-(MLMessage*) messageForHistoryID:(NSNumber*) historyID
{
    if(historyID == nil)
        return nil;
    NSArray* result = [self messagesForHistoryIDs:@[historyID]];
    if(![result count])
        return nil;
    return result[0];
}

-(NSNumber*) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString*) messageid serverMessageId:(NSString*) stanzaid messageType:(NSString*) messageType andOverrideDate:(NSDate*) messageDate encrypted:(BOOL) encrypted backwards:(BOOL) backwards displayMarkerWanted:(BOOL) displayMarkerWanted
{
    if(!from || !to || !message)
        return nil;
    
    return [self.db idWriteTransaction:^{
        if(![self hasMessageForStanzaId:stanzaid orMessageID:messageid toContact:from onAccount:accountNo])
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
            
            //do not do this in MUC
            if([actualfrom isEqualToString:from])
            {
                NSString* query;
                NSArray* params;
                if(backwards)
                {
                    NSNumber* nextHisoryId = [NSNumber numberWithInt:[(NSNumber*)[self.db executeScalar:@"SELECT MIN(message_history_id) FROM message_history;"] intValue] - 1];
                    DDLogVerbose(@"Inserting backwards with history id %@", nextHisoryId);
                    query = @"insert into message_history (message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
                    params = @[nextHisoryId, accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", messageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@""];
                }
                else
                {
                    //we use autoincrement here instead of MAX(message_history_id) + 1 to be a little bit faster (but at the cost of "duplicated code")
                    query = @"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
                    params = @[accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", messageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@""];
                }
                DDLogVerbose(@"%@", query);
                BOOL success = [self.db executeNonQuery:query andArguments:params];
                if(!success)
                    return (NSNumber*)nil;
                NSNumber* historyId = [self.db lastInsertId];
                [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo];
                return historyId;
            }
            else
            {
                NSString* query = @"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
                NSArray* params = @[accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithInteger:unread], [NSNumber numberWithInteger:sent], messageid ? messageid : @"", messageType, [NSNumber numberWithInteger:encrypted], stanzaid?stanzaid:@"" ];
                DDLogVerbose(@"%@", query);
                BOOL success = [self.db executeNonQuery:query andArguments:params];
                if(!success)
                    return (NSNumber*)nil;
                NSNumber* historyId = [self.db lastInsertId];
                [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo];
                return historyId;
            }
        }
        else
        {
            DDLogError(@"Message(%@) %@ with stanzaid %@ already existing, ignoring history update", accountNo, messageid, stanzaid);
            return (NSNumber*)nil;
        }
    }];
}

-(BOOL) hasMessageForStanzaId:(NSString*) stanzaId orMessageID:(NSString*) messageId toContact:(NSString*) contact onAccount:(NSString*) accountNo
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
        if(!contact)
        {
            DDLogVerbose(@"no contact given --> message not found");
            return NO;
        }
        
        NSNumber* historyId = (NSNumber*)[self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND message_from=? AND messageid=?;" andArguments:@[accountNo, contact, messageId]];
        if(historyId != nil)
        {
            DDLogVerbose(@"found by messageid");
            if(stanzaId)
            {
                DDLogDebug(@"Updating stanzaid of message_history_id %@ to %@ for (account=%@, messageid=%@, contact=%@)...", historyId, stanzaId, accountNo, messageId, contact);
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
    NSString* query = @"UPDATE message_history SET received=?, sent=? WHERE messageid=?;";
    DDLogVerbose(@"setting received confrmed %@", messageid);
    [self.db executeNonQuery:query andArguments:@[[NSNumber numberWithBool:received], [NSNumber numberWithBool:YES], messageid]];
}

-(void) setMessageId:( NSString* _Nonnull ) messageid errorType:( NSString* _Nonnull ) errorType errorReason:( NSString* _Nonnull ) errorReason
{
    //ignore error if the message was already received by *some* client
    if([self.db executeScalar:@"SELECT messageid FROM message_history WHERE messageid=? AND received;" andArguments:@[messageid]])
    {
        DDLogVerbose(@"ignoring message error for %@ [%@, %@]", messageid, errorType, errorReason);
        return;
    }
    NSString* query = @"UPDATE message_history SET errorType=?, errorReason=? WHERE messageid=?;";
    DDLogVerbose(@"setting message error %@ [%@, %@]", messageid, errorType, errorReason);
    [self.db executeNonQuery:query andArguments:@[errorType, errorReason, messageid]];
}

-(void) setMessageHistoryId:(NSNumber*) historyId filetransferMimeType:(NSString*) mimeType filetransferSize:(NSNumber*) size
{
    if(historyId == nil)
        return;
    NSString* query = @"UPDATE message_history SET messageType=?, filetransferMimeType=?, filetransferSize=? WHERE message_history_id=?;";
    DDLogVerbose(@"setting message type 'kMessageTypeFiletransfer', mime type '%@' and size %@ for history id %@", mimeType, size, historyId);
    [self.db executeNonQuery:query andArguments:@[kMessageTypeFiletransfer, mimeType, size, historyId]];
}

-(void) setMessageHistoryId:(NSNumber*) historyId messageType:(NSString*) messageType
{
    if(historyId == nil)
        return;
    NSString* query = @"UPDATE message_history SET messageType=? WHERE message_history_id=?;";
    DDLogVerbose(@"setting message type '%@' for history id %@", messageType, historyId);
    [self.db executeNonQuery:query andArguments:@[messageType, historyId]];
}

-(void) setMessageId:(NSString*) messageid previewText:(NSString*) text andPreviewImage:(NSString*) image
{
    if(!messageid) return;
    NSString* query = @"UPDATE message_history SET previewText=?, previewImage=? WHERE messageid=?;";
    DDLogVerbose(@"setting previews type %@", messageid);
    [self.db executeNonQuery:query  andArguments:@[text?text:@"", image?image:@"", messageid]];
}

-(void) setMessageId:(NSString*) messageid stanzaId:(NSString*) stanzaId
{
    NSString* query = @"UPDATE message_history SET stanzaid=? WHERE messageid=?;";
    DDLogVerbose(@"setting message stanzaid %@", query);
    [self.db executeNonQuery:query andArguments:@[stanzaId, messageid]];
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
    [self.db executeNonQuery:@"UPDATE message_history SET message=? WHERE message_history_id=?;" andArguments:@[newText, messageNo]];
}

-(NSNumber*) getHistoryIDForMessageId:(NSString*) messageid from:(NSString*) from andAccount:(NSString*) accountNo
{
    return [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE messageid=? AND message_from=? AND account_id=?;" andArguments:@[messageid, from, accountNo]];
}

-(BOOL) checkLMCEligible:(NSNumber*) historyID from:(NSString*) from
{
    MLMessage* msg = [self messageForHistoryID:historyID];
    if(from == nil || msg == nil)
        return NO;
    NSNumber* numberOfMessagesComingAfterThis = [self.db executeScalar:@"SELECT COUNT(message_history_id) FROM message_history WHERE message_history_id>? AND message_from=? AND message_to=? AND account_id=?;" andArguments:@[historyID, msg.from, msg.to, msg.accountId]];
    //only allow LMC for the 3 newest messages of this contact (or of us)
    if(
        numberOfMessagesComingAfterThis.intValue < 3
        && [msg.messageType isEqualToString:kMessageTypeText]
        && [msg.from isEqualToString:from]
        //not needed according to holger
        //&& ([NSDate date].timeIntervalSince1970 - msg.timestamp.timeIntervalSince1970) < 120
    )
        return YES;
    return NO;
}

-(NSArray*) messageHistoryListDates:(NSString*) buddy forAccount: (NSString*) accountNo
{
    NSString* accountJid = [self jidOfAccount:accountNo];

    if(accountJid != nil)
    {
        NSString* query = @"select distinct date(timestamp) as the_date from message_history where account_id=? and message_from=? or message_to=? order by timestamp, message_history_id desc";
        NSArray* params = @[accountNo, buddy, buddy];
        //DDLogVerbose(query);
        NSArray* toReturn = [self.db executeReader:query andArguments:params];

        if(toReturn!=nil)
        {
            DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count]);

            return toReturn; //[toReturn autorelease];
        }
        else
        {
            DDLogError(@"message history buddy date list is empty or failed to read");

            return [[NSArray alloc] init];
        }
    } else return [[NSArray alloc] init];
}

-(NSArray*) messageHistoryDateForContact:(NSString*) contact forAccount:(NSString*) accountNo forDate:(NSString*) date
{
    return [self.db idWriteTransaction:^{
        NSString* query = @"SELECT message_history_id FROM message_history WHERE account_id=? AND (message_from=? OR message_to=?) AND DATE(timestamp)=? ORDER BY message_history_id ASC;";
        NSArray* params = @[accountNo, contact, contact, date];
        DDLogVerbose(@"%@", query);
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}

-(NSArray*) allMessagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo
{
    //returns a buddy's message history

    NSString* query = @"select message_from, message, thetime from (select message_from, message, timestamp as thetime, message_history_id, previewImage, previewText from message_history where account_id=? and (message_from=? or message_to=?) order by message_history_id desc) order by message_history_id asc ";
    NSArray* params = @[accountNo, buddy, buddy];
    //DDLogVerbose(query);
    NSArray* toReturn = [self.db executeReader:query andArguments:params];

    if(toReturn!=nil)
    {

        DDLogVerbose(@" count: %lu",  (unsigned long)[toReturn count]);
        return toReturn; //[toReturn autorelease];
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
        return [[NSArray alloc] init];
    }
}

-(BOOL) messageHistoryClean:(NSString*) buddy forAccount:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSArray* messageHistoryIDs = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=? AND (message_from=? OR message_to=?);" andArguments:@[kMessageTypeFiletransfer, accountNo, buddy, buddy]];
        for(NSNumber* historyId in messageHistoryIDs)
            [MLFiletransfer deleteFileForMessage:[self messageForHistoryID:historyId]];
        return [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=? AND (message_from=? OR message_to=?);" andArguments:@[accountNo, buddy, buddy]];
    }];
}

-(NSMutableArray *) messageHistoryContacts:(NSString*) accountNo
{
    NSMutableArray* toReturn = [[NSMutableArray alloc] init];
    //returns a list of  buddy's with message history
    NSString* accountJid = [self jidOfAccount:accountNo];
    if(accountJid)
    {

        NSString* query = @"SELECT x.* FROM (select distinct buddy_name AS thename ,'', nick_name, message_from AS buddy_name, a.account_id from message_history AS a LEFT OUTER JOIN buddylist AS b ON a.message_from=b.buddy_name AND a.account_id=b.account_id WHERE a.account_id=? UNION select distinct message_to as thename ,'',  nick_name, message_to as buddy_name, a.account_id from message_history as a left outer JOIN buddylist AS b ON a.message_to=b.buddy_name AND a.account_id=b.account_id WHERE a.account_id=? AND message_to!=\"(null)\" ) AS x WHERE buddy_name!=? ORDER BY thename COLLATE NOCASE;";
        NSArray* params = @[accountNo, accountNo,
                            accountJid];
        //DDLogVerbose(query);
        for(NSDictionary* dic in [self.db executeReader:query andArguments:params])
            [toReturn addObject:[self contactForUsername:dic[@"buddy_name"] forAccount:dic[@"account_id"]]];
    }
    return toReturn;
}

//message history
-(NSNumber*) lastMessageHistoryIdForContact:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSNumber* msgHistoryID = (NSNumber*)[self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND (message_from=? OR message_to=?) ORDER BY message_history_id DESC LIMIT 1" andArguments:@[ accountNo, buddy, buddy]];
    return msgHistoryID;
}

//message history
-(NSMutableArray*) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo
{
    if(!accountNo || !buddy) {
        return nil;
    };
    NSNumber* lastMsgHistID = [self lastMessageHistoryIdForContact:buddy forAccount:accountNo];
    // Increment msgHistId -> all messages < msgHistId are feteched
    lastMsgHistID = [NSNumber numberWithInt:[lastMsgHistID intValue] + 1];
    return [self messagesForContact:buddy forAccount:accountNo beforeMsgHistoryID:lastMsgHistID];
}

//message history
-(NSMutableArray*) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo beforeMsgHistoryID:(NSNumber*) msgHistoryID
{
    if(!accountNo || !buddy || msgHistoryID == nil)
        return nil;
    return [self.db idWriteTransaction:^{
        NSString* query = @"SELECT message_history_id FROM (SELECT message_history_id FROM message_history WHERE account_id=? AND (message_from=? OR message_to=?) AND message_history_id<? ORDER BY message_history_id DESC LIMIT ?) ORDER BY message_history_id ASC;";
        NSNumber* msgLimit = @(kMonalChatFetchedMsgCnt);
        NSArray* params = @[accountNo, buddy, buddy, msgHistoryID, msgLimit];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}

-(MLMessage*) lastMessageForContact:(NSString*) contact forAccount:(NSString*) accountNo
{
    if(!accountNo || !contact)
        return nil;
    
    return [self.db idWriteTransaction:^{
        //return message draft (if any)
        NSString* query = @"SELECT bl.messageDraft AS message, ac.lastMessageTime AS thetime, 'MessageDraft' AS messageType, ? AS message_to, '' AS message_from, '' AS af, '' AS filetransferMimeType, 0 AS filetransferSize FROM buddylist AS bl INNER JOIN activechats AS ac WHERE bl.account_id = ac.account_id AND bl.buddy_name = ac.buddy_name AND ac.account_id=? AND ac.buddy_name=? AND messageDraft IS NOT NULL AND messageDraft != '';";
        NSArray* params = @[contact, accountNo, contact];
        NSArray* results = [self.db executeReader:query andArguments:params];
        if([results count])
            return [MLMessage messageFromDictionary:results[0] withDateFormatter:dbFormatter];
        
        //return "real" last message
        NSNumber* historyID = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND (message_from=? OR message_to=?) ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountNo, contact, contact]];
        if(historyID == nil)
            return (MLMessage*)nil;
        return [self messageForHistoryID:historyID];
    }];
}

-(NSArray*) markMessagesAsReadForBuddy:(NSString*) buddy andAccount:(NSString*) accountNo tillStanzaId:(NSString*) stanzaid wasOutgoing:(BOOL) outgoing
{
    if(!buddy || !accountNo)
    {
        DDLogError(@"No buddy or accountNo specified!");
        return @[];
    }
    
    return [self.db idWriteTransaction:^{
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
            historyId = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND (message_to=? OR message_from=?) ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountNo, buddy, buddy]];
            
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
            messageArray = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE displayed=0 AND displayMarkerWanted=1 AND received=1 AND account_id=? AND message_to=? AND message_history_id<=? ORDER BY message_history_id ASC;" andArguments:@[accountNo, buddy, historyId]];
        else
            messageArray = [self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE unread=1 AND account_id=? AND message_from=? AND message_history_id<=? ORDER BY message_history_id ASC;" andArguments:@[accountNo, buddy, historyId]];
        
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
        return [self messagesForHistoryIDs:messageArray];
    }];
}

-(NSNumber*) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString*) messageId encrypted:(BOOL) encrypted messageType:(NSString*) messageType mimeType:(NSString*) mimeType size:(NSNumber*) size
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
        query = @"INSERT INTO message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, displayMarkerWanted, filetransferMimeType, filetransferSize) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?);";
        params = @[accountNo, from, to, dateTime, message, actualfrom, [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], messageId, messageType, [NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:YES], mimeType, size];
    }
    else
    {
        query = @"INSERT INTO message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, displayMarkerWanted) VALUES(?,?,?,?,?,?,?,?,?,?,?,?);";
        params = @[accountNo, from, to, dateTime, message, actualfrom, [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], messageId, messageType, [NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:YES]];
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
    // count # of meaages in message table
    return [self.db executeScalar:@"SELECT COUNT(message_history_id) FROM message_history WHERE unread=1 AND NOT EXISTS(SELECT * FROM muteList WHERE jid=message_history.message_from);"];
}

//set all unread messages to read
-(void) setAllMessagesAsRead
{
    NSString* query = @"UPDATE message_history SET unread=0 WHERE unread=1;";

    [self.db executeNonQuery:query];
}

-(NSString*) lastStanzaIdForAccount:(NSString*) accountNo
{
    return [self.db executeScalar:@"SELECT lastStanzaId FROM account WHERE account_id=?;" andArguments:@[accountNo]];
}

-(void) setLastStanzaId:(NSString*) lastStanzaId forAccount:(NSString*) accountNo
{
    [self.db executeNonQuery:@"UPDATE account SET lastStanzaId=? WHERE account_id=?;" andArguments:@[lastStanzaId, accountNo]];
}

#pragma mark active chats

-(NSMutableArray*) activeContactsWithPinned:(BOOL) pinned
{
    NSString* query = @"SELECT a.buddy_name, a.account_id FROM activechats AS a JOIN buddylist AS b ON (a.buddy_name = b.buddy_name AND a.account_id = b.account_id) JOIN account  ON a.account_id = account.account_id WHERE account.username != a.buddy_name AND a.pinned=? ORDER BY lastMessageTime DESC;";
    NSMutableArray* toReturn = [[NSMutableArray alloc] init];
    for(NSDictionary* dic in [self.db executeReader:query andArguments:@[[NSNumber numberWithBool:pinned]]])
        [toReturn addObject:[self contactForUsername:dic[@"buddy_name"] forAccount:dic[@"account_id"]]];
    return toReturn;
}

-(NSMutableArray*) activeContactDict
{
    NSString* query = @"select  distinct a.buddy_name, b.full_name, b.nick_name, a.account_id from activechats as a LEFT OUTER JOIN buddylist AS b ON a.buddy_name = b.buddy_name  AND a.account_id = b.account_id order by lastMessageTime desc";

    NSMutableArray* results = [self.db executeReader:query];
    
    NSMutableArray* toReturn = [[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSMutableDictionary* dic = [[NSMutableDictionary alloc] initWithDictionary:(NSDictionary*)obj];
        if(!dic[@"full_name"] || ![dic[@"full_name"] length])
        {
            //default is local part, see https://docs.modernxmpp.org/client/design/#contexts
            //see also: MLContact.m (the only other source that decides what to use as display name)
            NSDictionary* jidParts = [HelperTools splitJid:dic[@"buddy_name"]];
            dic[@"full_name"] = jidParts[@"node"];
        }
        [toReturn addObject:dic];
    }];
    return toReturn;
}

-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        //mark all messages as read
        [self.db executeNonQuery:@"UPDATE message_history SET unread=0 WHERE account_id=? AND (message_from=? OR message_to=?);" andArguments:@[accountNo, buddyname, buddyname]];
        //remove contact from active chats list
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE buddy_name=? AND account_id=?;" andArguments:@[buddyname, accountNo]];
    }];
}

-(void) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    if(!buddyname)
        return;
    
    [self.db voidWriteTransaction:^{
        NSString* accountJid = [self jidOfAccount:accountNo];
        if(!accountJid)
            return;
        if([accountJid isEqualToString:buddyname])
        {
            // Something is broken
            DDLogWarn(@"We should never try to create a chat with our own jid");
            return;
        }
        else
        {
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
    NSString* query = @"SELECT COUNT(buddy_name) FROM activechats WHERE account_id=? AND buddy_name=?;";
    NSNumber* count = (NSNumber*)[self.db executeScalar:query andArguments:@[accountNo, buddyname]];
    if(count != nil)
    {
        NSInteger val = [((NSNumber*)count) integerValue];
        return (val > 0);
    } else {
        return NO;
    }
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
    // count # messages from a specific user in messages table
    return [self.db executeScalar:@"SELECT COUNT(message_history_id) FROM message_history WHERE unread=1 AND account_id=? AND message_from=?;" andArguments:@[accountNo, buddy]];
}

#pragma db Commands

-(void) updateDBTo:(double) version withBlock:(monal_void_block_t) block
{
    static BOOL accountStateInvalidated = NO;
    if([(NSNumber*)[self.db executeScalar:@"SELECT dbversion FROM dbversion;"] doubleValue] < version)
    {
        DDLogVerbose(@"Database version <%@ detected. Performing upgrade.", [NSNumber numberWithDouble:version]);
        //needed for sqlite >= 3.26.0 (see https://sqlite.org/lang_altertable.html point 2)
        [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
        [self.db executeNonQuery:@"PRAGMA legacy_alter_table=on;"];
        block();
        [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
        [self.db executeNonQuery:@"PRAGMA legacy_alter_table=off;"];
        if(!accountStateInvalidated)
            [self invalidateAllAccountStates];
        accountStateInvalidated = YES;
        [self.db executeNonQuery:@"UPDATE dbversion SET dbversion=?;" andArguments:@[[NSNumber numberWithDouble:version]]];
        DDLogDebug(@"Upgrade to %@ success", [NSNumber numberWithDouble:version]);
    }
}

-(void) invalidateAllAccountStates
{
#ifndef IS_ALPHA
    @try {
#endif
        DDLogWarn(@"Invalidating state of all accounts...");
        for(NSDictionary* entry in [self.db executeReader:@"SELECT account_id FROM account;"])
            [self persistState:[xmpp invalidateState:[self readStateForAccount:entry[@"account_id"]]] forAccount:entry[@"account_id"]];
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
    
    //this has to be done only when upgrading from a db < 4.82 because only older databases use DELETE journal_mode
    //this is a special case because it can not be done while in a transaction!!!
    NSNumber* dbversionWithoutTransaction = (NSNumber*)[self.db executeScalar:@"select dbversion from dbversion;"];
    if([dbversionWithoutTransaction doubleValue] < 4.83)
    {
        //set wal mode (this setting is permanent): https://www.sqlite.org/pragma.html#pragma_journal_mode
        [self.db executeNonQuery:@"pragma journal_mode=WAL;"];
        DDLogWarn(@"transaction mode set to WAL");
    }
    
    [self.db voidWriteTransaction:^{
        NSNumber* dbversion = (NSNumber*)[self.db executeScalar:@"select dbversion from dbversion;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'protocol_id' integer NOT NULL, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"UPDATE account SET rosterVersion='0' WHERE rosterVersion is NULL;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
        }];

        [self updateDBTo:4.71 withBlock:^{

            // Only reset server to '' when server == domain
            [self.db executeNonQuery:@"UPDATE account SET server='' where server=domain;"];
        }];
        
        [self updateDBTo:4.72 withBlock:^{

            // Delete column protocol_id from account and drop protocol table
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
            [self.db executeNonQuery:@"DROP TABLE protocol;"];
        }];
        
        [self updateDBTo:4.73 withBlock:^{

            // Delete column oauth from account
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
        }];
        
        [self updateDBTo:4.74 withBlock:^{
            // Rename column oldstyleSSL to directTLS
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
        }];
        
        [self updateDBTo:4.75 withBlock:^{
            // Delete column secure from account
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state from _accountTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _accountTMP;"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'message_history' (message_history_id integer not null primary key AUTOINCREMENT, account_id integer, message_from text collate nocase, message_to text collate nocase, timestamp datetime, message blob, actual_from text collate nocase, messageid text, messageType text, sent bool, received bool, unread bool, encrypted bool, previewText text, previewImage text, stanzaid text, errorType text, errorReason text);"];
            [self.db executeNonQuery:@"INSERT INTO message_history (message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, sent, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason) SELECT message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, delivered, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason from _message_historyTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
        }];
        
        [self updateDBTo:4.83 withBlock:^{
            [self.db executeNonQuery:@"alter table activechats add column pinned bool DEFAULT FALSE;"];
        }];
        
        [self updateDBTo:4.84 withBlock:^{
            [self.db executeNonQuery:@"DROP TABLE IF EXISTS ipc;"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE signalPreKey RENAME TO _signalPreKeyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE 'signalPreKey' ('account_id' int NOT NULL, 'prekeyid' int NOT NULL, 'preKey' BLOB, 'creationTimestamp' INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, 'pubSubRemovalTimestamp' INTEGER DEFAULT NULL, 'keyUsed' INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (account_id, prekeyid, preKey));"];
            [self.db executeNonQuery:@"INSERT INTO signalPreKey (account_id, prekeyid, preKey) SELECT account_id, prekeyid, preKey FROM _signalPreKeyTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _signalPreKeyTMP;"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50), nick_name varchar(50), group_name varchar(50), iconhash varchar(200), filename varchar(100), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(255), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0);"];
            [self.db executeNonQuery:@"INSERT INTO buddylist (buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction) SELECT buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction FROM _buddylistTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact on buddylist(buddy_name, account_id);"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
        }];
        
        [self updateDBTo:4.992 withBlock:^{
            [self.db executeNonQuery:@"ALTER TABLE account ADD COLUMN statusMessage TEXT;"];
        }];
        
        [self updateDBTo:4.993 withBlock:^{
            //make filetransferMimeType and filetransferSize have NULL as default value
            //(this makes it possible to distinguish unknown values from known ones)
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE message_history (message_history_id integer not null primary key AUTOINCREMENT, account_id integer, message_from text collate nocase, message_to text collate nocase, timestamp datetime, message blob, actual_from text collate nocase, messageid text collate nocase, messageType text, sent bool, received bool, unread bool, encrypted bool, previewText text, previewImage text, stanzaid text collate nocase, errorType text collate nocase, errorReason text, displayed BOOL DEFAULT FALSE, displayMarkerWanted BOOL DEFAULT FALSE, filetransferMimeType VARCHAR(32) DEFAULT NULL, filetransferSize INTEGER DEFAULT NULL);"];
            [self.db executeNonQuery:@"INSERT INTO message_history SELECT * FROM _message_historyTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
            [self.db executeNonQuery:@"CREATE INDEX stanzaidIndex on message_history(stanzaid collate nocase);"];
            [self.db executeNonQuery:@"CREATE INDEX messageidIndex on message_history(messageid collate nocase);"];
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
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
            
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
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
            [self.db executeNonQuery:@"PRAGMA foreign_keys=off;"];
            [self.db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(255) collate nocase, full_name varchar(255), nick_name varchar(255), iconhash varchar(200), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(1024), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0, blocked BOOL DEFAULT FALSE, muc_type VARCHAR(10) DEFAULT 'channel', lastMucStanzaId text DEFAULT NULL, UNIQUE(account_id, buddy_name));"];
            [self.db executeNonQuery:@"INSERT INTO buddylist SELECT buddy_id, account_id, buddy_name, full_name, nick_name, iconhash, state, status, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction, blocked, 'channel', NULL FROM _buddylistTMP;"];
            [self.db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [self.db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact ON buddylist(buddy_name, account_id);"];
            [self.db executeNonQuery:@"UPDATE buddylist SET muc_type='channel' WHERE Muc = true;"];     //muc default type
            [self.db executeNonQuery:@"PRAGMA foreign_keys=on;"];
            
            //create new muc favorites table
            [self.db executeNonQuery:@"DROP TABLE muc_favorites;"];
            [self.db executeNonQuery:@"CREATE TABLE muc_favorites (room VARCHAR(255) PRIMARY KEY, nick varchar(255), account_id INTEGER, UNIQUE(room, account_id));"];
        }];
        
    }];
    
    DDLogInfo(@"Database version check complete");
    return;
}

#pragma mark mute and block
-(void) muteJid:(NSString*) jid
{
    if(!jid) return;
    NSString* query = @"INSERT INTO muteList(jid) VALUES(?);";
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) unMuteJid:(NSString*) jid
{
    if(!jid) return;
    NSString* query = @"DELETE FROM muteList WHERE jid=?;";
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(BOOL) isMutedJid:(NSString*) jid
{
    if(!jid) return NO;
    NSString* query = @"SELECT COUNT(jid) FROM muteList WHERE jid=?;";
    NSArray* params = @[jid];
    NSObject* val = [self.db executeScalar:query andArguments:params];
        NSNumber* count = (NSNumber *) val;
    BOOL toreturn = NO;
    if(count.integerValue > 0)
    {
        toreturn = YES;
    }
    return toreturn;
}

-(void) blockJid:(NSString*) jid withAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return;
    NSDictionary<NSString*, NSString*>* parsedJid = [HelperTools splitJid:jid];
    [self.db executeNonQuery:@"INSERT OR IGNORE INTO blocklistCache(account_id, node, host, resource) VALUES(?, ?, ?, ?)" andArguments:@[accountNo,
            parsedJid[@"node"] ? parsedJid[@"node"] : [NSNull null],
            parsedJid[@"host"] ? parsedJid[@"host"] : [NSNull null],
            parsedJid[@"resource"] ? parsedJid[@"resource"] : [NSNull null],
    ]];
}

-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids forAccountNo:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        // remove blocked state for all buddies of account
        [self.db executeNonQuery:@"DELETE FROM blocklistCache WHERE account_id=?" andArguments:@[accountNo]];
        // set blocking
        for(NSString* blockedJid in blockedJids)
        {
            [self blockJid:blockedJid withAccountNo:accountNo];
        }
    }];
}

-(void) unBlockJid:(NSString*) jid withAccountNo:(NSString*) accountNo
{
    NSDictionary<NSString*, NSString*>* parsedJid = [HelperTools splitJid:jid];

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
}

-(u_int8_t) isBlockedJid:(NSString*) jid withAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return NO;

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
        return kBlockingNoMatch;
    }
    if(blocked.intValue == 1)
        return ruleId;
    else
        return kBlockingNoMatch;
}

-(NSArray<NSDictionary<NSString*, NSString*>*>*) blockedJidsForAccount:(NSString*) accountNo
{
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
}

-(BOOL) isPinnedChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid
{
    if(!accountNo || !buddyJid)
        return NO;
    NSNumber* pinnedNum = [self.db executeScalar:@"SELECT pinned FROM activechats WHERE account_id=? AND buddy_name=?;" andArguments:@[accountNo, buddyJid]];
    if(pinnedNum != nil)
        return [pinnedNum boolValue];
    else
        return NO;
}

-(void) pinChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid
{
    if(!accountNo || !buddyJid) return;
    NSString* query = @"UPDATE activechats SET pinned=1 WHERE account_id=? AND buddy_name=?";
    [self.db executeNonQuery:query andArguments:@[accountNo, buddyJid]];
}
-(void) unPinChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid
{
    if(!accountNo || !buddyJid) return;
    NSString* query = @"UPDATE activechats SET pinned=0 WHERE account_id=? AND buddy_name=?";
    [self.db executeNonQuery:query andArguments:@[accountNo, buddyJid]];
}

#pragma mark - Filetransfers

-(NSArray*) getAllCachedImages
{
    return [self.db executeReader:@"SELECT DISTINCT * FROM imageCache;"];
}

-(NSArray*) getAllMessagesForFiletransferUrl:(NSString*) url
{
    return [self messagesForHistoryIDs:[self.db executeScalarReader:@"SELECT message_history_id FROM message_history WHERE message=?;" andArguments:@[url]]];
}

-(void) upgradeImageMessagesToFiletransferMessages
{
    [self.db executeNonQuery:@"UPDATE message_history SET messageType=? WHERE messageType=?;" andArguments:@[kMessageTypeFiletransfer, @"Image"]];
}

-(void) removeImageCacheTables
{
    [self.db executeNonQuery:@"DROP TABLE imageCache;"];
}

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSString*) accountNo
{
    if(!accountNo ||! contact)
        return nil;
    
    NSString* query = @"SELECT message_history_id FROM message_history WHERE messageType=? AND account_id=? AND (message_from=? OR message_to=?) GROUP BY message ORDER BY message_history_id ASC;";
    NSArray* params = @[kMessageTypeFiletransfer, accountNo, contact, contact];
    
    NSMutableArray* retval = [[NSMutableArray alloc] init];
    for(MLMessage* msg in [self messagesForHistoryIDs:[self.db executeScalarReader:query andArguments:params]])
        [retval addObject:[MLFiletransfer getFileInfoForMessage:msg]];
    return retval;
}

#pragma mark - last interaction

-(NSDate*) lastInteractionOfJid:(NSString* _Nonnull) jid forAccountNo:(NSString* _Nonnull) accountNo
{
    NSAssert(jid, @"jid should not be null");
    NSAssert(accountNo != NULL, @"accountNo should not be null");

    NSString* query = @"SELECT lastInteraction FROM buddylist WHERE account_id=? AND buddy_name=?;";
    NSArray* params = @[accountNo, jid];
    NSNumber* lastInteractionTime = (NSNumber*)[self.db executeScalar:query andArguments:params];

    //return NSDate object or 1970, if last interaction is zero
    if(![lastInteractionTime integerValue])
        return [[NSDate date] initWithTimeIntervalSince1970:0] ;
    return [NSDate dateWithTimeIntervalSince1970:[lastInteractionTime integerValue]];
}

-(void) setLastInteraction:(NSDate*) lastInteractionTime forJid:(NSString* _Nonnull) jid andAccountNo:(NSString* _Nonnull) accountNo
{
    NSAssert(jid, @"jid should not be null");
    NSAssert(accountNo != NULL, @"accountNo should not be null");

    NSNumber* timestamp = @0;       //default value for "online" or "unknown"
    if(lastInteractionTime)
        timestamp = [NSNumber numberWithInt:lastInteractionTime.timeIntervalSince1970];

    NSString* query = @"UPDATE buddylist SET lastInteraction=? WHERE account_id=? AND buddy_name=?;";
    NSArray* params = @[timestamp, accountNo, jid];
    [self.db executeNonQuery:query andArguments:params];
}

#pragma mark - encryption

-(BOOL) shouldEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return NO;
    NSString* query = @"SELECT encrypt from buddylist where account_id=? and buddy_name=?";
    NSArray* params = @[accountNo, jid];
    NSNumber* status=(NSNumber*)[self.db executeScalar:query andArguments:params];
    return [status boolValue];
}


-(void) encryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return;
    NSString* query = @"update buddylist set encrypt=1 where account_id=?  and buddy_name=?";
    NSArray* params = @[ accountNo, jid];
    [self.db executeNonQuery:query andArguments:params];
    return;
}

-(void) disableEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return ;
    NSString* query = @"update buddylist set encrypt=0 where account_id=?  and buddy_name=?";
    NSArray* params = @[ accountNo, jid];
    [self.db executeNonQuery:query andArguments:params];
    return;
}

#pragma mark History Message Search (search keyword in message, message_from, actual_from, messageType)

-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword accountNo:(NSString*) accountNo
{
    if(!keyword || !accountNo)
        return nil;
    return [self.db idWriteTransaction:^{
        NSString *likeString = [NSString stringWithFormat:@"%%%@%%", keyword];
        NSString* query = @"SELECT message_history_id FROM message_history WHERE account_id = ? AND (message like ? OR message_from LIKE ? OR actual_from LIKE ? OR messageType LIKE ?) ORDER BY timestamp ASC;";
        NSArray* params = @[accountNo, likeString, likeString, likeString, likeString];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}

-(NSArray*) searchResultOfHistoryMessageWithKeyWords:(NSString*) keyword accountNo:(NSString*) accountNo betweenBuddy:(NSString* _Nonnull) accountJid1 andBuddy:(NSString* _Nonnull) accountJid2
{
    if(!keyword || !accountNo)
        return nil;
    return [self.db idWriteTransaction:^{
        NSString *likeString = [NSString stringWithFormat:@"%%%@%%", keyword];
        NSString* query = @"SELECT message_history_id FROM message_history WHERE account_id=? AND message LIKE ? AND ((message_from=? AND message_to=?) OR (message_from=? AND message_to=?)) ORDER BY timestamp ASC;";
        NSArray* params = @[accountNo, likeString, accountJid1, accountJid2, accountJid2, accountJid1];
        NSArray* results = [self.db executeScalarReader:query andArguments:params];
        return [self messagesForHistoryIDs:results];
    }];
}
@end
