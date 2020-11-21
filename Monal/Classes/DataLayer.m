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
NSString *const kSelfSigned = @"selfsigned";
NSString *const kRosterName = @"rosterName";

NSString *const kUsername = @"username";

NSString *const kMessageType = @"messageType";
NSString *const kMessageTypeGeo = @"Geo";
NSString *const kMessageTypeImage = @"Image";
NSString *const kMessageTypeMessageDraft = @"MessageDraft";
NSString *const kMessageTypeStatus = @"Status";
NSString *const kMessageTypeText = @"Text";
NSString *const kMessageTypeUrl = @"Url";

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
    
    //open db and update db version
    [self version];
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

#pragma mark account commands

-(NSArray*) accountList
{
    NSString* query = @"select * from account order by account_id asc";
    NSArray* result = [self.db executeReader:query];
    return result;
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

-(NSNumber*) accountIDForUser:(NSString *) user andDomain:(NSString *) domain
{
    if(!user && !domain)
        return nil;

    NSString* cleanUser = user;
    NSString* cleanDomain = domain;

    if(!cleanDomain) cleanDomain= @"";
    if(!cleanUser) cleanUser= @"";

    NSString* query = @"select account_id from account where domain=? and username=?";
    NSArray* result = [self.db executeReader:query andArguments:@[cleanDomain, cleanUser]];
    if(result.count > 0) {
        return [result[0] objectForKey:@"account_id"];
    }
    return nil;
}

-(BOOL) doesAccountExistUser:(NSString*) user andDomain:(NSString *) domain
{
    NSString* query = @"select * from account where domain=? and username=?";
    NSArray* result = [self.db executeReader:query andArguments:@[domain, user]];
    return result.count > 0;
}

-(NSDictionary*) detailsForAccount:(NSString*) accountNo
{
    if(!accountNo)
        return nil;
    NSArray* result = [self.db executeReader:@"SELECT account_id, directTLS, domain, enabled, lastStanzaId, other_port, resource, rosterVersion, selfsigned, server, username, rosterName FROM account WHERE account_id=?;" andArguments:@[accountNo]];
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
    NSString* query = @"UPDATE account SET server=?, other_port=?, username=?, resource=?, domain=?, enabled=?, selfsigned=?, directTLS=?, rosterName=? WHERE account_id=?;";

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
                       [dictionary objectForKey:kRosterName] ? ((NSString*)[dictionary objectForKey:kRosterName]) : @"",
                       [dictionary objectForKey:kAccountID]
    ];

    return [self.db executeNonQuery:query andArguments:params];
}

-(NSNumber*) addAccountWithDictionary:(NSDictionary*) dictionary
{
    NSString* query = @"INSERT INTO account (server, other_port, resource, domain, enabled, selfsigned, directTLS, username, rosterName) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);";
    
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
        ((NSString *)[dictionary objectForKey:kUsername]),
        [dictionary objectForKey:kRosterName] ? ((NSString*)[dictionary objectForKey:kRosterName]) : @""
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
        [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=?;" andArguments:@[accountNo]];
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE account_id=?;" andArguments:@[accountNo]];
        return [self.db executeNonQuery:@"DELETE FROM account WHERE account_id=?;" andArguments:@[accountNo]];
    }];
}

-(BOOL) disableEnabledAccount:(NSString*) accountNo
{
    return [self.db executeNonQuery:@"UPDATE account SET enabled=0 WHERE account_id=?;" andArguments:@[accountNo]] != NO;
}

-(NSMutableDictionary *) readStateForAccount:(NSString*) accountNo
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
        
        NSString* query = @"INSERT INTO buddylist ('account_id', 'buddy_name', 'full_name', 'nick_name', 'new', 'online', 'dirty', 'muc', 'muc_nick') VALUES(?, ?, ?, ?, 1, 0, 0, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET nick_name=?;";
        if(!accountNo || !contact)
            return NO;
        else
        {
            NSArray* params = @[accountNo, contact, @"", toPass, mucNick?@1:@0, mucNick ? mucNick : @"", toPass];
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
        NSString* query2 = @"delete from buddy_resources where buddy_id in (select buddy_id from buddylist where account_id=?)";
        NSArray* params = @[accountNo];
        [self.db executeNonQuery:query2 andArguments:params];
        NSString* query = @"update buddylist set dirty=0, new=0, online=0, state='offline', status='' where account_id=?";
        return [self.db executeNonQuery:query andArguments:params];
    }];
}

-(MLContact*) contactForUsername:(NSString*) username forAccount:(NSString*) accountNo
{
    if(!username || !accountNo)
        return nil;
    
    NSArray* results = [self.db executeReader:@"SELECT b.buddy_name, state, status, filename, b.full_name, b.nick_name, muc_subject, muc_nick, b.account_id, lastMessageTime, 0 AS 'count', subscription, ask, IFNULL(pinned, 0) AS 'pinned', \
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
        return [MLContact contactFromDictionary:@{
            @"buddy_name": username,
            @"nick_name": @"",
            @"full_name": @"",
            @"filename": @"",
            @"subscription": kSubNone,
            @"ask": @"",
            @"account_id": accountNo,
            //@"muc_subject": nil,
            //@"muc_nick": nil,
            @"Muc": @NO,
            @"pinned": @NO,
            @"status": @"",
            @"state": kSubNone,
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

-(NSMutableArray*) onlineContactsSortedBy:(NSString*) sort
{
    NSString* query = @"";

    if([sort isEqualToString:@"Name"])
    {
        query = @"SELECT buddy_name, account_id FROM buddylist WHERE online=1 AND subscription='both' ORDER BY nick_name, full_name, buddy_name COLLATE NOCASE ASC;";
    }

    if([sort isEqualToString:@"Status"])
    {
        query = @"SELECT buddy_name, account_id FROM buddylist WHERE online=1 AND subscription='both' ORDER BY state, nick_name, full_name, buddy_name COLLATE NOCASE ASC;";
    }

    NSMutableArray* toReturn = [[NSMutableArray alloc] init];
    for(NSDictionary* dic in [self.db executeReader:query])
        [toReturn addObject:[self contactForUsername:dic[@"buddy_name"] forAccount:dic[@"account_id"]]];
    return toReturn;
}

-(NSMutableArray*) offlineContacts
{
    NSString* query = @"SELECT buddy_name, a.account_id FROM buddylist AS A INNER JOIN account AS b ON a.account_id=b.account_id WHERE online=0 AND enabled=1 ORDER BY nick_name, full_name, buddy_name COLLATE NOCASE ASC;";
    NSMutableArray* toReturn = [[NSMutableArray alloc] init];
    for(NSDictionary* dic in [self.db executeReader:query])
        [toReturn addObject:[self contactForUsername:dic[@"buddy_name"] forAccount:dic[@"account_id"]]];
    return toReturn;
}

#pragma mark entity capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andAccountNo:(NSString*) acctNo
{
    NSString* query = @"select count(*) from buddylist as a inner join buddy_resources as b on a.buddy_id=b.buddy_id inner join ver_info as c on b.ver=c.ver where buddy_name=? and account_id=? and cap=?";
    NSArray *params = @[user, acctNo, cap];
    NSNumber* count = (NSNumber*) [self.db executeScalar:query andArguments:params];
    return [count integerValue]>0;
}

-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource
{
    NSString* query = @"select ver from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where resource=? and buddy_name=?";
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
        if(![self isBuddyOnline:presenceObj.fromUser forAccount:accountNo])
        {
            NSString* query = @"update buddylist set online=1, new=1, muc=? where account_id=? and  buddy_name=?";
            NSArray* params = @[[NSNumber numberWithBool:[presenceObj check:@"{http://jabber.org/protocol/muc#user}x"]], accountNo, presenceObj.fromUser];
            [self.db executeNonQuery:query andArguments:params];
        }
    }];
}

-(BOOL) setOfflineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSString* query1 = @"select buddy_id from buddylist where account_id=? and  buddy_name=?;";
        NSArray* params=@[accountNo, presenceObj.fromUser];
        NSString* buddyid = (NSString*)[self.db executeScalar:query1 andArguments:params];
        if(buddyid == nil)
            return NO;

        NSString* query2 = @"delete from buddy_resources where buddy_id=? and resource=?";
        NSArray* params2 = @[buddyid, presenceObj.fromResource ? presenceObj.fromResource : @""];
        if([self.db executeNonQuery:query2 andArguments:params2] == NO)
            return NO;

        //see how many left
        NSString* resourceCount = [self.db executeScalar:@"select count(buddy_id) from buddy_resources where buddy_id=?;" andArguments:@[buddyid]];

        if([resourceCount integerValue] < 1)
        {
            NSString* query = @"update buddylist set online=0, state='offline', dirty=1 where account_id=? and buddy_name=?;";
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

    NSString* query = @"update buddylist set state=?, dirty=1 where account_id=? and  buddy_name=?;";
    [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.fromUser]];
}

-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo
{

    NSString* query = @"select state from buddylist where account_id=? and buddy_name=?";
    NSArray* params = @[accountNo, buddy];
    NSString* state = (NSString*)[self.db executeScalar:query andArguments:params];
    return state;
}

-(BOOL) hasContactRequestForAccount:(NSString*) accountNo andBuddyName:(NSString*) buddy
{
    NSString* query = @"SELECT count(*) FROM subscriptionRequests WHERE account_id=? AND buddy_name=?";

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

    NSString* query = @"update buddylist set status=?, dirty=1 where account_id=? and  buddy_name=?;";
    [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.fromUser]];
}

-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = @"select status from buddylist where account_id=? and buddy_name=?";
    NSString* iconname =  (NSString *)[self.db executeScalar:query andArguments:@[accountNo, buddy]];
    return iconname;
}

-(NSString *) getRosterVersionForAccount:(NSString*) accountNo
{
    NSString* query = @"SELECT rosterVersion from account where account_id=?";
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

    NSString* query = @"update buddylist set full_name=?, dirty=1 where account_id=? and  buddy_name=?";
    NSArray* params = @[toPass , accountNo, contact];
    [self.db executeNonQuery:query  andArguments:params];
}

-(void) setAvatarHash:(NSString*) hash forContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    [self.db voidWriteTransaction:^{
        [self.db executeNonQuery:@"UPDATE account SET iconhash=? WHERE account_id=? AND printf('%s@%s', username, domain)=?;" andArguments:@[hash, accountNo, contact]];
        [self.db executeNonQuery:@"UPDATE buddylist SET iconhash=?, dirty=1 WHERE account_id=? AND buddy_name=?;" andArguments:@[hash, accountNo, contact]];
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

-(BOOL) isBuddyOnline:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSNumber* count = [self.db executeScalar:@"select count(buddy_id) from buddylist where account_id=? and buddy_name=? and online=1;" andArguments:@[accountNo, buddy]];
    if(count != nil && [count integerValue] > 0)
        return YES;
    return NO;
}

-(BOOL) saveMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo withComment:(NSString*) comment
{
    NSString* query = @"update buddylist set messageDraft=? where account_id=? and buddy_name=?";
    NSArray* params = @[comment, accountNo, buddy];
    BOOL success = [self.db executeNonQuery:query andArguments:params];

    return success;
}

-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = @"SELECT messageDraft from buddylist where account_id=? and buddy_name=?";
    NSArray* params = @[accountNo, buddy];
    NSObject* messageDraft = [self.db executeScalar:query andArguments:params];
    return (NSString*)messageDraft;
}

#pragma mark MUC

-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = @"SELECT Muc from buddylist where account_id=?  and buddy_name=? ";
    NSArray* params = @[ accountNo, buddy];
    NSNumber* status=(NSNumber*)[self.db executeScalar:query andArguments:params];
    return [status boolValue];
}

-(NSString *) ownNickNameforMuc:(NSString*) room andServer:(NSString*) server forAccount:(NSString*) accountNo
{
    NSString *combinedRoom = room;
    if([combinedRoom componentsSeparatedByString:@"@"].count == 1) {
        combinedRoom = [NSString stringWithFormat:@"%@@%@", room, server];
    }

    NSString* query = @"SELECT muc_nick from buddylist where account_id=?  and buddy_name=? ";
    NSArray* params = @[ accountNo, combinedRoom];
    NSString * nick=(NSString*)[self.db executeScalar:query andArguments:params];
    if(nick.length==0) {
        NSString* query2= @"SELECT nick from muc_favorites where account_id=?  and room=? ";
        NSArray *params2=@[ accountNo, combinedRoom];
        nick=(NSString*)[self.db executeScalar:query2 andArguments:params2];
    }
    return nick;
}

-(BOOL) updateOwnNickName:(NSString *) nick forMuc:(NSString*) room andServer:(NSString*) server forAccount:(NSString*) accountNo
{
    NSString* combinedRoom = room;
    if([combinedRoom componentsSeparatedByString:@"@"].count == 1) {
        combinedRoom = [NSString stringWithFormat:@"%@@%@", room, server];
    }

    NSString* query = @"update buddylist set muc_nick=?, muc=1 where account_id=? and buddy_name=?";
    NSArray* params = @[nick, accountNo, combinedRoom];
    DDLogVerbose(@"%@", query);

    return [self.db executeNonQuery:query andArguments:params];
}


-(BOOL) addMucFavoriteForAccount:(NSString*) accountNo withRoom:(NSString *) room nick:(NSString *)nick autoJoin:(BOOL) autoJoin
{
    NSString* query = @"insert into muc_favorites (room, nick, autojoin, account_id) values(?, ?, ?, ?)";
    NSArray* params = @[room, nick, [NSNumber numberWithBool:autoJoin], accountNo];
    DDLogVerbose(@"%@", query);

    return [self.db executeNonQuery:query andArguments:params];
}

-(BOOL) updateMucFavorite:(NSNumber *) mucid forAccountId:(NSInteger) accountNo autoJoin:(BOOL) autoJoin
{
    NSString* query = @"update muc_favorites set autojoin=? where mucid=? and account_id=?";
    NSArray* params = @[[NSNumber numberWithBool:autoJoin], mucid, [NSNumber numberWithInteger:accountNo]];
    DDLogVerbose(@"%@", query);

    return [self.db executeNonQuery:query andArguments:params];
}

-(BOOL) deleteMucFavorite:(NSNumber *) mucid forAccountId:(NSInteger) accountNo
{
    NSString* query = @"delete from muc_favorites where mucid=? and account_id=?";
    NSArray* params = @[mucid, [NSNumber numberWithInteger:accountNo]];
    DDLogVerbose(@"%@", query);

    BOOL success = [self.db executeNonQuery:query andArguments:params];
    return success;
}

-(NSMutableArray*) mucFavoritesForAccount:(NSString*) accountNo
{
    return [self.db executeReader:@"SELECT * FROM muc_favorites WHERE account_id=?;" andArguments:@[accountNo]];
}

-(BOOL) updateMucSubject:(NSString *) subject forAccount:(NSString*) accountNo andRoom:(NSString *) room
{
    NSString* query = @"update buddylist set muc_subject=? where account_id=? and buddy_name=?";
    NSArray* params = @[subject, accountNo, room];
    DDLogVerbose(@"%@", query);

    BOOL success = [self.db executeNonQuery:query andArguments:params];
    return success;
}

-(NSString*) mucSubjectforAccount:(NSString*) accountNo andRoom:(NSString *) room
{
    NSString* query = @"select muc_subject from buddylist where account_id=? and buddy_name=?";

    NSArray* params = @[accountNo, room];
    DDLogVerbose(@"%@", query);

    NSObject* result = [self.db executeScalar:query andArguments:params];
    return (NSString *)result;
}

#pragma mark message Commands

-(MLMessage*) messageForHistoryID:(NSInteger) historyID
{
    NSString* query = @"SELECT IFNULL(actual_from, message_from) AS af, message_from, message_to, account_id, message, received, displayed, displayMarkerWanted, encrypted, timestamp  AS thetime, message_history_id, sent, messageid, messageType, previewImage, previewText, unread, errorType, errorReason, stanzaid FROM message_history WHERE message_history_id=?;";
    NSArray* params = @[[NSNumber numberWithInteger:historyID]];

    for(NSDictionary* dic in [self.db executeReader:query andArguments:params])
        return [MLMessage messageFromDictionary:dic withDateFormatter:dbFormatter];
    return nil;
}

-(void) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString *) messageid serverMessageId:(NSString *) stanzaid messageType:(NSString *) messageType andOverrideDate:(NSDate *) messageDate encrypted:(BOOL) encrypted backwards:(BOOL) backwards displayMarkerWanted:(BOOL) displayMarkerWanted withCompletion: (void (^)(BOOL, NSString*, NSNumber*))completion
{
    if(!from || !to || !message)
    {
        if(completion)
            completion(NO, nil, nil);
        return;
    }

    NSString* typeToUse=messageType;
    if(!typeToUse) typeToUse=kMessageTypeText; //default to insert

    [self.db beginWriteTransaction];
    if(![self hasMessageForStanzaId:stanzaid orMessageID:messageid toContact:actualfrom onAccount:accountNo])
    {
        //this is always from a contact
        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSDate* sourceDate=[NSDate date];
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
        if(!messageType && [actualfrom isEqualToString:from])
        {
            NSString* foundMessageType = [self messageTypeForMessage:message withKeepThread:YES];
            NSString* query;
            NSArray* params;
            if(backwards)
            {
                NSNumber* nextHisoryId = [NSNumber numberWithInt:[(NSNumber*)[self.db executeScalar:@"SELECT MIN(message_history_id) FROM message_history;"] intValue] - 1];
                query = @"insert into message_history (message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
                params = @[nextHisoryId, accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", foundMessageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@""];
            }
            else
            {
                //we use autoincrement here instead of MAX(message_history_id) + 1 to be a little bit faster (but at the cost of "duplicated code")
                query = @"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
                params = @[accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", foundMessageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@""];
            }
            DDLogVerbose(@"%@", query);
            BOOL success = [self.db executeNonQuery:query andArguments:params];
            NSNumber* historyId = [self.db lastInsertId];
            if(success)
                [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo];
            [self.db endWriteTransaction];
            if(completion)
                completion(success, messageType, historyId);
        }
        else
        {
            NSString* query = @"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
            NSArray* params = @[accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithInteger:unread], [NSNumber numberWithInteger:sent], messageid?messageid:@"", typeToUse, [NSNumber numberWithInteger:encrypted], stanzaid?stanzaid:@"" ];
            DDLogVerbose(@"%@", query);
            BOOL success = [self.db executeNonQuery:query andArguments:params];
            NSNumber* historyId = [self.db lastInsertId];
            if(success)
                [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo];
            [self.db endWriteTransaction];
            if(completion)
                completion(success, messageType, historyId);
        }
    }
    else
    {
        DDLogError(@"Message(%@) %@ with stanzaid %@ already existing, ignoring history update", accountNo, messageid, stanzaid);
        [self.db endWriteTransaction];
        if(completion)
            completion(NO, nil, nil);
    }
}

-(BOOL) hasMessageForStanzaId:(NSString*) stanzaId orMessageID:(NSString*) messageId toContact:(NSString*) contact onAccount:(NSString*) accountNo
{
    if(!accountNo)
        return NO;
    
    return [self.db boolWriteTransaction:^{
        if(stanzaId)
        {
            NSObject* found = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND stanzaid!='' AND stanzaid=?;" andArguments:@[accountNo, stanzaId]];
            if(found)
                return YES;
        }
        
        //we check message ids per contact to increase uniqueness and abort here if no contact was provided
        if(!contact)
            return NO;
        
        NSNumber* historyId = (NSNumber*)[self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND message_from=? AND messageid=?;" andArguments:@[accountNo, contact, messageId]];
        if(historyId)
        {
            if(stanzaId)
            {
                DDLogVerbose(@"Updating stanzaid of message_history_id %@ to %@ for (account=%@, messageid=%@, contact=%@)...", historyId, stanzaId, accountNo, messageId, contact);
                //this entry needs an update of its stanzaid
                [self.db executeNonQuery:@"UPDATE message_history SET stanzaid=? WHERE message_history_id=?" andArguments:@[stanzaId, historyId]];
            }
            return YES;
        }
        
        return NO;
    }];
}

-(void) setMessageId:(NSString*) messageid sent:(BOOL) sent
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

-(void) setMessageId:(NSString*) messageid received:(BOOL) received
{
    NSString* query = @"update message_history set received=?, sent=? where messageid=?";
    DDLogVerbose(@"setting received confrmed %@", messageid);
    [self.db executeNonQuery:query andArguments:@[[NSNumber numberWithBool:received], [NSNumber numberWithBool:YES], messageid]];
}

-(void) setMessageId:(NSString*) messageid errorType:(NSString*) errorType errorReason:(NSString*) errorReason
{
    //ignore error if the message was already received by *some* client
    if([self.db executeScalar:@"SELECT messageid FROM message_history WHERE messageid=? AND received" andArguments:@[messageid]])
    {
        DDLogVerbose(@"ignoring message error for %@ [%@, %@]", messageid, errorType, errorReason);
        return;
    }
    NSString* query = @"update message_history set errorType=?, errorReason=? where messageid=?";
    DDLogVerbose(@"setting message error %@ [%@, %@]", messageid, errorType, errorReason);
    [self.db executeNonQuery:query andArguments:@[errorType, errorReason, messageid]];
}

-(void) setMessageId:(NSString*) messageid messageType:(NSString *) messageType
{
    NSString* query = @"update message_history set messageType=? where messageid=?";
    DDLogVerbose(@"setting message type %@", messageid);
    [self.db executeNonQuery:query andArguments:@[messageType, messageid]];
}

-(void) setMessageId:(NSString*) messageid previewText:(NSString *) text andPreviewImage:(NSString *) image
{
    if(!messageid) return;
    NSString* query = @"update message_history set previewText=?,  previewImage=? where messageid=?";
    DDLogVerbose(@"setting previews type %@", messageid);
    [self.db executeNonQuery:query  andArguments:@[text?text:@"", image?image:@"", messageid]];
}

-(void) setMessageId:(NSString*) messageid stanzaId:(NSString *) stanzaId
{
    NSString* query = @"update message_history set stanzaid=? where messageid=?";
    DDLogVerbose(@"setting message stanzaid %@", query);
    [self.db executeNonQuery:query andArguments:@[stanzaId, messageid]];
}

-(void) clearMessages:(NSString*) accountNo
{
    [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=?;" andArguments:@[accountNo]];
}

-(void) deleteMessageHistory:(NSNumber*) messageNo
{
    [self.db executeNonQuery:@"DELETE FROM message_history WHERE message_history_id=?;" andArguments:@[messageNo]];
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

            return nil;
        }
    } else return nil;
}

-(NSArray*) messageHistoryDateForContact:(NSString*) contact forAccount:(NSString*) accountNo forDate:(NSString*) date
{
    NSString* query = @"select af, message_from, message_to, message, thetime, sent, message_history_id from (select ifnull(actual_from, message_from) as af, message_from, message_to, message, sent, timestamp  as thetime, message_history_id, previewImage, previewText from message_history where account_id=? and (message_from=? or message_to=?) and date(timestamp)=? order by message_history_id desc) order by message_history_id asc";
    NSArray* params = @[accountNo, contact, contact, date];

    DDLogVerbose(@"%@", query);
    NSArray* results = [self.db executeReader:query andArguments:params];

    NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *dic = (NSDictionary *) obj;
        [toReturn addObject:[MLMessage messageFromDictionary:dic withDateFormatter:dbFormatter]];
    }];

    if(toReturn!=nil)
    {

        DDLogVerbose(@"count: %lu",  (unsigned long)[toReturn count]);

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
        return nil;
    }
}

-(BOOL) messageHistoryClean:(NSString*) buddy forAccount:(NSString*) accountNo
{
    return [self.db executeNonQuery:@"DELETE FROM message_history WHERE account_id=? AND (message_from=? OR message_to=?);" andArguments:@[accountNo, buddy, buddy]];
}

-(BOOL) messageHistoryCleanAll
{
    return [self.db executeNonQuery:@"DELETE FROM message_history;"];
}

-(NSMutableArray *) messageHistoryContacts:(NSString*) accountNo
{
    //returns a list of  buddy's with message history
    NSString* accountJid = [self jidOfAccount:accountNo];
    if(accountJid)
    {

        NSString* query = @"SELECT x.* FROM (select distinct buddy_name AS thename ,'', nick_name, message_from AS buddy_name, filename, a.account_id from message_history AS a LEFT OUTER JOIN buddylist AS b ON a.message_from=b.buddy_name AND a.account_id=b.account_id WHERE a.account_id=? UNION select distinct message_to as thename ,'',  nick_name, message_to as buddy_name,  filename, a.account_id from message_history as a left outer JOIN buddylist AS b ON a.message_to=b.buddy_name AND a.account_id=b.account_id WHERE a.account_id=? AND message_to!=\"(null)\" ) AS x WHERE buddy_name!=? ORDER BY thename COLLATE NOCASE;";
        NSArray* params = @[accountNo, accountNo,
                            accountJid];
        //DDLogVerbose(query);
        NSMutableArray* toReturn = [[NSMutableArray alloc] init];
        for(NSDictionary* dic in [self.db executeReader:query andArguments:params])
            [toReturn addObject:[self contactForUsername:dic[@"buddy_name"] forAccount:dic[@"account_id"]]];
        return toReturn;
    }
    else
        return nil;
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
    if(!accountNo || !buddy || !msgHistoryID) {
        return nil;
    };
    NSString* query = @"select af, message_from, message_to, account_id, message, thetime, message_history_id, sent, messageid, messageType, received, displayed, displayMarkerWanted, encrypted, previewImage, previewText, unread, errorType, errorReason, stanzaid from (select ifnull(actual_from, message_from) as af, message_from, message_to, account_id, message, received, displayed, displayMarkerWanted, encrypted, timestamp  as thetime, message_history_id, sent,messageid, messageType, previewImage, previewText, unread, errorType, errorReason, stanzaid from message_history where account_id=? and (message_from=? or message_to=?) and message_history_id<? order by message_history_id desc limit ?) order by message_history_id asc";
    NSNumber* msgLimit = [NSNumber numberWithInt:kMonalChatFetchedMsgCnt];
    NSArray* params = @[accountNo, buddy, buddy, msgHistoryID, msgLimit];
    NSArray* result = [self.db executeReader:query andArguments:params];
    NSMutableArray* toReturn = [[NSMutableArray alloc] initWithCapacity:result.count];
    [result enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary* dic = (NSDictionary *) obj;
        [toReturn addObject:[MLMessage messageFromDictionary:dic withDateFormatter:dbFormatter]];
    }];

    if(toReturn!=nil)
    {
        DDLogVerbose(@" message history count: %lu",  (unsigned long)[toReturn count]);
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
    }
    return toReturn;
}

-(NSMutableArray*) lastMessageForContact:(NSString*) contact forAccount:(NSString*) accountNo
{
    if(!accountNo ||! contact) return nil;
    NSString* query = @"SELECT message, thetime, messageType, message_to, message_from, actual_from AS 'af' FROM (SELECT 1 AS messagePrio, bl.messageDraft AS message, ac.lastMessageTime AS thetime, 'MessageDraft' AS messageType, ? AS message_to, '' AS message_from, '' AS actual_from FROM buddylist AS bl INNER JOIN activechats AS ac WHERE bl.account_id = ac.account_id AND bl.buddy_name = ac.buddy_name AND ac.account_id=? AND ac.buddy_name=? AND messageDraft IS NOT NULL AND messageDraft != '' UNION SELECT 2 AS messagePrio, message, timestamp, messageType, message_to, message_from, actual_from FROM (SELECT message, timestamp, messageType, message_to, message_from, actual_from FROM message_history WHERE account_id=? AND (message_from=? OR message_to=?) ORDER BY message_history_id DESC LIMIT 1) ORDER BY messagePrio ASC LIMIT 1);";
    NSArray* params = @[contact, accountNo, contact, accountNo, contact, contact];

    NSMutableArray* results = [self.db executeReader:query andArguments:params];
    NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *dic = (NSDictionary *) obj;
        [toReturn addObject:[MLMessage messageFromDictionary:dic withDateFormatter:dbFormatter]];
    }];

    if(toReturn != nil)
    {
        DDLogVerbose(@" message history count: %lu", (unsigned long)[toReturn count]);
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
    }
    return toReturn;
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
            if(!historyId)
            {
                DDLogVerbose(@"Stanzaid not found, trying messageid");
                historyId = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND messageid=? ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountNo, stanzaid]];
            }
            
            if(!historyId)
            {
                DDLogWarn(@"Could not get message_history_id for stanzaid/messageid %@", stanzaid);
                return @[];     //no messages with this stanzaid / messageid could be found
            }
        }
        else        //no stanzaid given --> return all unread / not displayed messages for this contact
        {
            DDLogDebug(@"Returning newest historyId (no stanzaid/messageid given)");
            historyId = [self.db executeScalar:@"SELECT message_history_id FROM message_history WHERE account_id=? AND (message_to=? OR message_from=?) ORDER BY message_history_id DESC LIMIT 1;" andArguments:@[accountNo, buddy, buddy]];
            
            if(!historyId)
            {
                DDLogWarn(@"Could not get newest message_history_id (history empty)");
                return @[];     //no messages with this stanzaid / messageid could be found
            }
        }
        
        //on outgoing messages we only allow displayed=true for markable messages that have been received properly by the other end
        //marking messages as displayed that have not been received (or marking messages that are not markable) would create false UI
        NSArray* messageArray;
        if(outgoing)
            messageArray = [self.db executeReader:@"SELECT ifnull(actual_from, message_from) as af, * FROM message_history WHERE displayed=0 AND displayMarkerWanted=1 AND received=1 AND account_id=? AND message_to=? AND message_history_id<=? ORDER BY message_history_id ASC;" andArguments:@[accountNo, buddy, historyId]];
        else
            messageArray = [self.db executeReader:@"SELECT ifnull(actual_from, message_from) as af, * FROM message_history WHERE unread=1 AND account_id=? AND message_from=? AND message_history_id<=? ORDER BY message_history_id ASC;" andArguments:@[accountNo, buddy, historyId]];
        
        DDLogVerbose(@"[%@:%@] messageArray=%@", outgoing ? @"OUT" : @"IN", historyId, messageArray);
        
        //return NSArray of MLMessage objects instead of NSArray of plain NSDictionary objects coming directly from db
        //use this iteration to mark messages as read/displayed, too
        NSMutableArray* retval = [[NSMutableArray alloc] init];
        for(NSDictionary* entry in messageArray)
        {
            [retval addObject:[MLMessage messageFromDictionary:entry withDateFormatter:dbFormatter]];
            if(outgoing)
                [self.db executeNonQuery:@"UPDATE message_history SET displayed=1 WHERE message_history_id=? AND received=1;" andArguments:@[entry[@"message_history_id"]]];
            else
                [self.db executeNonQuery:@"UPDATE message_history SET unread=0 WHERE message_history_id=?;" andArguments:@[entry[@"message_history_id"]]];
        }
        
        return (NSArray*)retval;
    }];
}

-(void) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString *)messageId encrypted:(BOOL) encrypted withCompletion:(void (^)(BOOL, NSString*, NSNumber*)) completion
{
    //Message_history going out, from is always the local user. always read and not sent

    NSString *cleanedActualFrom = actualfrom;

    if([actualfrom isEqualToString:@"(null)"])
    {
        //handle null dictionary string
        cleanedActualFrom = from;
    }

    NSString* messageType = [self messageTypeForMessage:message withKeepThread:YES];

    NSArray* parts = [[[NSDate date] description] componentsSeparatedByString:@" "];
    NSString* dateTime = [NSString stringWithFormat:@"%@ %@", [parts objectAtIndex:0], [parts objectAtIndex:1]];
    NSString* query = @"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, displayMarkerWanted) values (?,?,?,?,?,?,?,?,?,?,?,?);";
    NSArray* params = @[accountNo, from, to, dateTime, message, cleanedActualFrom, [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], messageId, messageType, [NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:YES]];
    
    [self.db voidWriteTransaction:^{
        DDLogVerbose(@"%@", query);
        BOOL result = [self.db executeNonQuery:query andArguments:params];
        NSNumber* historyId = [self.db lastInsertId];
        if(result)
            [self updateActiveBuddy:to setTime:dateTime forAccount:accountNo];
        //include this completion handler in our db transaction to include the smacks state update in the same transaction as the our history update
        if(completion)
            completion(result, messageType, historyId);
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

-(NSDate*) lastMessageDateForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    NSString* query = @"select timestamp from message_history where account_id=? and (message_from=? or (message_to=? and sent=1)) order by timestamp desc limit 1";

    NSObject* result = [self.db executeScalar:query andArguments:@[accountNo, contact, contact]];
    if(!result) return nil;
    
    NSDateFormatter *dateFromatter = [[NSDateFormatter alloc] init];
    NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

    [dateFromatter setLocale:enUSPOSIXLocale];
    [dateFromatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss"];
    [dateFromatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    NSDate* datetoReturn = [dateFromatter dateFromString:(NSString *)result];

    // We could not parse the string -> default to 0
    if(datetoReturn == nil)
        datetoReturn = [[NSDate date] initWithTimeIntervalSince1970:0];

    return datetoReturn;
}

-(NSString*) lastStanzaIdForAccount:(NSString*) accountNo
{
    return [self.db executeScalar:@"SELECT lastStanzaId FROM account WHERE account_id=?;" andArguments:@[accountNo]];
}

-(void) setLastStanzaId:(NSString*) lastStanzaId forAccount:(NSString*) accountNo
{
    [self.db executeNonQuery:@"UPDATE account SET lastStanzaId=? WHERE account_id=?;" andArguments:@[lastStanzaId, accountNo]];
}

-(NSDate*) lastMessageDateAccount:(NSString*) accountNo
{
    NSString* query = @"select timestamp from message_history where account_id=? order by timestamp desc limit 1";

    NSObject* result = [self.db executeScalar:query andArguments:@[accountNo]];

    NSDateFormatter* dateFromatter = [[NSDateFormatter alloc] init];
    NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

    [dateFromatter setLocale:enUSPOSIXLocale];
    [dateFromatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss"];
    [dateFromatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    NSDate* datetoReturn = [dateFromatter dateFromString:(NSString *)result];
    return datetoReturn;
}

-(NSString*)lastMessageActualFromByHistoryId:(NSNumber*) lastMsgHistoryId
{
    return [self.db executeScalar:@"select actual_from from message_history where message_history_id=? order by timestamp desc limit 1" andArguments:@[lastMsgHistoryId]];
}

#pragma mark active chats

-(NSMutableArray*) activeContactsWithPinned:(BOOL) pinned
{
    NSString* query = @"SELECT a.buddy_name, a.account_id FROM activechats AS a JOIN buddylist AS b WHERE a.buddy_name = b.buddy_name AND a.account_id = b.account_id AND a.pinned=? ORDER BY lastMessageTime DESC;";
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

-(BOOL) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    if(!buddyname)
        return NO;
    
    return [self.db boolWriteTransaction:^{
        // Check that we do not add a chat a second time to activechats
        if([self isActiveBuddy:buddyname forAccount:accountNo])
            return YES;
        
        NSString* accountJid = [self jidOfAccount:accountNo];
        if(!accountJid)
            return NO;
        
        if([accountJid isEqualToString:buddyname])
        {
            // Something is broken
            DDLogWarn(@"We should never try to create a chat with our own jid");
            return NO;
        }
        else
        {
            // insert
            NSString* query3 = @"INSERT INTO activechats (buddy_name, account_id, lastMessageTime) VALUES(?, ?, current_timestamp);";
            BOOL result = [self.db executeNonQuery:query3 andArguments:@[buddyname, accountNo]];
            return result;
        }
    }];
}


-(BOOL) isActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    NSString* query = @"select count(buddy_name) from activechats where account_id=? and buddy_name=? ";
    NSNumber* count = (NSNumber*)[self.db executeScalar:query andArguments:@[accountNo, buddyname]];
    if(count != nil)
    {
        NSInteger val = [((NSNumber*)count) integerValue];
        return (val > 0);
    } else {
        return NO;
    }
}

-(BOOL) updateActiveBuddy:(NSString*) buddyname setTime:(NSString *)timestamp forAccount:(NSString*) accountNo
{
    return [self.db boolWriteTransaction:^{
        NSString* query = @"select lastMessageTime from  activechats where account_id=? and buddy_name=?";
        NSObject* result = [self.db executeScalar:query andArguments:@[accountNo, buddyname]];
        NSString* lastTime = (NSString *) result;

        NSDate* lastDate = [dbFormatter dateFromString:lastTime];
        NSDate* newDate = [dbFormatter dateFromString:timestamp];

        if(lastDate.timeIntervalSince1970<newDate.timeIntervalSince1970) {
            NSString* query = @"update activechats set lastMessageTime=? where account_id=? and buddy_name=? ";
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
        block();
        if(!accountStateInvalidated)
            [self invalidateAllAccountStates];
        accountStateInvalidated = YES;
        [self.db executeNonQuery:@"UPDATE dbversion SET dbversion=?;" andArguments:@[[NSNumber numberWithDouble:version]]];
        DDLogDebug(@"Upgrade to %@ success", [NSNumber numberWithDouble:version]);
    }
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
            [self.db executeNonQuery:@" alter table activechats add COLUMN lastMessageTime datetime "];

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

        // remove dupl entries from activechats && budylist
        [self updateDBTo:4.990 withBlock:^{
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
    }];
    
    DDLogInfo(@"Database version check complete");
    return;
}

-(void) invalidateAllAccountStates
{
    DDLogWarn(@"Invalidating state of all accounts (but keeping outgoing unacked stanzas)...");
    for(NSDictionary* entry in [self.db executeReader:@"SELECT account_id FROM account;"])
        [self persistState:[xmpp invalidateState:[self readStateForAccount:entry[@"account_id"]]] forAccount:entry[@"account_id"]];
}

#pragma mark determine message type

-(NSString*) messageTypeForMessage:(NSString *) messageString withKeepThread:(BOOL) keepThread
{
    dispatch_semaphore_t semaphore;
    __block NSString* messageType = kMessageTypeText;
    if([messageString rangeOfString:@" "].location != NSNotFound) {
        return messageType;
    }

    if ([messageString hasPrefix:@"xmpp:"]) {
           messageType=kMessageTypeUrl;
    }

    if ([[HelperTools defaultsDB] boolForKey: @"ShowImages"] &&
        ([messageString hasPrefix:@"HTTPS://"] || [messageString hasPrefix:@"https://"] || [messageString hasPrefix:@"aesgcm://"])) {
            NSString *cleaned = [messageString stringByReplacingOccurrencesOfString:@"aesgcm://" withString:@"https://"];
            NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:cleaned]];
            request.HTTPMethod = @"HEAD";
            request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;

            if(keepThread)
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

                if(keepThread)
                    dispatch_semaphore_signal(semaphore);
            }] resume];

            if(keepThread)
            {
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            }
    } else if ([messageString hasPrefix:@"geo:"]) {
        messageType = kMessageTypeGeo;
    }
    return messageType;
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


-(void) blockJid:(NSString*) jid
{
    if(!jid ) return;
    NSString* query = @"insert into blockList(jid) values(?)";
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) unBlockJid:(NSString*) jid
{
    if(!jid ) return;
    NSString* query = @"delete from blockList where jid=?";
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(BOOL) isBlockedJid:(NSString*) jid
{
    if(!jid) return NO;
    NSString* query = @"select count(jid) from blockList where jid=?";
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

-(BOOL) isPinnedChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid
{
    if(!accountNo || !buddyJid) return NO;
    NSString* query = @"SELECT pinned FROM activechats WHERE account_id=? AND buddy_name=?";
    NSNumber* pinnedNum = (NSNumber*)[self.db executeScalar:query andArguments:@[accountNo, buddyJid]];
    
    if(pinnedNum) {
        return [pinnedNum boolValue];
    } else {
        return NO;
    }
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

#pragma mark - Images

-(void) createImageCache:(NSString *) path forUrl:(NSString*) url
{
    NSString* query = @"insert into imageCache(url, path) values(?, ?)";
    NSArray* params = @[url, path];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) deleteImageCacheForUrl:(NSString*) url
{
    NSString* query = @"delete from imageCache where url=?";
    NSArray* params = @[url];
    [self.db executeNonQuery:query andArguments:params];
}

-(NSString*) imageCacheForUrl:(NSString*) url
{
    if(!url) return nil;
    NSString* query = @"select path from imageCache where url=?";
    NSArray* params = @[url];
    NSObject* val = [self.db executeScalar:query andArguments:params];
    NSString* path = (NSString *) val;
    return path;
}

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSString*) accountNo
{
    if(!accountNo ||! contact) return nil;
    NSString* query = @"select distinct A.* from imageCache as A inner join  message_history as B on message = a.url where account_id=? and actual_from=? order by message_history_id desc";
    NSArray* params = @[accountNo, contact];
    NSMutableArray* toReturn = [[self.db executeReader:query andArguments:params] mutableCopy];

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

-(NSArray*)searchResultOfHistoryMessageWithKeyWords:(NSString*)keyword accountNo:(NSString*) accountNo
{
    if(!keyword || !accountNo) return nil;
    NSString *likeString = [NSString stringWithFormat:@"%%%@%%", keyword];
    NSString* query = @"select actual_from as af, message_from, message_to, account_id, message, timestamp  as thetime, message_history_id, sent, messageid, messageType, received, encrypted, previewImage, previewText, unread, errorType, errorReason, stanzaid from message_history where account_id = ? and (message like ? or message_from like ? or actual_from like ? or messageType like ?) order by timestamp";
    
    NSArray* params = @[accountNo, likeString, likeString, likeString, likeString];
    NSArray* result = [self.db executeReader:query andArguments:params];
    NSMutableArray* toReturn = [[NSMutableArray alloc] initWithCapacity:result.count];
    for (NSDictionary* dic in result)
    {
        [toReturn addObject:[MLMessage messageFromDictionary:dic withDateFormatter:dbFormatter]];
    }
    
    if(toReturn!=nil)
    {
        DDLogVerbose(@" message history count: %lu",  (unsigned long)[toReturn count]);
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
    }
    return toReturn;
}

#pragma mark History Message Search (search keyword in message, message_from, actual_from, messageType)

-(NSArray*)searchResultOfHistoryMessageWithKeyWords:(NSString*)keyword accountNo:(NSString*) accountNo betweenBuddy:(NSString * _Nonnull) accountJid1 andBuddy:(NSString * _Nonnull)accountJid2
{
    if(!keyword || !accountNo) return nil;
    NSString *likeString = [NSString stringWithFormat:@"%%%@%%", keyword];
    NSString* query = @"select actual_from as af, message_from, message_to, account_id, message, timestamp  as thetime0, message_history_id, sent, messageid, messageType, received, encrypted, previewImage, previewText, unread, errorType, errorReason, stanzaid from message_history where account_id = ? and (message like ?) and (((message_from = ?) and (message_to = ?)) or ((message_from = ?) and (message_to = ?)) ) order by timestamp";
    
    NSArray* params = @[accountNo, likeString, accountJid1, accountJid2, accountJid2, accountJid1];
    
    NSArray* result = [self.db executeReader:query andArguments:params];
    NSMutableArray* toReturn = [[NSMutableArray alloc] initWithCapacity:result.count];
    for (NSDictionary* dic in result)
    {
        [toReturn addObject:[MLMessage messageFromDictionary:dic withDateFormatter:dbFormatter]];
    }
    
    if(toReturn!=nil)
    {
        DDLogVerbose(@" message history count: %lu",  (unsigned long)[toReturn count]);
    }
    else
    {
        DDLogError(@"message history is empty or failed to read");
    }
    return toReturn;
}
@end
