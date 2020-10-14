//
//  DataLayer.m
//  SworIM
//
//  Created by Anurodh Pokharel on 3/28/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "DataLayer.h"
#import "MLSQLite.h"
#import "HelperTools.h"
#import "MLXMLNode.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"
#import "XMPPIQ.h"

@interface DataLayer()
@property (readonly, strong) MLSQLite* db;
@end

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
    NSString* query = [NSString stringWithFormat:@"select * from account order by account_id asc"];
    NSArray* result = [self.db executeReader:query];
    return result;
}

-(NSNumber*) enabledAccountCnts
{
    NSString* query = [NSString stringWithFormat:@"SELECT COUNT(*) FROM account WHERE enabled=1"];
    return (NSNumber*)[self.db executeScalar:query];
}

-(NSArray*) enabledAccountList
{
    NSString* query = [NSString stringWithFormat:@"select * from account where enabled=1 order by account_id asc"];
    NSArray* toReturn = [self.db executeReader:query andArguments:@[]] ;

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

-(NSNumber*) accountIDForUser:(NSString *) user andDomain:(NSString *) domain
{
    if(!user && !domain)
        return nil;

    NSString* cleanUser = user;
    NSString* cleanDomain = domain;

    if(!cleanDomain) cleanDomain= @"";
    if(!cleanUser) cleanUser= @"";

    NSString* query = [NSString stringWithFormat:@"select account_id from account where domain=? and username=?"];
    NSArray* result = [self.db executeReader:query andArguments:@[cleanDomain, cleanUser]];
    if(result.count > 0) {
        return [result[0] objectForKey:@"account_id"];
    }
    return nil;
}

-(BOOL) doesAccountExistUser:(NSString*) user andDomain:(NSString *) domain
{
    NSString* query = [NSString stringWithFormat:@"select * from account where domain=? and username=?"];
    NSArray* result = [self.db executeReader:query andArguments:@[domain, user]];
    return result.count > 0;
}

-(NSDictionary*) detailsForAccount:(NSString*) accountNo
{
    if(!accountNo)
        return nil;
    NSArray* result = [self.db executeReader:@"select account_id, directTLS, domain, enabled, lastStanzaId, other_port, resource, rosterVersion, selfsigned, server, username from account where account_id=?;" andArguments:@[accountNo]];
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
    NSString* query = [NSString stringWithFormat:@"select username, domain from account where account_id=?"];
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

    return [self.db executeNonQuery:query andArguments:params];
}

-(NSNumber*) addAccountWithDictionary:(NSDictionary*) dictionary
{
    NSString* query = [NSString stringWithFormat:@"insert into account (server, other_port, resource, domain, enabled, selfsigned, directTLS, username) values(?, ?, ?, ?, ?, ?, ?, ?);"];
    
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
    [self.db beginWriteTransaction];

    NSString* query1 = [NSString stringWithFormat:@"delete from buddylist  where account_id=%@;", accountNo];
    [self.db executeNonQuery:query1];

    NSString* query3= [NSString stringWithFormat:@"delete from message_history  where account_id=%@;", accountNo];
    [self.db executeNonQuery:query3];

    NSString* query4= [NSString stringWithFormat:@"delete from activechats  where account_id=%@;", accountNo];
    [self.db executeNonQuery:query4];

    NSString* query = [NSString stringWithFormat:@"delete from account  where account_id=%@;", accountNo];
    BOOL lastResult = [self.db executeNonQuery:query];

    [self.db endWriteTransaction];

    return (lastResult != NO);
}

-(BOOL) disableEnabledAccount:(NSString*) accountNo
{

    NSString* query = [NSString stringWithFormat:@"update account set enabled=0 where account_id=%@  ", accountNo];
    return ([self.db executeNonQuery:query andArguments:@[]]!=NO);
}

-(NSMutableDictionary *) readStateForAccount:(NSString*) accountNo
{
    if(!accountNo) return nil;
    NSString* query = [NSString stringWithFormat:@"SELECT state from account where account_id=?"];
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
            [MLXMLNode class],
            [XMPPIQ class],
            [XMPPPresence class],
            [XMPPMessage class]
        ]] fromData:data error:&error];
        if(error)
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
        return dic;
    }
    return nil;
}

-(void) persistState:(NSMutableDictionary*) state forAccount:(NSString*) accountNo
{
    if(!accountNo || !state) return;
    NSString* query = [NSString stringWithFormat:@"update account set state=? where account_id=?"];
    NSError* error;
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:state requiringSecureCoding:YES error:&error];
    if(error)
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:@{@"error": error}];
    NSArray *params = @[data, accountNo];
    [self.db executeNonQuery:query andArguments:params];
}

#pragma mark contact Commands

-(BOOL) addContact:(NSString*) contact forAccount:(NSString*) accountNo fullname:(NSString*) fullName nickname:(NSString*) nickName andMucNick:(NSString*) mucNick
{
    // no blank full names
    NSString* actualfull = fullName;
    if([[actualfull stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0)
        actualfull = contact;

    NSString* query = [NSString stringWithFormat:@"insert into buddylist ('account_id', 'buddy_name', 'full_name', 'nick_name', 'new', 'online', 'dirty', 'muc', 'muc_nick') values(?, ?, ?, ?, 1, 0, 0, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET account_id=?, buddy_name=?;"];
    if(!(accountNo && contact && actualfull && nickName)) {
        return NO;
    } else  {
        NSArray* params = @[accountNo, contact, actualfull, nickName, mucNick?@1:@0, mucNick ? mucNick : @"", accountNo, contact];
        BOOL success = [self.db executeNonQuery:query andArguments:params];
        return success;
    }
}

-(void) removeBuddy:(NSString*) buddy forAccount:(NSString*) accountNo
{
    [self.db beginWriteTransaction];
    //clean up logs
    [self messageHistoryClean:buddy :accountNo];

    NSString* query = [NSString stringWithFormat:@"delete from buddylist where account_id=? and buddy_name=?;"];
    NSArray* params = @[accountNo, buddy];

    [self.db executeNonQuery:query andArguments:params];

    [self setSubscription:kSubNone andAsk:@"" forContact:buddy andAccount:accountNo];
    [self.db endWriteTransaction];
}

-(BOOL) clearBuddies:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"delete from buddylist where account_id=%@;", accountNo];
    return ([self.db executeNonQuery:query andArguments:@[]] != NO);
}

#pragma mark Buddy Property commands

-(BOOL) resetContactsForAccount:(NSString*) accountNo
{
    if(!accountNo) return NO;
    [self.db beginWriteTransaction];
    NSString* query2 = [NSString stringWithFormat:@"delete from buddy_resources where buddy_id in (select buddy_id from buddylist where account_id=?)"];
    NSArray* params = @[accountNo];
    [self.db executeNonQuery:query2 andArguments:params];


    NSString* query = [NSString stringWithFormat:@"update buddylist set dirty=0, new=0, online=0, state='offline', status='' where account_id=?"];
    BOOL retval = [self.db executeNonQuery:query andArguments:params];
    [self.db endWriteTransaction];

    return (retval != NO);
}

-(NSArray*) contactForUsername:(NSString*) username forAccount: (NSString*) accountNo
{
    if(!username || !accountNo) return nil;
    NSString* query = query = [NSString stringWithFormat:@"SELECT a.buddy_name,  state, status,  filename, ifnull(b.full_name, a.buddy_name) AS full_name, nick_name, muc_subject, muc_nick, a.account_id, lastMessageTime, 0 AS 'count', subscription, ask, pinned from activechats as a JOIN buddylist AS b WHERE a.buddy_name = b.buddy_name AND a.account_id = b.account_id AND a.buddy_name=? and a.account_id=?"];
    NSArray* params = @[username, accountNo];

    NSArray* results = [self.db executeReader:query andArguments:params];
    if(results != nil)
    {
        DDLogVerbose(@" count: %lu",  (unsigned long)[results count]);

    }
    else
    {
        DDLogError(@"buddylist is empty or failed to read");
    }

    NSMutableArray* toReturn = [[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary* dic = (NSDictionary *) obj;
        [toReturn addObject:[MLContact contactFromDictionary:dic]];
    }];
    return toReturn;
}


-(NSArray*) searchContactsWithString:(NSString*) search
{
    NSString *likeString = [NSString stringWithFormat:@"%%%@%%", search];
    NSString* query = @"";
    query = [NSString stringWithFormat:@"select buddy_name, state, status, filename, 0 as 'count', ifnull(full_name, buddy_name) as full_name, account_id, online from buddylist where buddy_name like ? or full_name like ? order by full_name COLLATE NOCASE asc "];

    NSArray *params = @[likeString, likeString];

    //DDLogVerbose(query);
    NSArray* results = [self.db executeReader:query andArguments:params];

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

-(NSMutableArray*) onlineContactsSortedBy:(NSString*) sort
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

    NSMutableArray* results = [self.db executeReader:query];

    NSMutableArray *toReturn = [[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *dic = (NSDictionary *) obj;
        [toReturn addObject:[MLContact contactFromDictionary:dic]];
    }];
    return toReturn;
}

-(NSMutableArray*) offlineContacts
{
    NSString* query = [NSString stringWithFormat:@"select buddy_name, A.state, status, filename, 0, ifnull(full_name, buddy_name) as full_name,nick_name, a.account_id, MUC, muc_subject, muc_nick from buddylist as A inner join account as b  on a.account_id=b.account_id  where  online=0 and enabled=1 order by full_name COLLATE NOCASE "];
    NSMutableArray* results = [self.db executeReader:query];

    NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *dic = (NSDictionary *) obj;
        [toReturn addObject:[MLContact contactFromDictionary:dic]];
    }];
    return toReturn;
}

#pragma mark entity capabilities

-(BOOL) checkCap:(NSString*) cap forUser:(NSString*) user andAccountNo:(NSString*) acctNo
{
    NSString* query = [NSString stringWithFormat:@"select count(*) from buddylist as a inner join buddy_resources as b on a.buddy_id=b.buddy_id inner join ver_info as c on b.ver=c.ver where buddy_name=? and account_id=? and cap=?"];
    NSArray *params = @[user, acctNo, cap];
    NSNumber* count = (NSNumber*) [self.db executeScalar:query andArguments:params];
    return [count integerValue]>0;
}

-(NSString*) getVerForUser:(NSString*) user andResource:(NSString*) resource
{
    NSString* query = [NSString stringWithFormat:@"select ver from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where resource=? and buddy_name=?"];
    NSArray * params = @[resource, user];
    NSString* ver = (NSString*) [self.db executeScalar:query andArguments:params];
    return ver;
}

-(void) setVer:(NSString*) ver forUser:(NSString*) user andResource:(NSString*) resource
{
    NSNumber* timestamp = [NSNumber numberWithInt:[NSDate date].timeIntervalSince1970];
    [self.db beginWriteTransaction];
    
    //set ver for user and resource
    NSString* query = [NSString stringWithFormat:@"UPDATE buddy_resources SET ver=? WHERE EXISTS(SELECT * FROM buddylist WHERE buddy_resources.buddy_id=buddylist.buddy_id AND resource=? AND buddy_name=?)"];
    NSArray * params = @[ver, resource, user];
    [self.db executeNonQuery:query andArguments:params];
    
    //update timestamp for this ver string to make it not timeout (old ver strings and features are removed from feature cache after 28 days)
    NSString* query2 = [NSString stringWithFormat:@"INSERT INTO ver_timestamp (ver, timestamp) VALUES (?, ?) ON CONFLICT(ver) DO UPDATE SET timestamp=?;"];
    NSArray * params2 = @[ver, timestamp, timestamp];
    [self.db executeNonQuery:query2 andArguments:params2];
    
    [self.db endWriteTransaction];
}

-(NSSet*) getCapsforVer:(NSString*) ver
{
    NSString* query = [NSString stringWithFormat:@"select cap from ver_info where ver=?"];
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
    [self.db beginWriteTransaction];
    
    //remove old caps for this ver
    NSString* query0 = [NSString stringWithFormat:@"DELETE FROM ver_info WHERE ver=?;"];
    NSArray * params0 = @[ver];
    [self.db executeNonQuery:query0 andArguments:params0];
    
    //insert new caps
    for(NSString* feature in caps)
    {
        NSString* query1 = [NSString stringWithFormat:@"INSERT INTO ver_info (ver, cap) VALUES (?, ?);"];
        NSArray * params1 = @[ver, feature];
        [self.db executeNonQuery:query1 andArguments:params1];
    }
    
    //update timestamp for this ver string
    NSString* query2 = [NSString stringWithFormat:@"INSERT INTO ver_timestamp (ver, timestamp) VALUES (?, ?) ON CONFLICT(ver) DO UPDATE SET timestamp=?;"];
    NSArray * params2 = @[ver, timestamp, timestamp];
    [self.db executeNonQuery:query2 andArguments:params2];
    
    //cleanup old entries
    NSString* query3 = [NSString stringWithFormat:@"SELECT ver FROM ver_timestamp WHERE timestamp<?"];
    NSArray* params3 = @[[NSNumber numberWithInt:[timestamp integerValue] - (86400 * 28)]];     //cache timeout is 28 days
    NSArray* oldEntries = [self.db executeReader:query3 andArguments:params3];
    if(oldEntries)
        for(NSDictionary* row in oldEntries)
        {
            NSString* query4 = [NSString stringWithFormat:@"DELETE FROM ver_info WHERE ver=?;"];
            NSArray * params4 = @[row[@"ver"]];
            [self.db executeNonQuery:query4 andArguments:params4];
        }
    
    [self.db endWriteTransaction];
}

#pragma mark presence functions

-(void) setResourceOnline:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
{
    if(!presenceObj.fromResource)
        return;
    [self.db writeTransaction:^{
        //get buddyid for name and account
        NSString* query1 = [NSString stringWithFormat:@"select buddy_id from buddylist where account_id=? and buddy_name=?;"];
        NSObject* buddyid = [self.db executeScalar:query1 andArguments:@[accountNo, presenceObj.fromUser]];
        if(buddyid)
        {
            NSString* query = [NSString stringWithFormat:@"insert or ignore into buddy_resources ('buddy_id', 'resource', 'ver') values (?, ?, '')"];
            [self.db executeNonQuery:query andArguments:@[buddyid, presenceObj.fromResource]];
        }
    }];
}


-(NSArray*) resourcesForContact:(NSString*) contact
{
    if(!contact) return nil;
    NSString* query1 = [NSString stringWithFormat:@" select resource from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where  buddy_name=?  "];
    NSArray* params = @[contact ];
    NSArray* resources = [self.db executeReader:query1 andArguments:params];
    return resources;
}

-(NSArray*) softwareVersionInfoForAccount:(NSString*)account andContact:(NSString*)contact
{
    if(!account) return nil;
    NSString* query1 = [NSString stringWithFormat:@"select platform_App_Name, platform_App_Version, platform_OS from buddy_resources where buddy_id in (select buddy_id from buddylist where account_id=? and buddy_name=?)"];
    NSArray* params = @[account, contact];
    NSArray* resources = [self.db executeReader:query1 andArguments:params];
    return resources;
}

-(void) setSoftwareVersionInfoForAppName:(NSString*)appName
                      appVersion:(NSString*)appVersion
                      platformOS:(NSString*)platformOS
                     withAccount:(NSString*)account
                      andContact:(NSString*)contact
{
    NSString* query = [NSString stringWithFormat:@"update buddy_resources set platform_App_Name=?, platform_App_Version=?, platform_OS=? where buddy_id in (select buddy_id from buddylist where account_id=? and buddy_name=?)"];
    NSArray* params = @[appName, appVersion, platformOS, account, contact];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) setOnlineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
{
    [self.db writeTransaction:^{
        [self setResourceOnline:presenceObj forAccount:accountNo];
        if(![self isBuddyOnline:presenceObj.fromUser forAccount:accountNo])
        {
            NSString* query = [NSString stringWithFormat:@"update buddylist set online=1, new=1, muc=? where account_id=? and  buddy_name=?"];
            NSArray* params = @[[NSNumber numberWithBool:[presenceObj check:@"{http://jabber.org/protocol/muc#user}x"]], accountNo, presenceObj.fromUser];
            [self.db executeNonQuery:query andArguments:params];
        }
    }];
}

-(BOOL) setOfflineBuddy:(XMPPPresence*) presenceObj forAccount:(NSString*) accountNo
{
    [self.db beginWriteTransaction];
    NSString* query1 = [NSString stringWithFormat:@" select buddy_id from buddylist where account_id=? and  buddy_name=?;"];
    NSArray* params=@[accountNo, presenceObj.fromUser];
    NSString* buddyid = (NSString*)[self.db executeScalar:query1 andArguments:params];
    if(buddyid == nil)
    {
        [self.db endWriteTransaction];
        return NO;
    }

    NSString* query2 = [NSString stringWithFormat:@"delete from buddy_resources where buddy_id=? and resource=?"];
    NSArray* params2 = @[buddyid, presenceObj.fromResource ? presenceObj.fromResource : @""];
    if([self.db executeNonQuery:query2 andArguments:params2] == NO)
    {
        [self.db endWriteTransaction];
        return NO;
    }

    //see how many left
    NSString* query3 = [NSString stringWithFormat:@"select count(buddy_id) from buddy_resources where buddy_id=%@;", buddyid ];
    NSString* resourceCount = (NSString*)[self.db executeScalar:query3];

    if([resourceCount integerValue]<1)
    {
        NSString* query = [NSString stringWithFormat:@"update buddylist set online=0, state='offline', dirty=1 where account_id=? and buddy_name=?;"];
        NSArray* params4 = @[accountNo, presenceObj.fromUser];
        BOOL retval = [self.db executeNonQuery:query andArguments:params4];
        [self.db endWriteTransaction];
        return retval;
    }
    else
    {
        [self.db endWriteTransaction];
        return NO;
    }
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

    NSString* query = [NSString stringWithFormat:@"update buddylist set state=?, dirty=1 where account_id=? and  buddy_name=?;"];
    [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.fromUser]];
}

-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo
{

    NSString* query = [NSString stringWithFormat:@"select state from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, buddy];
    NSString* state = (NSString*)[self.db executeScalar:query andArguments:params];
    return state;
}

-(BOOL) hasContactRequestForAccount:(NSString*) accountNo andBuddyName:(NSString*) buddy
{
    NSString* query = [NSString stringWithFormat:@"SELECT count(*) FROM subscriptionRequests WHERE account_id=? AND buddy_name=?"];

    NSNumber* result = (NSNumber*)[self.db executeScalar:query andArguments:@[accountNo, buddy]];

    return result.intValue == 1;
}

-(NSMutableArray*) contactRequestsForAccount
{
    NSString* query = [NSString stringWithFormat:@"select account_id, buddy_name from subscriptionRequests"];

    NSMutableArray* results = [self.db executeReader:query];

     NSMutableArray* toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
     [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
         NSDictionary* dic = (NSDictionary *) obj;
         [toReturn addObject:[MLContact contactFromDictionary:dic]];
     }];
    return toReturn;
}

-(void) addContactRequest:(MLContact *) requestor;
{
    NSString* query2 = [NSString stringWithFormat:@"INSERT OR IGNORE INTO subscriptionRequests (buddy_name, account_id) VALUES (?,?)"];
    [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId] ];
}

-(void) deleteContactRequest:(MLContact *) requestor
{
    NSString* query2 = [NSString stringWithFormat:@"delete from subscriptionRequests where buddy_name=? and account_id=? "];
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

    NSString* query = [NSString stringWithFormat:@"update buddylist set status=?, dirty=1 where account_id=? and  buddy_name=?;"];
    [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.fromUser]];
}

-(NSString*) buddyStatus:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"select status from buddylist where account_id=? and buddy_name=?"];
    NSString* iconname =  (NSString *)[self.db executeScalar:query andArguments:@[accountNo, buddy]];
    return iconname;
}

-(NSString *) getRosterVersionForAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"SELECT rosterVersion from account where account_id=?"];
    NSArray* params = @[ accountNo];
    NSString * version=(NSString*)[self.db executeScalar:query andArguments:params];
    return version;
}

-(void) setRosterVersion:(NSString *) version forAccount: (NSString*) accountNo
{
    if(!accountNo || !version) return;
    NSString* query = [NSString stringWithFormat:@"update account set rosterVersion=? where account_id=?"];
    NSArray* params = @[version , accountNo];
    [self.db executeNonQuery:query  andArguments:params];
}

-(NSDictionary *) getSubscriptionForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    if(!contact || !accountNo) return nil;
    NSString* query = [NSString stringWithFormat:@"SELECT subscription, ask from buddylist where buddy_name=? and account_id=?"];
    NSArray* params = @[contact, accountNo];
    NSArray* version=[self.db executeReader:query andArguments:params];
    return version.firstObject;
}

-(void) setSubscription:(NSString *)sub andAsk:(NSString*) ask forContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    if(!contact || !accountNo || !sub) return;
    NSString* query = [NSString stringWithFormat:@"update buddylist set subscription=?, ask=? where account_id=? and buddy_name=?"];
    NSArray* params = @[sub, ask?ask:@"", accountNo, contact];
    [self.db executeNonQuery:query  andArguments:params];
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
    [self.db executeNonQuery:query  andArguments:params];
}

-(void) setNickName:(NSString*) nickName forContact:(NSString*) buddy andAccount:(NSString*) accountNo
{
    if(!nickName || !buddy) return;
    NSString* toPass;
    //data length check

    if([nickName length]>50) toPass=[nickName substringToIndex:49]; else toPass=nickName;
    NSString* query = [NSString stringWithFormat:@"update buddylist set nick_name=?, dirty=1 where account_id=? and  buddy_name=?"];
    NSArray* params = @[toPass, accountNo, buddy];

    [self.db executeNonQuery:query andArguments:params];
}

-(NSString*) nickName:(NSString*) buddy forAccount:(NSString*) accountNo;
{
    if(!accountNo  || !buddy) return nil;
    NSString* query = [NSString stringWithFormat:@"select nick_name from buddylist where account_id=? and buddy_name=?"];
    NSArray * params=@[accountNo, buddy];
    NSString* fullname= (NSString*)[self.db executeScalar:query andArguments:params];
    return fullname;
}

-(NSString*) fullNameForContact:(NSString*) contact inAccount:(NSString*) accountNo
{
    if(!accountNo  || !contact) return nil;
    NSString* query = [NSString stringWithFormat:@"select full_name from buddylist where account_id=? and buddy_name=?"];
    NSArray * params=@[accountNo, contact];
    NSObject* name = [self.db executeScalar:query andArguments:params];
    return (NSString *)name;
}

-(void) setAvatarHash:(NSString*) hash forContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    [self.db executeNonQuery:@"update buddylist set iconhash=?, dirty=1 where account_id=? and buddy_name=?;" andArguments:@[hash, accountNo, contact]];

}

-(NSString*) getAvatarHashForContact:(NSString*) buddy andAccount:(NSString*) accountNo
{
    return [self.db executeScalar:@"select iconhash from buddylist where account_id=? and buddy_name=?" andArguments:@[accountNo, buddy]];
}

-(BOOL) isContactInList:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"select count(buddy_id) from buddylist where account_id=? and buddy_name=? "];
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
    NSString* query = [NSString stringWithFormat:@"update buddylist set messageDraft=? where account_id=? and buddy_name=?"];
    NSArray* params = @[comment, accountNo, buddy];
    BOOL success = [self.db executeNonQuery:query andArguments:params];

    return success;
}

-(NSString*) loadMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"SELECT messageDraft from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, buddy];
    NSObject* messageDraft = [self.db executeScalar:query andArguments:params];
    return (NSString*)messageDraft;
}

#pragma mark MUC

-(BOOL) isBuddyMuc:(NSString*) buddy forAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"SELECT Muc from buddylist where account_id=?  and buddy_name=? "];
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

    NSString* query = [NSString stringWithFormat:@"SELECT muc_nick from buddylist where account_id=?  and buddy_name=? "];
    NSArray* params = @[ accountNo, combinedRoom];
    NSString * nick=(NSString*)[self.db executeScalar:query andArguments:params];
    if(nick.length==0) {
        NSString* query2= [NSString stringWithFormat:@"SELECT nick from muc_favorites where account_id=?  and room=? "];
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

    NSString* query = [NSString stringWithFormat:@"update buddylist set muc_nick=?, muc=1 where account_id=? and buddy_name=?"];
    NSArray* params = @[nick, accountNo, combinedRoom];
    DDLogVerbose(@"%@", query);

    return [self.db executeNonQuery:query andArguments:params];
}


-(BOOL) addMucFavoriteForAccount:(NSString*) accountNo withRoom:(NSString *) room nick:(NSString *)nick autoJoin:(BOOL) autoJoin
{
    NSString* query = [NSString stringWithFormat:@"insert into muc_favorites (room, nick, autojoin, account_id) values(?, ?, ?, ?)"];
    NSArray* params = @[room, nick, [NSNumber numberWithBool:autoJoin], accountNo];
    DDLogVerbose(@"%@", query);

    return [self.db executeNonQuery:query andArguments:params];
}

-(BOOL) updateMucFavorite:(NSNumber *) mucid forAccountId:(NSInteger) accountNo autoJoin:(BOOL) autoJoin
{
    NSString* query = [NSString stringWithFormat:@"update muc_favorites set autojoin=? where mucid=? and account_id=?"];
    NSArray* params = @[[NSNumber numberWithBool:autoJoin], mucid, [NSNumber numberWithInteger:accountNo]];
    DDLogVerbose(@"%@", query);

    return [self.db executeNonQuery:query andArguments:params];
}

-(BOOL) deleteMucFavorite:(NSNumber *) mucid forAccountId:(NSInteger) accountNo
{
    NSString* query = [NSString stringWithFormat:@"delete from muc_favorites where mucid=? and account_id=?"];
    NSArray* params = @[mucid, [NSNumber numberWithInteger:accountNo]];
    DDLogVerbose(@"%@", query);

    BOOL success = [self.db executeNonQuery:query andArguments:params];
    return success;
}

-(NSMutableArray*) mucFavoritesForAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"select * from muc_favorites where account_id=%@", accountNo];
    DDLogVerbose(@"%@", query);
    NSMutableArray* favorites = [self.db executeReader:query];
    if(favorites != nil) {
        DDLogVerbose(@"fetched muc favorites");
    }
    else{
        DDLogVerbose(@"could not fetch  muc favorites");

    }
    return favorites;
}

-(BOOL) updateMucSubject:(NSString *) subject forAccount:(NSString*) accountNo andRoom:(NSString *) room
{
    NSString* query = [NSString stringWithFormat:@"update buddylist set muc_subject=? where account_id=? and buddy_name=?"];
    NSArray* params = @[subject, accountNo, room];
    DDLogVerbose(@"%@", query);

    BOOL success = [self.db executeNonQuery:query andArguments:params];
    return success;
}

-(NSString*) mucSubjectforAccount:(NSString*) accountNo andRoom:(NSString *) room
{
    NSString* query = [NSString stringWithFormat:@"select muc_subject from buddylist where account_id=? and buddy_name=?"];

    NSArray* params = @[accountNo, room];
    DDLogVerbose(@"%@", query);

    NSObject* result = [self.db executeScalar:query andArguments:params];
    return (NSString *)result;
}

#pragma mark message Commands

-(NSArray *) messageForHistoryID:(NSInteger) historyID
{
    NSString* query = [NSString stringWithFormat:@"select message, messageid from message_history where message_history_id=%ld", (long)historyID];
    NSArray* messageArray= [self.db executeReader:query];
    return messageArray;
}

-(void) addMessageFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withBody:(NSString*) message actuallyfrom:(NSString*) actualfrom sent:(BOOL) sent unread:(BOOL) unread messageId:(NSString *) messageid serverMessageId:(NSString *) stanzaid messageType:(NSString *) messageType andOverrideDate:(NSDate *) messageDate encrypted:(BOOL) encrypted backwards:(BOOL) backwards displayMarkerWanted:(BOOL) displayMarkerWanted withCompletion: (void (^)(BOOL, NSString*))completion
{
    if(!from || !to || !message) {
        if(completion) completion(NO, nil);
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
                query = [NSString stringWithFormat:@"insert into message_history (message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"];
                params = @[nextHisoryId, accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", foundMessageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@""];
            }
            else
            {
                //we use autoincrement here instead of MAX(message_history_id) + 1 to be a little bit faster (but at the cost of "duplicated code")
                query = [NSString stringWithFormat:@"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, displayMarkerWanted, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"];
                params = @[accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithBool:unread], [NSNumber numberWithBool:sent], [NSNumber numberWithBool:displayMarkerWanted], messageid?messageid:@"", foundMessageType, [NSNumber numberWithBool:encrypted], stanzaid?stanzaid:@""];
            }
            DDLogVerbose(@"%@", query);
            BOOL success = [self.db executeNonQuery:query andArguments:params];
            if(success)
                [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo];
            [self.db endWriteTransaction];
            if(completion)
                completion(success, messageType);
        }
        else
        {
            NSString* query = [NSString stringWithFormat:@"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, stanzaid) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"];
            NSArray* params = @[accountNo, from, to, dateString, message, actualfrom, [NSNumber numberWithInteger:unread], [NSNumber numberWithInteger:sent], messageid?messageid:@"", typeToUse, [NSNumber numberWithInteger:encrypted], stanzaid?stanzaid:@"" ];
            DDLogVerbose(@"%@", query);
            BOOL success = [self.db executeNonQuery:query andArguments:params];
            if(success)
                [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo];
            [self.db endWriteTransaction];
            if(completion)
                completion(success, messageType);
        }
    }
    else
    {
        DDLogError(@"Message(%@) %@ with stanzaid %@ already existing, ignoring history update", accountNo, messageid, stanzaid);
        [self.db endWriteTransaction];
        if(completion)
            completion(NO, nil);
    }
}

-(BOOL) hasMessageForStanzaId:(NSString*) stanzaId orMessageID:(NSString*) messageId toContact:(NSString*) contact onAccount:(NSString*) accountNo
{
    if(!accountNo)
        return NO;
    
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
}

-(void) setMessageId:(NSString*) messageid sent:(BOOL) sent
{
    [self.db beginWriteTransaction];
    //force sent YES if the message was already received
    if(!sent)
    {
        if([self.db executeScalar:@"SELECT messageid FROM message_history WHERE messageid=? AND received" andArguments:@[messageid]])
            sent = YES;
    }
    NSString* query = [NSString stringWithFormat:@"update message_history set sent=? where messageid=? and not sent"];
    DDLogVerbose(@"setting sent %@", messageid);
    [self.db executeNonQuery:query andArguments:@[[NSNumber numberWithBool:sent], messageid]];
    [self.db endWriteTransaction];
}

-(void) setMessageId:(NSString*) messageid received:(BOOL) received
{
    NSString* query = [NSString stringWithFormat:@"update message_history set received=?, sent=? where messageid=?"];
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
    NSString* query = [NSString stringWithFormat:@"update message_history set errorType=?, errorReason=? where messageid=?"];
    DDLogVerbose(@"setting message error %@ [%@, %@]", messageid, errorType, errorReason);
    [self.db executeNonQuery:query andArguments:@[errorType, errorReason, messageid]];
}

-(void) setMessageId:(NSString*) messageid messageType:(NSString *) messageType
{
    NSString* query = [NSString stringWithFormat:@"update message_history set messageType=? where messageid=?"];
    DDLogVerbose(@"setting message type %@", messageid);
    [self.db executeNonQuery:query andArguments:@[messageType, messageid]];
}

-(void) setMessageId:(NSString*) messageid previewText:(NSString *) text andPreviewImage:(NSString *) image
{
    if(!messageid) return;
    NSString* query = [NSString stringWithFormat:@"update message_history set previewText=?,  previewImage=? where messageid=?"];
    DDLogVerbose(@"setting previews type %@", messageid);
    [self.db executeNonQuery:query  andArguments:@[text?text:@"", image?image:@"", messageid]];
}

-(void) setMessageId:(NSString*) messageid stanzaId:(NSString *) stanzaId
{
    NSString* query = [NSString stringWithFormat:@"update message_history set stanzaid=? where messageid=?"];
    DDLogVerbose(@"setting message stanzaid %@", query);
    [self.db executeNonQuery:query andArguments:@[stanzaId, messageid]];
}

-(void) clearMessages:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"delete from message_history where account_id=%@", accountNo];
    [self.db executeNonQuery:query];
}

-(void) deleteMessageHistory:(NSNumber*) messageNo
{
    NSString* query = [NSString stringWithFormat:@"delete from message_history where message_history_id=%@", messageNo];
    [self.db executeNonQuery:query];
}

-(NSArray*) messageHistoryListDates:(NSString*) buddy forAccount: (NSString*) accountNo
{
    NSString* accountJid = [self jidOfAccount:accountNo];

    if(accountJid != nil)
    {
        NSString* query = [NSString stringWithFormat:@"select distinct date(timestamp) as the_date from message_history where account_id=? and message_from=? or message_to=? order by timestamp, message_history_id desc"];
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
    NSString* query = [NSString stringWithFormat:@"select af, message_from, message_to, message, thetime, sent, message_history_id from (select ifnull(actual_from, message_from) as af, message_from, message_to, message, sent, timestamp  as thetime, message_history_id, previewImage, previewText from message_history where account_id=? and (message_from=? or message_to=?) and date(timestamp)=? order by message_history_id desc) order by message_history_id asc"];
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

    NSString* query = [NSString stringWithFormat:@"select message_from, message, thetime from (select message_from, message, timestamp as thetime, message_history_id, previewImage, previewText from message_history where account_id=? and (message_from=? or message_to=?) order by message_history_id desc) order by message_history_id asc "];
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

-(BOOL) messageHistoryClean:(NSString*) buddy :(NSString*) accountNo
{
    //returns a buddy's message history

    NSString* query = [NSString stringWithFormat:@"delete from message_history where account_id=? and (message_from=? or message_to=?) "];
    NSArray* params = @[accountNo, buddy, buddy];
    //DDLogVerbose(query);
    if( [self.db executeNonQuery:query andArguments:params])

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
    if( [self.db executeNonQuery:query andArguments:@[]])
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
    NSString* accountJid = [self jidOfAccount:accountNo];
    if(accountJid)
    {

        NSString* query = [NSString stringWithFormat:@"select x.* from(select distinct buddy_name as thename ,'', nick_name, message_from as buddy_name, filename, a.account_id from message_history as a left outer join buddylist as b on a.message_from=b.buddy_name and a.account_id=b.account_id where a.account_id=?  union select distinct message_to as thename ,'',  nick_name, message_to as buddy_name,  filename, a.account_id from message_history as a left outer join buddylist as b on a.message_to=b.buddy_name and a.account_id=b.account_id where a.account_id=?  and message_to!=\"(null)\" )  as x where buddy_name!=?  order by thename COLLATE NOCASE "];
        NSArray* params = @[accountNo, accountNo,
                            accountJid];
        //DDLogVerbose(query);
        NSArray* results = [self.db executeReader:query andArguments:params];

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
    NSString* query = [NSString stringWithFormat:@"select af, message_from, message_to, account_id, message, thetime, message_history_id, sent, messageid, messageType, received, displayed, displayMarkerWanted, encrypted, previewImage, previewText, unread, errorType, errorReason, stanzaid from (select ifnull(actual_from, message_from) as af, message_from, message_to, account_id, message, received, displayed, displayMarkerWanted, encrypted, timestamp  as thetime, message_history_id, sent,messageid, messageType, previewImage, previewText, unread, errorType, errorReason, stanzaid from message_history where account_id=? and (message_from=? or message_to=?) and message_history_id<? order by message_history_id desc limit ?) order by message_history_id asc"];
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
    NSString* query = [NSString stringWithFormat:@"SELECT message, thetime, messageType FROM (SELECT 1 as messagePrio, bl.messageDraft as message, ac.lastMessageTime as thetime, 'MessageDraft' as messageType FROM buddylist AS bl INNER JOIN activechats AS ac where bl.account_id = ac.account_id and bl.buddy_name = ac.buddy_name and ac.account_id = ? and ac.buddy_name = ? and messageDraft is not NULL and messageDraft != '' UNION SELECT 2 as messagePrio, message, timestamp, messageType from (select message, timestamp, messageType FROM message_history where account_id=? and (message_from =? or message_to=?) ORDER BY message_history_id DESC LIMIT 1) ORDER BY messagePrio ASC LIMIT 1)"];
    NSArray* params = @[accountNo, contact, accountNo, contact, contact];

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
    
    return [self.db returningWriteTransaction:^{
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

-(void) addMessageHistoryFrom:(NSString*) from to:(NSString*) to forAccount:(NSString*) accountNo withMessage:(NSString*) message actuallyFrom:(NSString*) actualfrom withId:(NSString *)messageId encrypted:(BOOL) encrypted withCompletion:(void (^)(BOOL, NSString *))completion
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
    NSString* dateTime = [NSString stringWithFormat:@"%@ %@", [parts objectAtIndex:0],[parts objectAtIndex:1]];
    NSString* query = [NSString stringWithFormat:@"insert into message_history (account_id, message_from, message_to, timestamp, message, actual_from, unread, sent, messageid, messageType, encrypted, displayMarkerWanted) values (?,?,?,?,?,?,?,?,?,?,?,?);"];
    NSArray* params = @[accountNo, from, to, dateTime, message, cleanedActualFrom, [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], messageId, messageType, [NSNumber numberWithBool:encrypted], [NSNumber numberWithBool:YES]];
    [self.db beginWriteTransaction];
    DDLogVerbose(@"%@", query);
    BOOL result = [self.db executeNonQuery:query andArguments:params];
    if(result) {
        BOOL innerSuccess = [self updateActiveBuddy:to setTime:dateTime forAccount:accountNo];
        if(innerSuccess) {
            [self.db endWriteTransaction];
            if (completion) {
                completion(result, messageType);
            }
            return;
        }
    }
    [self.db endWriteTransaction];
}

//count unread
-(NSNumber*) countUnreadMessages
{
    // count # of meaages in message table
    NSString* query = [NSString stringWithFormat:@"select count(message_history_id) from  message_history where unread=1"];

    NSNumber* count = (NSNumber*)[self.db executeScalar:query];
    return count;
}

//set all unread messages to read
-(void) setAllMessagesAsRead
{
    NSString* query = [NSString stringWithFormat:@"update message_history set unread=0 where unread=1"];

    [self.db executeNonQuery:query];
}

-(NSDate*) lastMessageDateForContact:(NSString*) contact andAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"select timestamp from message_history where account_id=? and (message_from=? or (message_to=? and sent=1)) order by timestamp desc limit 1"];

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
    NSString* query = [NSString stringWithFormat:@"select timestamp from message_history where account_id=? order by timestamp desc limit 1"];

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

-(NSMutableArray*) activeContacts:(BOOL) pinned
{
    NSString* query = [NSString stringWithFormat:@"SELECT a.buddy_name,  state, status,  filename, ifnull(b.full_name, a.buddy_name) AS full_name, nick_name, muc_subject, muc_nick, a.account_id, lastMessageTime, 0 AS 'count', subscription, ask, pinned from activechats as a JOIN buddylist AS b WHERE a.buddy_name = b.buddy_name AND a.account_id = b.account_id AND a.pinned=? ORDER BY lastMessageTime DESC"];

    NSDateFormatter* dateFromatter = [[NSDateFormatter alloc] init];
    NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

    [dateFromatter setLocale:enUSPOSIXLocale];
    [dateFromatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss"];
    [dateFromatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    NSMutableArray* results = [self.db executeReader:query andArguments:@[[NSNumber numberWithBool:pinned]]];
    NSMutableArray* toReturn = [[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary* dic = (NSDictionary *) obj;
        [toReturn addObject:[MLContact contactFromDictionary:dic withDateFormatter:dateFromatter]];
    }];
    return toReturn;
}

-(NSMutableArray*) activeContactDict
{
    NSString* query = [NSString stringWithFormat:@"select  distinct a.buddy_name, ifnull(b.full_name, a.buddy_name) AS full_name, nick_name, a.account_id from activechats as a LEFT OUTER JOIN buddylist AS b ON a.buddy_name = b.buddy_name  AND a.account_id = b.account_id order by lastMessageTime desc"];

    NSMutableArray* results = [self.db executeReader:query];
    
    NSMutableArray* toReturn = [[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary* dic = (NSDictionary *) obj;
        [toReturn addObject:dic];
    }];
    return toReturn;
}

-(void) removeActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    [self.db writeTransaction:^{
        //mark all messages as read
        [self.db executeNonQuery:@"UPDATE message_history SET unread=0 WHERE account_id=? AND (message_from=? OR message_to=?);" andArguments:@[accountNo, buddyname, buddyname]];
        //remove contact from active chats list
        [self.db executeNonQuery:@"DELETE FROM activechats WHERE buddy_name=? AND account_id=?;" andArguments:@[buddyname, accountNo]];
    }];
}

-(void) removeAllActiveBuddies
{

    NSString* query = [NSString stringWithFormat:@"delete from activechats " ];
    //    DDLogVerbose(query);
    [self.db executeNonQuery:query];
}

-(BOOL) addActiveBuddies:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    if(!buddyname)
    {
        return NO;
    }
    [self.db beginWriteTransaction];
    // Check that we do not add a chat a second time to activechats
    if([self isActiveBuddy:buddyname forAccount:accountNo]) {
        // active chat entry does not exist yet -> insert
        [self.db endWriteTransaction];
        return YES;
    }
    
    NSString* query = [NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=? and buddy_name=?"];
    NSObject* count = [self.db executeScalar:query  andArguments:@[accountNo, buddyname]];
    if(count != nil)
    {
        NSInteger val = [((NSNumber *)count) integerValue];
        if(val > 0) {
            [self.db endWriteTransaction];
            return NO;
        } else
        {
            NSString* accountJid = [self jidOfAccount:accountNo];
            if(!accountJid) {
                [self.db endWriteTransaction];
                return NO;
            }

            if([accountJid isEqualToString:buddyname]) {
                // Something is broken
                [self.db endWriteTransaction];
                DDLogWarn(@"We should never try to create a cheat with our own jid");
                return NO;
            } else {
                // insert
                NSString* query3 = [NSString stringWithFormat:@"insert into activechats (buddy_name, account_id, lastMessageTime) values (?, ?, current_timestamp)"];
                BOOL result = [self.db executeNonQuery:query3 andArguments:@[buddyname, accountNo]];
                [self.db endWriteTransaction];
                return result;
            }
        }
    } else {
        [self.db endWriteTransaction];
        return NO;
    }
}


-(BOOL) isActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=? and buddy_name=? "];
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
    NSString* query = [NSString stringWithFormat:@"select lastMessageTime from  activechats where account_id=? and buddy_name=?"];
    [self.db beginWriteTransaction];
    NSObject* result = [self.db executeScalar:query andArguments:@[accountNo, buddyname]];
    NSString* lastTime = (NSString *) result;

    NSDate* lastDate = [dbFormatter dateFromString:lastTime];
    NSDate* newDate = [dbFormatter dateFromString:timestamp];

    if(lastDate.timeIntervalSince1970<newDate.timeIntervalSince1970) {
        NSString* query = [NSString stringWithFormat:@"update activechats set lastMessageTime=? where account_id=? and buddy_name=? "];
        BOOL success = [self.db executeNonQuery:query andArguments:@[timestamp, accountNo, buddyname]];
        [self.db endWriteTransaction];
        return success;
    } else {
        [self.db endWriteTransaction];
        return NO;
    }
}





#pragma mark chat properties
-(NSNumber*) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo
{
    // count # messages from a specific user in messages table
    NSString* query = [NSString stringWithFormat:@"select count(message_history_id) from message_history where unread=1 and account_id=? and message_from=?"];

    NSNumber* count = (NSNumber*)[self.db executeScalar:query andArguments:@[accountNo, buddy]];
    return count;
}

#pragma db Commands

-(void) updateDBTo:(double) version withBlock:(monal_void_block_t) block
{
    if([(NSNumber*)[self.db executeScalar:@"SELECT dbversion FROM dbversion;"] doubleValue] < version)
    {
        DDLogVerbose(@"Database version <%@ detected. Performing upgrade.", [NSNumber numberWithDouble:version]);
        block();
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
    
    [self.db beginWriteTransaction];

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
        NSString* resourceQuery = [NSString stringWithFormat:@"update account set resource='%@';", [HelperTools encodeRandomResource]];
        [self.db executeNonQuery:resourceQuery];
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
        //truncate internal account state to create a clean working set
        [self.db executeNonQuery:@"UPDATE account SET state=NULL;"];
    }];
    
    [self updateDBTo:4.92 withBlock:^{
        //add displayed and displayMarkerWanted fields
        [self.db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN displayed BOOL DEFAULT FALSE;"];
        [self.db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN displayMarkerWanted BOOL DEFAULT FALSE;"];
    }];
    
    [self.db endWriteTransaction];
    
    DDLogInfo(@"Database version check complete");
    return;
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
    NSString* query = [NSString stringWithFormat:@"insert into muteList(jid) values(?)"];
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) unMuteJid:(NSString*) jid
{
    if(!jid) return;
    NSString* query = [NSString stringWithFormat:@"delete from muteList where jid=?"];
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(BOOL) isMutedJid:(NSString*) jid
{
    if(!jid) return NO;
    NSString* query = [NSString stringWithFormat:@"select count(jid) from muteList where jid=?"];
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
    NSString* query = [NSString stringWithFormat:@"insert into blockList(jid) values(?)"];
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) unBlockJid:(NSString*) jid
{
    if(!jid ) return;
    NSString* query = [NSString stringWithFormat:@"delete from blockList where jid=?"];
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(BOOL) isBlockedJid:(NSString*) jid
{
    if(!jid) return NO;
    NSString* query = [NSString stringWithFormat:@"select count(jid) from blockList where jid=?"];
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
    NSString* query = [NSString stringWithFormat:@"SELECT pinned FROM activechats WHERE account_id=? AND buddy_name=?"];
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
    NSString* query = [NSString stringWithFormat:@"UPDATE activechats SET pinned=1 WHERE account_id=? AND buddy_name=?"];
    [self.db executeNonQuery:query andArguments:@[accountNo, buddyJid]];
}
-(void) unPinChat:(NSString*) accountNo andBuddyJid:(NSString*) buddyJid
{
    if(!accountNo || !buddyJid) return;
    NSString* query = [NSString stringWithFormat:@"UPDATE activechats SET pinned=0 WHERE account_id=? AND buddy_name=?"];
    [self.db executeNonQuery:query andArguments:@[accountNo, buddyJid]];
}

#pragma mark - Images

-(void) createImageCache:(NSString *) path forUrl:(NSString*) url
{
    NSString* query = [NSString stringWithFormat:@"insert into imageCache(url, path) values(?, ?)"];
    NSArray* params = @[url, path];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) deleteImageCacheForUrl:(NSString*) url
{
    NSString* query = [NSString stringWithFormat:@"delete from imageCache where url=?"];
    NSArray* params = @[url];
    [self.db executeNonQuery:query andArguments:params];
}

-(NSString*) imageCacheForUrl:(NSString*) url
{
    if(!url) return nil;
    NSString* query = [NSString stringWithFormat:@"select path from imageCache where url=?"];
    NSArray* params = @[url];
    NSObject* val = [self.db executeScalar:query andArguments:params];
    NSString* path = (NSString *) val;
    return path;
}

-(NSMutableArray*) allAttachmentsFromContact:(NSString*) contact forAccount:(NSString*) accountNo
{
    if(!accountNo ||! contact) return nil;
    NSString* query = [NSString stringWithFormat:@"select distinct A.* from imageCache as A inner join  message_history as B on message = a.url where account_id=? and actual_from=? order by message_history_id desc"];
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

    NSString* query = [NSString stringWithFormat:@"SELECT lastInteraction from buddylist where account_id=? and buddy_name=?"];
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

    NSString* query = [NSString stringWithFormat:@"UPDATE buddylist SET lastInteraction=? WHERE account_id=? and buddy_name=?"];
    NSArray* params = @[timestamp, accountNo, jid];
    [self.db executeNonQuery:query andArguments:params];
}

#pragma mark - encryption

-(BOOL) shouldEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return NO;
    NSString* query = [NSString stringWithFormat:@"SELECT encrypt from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, jid];
    NSNumber* status=(NSNumber*)[self.db executeScalar:query andArguments:params];
    return [status boolValue];
}


-(void) encryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return;
    NSString* query = [NSString stringWithFormat:@"update buddylist set encrypt=1 where account_id=?  and buddy_name=?"];
    NSArray* params = @[ accountNo, jid];
    [self.db executeNonQuery:query andArguments:params];
    return;
}

-(void) disableEncryptForJid:(NSString*) jid andAccountNo:(NSString*) accountNo
{
    if(!jid || !accountNo) return ;
    NSString* query = [NSString stringWithFormat:@"update buddylist set encrypt=0 where account_id=?  and buddy_name=?"];
    NSArray* params = @[ accountNo, jid];
    [self.db executeNonQuery:query andArguments:params];
    return;
}

@end
