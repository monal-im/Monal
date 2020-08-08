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

@interface DataLayer()
{
    NSDateFormatter* dbFormatter;
}

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
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:nil];
    }
    
    //old install is being upgraded --> copy old database to new app group path
    if([fileManager fileExistsAtPath:oldDBPath] && ![fileManager fileExistsAtPath:writableDBPath])
    {
        DDLogInfo(@"initialize: copying existing DB from OLD path to new app group one: %@ --> %@", oldDBPath, writableDBPath);
        [fileManager copyItemAtPath:oldDBPath toPath:writableDBPath error:&error];
        if(error)
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:nil];
        DDLogInfo(@"initialize: removing old DB at: %@", oldDBPath);
        [fileManager removeItemAtPath:oldDBPath error:&error];
        if(error)
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:nil];
    }
    
    //the file still does not exist (e.g. fresh install) --> copy default database to app group path
    if(![fileManager fileExistsAtPath:writableDBPath])
    {
        DDLogInfo(@"initialize: copying default DB to: %@", writableDBPath);
        NSString* defaultDBPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"sworim.sqlite"];
        NSError* error;
        [fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:&error];
        if(error)
            @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:nil];
    }
    
    NSDictionary *attributes = @{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication};
    [fileManager setAttributes:attributes ofItemAtPath:writableDBPath error:&error];
    
    //init global state
    dbPath = writableDBPath;
    dbFormatter = [[NSDateFormatter alloc] init];
    [dbFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    [dbFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    
    //open db and update db version
    MLSQLite* db = [MLSQLite sharedInstanceForFile:dbPath];
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

-(void) accountListWithCompletion: (void (^)(NSArray* result))completion
{
    NSString* query = [NSString stringWithFormat:@"select * from account order by account_id asc"];
    [self.db executeReader:query withCompletion:^(NSMutableArray* result) {
        if(completion) completion(result);
    }];
}

-(void) accountListEnabledWithCompletion: (void (^)(NSArray* result))completion
{
    NSString* query = [NSString stringWithFormat:@"select * from account where enabled=1 order by account_id asc"];
    [self.db executeReader:query withCompletion:^(NSMutableArray* result) {
        if(completion) completion(result);
    }];
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

-(void) accountIDForUser:(NSString *) user andDomain:(NSString *) domain withCompletion:(void (^)(NSString *result))completion
{
    if(!user && !domain) return;
    NSString* cleanUser =user;
    NSString* cleanDomain = domain;

    if(!cleanDomain) cleanDomain= @"";
    if(!cleanUser) cleanUser= @"";

    NSString *query = [NSString stringWithFormat:@"select account_id from account where domain=? and username=?"];
    [self.db executeReader:query andArguments:@[cleanDomain, cleanUser] withCompletion:^(NSMutableArray * result) {
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
    [self.db executeReader:query andArguments:@[domain, user] withCompletion:^(NSMutableArray * result) {
        if(completion) completion(result.count>0);
    }];
}

-(void) detailsForAccount:(NSString*) accountNo withCompletion:(void (^)(NSArray* result))completion
{
    if(!accountNo) return;
    NSString* query = [NSString stringWithFormat:@"select * from account where account_id=?"];
    NSArray* params = @[accountNo];
    [self.db executeReader:query andArguments:params withCompletion:^(NSMutableArray *result) {
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

    [self.db executeNonQuery:query andArguments:params withCompletion:completion];
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
    [self.db executeNonQuery:query andArguments:params withCompletion:completion];
}

-(BOOL) removeAccount:(NSString*) accountNo
{
    // remove all other traces of the account_id in one transaction
    [self.db beginWriteTransaction];

    NSString* query1 = [NSString stringWithFormat:@"delete from buddylist  where account_id=%@;", accountNo];
    [self.db executeNonQuery:query1 andArguments:@[]];

    NSString* query3= [NSString stringWithFormat:@"delete from message_history  where account_id=%@;", accountNo];
    [self.db executeNonQuery:query3 andArguments:@[]];

    NSString* query4= [NSString stringWithFormat:@"delete from activechats  where account_id=%@;", accountNo];
    [self.db executeNonQuery:query4 andArguments:@[]];

    NSString* query = [NSString stringWithFormat:@"delete from account  where account_id=%@;", accountNo];
    BOOL lastResult = [self.db executeNonQuery:query andArguments:@[]];

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
    [self.db executeNonQuery:query andArguments:params];
}

-(void) getHighestAccountIdWithCompletion:(void (^)(NSObject * accountid)) completion
{
    [self.db executeScalar:@"select max(account_id) from account" withCompletion:completion];
}

#pragma mark contact Commands

-(void) addContact:(NSString*) contact forAccount:(NSString*) accountNo fullname:(NSString*) fullName nickname:(NSString*) nickName andMucNick:(NSString*) mucNick withCompletion: (void (^)(BOOL))completion
{
    // no blank full names
    NSString* actualfull = fullName;
    if([[actualfull stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0)
        actualfull = contact;

    NSString* query = [NSString stringWithFormat:@"insert into buddylist ('account_id', 'buddy_name', 'full_name', 'nick_name', 'new', 'online', 'dirty', 'muc', 'muc_nick') values(?, ?, ?, ?, 1, 0, 0, ?, ?) ON CONFLICT(account_id, buddy_name) DO UPDATE SET account_id=?, buddy_name=?;"];
    if(!(accountNo && contact && actualfull && nickName)) {
        if(completion)
        {
            completion(NO);
        }
    } else  {
        NSArray* params = @[accountNo, contact, actualfull, nickName, mucNick?@1:@0, mucNick ? mucNick : @"", accountNo, contact];
        [self.db executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {
            if(completion)
            {
                completion(success);
            }
        }];
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

-(void) contactForUsername:(NSString*) username forAccount: (NSString*) accountNo withCompletion: (void (^)(NSArray *))completion
{
    if(!username || !accountNo) return;
    NSString* query = query = [NSString stringWithFormat:@"select buddy_name, state, status, filename, 0, ifnull(full_name, buddy_name) as full_name, nick_name, account_id, MUC, muc_subject, muc_nick , full_name as raw_full, subscription, ask from buddylist where buddy_name=? and account_id=?"];
    NSArray *params= @[username, accountNo];

    [self.db executeReader:query andArguments:params  withCompletion:^(NSArray * results) {
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

    [self.db executeReader:query withCompletion:^(NSMutableArray *results) {

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
    [self.db executeReader:query withCompletion:^(NSMutableArray *results) {

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

-(void) setResourceOnline:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
    if(!presenceObj.resource)
        return;
    [self.db beginWriteTransaction];
    //get buddyid for name and account
    NSString* query1 = [NSString stringWithFormat:@"select buddy_id from buddylist where account_id=? and buddy_name=?;"];
    [self.db executeScalar:query1 andArguments:@[accountNo, presenceObj.user] withCompletion:^(NSObject *buddyid) {
        if(buddyid)
        {
            NSString* query = [NSString stringWithFormat:@"insert or ignore into buddy_resources ('buddy_id', 'resource', 'ver') values (?, ?, '')"];
            [self.db executeNonQuery:query andArguments:@[buddyid, presenceObj.resource] withCompletion:nil];
        }
    }];
    [self.db endWriteTransaction];
}


-(NSArray*)resourcesForContact:(NSString*)contact
{
    if(!contact) return nil;
    NSString* query1 = [NSString stringWithFormat:@" select resource from buddy_resources as A inner join buddylist as B on a.buddy_id=b.buddy_id where  buddy_name=?  "];
    NSArray* params = @[contact ];
    NSArray* resources = [self.db executeReader:query1 andArguments:params];
    return resources;
}


-(void) setOnlineBuddy:(ParsePresence*) presenceObj forAccount:(NSString *)accountNo
{
    [self.db beginWriteTransaction];
    [self setResourceOnline:presenceObj forAccount:accountNo];
    [self isBuddyOnline:presenceObj.user forAccount:accountNo withCompletion:^(BOOL isOnline) {
        if(!isOnline) {
            NSString* query = [NSString stringWithFormat:@"update buddylist set online=1, new=1, muc=? where account_id=? and  buddy_name=?"];
            NSArray* params = @[[NSNumber numberWithBool:presenceObj.MUC], accountNo, presenceObj.user ];
            [self.db executeNonQuery:query andArguments:params];
        }
    }];
    [self.db endWriteTransaction];
}

-(BOOL) setOfflineBuddy:(ParsePresence *)presenceObj forAccount:(NSString *)accountNo
{
    [self.db beginWriteTransaction];
    NSString* query1 = [NSString stringWithFormat:@" select buddy_id from buddylist where account_id=? and  buddy_name=?;"];
    NSArray* params=@[accountNo, presenceObj.user];
    NSString* buddyid = (NSString*)[self.db executeScalar:query1 andArguments:params];
    if(buddyid == nil)
    {
        [self.db endWriteTransaction];
        return NO;
    }

    NSString* query2 = [NSString stringWithFormat:@"delete from buddy_resources where buddy_id=? and resource=?"];
    NSArray* params2 = @[buddyid, presenceObj.resource?presenceObj.resource:@""];
    if([self.db executeNonQuery:query2 andArguments:params2] == NO)
    {
        [self.db endWriteTransaction];
        return NO;
    }

    //see how many left
    NSString* query3 = [NSString stringWithFormat:@"select count(buddy_id) from buddy_resources where buddy_id=%@;", buddyid ];
    NSString* resourceCount = (NSString*)[self.db executeScalar:query3 andArguments:@[]];

    if([resourceCount integerValue]<1)
    {
        NSString* query = [NSString stringWithFormat:@"update buddylist set online=0, state='offline', dirty=1 where account_id=? and buddy_name=?;"];
        NSArray* params4 = @[accountNo, presenceObj.user];
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

-(void) setBuddyState:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo;
{
    NSString* toPass;
    //data length check
    if([presenceObj.show length] > 20)
        toPass = [presenceObj.show substringToIndex:19];
    else
        toPass = presenceObj.show;
    if(!toPass)
        toPass= @"";

    NSString* query = [NSString stringWithFormat:@"update buddylist set state=?, dirty=1 where account_id=? and  buddy_name=?;"];
    [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.user]];
}

-(NSString*) buddyState:(NSString*) buddy forAccount:(NSString*) accountNo
{

    NSString* query = [NSString stringWithFormat:@"select state from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, buddy];
    NSString* state = (NSString*)[self.db executeScalar:query andArguments:params];
    return state;
}

-(void) contactRequestsForAccountWithCompletion:(void (^)(NSMutableArray *))completion
{
    NSString* query = [NSString stringWithFormat:@"select account_id, buddy_name from subscriptionRequests"];

     [self.db executeReader:query withCompletion:^(NSMutableArray *results) {

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
    [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId] ];
}

-(void) deleteContactRequest:(MLContact *) requestor
{
    NSString* query2 = [NSString stringWithFormat:@"delete from subscriptionRequests where buddy_name=? and account_id=? "];
    [self.db executeNonQuery:query2 andArguments:@[requestor.contactJid, requestor.accountId] ];
}

-(void) setBuddyStatus:(ParsePresence*)presenceObj forAccount: (NSString*) accountNo
{
    NSString* toPass;
    //data length check
    if([presenceObj.status length] > 200)
        toPass = [presenceObj.status substringToIndex:199];
    else
        toPass = presenceObj.status;
    if(!toPass)
        toPass = @"";

    NSString* query = [NSString stringWithFormat:@"update buddylist set status=?, dirty=1 where account_id=? and  buddy_name=?;"];
    [self.db executeNonQuery:query andArguments:@[toPass, accountNo, presenceObj.user]];
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

-(void) fullNameForContact:(NSString*) contact inAccount:(NSString*) accountNo withCompeltion: (void (^)(NSString *))completion;
{
    if(!accountNo  || !contact) return ;
    NSString* query = [NSString stringWithFormat:@"select full_name from buddylist where account_id=? and buddy_name=?"];
    NSArray * params=@[accountNo, contact];
    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject *name) {
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
    [self.db executeNonQuery:query  andArguments:params];

}

-(void) contactHash:(NSString*) buddy forAccount:(NSString*) accountNo withCompeltion: (void (^)(NSString *))completion
{
    NSString* query = [NSString stringWithFormat:@"select iconhash from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, buddy];
    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject *iconHash) {
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

    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject *value) {

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

    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject *value) {

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
   [self.db beginWriteTransaction];
    NSString* query = [NSString stringWithFormat:@"update buddylist set messageDraft=? where account_id=? and buddy_name=?"];
    NSArray* params = @[comment, accountNo, buddy];
    [self.db executeNonQuery:query andArguments:params  withCompletion:^(BOOL success) {
        [self.db endWriteTransaction];
        if(completion) {
                completion(success);
            }
    }];
}

-(void) loadMessageDraft:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion:(void (^)(NSString*))completion
{
    NSString* query = [NSString stringWithFormat:@"SELECT messageDraft from buddylist where account_id=? and buddy_name=?"];
    NSArray* params = @[accountNo, buddy];
    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject* messageDraft) {
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

-(void) updateOwnNickName:(NSString *) nick forMuc:(NSString*) room andServer:(NSString*) server forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    NSString *combinedRoom = room;
    if([combinedRoom componentsSeparatedByString:@"@"].count == 1) {
        combinedRoom = [NSString stringWithFormat:@"%@@%@", room, server];
    }

    NSString* query = [NSString stringWithFormat:@"update buddylist set muc_nick=?, muc=1 where account_id=? and buddy_name=?"];
    NSArray* params = @[nick, accountNo, combinedRoom];
    DDLogVerbose(@"%@", query);

    [self.db executeNonQuery:query andArguments:params  withCompletion:completion];
}


-(void) addMucFavoriteForAccount:(NSString*) accountNo withRoom:(NSString *) room nick:(NSString *)nick autoJoin:(BOOL) autoJoin andCompletion:(void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"insert into muc_favorites (room, nick, autojoin, account_id) values(?, ?, ?, ?)"];
    NSArray* params = @[room, nick, [NSNumber numberWithBool:autoJoin], accountNo];
    DDLogVerbose(@"%@", query);

    [self.db executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {
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

    [self.db executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {
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

    [self.db executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {
        if(completion) {
            completion(success);
        }
    }];
}

-(void) mucFavoritesForAccount:(NSString*) accountNo withCompletion:(void (^)(NSMutableArray *))completion
{
    NSString* query = [NSString stringWithFormat:@"select * from muc_favorites where account_id=%@", accountNo];
    DDLogVerbose(@"%@", query);
    [self.db executeReader:query withCompletion:^(NSMutableArray *favorites) {
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

    [self.db executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {

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

    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject *result) {
        if(completion) completion((NSString *)result);
    }];

}

#pragma mark message Commands

-(NSArray *) messageForHistoryID:(NSInteger) historyID
{
    NSString* query = [NSString stringWithFormat:@"select message, messageid from message_history  where message_history_id=%ld", (long)historyID];
    NSArray* messageArray= [self.db executeReader:query andArguments:@[]];
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

    [self.db beginWriteTransaction];
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
                        [self.db executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {

                            if(success) {
                                [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo withCompletion:^(BOOL innerSuccess) {
                                    [self.db endWriteTransaction];
                                    if(completion) {
                                        completion(success, messageType);
                                    }
                                }];
                            }
                            else {
                                [self.db endWriteTransaction];
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
                [self.db executeNonQuery:query andArguments:params withCompletion:^(BOOL success) {

                    if(success) {
                        [self updateActiveBuddy:actualfrom setTime:dateString forAccount:accountNo withCompletion:^(BOOL innerSuccess) {
                            [self.db endWriteTransaction];
                            if(completion) {
                                completion(success, messageType);
                            }
                        }];
                    }
                    else {
                        [self.db endWriteTransaction];
                        if(completion) {
                            completion(success, messageType);
                        }
                    }
                }];
            }
        }
        else {
            [self.db endWriteTransaction];
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

    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject* result) {

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

    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject* result) {

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
    //force delivered YES if the message was already received
    if(!delivered)
    {
        if([self.db executeScalar:@"SELECT messageid FROM message_history WHERE messageid=? && received" andArguments:@[messageid]])
            delivered = YES;
    }
    NSString* query = [NSString stringWithFormat:@"update message_history set delivered=? where messageid=? and not delivered"];
    DDLogVerbose(@"setting delivered %@", messageid);
    [self.db executeNonQuery:query andArguments:@[[NSNumber numberWithBool:delivered], messageid]];
}

-(void) setMessageId:(NSString*) messageid received:(BOOL) received
{
    NSString* query = [NSString stringWithFormat:@"update message_history set received=?, delivered=? where messageid=?"];
    DDLogVerbose(@"setting received confrmed %@", messageid);
    [self.db executeNonQuery:query andArguments:@[[NSNumber numberWithBool:received], [NSNumber numberWithBool:YES], messageid]];
}

-(void) setMessageId:(NSString*) messageid errorType:(NSString*) errorType errorReason:(NSString*) errorReason
{
    //ignore error if the message was already received by *some* client
    if([self.db executeScalar:@"SELECT messageid FROM message_history WHERE messageid=? && received" andArguments:@[messageid]])
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
    DDLogVerbose(@" setting message stanzaid %@", query);
    [self.db executeNonQuery:query  andArguments:@[stanzaId, messageid]];
}

-(void) clearMessages:(NSString*) accountNo
{
    NSString* query = [NSString stringWithFormat:@"delete from message_history where account_id=%@", accountNo];
    [self.db executeNonQuery:query andArguments:@[]];
}

-(void) deleteMessageHistory:(NSNumber*) messageNo
{
    NSString* query = [NSString stringWithFormat:@"delete from message_history where message_history_id=%@", messageNo];
    [self.db executeNonQuery:query andArguments:@[]];
}

-(NSArray*) messageHistoryListDates:(NSString*) buddy forAccount: (NSString*) accountNo
{
    //returns a list of  buddy's with message history

    NSString* query1 = [NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
    //DDLogVerbose(query);
    NSArray* user = [self.db executeReader:query1 andArguments:@[]];

    if(user!=nil)
    {
        NSString* query = [NSString stringWithFormat:@"select distinct date(timestamp) as the_date from message_history where account_id=? and message_from=? or message_to=? order by timestamp desc"];
        NSArray  *params=@[accountNo, buddy, buddy  ];
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

-(NSArray*) messageHistoryDate:(NSString*) buddy forAccount:(NSString*) accountNo forDate:(NSString*) date
{
    NSString* query = [NSString stringWithFormat:@"select af, message_from, message_to, message, thetime, delivered, message_history_id from (select ifnull(actual_from, message_from) as af, message_from, message_to, message, delivered, timestamp  as thetime, message_history_id, previewImage, previewText from message_history where account_id=? and (message_from=? or message_to=?) and date(timestamp)=? order by message_history_id desc) order by message_history_id asc"];
    NSArray* params = @[accountNo, buddy, buddy, date];

    DDLogVerbose(@"%@", query);
    NSArray* results = [self.db executeReader:query andArguments:params];

    NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
    [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *dic = (NSDictionary *) obj;
        [toReturn addObject:[MLMessage messageFromDictionary:dic withDateFormatter:dbFormatter]];
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

    NSString* query1 = [NSString stringWithFormat:@"select username, domain from account where account_id=%@", accountNo];
    //DDLogVerbose(query);
    NSArray* user = [self.db executeReader:query1 andArguments:@[]];

    if([user count]>0)
    {

        NSString* query = [NSString stringWithFormat:@"select x.* from(select distinct buddy_name as thename ,'', nick_name, message_from as buddy_name, filename, a.account_id from message_history as a left outer join buddylist as b on a.message_from=b.buddy_name and a.account_id=b.account_id where a.account_id=?  union select distinct message_to as thename ,'',  nick_name, message_to as buddy_name,  filename, a.account_id from message_history as a left outer join buddylist as b on a.message_to=b.buddy_name and a.account_id=b.account_id where a.account_id=?  and message_to!=\"(null)\" )  as x where buddy_name!=?  order by thename COLLATE NOCASE "];
        NSArray* params = @[accountNo, accountNo,
                          ((NSString *)[[user objectAtIndex:0] objectForKey:@"username"]),
                          // ((NSString *)[[user objectAtIndex:0] objectForKey:@"username"]),
                          ((NSString *)[[user objectAtIndex:0] objectForKey:@"domain"])  ];
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
-(void) messagesForContact:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion:(void (^)(NSMutableArray *))completion
{
    if(!accountNo ||! buddy) {
        if(completion) completion(nil);
        return;
    };
    NSString* query = [NSString stringWithFormat:@"select af, message_from, message_to, account_id, message, thetime, message_history_id, delivered, messageid, messageType, received, encrypted, previewImage, previewText, unread, errorType, errorReason from (select ifnull(actual_from, message_from) as af, message_from, message_to, account_id,   message, received, encrypted, timestamp  as thetime, message_history_id, delivered,messageid, messageType, previewImage, previewText, unread, errorType, errorReason from message_history where account_id=? and (message_from=? or message_to=?) order by message_history_id desc limit 250) order by thetime asc"];
    NSArray* params = @[accountNo, buddy, buddy];
    [self.db executeReader:query andArguments:params withCompletion:^(NSMutableArray *rawArray) {
        NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:rawArray.count];
        [rawArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic = (NSDictionary *) obj;
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

        if(completion) completion(toReturn);
    }];
}

-(void) lastMessageForContact:(NSString*) contact forAccount:(NSString*) accountNo withCompletion:(void (^)(NSMutableArray *))completion
{
    if(!accountNo ||! contact) return;
    NSString* query = [NSString stringWithFormat:@"SELECT message, thetime, messageType FROM (SELECT 1 as messagePrio, bl.messageDraft as message, ac.lastMessageTime as thetime, 'MessageDraft' as messageType FROM buddylist AS bl INNER JOIN activechats AS ac where bl.account_id = ac.account_id and bl.buddy_name = ac.buddy_name and ac.account_id = ? and ac.buddy_name = ? and messageDraft is not NULL and messageDraft != '' UNION SELECT 2 as messagePrio, message, timestamp, messageType from (select message, timestamp, messageType FROM message_history where account_id=? and (message_from =? or message_to=?) ORDER BY message_history_id DESC LIMIT 1) ORDER BY messagePrio ASC LIMIT 1)"];
    NSArray* params = @[accountNo, contact, accountNo, contact, contact];

    [self.db executeReader:query andArguments:params withCompletion:^(NSMutableArray *results) {
        NSMutableArray *toReturn =[[NSMutableArray alloc] initWithCapacity:results.count];
        [results enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic = (NSDictionary *) obj;
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

        if(completion) completion(toReturn);
    }];
}

-(void) markAsReadBuddy:(NSString*) buddy forAccount:(NSString*) accountNo
{
    if(!buddy || !accountNo) return;
    NSString* query2 = [NSString stringWithFormat:@"  update message_history set unread=0 where account_id=? and message_from=? or message_to=?"];
    [self.db executeNonQuery:query2 andArguments:@[accountNo, buddy, buddy]];
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
        [self.db beginWriteTransaction];
        DDLogVerbose(@"%@", query);
        [self.db executeNonQuery:query andArguments:params  withCompletion:^(BOOL result) {
            [self updateActiveBuddy:to setTime:dateTime forAccount:accountNo withCompletion:^(BOOL innerSuccess) {
                [self.db endWriteTransaction];
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

    [self.db executeScalar:query withCompletion:^(NSObject *result) {
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

    [self.db executeNonQuery:query andArguments:@[]];
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

    [self.db executeNonQuery:query andArguments:@[synchPoint, accountNo]];
}

-(void) synchPointforAccount:(NSString*) accountNo withCompletion: (void (^)(NSDate *))completion
{
    NSString* query = [NSString stringWithFormat:@"select synchpoint from buddylist  where account_id=? order by synchpoint  desc limit 1"];

    [self.db executeScalar:query andArguments:@[accountNo] withCompletion:^(NSObject* result) {
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

    [self.db executeScalar:query andArguments:@[accountNo, contact, contact] withCompletion:^(NSObject* result) {
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

    [self.db executeScalar:query andArguments:@[accountNo, jid] withCompletion:^(NSObject* result) {
        if(completion)
        {
            completion((NSString *) result);
        }
    }];
}

-(void) lastMessageDateAccount:(NSString*) accountNo withCompletion: (void (^)(NSDate *))completion
{
    NSString* query = [NSString stringWithFormat:@"select timestamp from  message_history where account_id=? order by timestamp desc limit 1"];

    [self.db executeScalar:query andArguments:@[accountNo] withCompletion:^(NSObject* result) {
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
    NSString* query = [NSString stringWithFormat:@"select distinct a.buddy_name,  state, status,  filename, ifnull(b.full_name, a.buddy_name) AS full_name, nick_name, muc_subject, muc_nick, a.account_id,lastMessageTime, 0 AS 'count', subscription, ask from activechats as a LEFT OUTER JOIN buddylist AS b ON a.buddy_name = b.buddy_name  AND a.account_id = b.account_id order by lastMessageTime desc"];

    NSDateFormatter* dateFromatter = [[NSDateFormatter alloc] init];
    NSLocale* enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

    [dateFromatter setLocale:enUSPOSIXLocale];
    [dateFromatter setDateFormat:@"yyyy'-'MM'-'dd HH':'mm':'ss"];
    [dateFromatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    [self.db executeReader:query withCompletion:^(NSMutableArray *results) {

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

    [self.db executeReader:query withCompletion:^(NSMutableArray *results) {

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
    [self.db beginWriteTransaction];
    //mark messages as read
    [self markAsReadBuddy:buddyname forAccount:accountNo];

    NSString* query = [NSString stringWithFormat:@"delete from activechats where buddy_name=? and account_id=? "];
    //    DDLogVerbose(query);
    [self.db executeNonQuery:query andArguments:@[buddyname, accountNo] withCompletion:nil];
    [self.db endWriteTransaction];
}

-(void) removeAllActiveBuddies
{

    NSString* query = [NSString stringWithFormat:@"delete from activechats " ];
    //    DDLogVerbose(query);
    [self.db executeNonQuery:query andArguments:@[]];
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
    [self.db beginWriteTransaction];
    // Check that we do not add a chat a second time to activechats
    NSString* query = [NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=? and buddy_name=?"];
    [self.db executeScalar:query  andArguments:@[accountNo, buddyname] withCompletion:^(NSObject * count) {
        if(count != nil)
        {
            NSInteger val=[((NSNumber *)count) integerValue];
            if(val > 0) {
                [self.db endWriteTransaction];
                if (completion) {
                    completion(NO);
                }
            } else
            {
                // active chat entry does not exist yet -> insert
                NSString* query2 = [NSString stringWithFormat:@"select username, domain from account where account_id=?"];
                [self.db executeReader:query2 andArguments:@[accountNo] withCompletion:^(NSMutableArray* accountVals) {
                    // Check if we create a chat with our own jid -> should never happen
                    NSDictionary* firstRow = [accountVals objectAtIndex:0];
                    NSString* accountJid = [NSString stringWithFormat:@"%@@%@", [firstRow objectForKey:kUsername], [firstRow objectForKey:kDomain]];
                    if([accountJid isEqualToString:buddyname]) {
                        // Something is broken
                        [self.db endWriteTransaction];
                        DDLogWarn(@"We should never try to create a cheat with our own jid");
                        if(completion)
                            completion(NO);
                        return;
                    } else {
                        // insert
                        NSString* query3 = [NSString stringWithFormat:@"insert into activechats (buddy_name, account_id, lastMessageTime) values (?, ?, current_timestamp)"];
                        [self.db executeNonQuery:query3 andArguments:@[buddyname, accountNo] withCompletion:^(BOOL result) {
                            [self.db endWriteTransaction];
                            if (completion) {
                                completion(result);
                            }
                        }];
                    }
                }];
            }
        }
    }];
}


-(void) isActiveBuddy:(NSString*) buddyname forAccount:(NSString*) accountNo withCompletion: (void (^)(BOOL))completion
{
    NSString* query = [NSString stringWithFormat:@"select count(buddy_name) from activechats where account_id=? and buddy_name=? "];
    [self.db executeScalar:query andArguments:@[accountNo, buddyname] withCompletion:^(NSObject * count) {
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
    [self.db beginWriteTransaction];
    [self.db executeScalar:query andArguments:@[accountNo, buddyname] withCompletion:^(NSObject *result) {
        NSString* lastTime = (NSString *) result;

        NSDate* lastDate = [dbFormatter dateFromString:lastTime];
        NSDate* newDate = [dbFormatter dateFromString:timestamp];

        if(lastDate.timeIntervalSince1970<newDate.timeIntervalSince1970) {
            NSString* query = [NSString stringWithFormat:@"update activechats set lastMessageTime=? where account_id=? and buddy_name=? "];
            [self.db executeNonQuery:query andArguments:@[timestamp, accountNo, buddyname] withCompletion:^(BOOL success) {
                [self.db endWriteTransaction];
                if(completion) completion(success);
            }];
        } else {
            [self.db endWriteTransaction];
            if(completion) completion(NO);
        }
    }];
}





#pragma mark chat properties
-(void) countUserUnreadMessages:(NSString*) buddy forAccount:(NSString*) accountNo withCompletion:(void (^)(NSNumber *))completion
{
    // count # messages from a specific user in messages table
    NSString* query = [NSString stringWithFormat:@"select count(message_history_id) from  message_history where unread=1 and account_id=? and message_from=?"];

    [self.db executeScalar:query andArguments:@[accountNo, buddy] withCompletion:^(NSObject* result) {
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

    [self.db executeScalar:query andArguments:@[accountNo, buddy, buddy] withCompletion:^(NSObject* result) {
        if(completion)
        {
            completion((NSNumber *)result);
        }
    }];
}

#pragma db Commands

-(void) version
{
    [self.db beginWriteTransaction];

    // checking db version and upgrading if necessary
    DDLogInfo(@"Database version check");

    NSNumber* dbversion=(NSNumber*)[self.db executeScalar:@"select dbversion from dbversion;" andArguments:@[]];
    DDLogInfo(@"Got db version %@", dbversion);

    if([dbversion doubleValue] < 2.0)
    {
        DDLogVerbose(@"Database version <2.0 detected. Performing upgrade on accounts.");

        [self.db executeNonQuery:@"drop table muc_favorites" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE IF NOT EXISTS \"muc_favorites\" (\"mucid\" integer NOT NULL primary key autoincrement,\"room\" varchar(255,0),\"nick\" varchar(255,0),\"autojoin\" bool, account_id int);" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='2.0';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 2.0 success");
    }

    if([dbversion doubleValue] < 2.1)
    {
        DDLogVerbose(@"Database version <2.1 detected. Performing upgrade on accounts.");


        [self.db executeNonQuery:@"alter table message_history add column received bool;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='2.1';" andArguments:@[]];

        DDLogVerbose(@"Upgrade to 2.1 success");
    }

    if([dbversion doubleValue] < 2.2)
    {
        DDLogVerbose(@"Database version <2.2 detected. Performing upgrade.");

        [self.db executeNonQuery:@"alter table buddylist add column synchPoint datetime;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='2.2';" andArguments:@[]];

        DDLogVerbose(@"Upgrade to 2.2 success");
    }

    if([dbversion doubleValue] < 2.3)
    {
        DDLogVerbose(@"Database version <2.3 detected. Performing upgrade.");

        NSString* resourceQuery = [NSString stringWithFormat:@"update account set resource='%@';", [HelperTools encodeRandomResource]];

        [self.db executeNonQuery:resourceQuery andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='2.3';" andArguments:@[]];

        DDLogVerbose(@"Upgrade to 2.3 success");
    }

    //OMEMO begins below
    if([dbversion doubleValue] < 3.1)
    {
        DDLogVerbose(@"Database version <3.1 detected. Performing upgrade.");

        [self.db executeNonQuery:@"CREATE TABLE signalIdentity (deviceid int NOT NULL PRIMARY KEY, account_id int NOT NULL unique,identityPublicKey BLOB,identityPrivateKey BLOB)" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE signalSignedPreKey (account_id int NOT NULL,signedPreKeyId int not null,signedPreKey BLOB);" andArguments:@[]];

        [self.db executeNonQuery:@"CREATE TABLE signalPreKey (account_id int NOT NULL,prekeyid int not null,preKey BLOB);" andArguments:@[]];

        [self.db executeNonQuery:@"CREATE TABLE signalContactIdentity ( account_id int NOT NULL,contactName text,contactDeviceId int not null,identity BLOB,trusted boolean);" andArguments:@[]];

        [self.db executeNonQuery:@"CREATE TABLE signalContactKey (account_id int NOT NULL,contactName text,contactDeviceId int not null, groupId text,senderKey BLOB);" andArguments:@[]];

        [self.db executeNonQuery:@"  CREATE TABLE signalContactSession (account_id int NOT NULL, contactName text, contactDeviceId int not null, recordData BLOB)" andArguments:@[]];
        [self.db executeNonQuery:@"alter table message_history add column encrypted bool;" andArguments:@[]];

        [self.db executeNonQuery:@"alter table message_history add column previewText text;" andArguments:@[]];
        [self.db executeNonQuery:@"alter table message_history add column previewImage text;" andArguments:@[]];

        [self.db executeNonQuery:@"alter table buddylist add column backgroundImage text;" andArguments:@[]];

        [self.db executeNonQuery:@"update dbversion set dbversion='3.1';" andArguments:@[]];

        DDLogVerbose(@"Upgrade to 3.1 success");
    }


    if([dbversion doubleValue] < 3.2)
    {
        DDLogVerbose(@"Database version <3.2 detected. Performing upgrade.");

        [self.db executeNonQuery:@"update dbversion set dbversion='3.2';" andArguments:@[]];

        [self.db executeNonQuery:@"CREATE TABLE muteList (jid varchar(50));" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE blockList (jid varchar(50));" andArguments:@[]];

        DDLogVerbose(@"Upgrade to 3.2 success");
    }

    if([dbversion doubleValue] < 3.3)
    {
        DDLogVerbose(@"Database version <3.3 detected. Performing upgrade.");
        [self.db executeNonQuery:@"update dbversion set dbversion='3.3';" andArguments:@[]];

        [self.db executeNonQuery:@"alter table buddylist add column encrypt bool;" andArguments:@[]];

        DDLogVerbose(@"Upgrade to 3.3 success");
    }

    if([dbversion doubleValue] < 3.4)
    {
        DDLogVerbose(@"Database version <3.4 detected. Performing upgrade.");
        [self.db executeNonQuery:@"update dbversion set dbversion='3.4';" andArguments:@[]];

        [self.db executeNonQuery:@" alter table activechats add COLUMN lastMessageTime datetime " andArguments:@[]];

        //iterate current active and set their times
        NSArray* active = [self.db executeReader:@"select distinct buddy_name, account_id from activeChats" andArguments:@[]];
        [active enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary* row = (NSDictionary*)obj;
            //get max
            NSNumber* max = (NSNumber *)[self.db executeScalar:@"select max(TIMESTAMP) from message_history where (message_to=? or message_from=?) and account_id=?" andArguments:@[[row objectForKey:@"buddy_name"],[row objectForKey:@"buddy_name"], [row objectForKey:@"account_id"]]];
            if(max != nil) {
                [self.db executeNonQuery:@"update activechats set lastMessageTime=? where buddy_name=? and account_id=?" andArguments:@[max,[row objectForKey:@"buddy_name"], [row objectForKey:@"account_id"]]];
            } else  {

            }
        }];

        DDLogVerbose(@"Upgrade to 3.4 success");
    }

    if([dbversion doubleValue] < 3.5)
    {
        DDLogVerbose(@"Database version <3.5 detected. Performing upgrade.");
        [self.db executeNonQuery:@"update dbversion set dbversion='3.5';" andArguments:@[]];

        [self.db executeNonQuery:@"CREATE UNIQUE INDEX uniqueContact on buddylist (buddy_name, account_id);" andArguments:@[]];
        [self.db executeNonQuery:@"delete from buddy_resources" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE UNIQUE INDEX uniqueResource on buddy_resources (buddy_id, resource);" andArguments:@[]];

        DDLogVerbose(@"Upgrade to 3.5 success ");
    }


    if([dbversion doubleValue] < 3.6)
    {
        DDLogVerbose(@"Database version <3.6 detected. Performing upgrade.");
        [self.db executeNonQuery:@"update dbversion set dbversion='3.6';" andArguments:@[]];

        [self.db executeNonQuery:@"CREATE TABLE imageCache (url varchar(255), path varchar(255) );" andArguments:@[]];

        DDLogVerbose(@"Upgrade to 3.6 success");
    }

    if([dbversion doubleValue] < 3.7)
    {

        DDLogVerbose(@"Database version <3.7 detected. Performing upgrade.");
        [self.db executeNonQuery:@"update dbversion set dbversion='3.7';" andArguments:@[]];

        [self.db executeNonQuery:@"alter table message_history add column stanzaid text;" andArguments:@[]];

        DDLogVerbose(@"Upgrade to 3.7 success");
    }

    if([dbversion doubleValue] < 3.8)
    {
        DDLogVerbose(@"Database version <3.8 detected. Performing upgrade on accounts.");

        [self.db executeNonQuery:@"alter table account add column airdrop bool;" andArguments:@[]];

        [self.db executeNonQuery:@"update dbversion set dbversion='3.8';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 3.8 success");
    }

    if([dbversion doubleValue] < 3.9)
    {
        DDLogVerbose(@"Database version <3.9 detected. Performing upgrade on accounts.");

        [self.db executeNonQuery:@"alter table account add column rosterVersion varchar(50);" andArguments:@[]];

        [self.db executeNonQuery:@"update dbversion set dbversion='3.9';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 3.9 success");
    }

    if([dbversion doubleValue] < 4.0)
     {
         DDLogVerbose(@"Database version <4.0 detected. Performing upgrade on accounts.");

         [self.db executeNonQuery:@"alter table message_history add column errorType varchar(50);" andArguments:@[]];
         [self.db executeNonQuery:@"alter table message_history add column errorReason varchar(50);" andArguments:@[]];

         [self.db executeNonQuery:@"update dbversion set dbversion='4.0';" andArguments:@[]];
         DDLogVerbose(@"Upgrade to 4.0 success");
     }

    if([dbversion doubleValue] < 4.1)
     {
         DDLogVerbose(@"Database version <4.1 detected. Performing upgrade on accounts.");

         [self.db executeNonQuery:@"CREATE TABLE subscriptionRequests(requestid integer not null primary key AUTOINCREMENT,account_id integer not null,buddy_name varchar(50) collate nocase, UNIQUE(account_id,buddy_name))" andArguments:@[]];

         [self.db executeNonQuery:@"update dbversion set dbversion='4.1';" andArguments:@[]];
         DDLogVerbose(@"Upgrade to 4.1 success");
     }

    if([dbversion doubleValue] < 4.2)
     {
         DDLogVerbose(@"Database version <4.2 detected. Performing upgrade on accounts.");

         NSArray* contacts = [self.db executeReader:@"select distinct account_id, buddy_name, lastMessageTime from activechats;" andArguments:@[]];
          [self.db executeNonQuery:@"delete from activechats;" andArguments:@[]];
         [contacts enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
             [self.db executeNonQuery:@"insert into activechats (account_id, buddy_name, lastMessageTime) values (?,?,?);"
                      andArguments:@[
                      [obj objectForKey:@"account_id"],
                       [obj objectForKey:@"buddy_name"],
                       [obj objectForKey:@"lastMessageTime"]
                      ]];
         }];

          NSArray *dupeMessageids= [self.db executeReader:@"select * from (select messageid, count(messageid) as c from message_history   group by messageid) where c>1" andArguments:@[]];


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

         [self.db executeNonQuery:@"CREATE UNIQUE INDEX ux_account_messageid ON message_history(account_id, messageid)" andArguments:@[]];

         [self.db executeNonQuery:@"alter table activechats add column lastMesssage blob;" andArguments:@[]];
         [self.db executeNonQuery:@"CREATE UNIQUE INDEX ux_account_buddy ON activechats(account_id, buddy_name)" andArguments:@[]];

         [self.db executeNonQuery:@"update dbversion set dbversion='4.2';" andArguments:@[]];
         DDLogVerbose(@"Upgrade to 4.2 success");
     }

    if([dbversion doubleValue] < 4.3)
    {
        DDLogVerbose(@"Database version <4.3 detected. Performing upgrade on accounts.");
        [self.db executeNonQuery:@"alter table buddylist add column subscription varchar(50)" andArguments:@[]];
        [self.db executeNonQuery:@"alter table buddylist add column ask varchar(50)" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.3';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.3 success");
    }

    if([dbversion doubleValue] < 4.4)
    {
        DDLogVerbose(@"Database version <4.4 detected. Performing upgrade on accounts.");
        [self.db executeNonQuery:@"update account set rosterVersion='0';" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.4';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.4 success");
    }

    if([dbversion doubleValue] < 4.5)
    {
        DDLogVerbose(@"Database version <4.5 detected. Performing upgrade on accounts.");
        [self.db executeNonQuery:@"alter table account add column state blob;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.5';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.5 success");
    }

    if([dbversion doubleValue] < 4.6)
    {
        DDLogVerbose(@"Database version <4.6 detected. Performing upgrade on accounts.");
        [self.db executeNonQuery:@"alter table buddylist add column messageDraft text;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.6';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.6 success");
    }

    if([dbversion doubleValue] < 4.7)
    {
        DDLogVerbose(@"Database version <4.7 detected. Performing upgrade on accounts.");
        // Delete column password,account_name from account, set default value for rosterVersion to 0, increased varchar size
        [self.db executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:@[]];
        [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'protocol_id' integer NOT NULL, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:@[]];
        [self.db executeNonQuery:@"INSERT INTO account (account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"UPDATE account SET rosterVersion='0' WHERE rosterVersion is NULL;" andArguments:@[]];
        [self.db executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.7';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.7 success");
    }

    if([dbversion doubleValue] < 4.71)
    {
        DDLogVerbose(@"Database version <4.71 detected. Performing upgrade on accounts.");
        // Only reset server to '' when server == domain
        [self.db executeNonQuery:@"UPDATE account SET server='' where server=domain;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.71';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.71 success");
    }
    
    if([dbversion doubleValue] < 4.72)
    {
        DDLogVerbose(@"Database version <4.72 detected. Performing upgrade on accounts.");
        // Delete column protocol_id from account and drop protocol table
        [self.db executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:@[]];
        [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:@[]];
        [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:@[]];
        [self.db executeNonQuery:@"DROP TABLE protocol;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.72';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.72 success");
    }
    
    if([dbversion doubleValue] < 4.73)
    {
        DDLogVerbose(@"Database version <4.73 detected. Performing upgrade on accounts.");
        // Delete column oauth from account
        [self.db executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:@[]];
        [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:@[]];
        [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.73';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.73 success");
    }
    
    if([dbversion doubleValue] < 4.74)
    {
        DDLogVerbose(@"Database version <4.74 detected. Performing upgrade on accounts.");
        // Rename column oldstyleSSL to directTLS
        [self.db executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:@[]];
        [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:@[]];
        [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.74';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.74 success");
    }
    
    if([dbversion doubleValue] < 4.75)
    {
        DDLogVerbose(@"Database version <4.75 detected. Performing upgrade on accounts.");
        // Delete column secure from account
        [self.db executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:@[]];
        [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:@[]];
        [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state from _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.75';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.75 success");
    }
    
    if([dbversion doubleValue] < 4.76)
    {
        DDLogVerbose(@"Database version <4.76 detected. Performing upgrade on accounts.");
        // Add column for the last interaction of a contact
        [self.db executeNonQuery:@"alter table buddylist add column lastInteraction INTEGER NOT NULL DEFAULT 0;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.76';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.76 success");
    }
    
    if([dbversion doubleValue] < 4.77)
    {
        DDLogVerbose(@"Database version <4.77 detected. Performing upgrade on accounts.");
        // drop legacy caps tables
        [self.db executeNonQuery:@"DROP TABLE IF EXISTS legacy_caps;" andArguments:@[]];
        [self.db executeNonQuery:@"DROP TABLE IF EXISTS buddy_resources_legacy_caps;" andArguments:@[]];
        //recreate capabilities cache to make a fresh start
        [self.db executeNonQuery:@"DROP TABLE IF EXISTS ver_info;" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE ver_info(ver VARCHAR(32), cap VARCHAR(255), PRIMARY KEY (ver,cap));" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE ver_timestamp (ver VARCHAR(32), timestamp INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (ver));" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE INDEX timeindex ON ver_timestamp(timestamp);"  andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.77';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.77 success");
    }
    
    if([dbversion doubleValue] < 4.78)
    {
        DDLogVerbose(@"Database version <4.78 detected. Performing upgrade on accounts.");
        // drop airdrop column
        [self.db executeNonQuery:@"PRAGMA foreign_keys=off;" andArguments:@[]];
        [self.db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);" andArguments:@[]];
        [self.db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state from _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"DROP TABLE _accountTMP;" andArguments:@[]];
        [self.db executeNonQuery:@"PRAGMA foreign_keys=on;" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.78';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.78 success");
    }
    
    if([dbversion doubleValue] < 4.79)
    {
        //drop and recreate in 4.77 was faulty (wrong drop syntax), do it right this time
        [self.db executeNonQuery:@"DROP TABLE IF EXISTS ver_info;" andArguments:@[]];
        [self.db executeNonQuery:@"CREATE TABLE ver_info(ver VARCHAR(32), cap VARCHAR(255), PRIMARY KEY (ver,cap));" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.79';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.79 success");
    }
    
    if([dbversion doubleValue] < 4.80)
    {
        [self.db executeNonQuery:@"CREATE TABLE ipc(id integer NOT NULL PRIMARY KEY AUTOINCREMENT, name VARCHAR(255), destination VARCHAR(255), data BLOB, timeout INTEGER NOT NULL DEFAULT 0);" andArguments:@[]];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.80';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.80 success");
    }

    // Remove silly chats
    if([dbversion doubleValue] < 4.81)
    {
        [self.db executeReader:@"select account_id, username, domain from account" andArguments:@[] withCompletion:^(NSMutableArray* results) {
            for(NSDictionary* row in results) {
                NSString* accountJid = [NSString stringWithFormat:@"%@@%@", [row objectForKey:kUsername], [row objectForKey:kDomain]];
                NSString* accountNo = [row objectForKey:kAccountID];

                // delete chats with accountJid == buddy_name
                [self.db executeNonQuery:@"delete from activechats where account_id=? and buddy_name=?" andArguments:@[accountNo, accountJid]];
            }
        }];
        [self.db executeNonQuery:@"update dbversion set dbversion='4.81';" andArguments:@[]];
        DDLogVerbose(@"Upgrade to 4.81 success");
    }

    [self.db endWriteTransaction];
    DDLogInfo(@"Database version check done");
    return;
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

    if ([[HelperTools defaultsDB] boolForKey: @"ShowImages"] &&
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
    [self.db executeNonQuery:query andArguments:params];
}

-(void) unMuteJid:(NSString*) jid
{
    if(!jid) return;
    NSString* query = [NSString stringWithFormat:@"delete from muteList where jid=?"];
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) isMutedJid:(NSString*) jid withCompletion: (void (^)(BOOL))completion
{
    if(!jid) return;
    NSString* query = [NSString stringWithFormat:@"select count(jid) from muteList where jid=?"];
    NSArray* params = @[jid];
    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject *val) {
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
    [self.db executeNonQuery:query andArguments:params];
}

-(void) unBlockJid:(NSString*) jid
{
    if(!jid ) return;
    NSString* query = [NSString stringWithFormat:@"delete from blockList where jid=?"];
    NSArray* params = @[jid];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) isBlockedJid:(NSString*) jid withCompletion: (void (^)(BOOL))completion
{
    if(!jid) return completion(NO);
    NSString* query = [NSString stringWithFormat:@"select count(jid) from blockList where jid=?"];
    NSArray* params = @[jid];
    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject *val) {
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
    [self.db executeNonQuery:query andArguments:params];
}

-(void) deleteImageCacheForUrl:(NSString*) url
{
    NSString* query = [NSString stringWithFormat:@"delete from imageCache where url=?"];
    NSArray* params = @[url];
    [self.db executeNonQuery:query andArguments:params];
}

-(void) imageCacheForUrl:(NSString*) url withCompletion: (void (^)(NSString *path))completion
{
    if(!url) return;
    NSString* query = [NSString stringWithFormat:@"select path from imageCache where url=?"];
    NSArray* params = @[url];
    [self.db executeScalar:query andArguments:params withCompletion:^(NSObject *val) {
        NSString *path= (NSString *) val;
        if(completion) completion(path);
    }];
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
