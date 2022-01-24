//
//  DataLayerMigrations.m
//  monalxmpp
//
//  Created by Friedrich Altheide on 15.01.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

#import "MLSQLite.h"
#import "DataLayerMigrations.h"
#import "DataLayer.h"
#import "HelperTools.h"
#import "MLImageManager.h"

@implementation DataLayerMigrations

+(NSNumber*) readDBVersion:(MLSQLite*) db
{
    return [NSNumber numberWithDouble:[[db executeScalar:@"SELECT value FROM flags WHERE name='dbversion';"] doubleValue]];
}

+(BOOL) updateDB:(MLSQLite*) db withDataLayer:(DataLayer*) dataLayer toVersion:(double) version withBlock:(monal_void_block_t) block
{
    static BOOL accountStateInvalidated = NO;
    if([(NSNumber*)[db executeScalar:@"SELECT value FROM flags WHERE name='dbversion';"] doubleValue] < version)
    {
        DDLogVerbose(@"Database version <%@ detected. Performing upgrade.", [NSNumber numberWithDouble:version]);
        block();
        if(!accountStateInvalidated)
            [dataLayer invalidateAllAccountStates];
        accountStateInvalidated = YES;
        [db executeNonQuery:@"UPDATE flags SET value=? WHERE name='dbversion';" andArguments:@[[NSNumber numberWithDouble:version]]];
        DDLogDebug(@"Upgrade to %@ success", [NSNumber numberWithDouble:version]);
        return YES;
    }
    return NO;
}

+(BOOL) migrateDB:(MLSQLite*) db withDataLayer:(DataLayer*) dataLayer
{
    //migrate dbversion ino flags table (the exception indicates we are already migrated)
    [db voidWriteTransaction:^{
        NSNumber* alreadyMigrated = [db executeScalar:@"SELECT count(*) FROM sqlite_master WHERE type='table' AND name='dbversion';"];
        if([alreadyMigrated boolValue])
        {
            NSNumber* unmigratedDBVersion = [db executeScalar:@"SELECT dbversion FROM dbversion;"];
            DDLogInfo(@"Migrating dbversion to flags table...");
            [db executeNonQuery:@"DROP TABLE dbversion;"];
            [db executeNonQuery:@"CREATE TABLE 'flags' ( \
                    'name' VARCHAR(32) NOT NULL PRIMARY KEY, \
                    'value' TEXT DEFAULT NULL \
            );"];
            [db executeNonQuery:@"INSERT INTO flags (name, value) VALUES('dbversion', ?);" andArguments:@[unmigratedDBVersion]];
        }
        else
            DDLogVerbose(@"dbversion table already migrated");
    }];
    
    __block NSNumber* dbversion = nil;
    [db voidWriteTransaction:^{
        dbversion = [self readDBVersion:db];
        DDLogInfo(@"Got db version %@", dbversion);

        [self updateDB:db withDataLayer:dataLayer toVersion:2.0 withBlock:^{
            [db executeNonQuery:@"drop table muc_favorites"];
            [db executeNonQuery:@"CREATE TABLE IF NOT EXISTS \"muc_favorites\" (\"mucid\" integer NOT NULL primary key autoincrement,\"room\" varchar(255,0),\"nick\" varchar(255,0),\"autojoin\" bool, account_id int);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:2.1 withBlock:^{
            [db executeNonQuery:@"alter table message_history add column received bool;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:2.2 withBlock:^{
            [db executeNonQuery:@"alter table buddylist add column synchPoint datetime;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:2.3 withBlock:^{
            [db executeNonQuery:@"UPDATE account SET resource=?;" andArguments:@[[HelperTools encodeRandomResource]]];
        }];

        //OMEMO begins below
        [self updateDB:db withDataLayer:dataLayer toVersion:3.1 withBlock:^{
            [db executeNonQuery:@"CREATE TABLE signalIdentity (deviceid int NOT NULL PRIMARY KEY, account_id int NOT NULL unique,identityPublicKey BLOB,identityPrivateKey BLOB)"];
            [db executeNonQuery:@"CREATE TABLE signalSignedPreKey (account_id int NOT NULL,signedPreKeyId int not null,signedPreKey BLOB);"];

            [db executeNonQuery:@"CREATE TABLE signalPreKey (account_id int NOT NULL,prekeyid int not null,preKey BLOB);"];

            [db executeNonQuery:@"CREATE TABLE signalContactIdentity ( account_id int NOT NULL,contactName text,contactDeviceId int not null,identity BLOB,trusted boolean);"];

            [db executeNonQuery:@"CREATE TABLE signalContactKey (account_id int NOT NULL,contactName text,contactDeviceId int not null, groupId text,senderKey BLOB);"];

            [db executeNonQuery:@"  CREATE TABLE signalContactSession (account_id int NOT NULL, contactName text, contactDeviceId int not null, recordData BLOB)"];
            [db executeNonQuery:@"alter table message_history add column encrypted bool;"];

            [db executeNonQuery:@"alter table message_history add column previewText text;"];
            [db executeNonQuery:@"alter table message_history add column previewImage text;"];

            [db executeNonQuery:@"alter table buddylist add column backgroundImage text;"];
        }];


        [self updateDB:db withDataLayer:dataLayer toVersion:3.2 withBlock:^{
            [db executeNonQuery:@"CREATE TABLE muteList (jid varchar(50));"];
            [db executeNonQuery:@"CREATE TABLE blockList (jid varchar(50));"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:3.3 withBlock:^{
            [db executeNonQuery:@"alter table buddylist add column encrypt bool;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:3.4 withBlock:^{
            [db executeNonQuery:@"alter table activechats add COLUMN lastMessageTime datetime "];

            //iterate current active and set their times
            NSArray* active = [db executeReader:@"select distinct buddy_name, account_id from activeChats"];
            [active enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSDictionary* row = (NSDictionary*)obj;
                //get max
                NSNumber* max = (NSNumber *)[db executeScalar:@"select max(TIMESTAMP) from message_history where (message_to=? or message_from=?) and account_id=?" andArguments:@[[row objectForKey:@"buddy_name"],[row objectForKey:@"buddy_name"], [row objectForKey:@"account_id"]]];
                if(max != nil) {
                    [db executeNonQuery:@"update activechats set lastMessageTime=? where buddy_name=? and account_id=?" andArguments:@[max,[row objectForKey:@"buddy_name"], [row objectForKey:@"account_id"]]];
                } else  {

                }
            }];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:3.5 withBlock:^{
            [db executeNonQuery:@"CREATE UNIQUE INDEX uniqueContact on buddylist (buddy_name, account_id);"];
            [db executeNonQuery:@"delete from buddy_resources"];
            [db executeNonQuery:@"CREATE UNIQUE INDEX uniqueResource on buddy_resources (buddy_id, resource);"];
        }];


        [self updateDB:db withDataLayer:dataLayer toVersion:3.6 withBlock:^{
            [db executeNonQuery:@"CREATE TABLE imageCache (url varchar(255), path varchar(255) );"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:3.7 withBlock:^{
            [db executeNonQuery:@"alter table message_history add column stanzaid text;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:3.8 withBlock:^{
            [db executeNonQuery:@"alter table account add column airdrop bool;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:3.9 withBlock:^{
            [db executeNonQuery:@"alter table account add column rosterVersion varchar(50);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.0 withBlock:^{
            [db executeNonQuery:@"alter table message_history add column errorType varchar(50);"];
            [db executeNonQuery:@"alter table message_history add column errorReason varchar(50);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.1 withBlock:^{
            [db executeNonQuery:@"CREATE TABLE subscriptionRequests(requestid integer not null primary key AUTOINCREMENT,account_id integer not null,buddy_name varchar(50) collate nocase, UNIQUE(account_id,buddy_name))"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.2 withBlock:^{
            NSArray* contacts = [db executeReader:@"select distinct account_id, buddy_name, lastMessageTime from activechats;"];
            [db executeNonQuery:@"delete from activechats;"];
            [contacts enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                [db executeNonQuery:@"insert into activechats (account_id, buddy_name, lastMessageTime) values (?,?,?);"
                        andArguments:@[
                        [obj objectForKey:@"account_id"],
                        [obj objectForKey:@"buddy_name"],
                        [obj objectForKey:@"lastMessageTime"]
                        ]];
            }];
            NSArray *dupeMessageids= [db executeReader:@"select * from (select messageid, count(messageid) as c from message_history   group by messageid) where c>1"];

            [dupeMessageids enumerateObjectsUsingBlock:^(NSDictionary *  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    NSArray* dupeMessages = [db executeReader:@"select * from message_history where messageid=? order by message_history_id asc " andArguments:@[[obj objectForKey:@"messageid"]]];
                //hopefully this is quick and doesnt grow..
                [dupeMessages enumerateObjectsUsingBlock:^(NSDictionary *  _Nonnull message, NSUInteger idx, BOOL * _Nonnull stop) {
                    //keep first one
                    if(idx > 0) {
                        [db executeNonQuery:@"delete from message_history where message_history_id=?" andArguments:@[[message objectForKey:@"message_history_id"]]];
                    }
                }];
            }];
            [db executeNonQuery:@"CREATE UNIQUE INDEX ux_account_messageid ON message_history(account_id, messageid)"];

            [db executeNonQuery:@"alter table activechats add column lastMesssage blob;"];
            [db executeNonQuery:@"CREATE UNIQUE INDEX ux_account_buddy ON activechats(account_id, buddy_name)"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.3 withBlock:^{

            [db executeNonQuery:@"alter table buddylist add column subscription varchar(50)"];
            [db executeNonQuery:@"alter table buddylist add column ask varchar(50)"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.4 withBlock:^{

            [db executeNonQuery:@"update account set rosterVersion='0';"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.5 withBlock:^{

            [db executeNonQuery:@"alter table account add column state blob;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.6 withBlock:^{

            [db executeNonQuery:@"alter table buddylist add column messageDraft text;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.7 withBlock:^{

            // Delete column password,account_name from account, set default value for rosterVersion to 0, increased varchar size
            [db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'protocol_id' integer NOT NULL, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [db executeNonQuery:@"INSERT INTO account (account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, protocol_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;"];
            [db executeNonQuery:@"UPDATE account SET rosterVersion='0' WHERE rosterVersion is NULL;"];
            [db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.71 withBlock:^{

            // Only reset server to '' when server == domain
            [db executeNonQuery:@"UPDATE account SET server='' where server=domain;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.72 withBlock:^{

            // Delete column protocol_id from account and drop protocol table
            [db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'oauth' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, oauth, airdrop, rosterVersion, state from _accountTMP;"];
            [db executeNonQuery:@"DROP TABLE _accountTMP;"];
            [db executeNonQuery:@"DROP TABLE protocol;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.73 withBlock:^{

            // Delete column oauth from account
            [db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'oldstyleSSL' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;"];
            [db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.74 withBlock:^{
            // Rename column oldstyleSSL to directTLS
            [db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'secure' bool, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, secure, resource, domain, enabled, selfsigned, oldstyleSSL, airdrop, rosterVersion, state from _accountTMP;"];
            [db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.75 withBlock:^{
            // Delete column secure from account
            [db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'airdrop' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, airdrop, rosterVersion, state from _accountTMP;"];
            [db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.76 withBlock:^{
            // Add column for the last interaction of a contact
            [db executeNonQuery:@"alter table buddylist add column lastInteraction INTEGER NOT NULL DEFAULT 0;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.77 withBlock:^{
            // drop legacy caps tables
            [db executeNonQuery:@"DROP TABLE IF EXISTS legacy_caps;"];
            [db executeNonQuery:@"DROP TABLE IF EXISTS buddy_resources_legacy_caps;"];
            //recreate capabilities cache to make a fresh start
            [db executeNonQuery:@"DROP TABLE IF EXISTS ver_info;"];
            [db executeNonQuery:@"CREATE TABLE ver_info(ver VARCHAR(32), cap VARCHAR(255), PRIMARY KEY (ver,cap));"];
            [db executeNonQuery:@"CREATE TABLE ver_timestamp (ver VARCHAR(32), timestamp INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (ver));"];
            [db executeNonQuery:@"CREATE INDEX timeindex ON ver_timestamp(timestamp);" ];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.78 withBlock:^{
            // drop airdrop column
            [db executeNonQuery:@"ALTER TABLE account RENAME TO _accountTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'account' ('account_id' integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'server' varchar(1023) NOT NULL, 'other_port' integer, 'username' varchar(1023) NOT NULL, 'resource'  varchar(1023) NOT NULL, 'domain' varchar(1023) NOT NULL, 'enabled' bool, 'selfsigned' bool, 'directTLS' bool, 'rosterVersion' varchar(50) DEFAULT 0, 'state' blob);"];
            [db executeNonQuery:@"INSERT INTO account (account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state) SELECT account_id, server, other_port, username, resource, domain, enabled, selfsigned, directTLS, rosterVersion, state from _accountTMP;"];
            [db executeNonQuery:@"DROP TABLE _accountTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.80 withBlock:^{
            [db executeNonQuery:@"CREATE TABLE ipc(id integer NOT NULL PRIMARY KEY AUTOINCREMENT, name VARCHAR(255), destination VARCHAR(255), data BLOB, timeout INTEGER NOT NULL DEFAULT 0);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.81 withBlock:^{
            // Remove silly chats
            NSMutableArray* results = [db executeReader:@"select account_id, username, domain from account"];
            for(NSDictionary* row in results) {
                NSString* accountJid = [NSString stringWithFormat:@"%@@%@", [row objectForKey:kUsername], [row objectForKey:kDomain]];
                NSString* accountNo = [row objectForKey:kAccountID];

                // delete chats with accountJid == buddy_name
                [db executeNonQuery:@"delete from activechats where account_id=? and buddy_name=?" andArguments:@[accountNo, accountJid]];
            }
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.82 withBlock:^{
            //use the more appropriate name "sent" for the "delivered" column of message_history
            [db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'message_history' (message_history_id integer not null primary key AUTOINCREMENT, account_id integer, message_from text collate nocase, message_to text collate nocase, timestamp datetime, message blob, actual_from text collate nocase, messageid text, messageType text, sent bool, received bool, unread bool, encrypted bool, previewText text, previewImage text, stanzaid text, errorType text, errorReason text);"];
            [db executeNonQuery:@"INSERT INTO message_history (message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, sent, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason) SELECT message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, delivered, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason from _message_historyTMP;"];
            [db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.83 withBlock:^{
            [db executeNonQuery:@"alter table activechats add column pinned bool DEFAULT FALSE;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.84 withBlock:^{
            [db executeNonQuery:@"DROP TABLE IF EXISTS ipc;"];
            //remove synchPoint from db
            [db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50), nick_name varchar(50), group_name varchar(50), iconhash varchar(200), filename varchar(100), state varchar(20), status varchar(200), online bool, dirty bool, new bool, Muc bool, muc_subject varchar(255), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0);"];
            [db executeNonQuery:@"INSERT INTO buddylist (buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, online, dirty, new, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction) SELECT buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, online, dirty, new, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction FROM _buddylistTMP;"];
            [db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact on buddylist(buddy_name, account_id);"];
            //make stanzaid, messageid and errorType caseinsensitive and create indixes for stanzaid and messageid
            [db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            [db executeNonQuery:@"CREATE TABLE message_history (message_history_id integer not null primary key AUTOINCREMENT, account_id integer, message_from text collate nocase, message_to text collate nocase, timestamp datetime, message blob, actual_from text collate nocase, messageid text collate nocase, messageType text, sent bool, received bool, unread bool, encrypted bool, previewText text, previewImage text, stanzaid text collate nocase, errorType text collate nocase, errorReason text);"];
            [db executeNonQuery:@"INSERT INTO message_history (message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, sent, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason) SELECT message_history_id, account_id, message_from, message_to, timestamp, message, actual_from, messageid, messageType, sent, received, unread, encrypted, previewText, previewImage, stanzaid, errorType, errorReason FROM _message_historyTMP;"];
            [db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
            [db executeNonQuery:@"CREATE INDEX stanzaidIndex on message_history(stanzaid collate nocase);"];
            [db executeNonQuery:@"CREATE INDEX messageidIndex on message_history(messageid collate nocase);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.85 withBlock:^{
            //Performing upgrade on buddy_resources.
            [db executeNonQuery:@"ALTER TABLE buddy_resources ADD platform_App_Name text;"];
            [db executeNonQuery:@"ALTER TABLE buddy_resources ADD platform_App_Version text;"];
            [db executeNonQuery:@"ALTER TABLE buddy_resources ADD platform_OS text;"];

            //drop and recreate in 4.77 was faulty (wrong drop syntax), do it right this time
            [db executeNonQuery:@"DROP TABLE IF EXISTS ver_info;"];
            [db executeNonQuery:@"CREATE TABLE ver_info(ver VARCHAR(32), cap VARCHAR(255), PRIMARY KEY (ver,cap));"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.86 withBlock:^{
            //add new stanzaid field to account table that always points to the last received stanzaid (even if that does not have a body)
            [db executeNonQuery:@"ALTER TABLE account ADD lastStanzaId text;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.87 withBlock:^{
            //populate new stanzaid field in account table from message_history table
            NSString* stanzaId = (NSString*)[db executeScalar:@"SELECT stanzaid FROM message_history WHERE stanzaid!='' ORDER BY message_history_id DESC LIMIT 1;"];
            DDLogVerbose(@"Populating lastStanzaId with id %@ from history table", stanzaId);
            if(stanzaId && [stanzaId length])
                [db executeNonQuery:@"UPDATE account SET lastStanzaId=?;" andArguments:@[stanzaId]];
            //remove all old and most probably *wrong* stanzaids from history table
            [db executeNonQuery:@"UPDATE message_history SET stanzaid='';"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.9 withBlock:^{
            // add timestamps to omemo prekeys
            [db executeNonQuery:@"ALTER TABLE signalPreKey RENAME TO _signalPreKeyTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'signalPreKey' ('account_id' int NOT NULL, 'prekeyid' int NOT NULL, 'preKey' BLOB, 'creationTimestamp' INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, 'pubSubRemovalTimestamp' INTEGER DEFAULT NULL, 'keyUsed' INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (account_id, prekeyid, preKey));"];
            [db executeNonQuery:@"INSERT INTO signalPreKey (account_id, prekeyid, preKey) SELECT account_id, prekeyid, preKey FROM _signalPreKeyTMP;"];
            [db executeNonQuery:@"DROP TABLE _signalPreKeyTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.91 withBlock:^{
            //not needed anymore (better handled by 4.97)
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.92 withBlock:^{
            //add displayed and displayMarkerWanted fields
            [db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN displayed BOOL DEFAULT FALSE;"];
            [db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN displayMarkerWanted BOOL DEFAULT FALSE;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.93 withBlock:^{
            //full_name should not be buddy_name anymore, but the user provided XEP-0172 nickname
            //and nick_name will be the roster name, if given
            //if none of these two are given, the local part of the jid (called node in prosody and in jidSplit:) will be used, like in other clients
            //see also https://docs.modernxmpp.org/client/design/#contexts
            [db executeNonQuery:@"UPDATE buddylist SET full_name='' WHERE full_name=buddy_name;"];
            [db executeNonQuery:@"UPDATE account SET rosterVersion=?;" andArguments:@[@""]];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.94 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE account ADD COLUMN rosterName TEXT;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.95 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE account ADD COLUMN iconhash VARCHAR(200);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.96 withBlock:^{
            //not needed anymore (better handled by 4.97)
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.97 withBlock:^{
            [dataLayer invalidateAllAccountStates];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.98 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN filetransferMimeType VARCHAR(32) DEFAULT 'application/octet-stream';"];
            [db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN filetransferSize INTEGER DEFAULT 0;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.990 withBlock:^{
            // remove dupl entries from activechats && budylist
            [db executeNonQuery:@"DELETE FROM activechats \
                WHERE ROWID NOT IN \
                    (SELECT tmpID FROM \
                        (SELECT ROWID as tmpID, account_id, buddy_name FROM activechats WHERE \
                        ROWID IN \
                            (SELECT ROWID FROM activechats ORDER BY lastMessageTime DESC) \
                        GROUP BY account_id, buddy_name) \
                    )"];
            [db executeNonQuery:@"DELETE FROM buddylist WHERE ROWID NOT IN \
                    (SELECT tmpID FROM \
                        (SELECT ROWID as tmpID, account_id, buddy_name FROM buddylist GROUP BY account_id, buddy_name) \
                    )"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.991 withBlock:^{
            //remove dirty, online, new from db
            [db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50), nick_name varchar(50), group_name varchar(50), iconhash varchar(200), filename varchar(100), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(255), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0);"];
            [db executeNonQuery:@"INSERT INTO buddylist (buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction) SELECT buddy_id, account_id, buddy_name, full_name, nick_name, group_name, iconhash, filename, state, status, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction FROM _buddylistTMP;"];
            [db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact on buddylist(buddy_name, account_id);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.992 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE account ADD COLUMN statusMessage TEXT;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.993 withBlock:^{
            //make filetransferMimeType and filetransferSize have NULL as default value
            //(this makes it possible to distinguish unknown values from known ones)
            [db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            [db executeNonQuery:@"CREATE TABLE message_history (message_history_id integer not null primary key AUTOINCREMENT, account_id integer, message_from text collate nocase, message_to text collate nocase, timestamp datetime, message blob, actual_from text collate nocase, messageid text collate nocase, messageType text, sent bool, received bool, unread bool, encrypted bool, previewText text, previewImage text, stanzaid text collate nocase, errorType text collate nocase, errorReason text, displayed BOOL DEFAULT FALSE, displayMarkerWanted BOOL DEFAULT FALSE, filetransferMimeType VARCHAR(32) DEFAULT NULL, filetransferSize INTEGER DEFAULT NULL);"];
            [db executeNonQuery:@"INSERT INTO message_history SELECT * FROM _message_historyTMP;"];
            [db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
            [db executeNonQuery:@"CREATE INDEX stanzaidIndex on message_history(stanzaid collate nocase);"];
            [db executeNonQuery:@"CREATE INDEX messageidIndex on message_history(messageid collate nocase);"];
        }];

        // skipping 4.994 due to invalid command

        [self updateDB:db withDataLayer:dataLayer toVersion:4.995 withBlock:^{
            [db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueActiveChat ON activechats(buddy_name, account_id);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.996 withBlock:^{
            //remove all icon hashes to reload all icons on next app/nse start
            //(the db upgrade mechanism will make sure that no smacks resume will take place and pep pushes come in for all avatars)
            [db executeNonQuery:@"UPDATE account SET iconhash='';"];
            [db executeNonQuery:@"UPDATE buddylist SET iconhash='';"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:4.997 withBlock:^{
            //create unique constraint for (account_id, buddy_name) on activechats table
            [db executeNonQuery:@"ALTER TABLE activechats RENAME TO _activechatsTMP;"];
            [db executeNonQuery:@"CREATE TABLE activechats (account_id integer not null, buddy_name varchar(50) collate nocase, lastMessageTime datetime, lastMesssage blob, pinned bool DEFAULT FALSE, UNIQUE(account_id, buddy_name));"];
            [db executeNonQuery:@"INSERT INTO activechats SELECT * FROM _activechatsTMP;"];
            [db executeNonQuery:@"DROP TABLE _activechatsTMP;"];
            [db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueActiveChat ON activechats(buddy_name, account_id);"];

            //create unique constraint for (buddy_name, account_id) on buddylist table
            [db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50), nick_name varchar(50), group_name varchar(50), iconhash varchar(200), filename varchar(100), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(255), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0, UNIQUE(account_id, buddy_name));"];
            [db executeNonQuery:@"INSERT INTO buddylist SELECT * FROM _buddylistTMP;"];
            [db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact on buddylist(buddy_name, account_id);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.000 withBlock:^{
            // cleanup omemo tables
            [db executeNonQuery:@"DELETE FROM signalContactIdentity WHERE account_id NOT IN (SELECT account_id FROM account);"];
            [db executeNonQuery:@"DELETE FROM signalContactKey WHERE account_id NOT IN (SELECT account_id FROM account);"];
            [db executeNonQuery:@"DELETE FROM signalIdentity WHERE account_id NOT IN (SELECT account_id FROM account);"];
            [db executeNonQuery:@"DELETE FROM signalPreKey WHERE account_id NOT IN (SELECT account_id FROM account);"];
            [db executeNonQuery:@"DELETE FROM signalSignedPreKey WHERE account_id NOT IN (SELECT account_id FROM account);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.001 withBlock:^{
            //do this in 5.0 branch as well

            //create unique constraint for (account_id, buddy_name) on activechats table
            [db executeNonQuery:@"ALTER TABLE activechats RENAME TO _activechatsTMP;"];
            [db executeNonQuery:@"CREATE TABLE activechats (account_id integer not null, buddy_name varchar(50) collate nocase, lastMessageTime datetime, lastMesssage blob, pinned bool DEFAULT FALSE, UNIQUE(account_id, buddy_name));"];
            [db executeNonQuery:@"INSERT INTO activechats SELECT * FROM _activechatsTMP;"];
            [db executeNonQuery:@"DROP TABLE _activechatsTMP;"];
            [db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueActiveChat ON activechats(buddy_name, account_id);"];

            //create unique constraint for (buddy_name, account_id) on buddylist table
            [db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(50) collate nocase, full_name varchar(50), nick_name varchar(50), group_name varchar(50), iconhash varchar(200), filename varchar(100), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(255), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0, UNIQUE(account_id, buddy_name));"];
            [db executeNonQuery:@"INSERT INTO buddylist SELECT * FROM _buddylistTMP;"];
            [db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact on buddylist(buddy_name, account_id);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.002 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE buddylist ADD COLUMN blocked BOOL DEFAULT FALSE;"];
            [db executeNonQuery:@"DROP TABLE blockList;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.003 withBlock:^{
            [db executeNonQuery:@"CREATE TABLE 'blocklistCache' (\
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
        [self updateDB:db withDataLayer:dataLayer toVersion:5.004 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE signalContactIdentity RENAME TO _signalContactIdentityTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'signalContactIdentity' ( \
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
            [db executeNonQuery:@"INSERT INTO signalContactIdentity \
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
            [db executeNonQuery:@"DROP TABLE _signalContactIdentityTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.005 withBlock:^{
            //remove group_name and filename columns from buddylist, resize buddy_name, full_name, nick_name and muc_subject columns and add lastStanzaId column (only used for mucs)
            [db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [db executeNonQuery:@"CREATE TABLE buddylist(buddy_id integer not null primary key AUTOINCREMENT, account_id integer not null, buddy_name varchar(255) collate nocase, full_name varchar(255), nick_name varchar(255), iconhash varchar(200), state varchar(20), status varchar(200), Muc bool, muc_subject varchar(1024), muc_nick varchar(255), backgroundImage text, encrypt bool, subscription varchar(50), ask varchar(50), messageDraft text, lastInteraction INTEGER NOT NULL DEFAULT 0, blocked BOOL DEFAULT FALSE, muc_type VARCHAR(10) DEFAULT 'channel', lastMucStanzaId text DEFAULT NULL, UNIQUE(account_id, buddy_name));"];
            [db executeNonQuery:@"INSERT INTO buddylist SELECT buddy_id, account_id, buddy_name, full_name, nick_name, iconhash, state, status, Muc, muc_subject, muc_nick, backgroundImage, encrypt, subscription, ask, messageDraft, lastInteraction, blocked, 'channel', NULL FROM _buddylistTMP;"];
            [db executeNonQuery:@"DROP TABLE _buddylistTMP;"];
            [db executeNonQuery:@"CREATE UNIQUE INDEX IF NOT EXISTS uniqueContact ON buddylist(buddy_name, account_id);"];
            [db executeNonQuery:@"UPDATE buddylist SET muc_type='channel' WHERE Muc = true;"];     //muc default type

            //create new muc favorites table
            [db executeNonQuery:@"DROP TABLE muc_favorites;"];
            [db executeNonQuery:@"CREATE TABLE muc_favorites (room VARCHAR(255) PRIMARY KEY, nick varchar(255), account_id INTEGER, UNIQUE(room, account_id));"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.006 withBlock:^{
            // recreate blocklistCache - fixes foreign key
            [db executeNonQuery:@"ALTER TABLE blocklistCache RENAME TO _blocklistCacheTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'blocklistCache' (\
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
            [db executeNonQuery:@"DELETE FROM _blocklistCacheTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [db executeNonQuery:@"INSERT INTO blocklistCache SELECT * FROM _blocklistCacheTMP;"];
            [db executeNonQuery:@"DROP TABLE _blocklistCacheTMP;"];

            // recreate signalContactIdentity - fixes foreign key
            [db executeNonQuery:@"ALTER TABLE signalContactIdentity RENAME TO _signalContactIdentityTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'signalContactIdentity' ( \
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
            [db executeNonQuery:@"DELETE FROM _signalContactIdentityTMP WHERE account_id NOT IN (SELECT account_id FROM account) OR (account_id, contactName) NOT IN (SELECT account_id, buddy_name FROM buddylist);"];
            [db executeNonQuery:@"INSERT INTO signalContactIdentity SELECT * FROM _signalContactIdentityTMP;"];
            [db executeNonQuery:@"DROP TABLE _signalContactIdentityTMP;"];
            // add self chats for omemo
            [db executeNonQuery:@"INSERT OR IGNORE INTO buddylist ('account_id', 'buddy_name', 'muc') SELECT account_id, (username || '@' || domain), 0 FROM account;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.007 withBlock:^{
            // remove broken omemo sessions
            [db executeNonQuery:@"DELETE FROM signalContactIdentity WHERE (account_id, contactName) NOT IN (SELECT account_id, contactName FROM signalContactSession);"];
            [db executeNonQuery:@"DELETE FROM signalContactSession WHERE (account_id, contactName) NOT IN (SELECT account_id, contactName FROM signalContactIdentity);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.008 withBlock:^{
            [db executeNonQuery:@"DROP TABLE muc_favorites;"];
            [db executeNonQuery:@"CREATE TABLE 'muc_favorites' ( \
                 'account_id' INTEGER NOT NULL, \
                 'room' VARCHAR(255) NOT NULL, \
                 'nick' varchar(255), \
                 'autojoin' BOOL NOT NULL DEFAULT 0, \
                 FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                 UNIQUE('room', 'account_id'), \
                 PRIMARY KEY('account_id', 'room') \
             );"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.009 withBlock:^{
            // add foreign key to signalContactSession
            [db executeNonQuery:@"ALTER TABLE signalContactSession RENAME TO _signalContactSessionTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'signalContactSession' ( \
                     'account_id' int NOT NULL, \
                     'contactName' text, \
                     'contactDeviceId' int NOT NULL, \
                     'recordData' BLOB, \
                     PRIMARY KEY('account_id','contactName','contactDeviceId'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                     FOREIGN KEY('account_id', 'contactName') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
                 );"];
            [db executeNonQuery:@"DELETE FROM _signalContactSessionTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [db executeNonQuery:@"DELETE FROM _signalContactSessionTMP WHERE (account_id, contactName) NOT IN (SELECT account_id, buddy_name FROM buddylist)"];
            [db executeNonQuery:@"INSERT INTO signalContactSession SELECT * FROM _signalContactSessionTMP;"];
            [db executeNonQuery:@"DROP TABLE _signalContactSessionTMP;"];

            // add foreign key to signalIdentity
            [db executeNonQuery:@"ALTER TABLE signalIdentity RENAME TO _signalIdentityTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'signalIdentity' ( \
                     'account_id' int NOT NULL, \
                     'deviceid' int NOT NULL, \
                     'identityPublicKey' BLOB NOT NULL, \
                     'identityPrivateKey' BLOB NOT NULL, \
                     PRIMARY KEY('account_id', 'deviceid'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE \
                 );"];
            [db executeNonQuery:@"DELETE FROM _signalIdentityTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [db executeNonQuery:@"INSERT INTO signalIdentity (account_id, deviceid, identityPublicKey, identityPrivateKey) SELECT account_id, deviceid, identityPublicKey, identityPrivateKey FROM _signalIdentityTMP;"];
            [db executeNonQuery:@"DROP TABLE _signalIdentityTMP;"];

            // add foreign key to signalPreKey
            [db executeNonQuery:@"ALTER TABLE signalPreKey RENAME TO _signalPreKeyTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'signalPreKey' ( \
                     'account_id' int NOT NULL, \
                     'prekeyid' int NOT NULL, \
                     'preKey' BLOB, \
                     'creationTimestamp' INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, \
                     'pubSubRemovalTimestamp' INTEGER DEFAULT NULL, \
                     'keyUsed' INTEGER NOT NULL DEFAULT 0, \
                     PRIMARY KEY('account_id', 'prekeyid'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE \
                 );"];
            [db executeNonQuery:@"DELETE FROM _signalPreKeyTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [db executeNonQuery:@"INSERT INTO signalPreKey SELECT * FROM _signalPreKeyTMP;"];
            [db executeNonQuery:@"DROP TABLE _signalPreKeyTMP;"];

            // add foreign key to signalSignedPreKey
            [db executeNonQuery:@"ALTER TABLE signalSignedPreKey RENAME TO _signalSignedPreKeyTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'signalSignedPreKey' ( \
                     'account_id' int NOT NULL, \
                     'signedPreKeyId' int NOT NULL, \
                     'signedPreKey' BLOB, \
                     PRIMARY KEY('account_id', 'signedPreKeyId'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE \
                 );"];
            [db executeNonQuery:@"DELETE FROM _signalSignedPreKeyTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [db executeNonQuery:@"DELETE FROM _signalSignedPreKeyTMP WHERE (ROWID, account_id, signedPreKeyId, signedPreKey) NOT IN (SELECT ROWID, account_id, signedPreKeyId, signedPreKey FROM _signalSignedPreKeyTMP GROUP BY account_id);"];
            [db executeNonQuery:@"INSERT INTO signalSignedPreKey SELECT * FROM _signalSignedPreKeyTMP;"];
            [db executeNonQuery:@"DROP TABLE _signalSignedPreKeyTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.010 withBlock:^{
            // add foreign key to activechats
            [db executeNonQuery:@"ALTER TABLE activechats RENAME TO _activechatsTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'activechats' ( \
                     'account_id' integer NOT NULL, \
                     'buddy_name' varchar(50) NOT NULL COLLATE nocase, \
                     'lastMessageTime' datetime, \
                     'lastMesssage' blob, \
                     'pinned' bool NOT NULL DEFAULT FALSE, \
                     PRIMARY KEY('account_id', 'buddy_name'), \
                     FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                     FOREIGN KEY('account_id', 'buddy_name') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
                 );"];
            [db executeNonQuery:@"DELETE FROM _activechatsTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [db executeNonQuery:@"DELETE FROM _activechatsTMP WHERE (account_id, buddy_name) NOT IN (SELECT account_id, buddy_name FROM buddylist)"];
            [db executeNonQuery:@"INSERT INTO activechats SELECT * FROM _activechatsTMP;"];
            [db executeNonQuery:@"DROP TABLE _activechatsTMP;"];

            // add foreign key to activechats
            [db executeNonQuery:@"ALTER TABLE buddylist RENAME TO _buddylistTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'buddylist' ( \
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
            [db executeNonQuery:@"DELETE FROM _buddylistTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [db executeNonQuery:@"INSERT INTO buddylist SELECT * FROM _buddylistTMP;"];
            [db executeNonQuery:@"DROP TABLE _buddylistTMP;"];

            // add foreign key to buddy_resources
            [db executeNonQuery:@"ALTER TABLE buddy_resources RENAME TO _buddy_resourcesTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'buddy_resources' ( \
                     'buddy_id' integer NOT NULL, \
                     'resource' varchar(255, 0) NOT NULL, \
                     'ver' varchar(20, 0), \
                     'platform_App_Name' text, \
                     'platform_App_Version' text, \
                     'platform_OS' text, \
                     PRIMARY KEY('buddy_id','resource'), \
                     FOREIGN KEY('buddy_id') REFERENCES 'buddylist'('buddy_id') ON DELETE CASCADE \
                 );"];
            [db executeNonQuery:@"DELETE FROM _buddy_resourcesTMP WHERE buddy_id NOT IN (SELECT buddy_id FROM buddylist)"];
            [db executeNonQuery:@"DELETE FROM _buddy_resourcesTMP WHERE (ROWID, buddy_id, resource) NOT IN (SELECT ROWID, buddy_id, resource FROM _buddy_resourcesTMP GROUP BY buddy_id, resource);"];
            [db executeNonQuery:@"INSERT INTO buddy_resources (buddy_id, resource, ver, platform_App_Name, platform_App_Version, platform_OS) SELECT buddy_id, resource, ver, platform_App_Name, platform_App_Version, platform_OS FROM _buddy_resourcesTMP;"];
            [db executeNonQuery:@"DROP TABLE _buddy_resourcesTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.011 withBlock:^{
            [db executeNonQuery:@"CREATE TABLE 'muc_participants' ( \
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

        [self updateDB:db withDataLayer:dataLayer toVersion:5.012 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE buddylist ADD COLUMN muted BOOL DEFAULT FALSE"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.013 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE signalContactIdentity ADD COLUMN brokenSession BOOL DEFAULT FALSE"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.014 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE message_history RENAME TO _message_historyTMP;"];
            // Create a backup before changing a lot of the table style
            [db executeNonQuery:@"CREATE TABLE message_history_backup AS SELECT * FROM _message_historyTMP WHERE 0"];
            [db executeNonQuery:@"INSERT INTO message_history_backup SELECT * FROM _message_historyTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'message_history' ( \
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
            [db executeNonQuery:@"DELETE FROM _message_historyTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            // delete all group chats and all chats that don't have a valid buddy
            [db executeNonQuery:@"DELETE FROM _message_historyTMP WHERE message_history_id IN (\
                SELECT message_history_id \
                FROM _message_historyTMP AS M INNER JOIN account AS A \
                    ON M.account_id=A.account_id \
                    WHERE (M.message_from!=(A.username || '@' || A.domain) AND M.message_to!=(A.username || '@' || A.domain))\
                )\
            "];
            [db executeNonQuery:@"INSERT INTO message_history \
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
            [db executeNonQuery:@"DELETE FROM message_history WHERE message_history_id IN (\
                SELECT message_history_id \
                FROM message_history AS M INNER JOIN buddylist AS B\
                ON M.account_id=B.account_id AND M.buddy_name=B.buddy_name \
                WHERE B.Muc=1) \
            "];
            [db executeNonQuery:@"DROP TABLE _message_historyTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.015 withBlock:^{
            [db executeNonQuery:@"CREATE TABLE 'muc_members' ( \
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
        [self updateDB:db withDataLayer:dataLayer toVersion:5.016 withBlock:^{
            [db executeNonQuery:@"UPDATE buddylist SET muted=1 \
                WHERE buddy_name IN ( \
                    SELECT DISTINCT jid FROM muteList \
             );"];
            [db executeNonQuery:@"DROP TABLE muteList;"];
        }];

        // Delete all muc's
        [self updateDB:db withDataLayer:dataLayer toVersion:5.017 withBlock:^{
            [db executeNonQuery:@"DELETE FROM buddylist WHERE Muc=1;"];
            [db executeNonQuery:@"DELETE FROM muc_participants;"];
            [db executeNonQuery:@"DELETE FROM muc_members;"];
            [db executeNonQuery:@"DELETE FROM muc_favorites;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.018 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE message_history ADD COLUMN participant_jid TEXT DEFAULT NULL"];
        }];

        // delete message_history backup table
        [self updateDB:db withDataLayer:dataLayer toVersion:5.019 withBlock:^{
            [db executeNonQuery:@"DROP TABLE message_history_backup;"];
        }];

        //update muc favorites to have the autojoin flag set
        [self updateDB:db withDataLayer:dataLayer toVersion:5.020 withBlock:^{
            [db executeNonQuery:@"UPDATE muc_favorites SET autojoin=1;"];
        }];

        // jid's should be lower only
        [self updateDB:db withDataLayer:dataLayer toVersion:5.021 withBlock:^{
            [db executeNonQuery:@"UPDATE account SET username=LOWER(username), domain=LOWER(domain);"];
            [db executeNonQuery:@"UPDATE activechats SET buddy_name=lower(buddy_name);"];
            [db executeNonQuery:@"UPDATE buddylist SET buddy_name=LOWER(buddy_name);"];
            [db executeNonQuery:@"UPDATE message_history SET buddy_name=LOWER(buddy_name), actual_from=LOWER(actual_from), participant_jid=LOWER(participant_jid);"];
            [db executeNonQuery:@"UPDATE muc_members SET room=LOWER(room);"];
            [db executeNonQuery:@"UPDATE muc_participants SET room=LOWER(room);"];
            [db executeNonQuery:@"UPDATE muc_participants SET room=LOWER(room);"];
            [db executeNonQuery:@"UPDATE signalContactIdentity SET contactName=LOWER(contactName);"];
            [db executeNonQuery:@"UPDATE signalContactSession SET contactName=LOWER(contactName);"];
            [db executeNonQuery:@"UPDATE subscriptionRequests SET buddy_name=LOWER(buddy_name);"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.022 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE subscriptionRequests RENAME TO _subscriptionRequestsTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'subscriptionRequests' ( \
                'account_id' integer NOT NULL, \
                'buddy_name' varchar(255) NOT NULL, \
                FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                PRIMARY KEY('account_id','buddy_name') \
            );"];
            [db executeNonQuery:@"DELETE FROM _subscriptionRequestsTMP WHERE account_id NOT IN (SELECT account_id FROM account)"];
            [db executeNonQuery:@"INSERT INTO subscriptionRequests (account_id, buddy_name) SELECT account_id, buddy_name FROM _subscriptionRequestsTMP;"];
            [db executeNonQuery:@"DROP TABLE _subscriptionRequestsTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.023 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE muc_favorites RENAME TO _muc_favoritesTMP;"];
            [db executeNonQuery:@"CREATE TABLE 'muc_favorites' ( \
                'account_id' INTEGER NOT NULL, \
                'room' VARCHAR(255) NOT NULL, \
                'nick' varchar(255), \
                FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                UNIQUE('room', 'account_id'), \
                PRIMARY KEY('account_id', 'room') \
            );"];
            [db executeNonQuery:@"INSERT INTO muc_favorites (account_id, room, nick) SELECT account_id, room, nick FROM _muc_favoritesTMP;"];
            [db executeNonQuery:@"DROP TABLE _muc_favoritesTMP;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.024 withBlock:^{
            //nicknames should be compared case sensitive --> change collation
            //we don't need to migrate our table data because the db upgrade triggers a xmpp reconnect and this in turn triggers
            //a new muc join which does clear this table anyways
            [db executeNonQuery:@"DROP TABLE muc_participants;"];
            [db executeNonQuery:@"CREATE TABLE 'muc_participants' ( \
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

        [self updateDB:db withDataLayer:dataLayer toVersion:5.026 withBlock:^{
            //new outbox table for sharesheet
            [db executeNonQuery:@"CREATE TABLE 'sharesheet_outbox' ( \
                    'id' INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, \
                    'account_id' INTEGER NOT NULL, \
                    'recipient' VARCHAR(255) NOT NULL, \
                    'type' VARCHAR(32), \
                    'data' VARCHAR(1023), \
                    'comment' VARCHAR(255), \
                    FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                    FOREIGN KEY('account_id', 'recipient') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
            );"];
            [[HelperTools defaultsDB] removeObjectForKey:@"outbox"];
            [[HelperTools defaultsDB] synchronize];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.101 withBlock:^{
            //save the smallest unread id for faster retrieval of unread message count per contact
            //we use -1because all queries using this test for message_history_id > this field, not >=
            [db executeNonQuery:@"ALTER TABLE 'buddylist' ADD COLUMN 'latest_read_message_history_id' INTEGER NOT NULL DEFAULT -1;"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.103 withBlock:^{
            //make sure the latest_read_message_history_id is filled with correct initial values
            [db executeNonQuery:@"UPDATE buddylist AS b SET latest_read_message_history_id=IFNULL((\
                SELECT message_history_id FROM message_history AS h\
                    WHERE h.account_id=b.account_id AND h.buddy_name=b.buddy_name AND unread=1 AND inbound=1\
                    ORDER BY h.message_history_id ASC LIMIT 1\
            )-1, (\
                SELECT message_history_id FROM message_history ORDER BY message_history_id DESC LIMIT 1\
            ));"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.104 withBlock:^{
            //database table for storage of delayed message stanzas during catchup phase (we store this into a database to make sure we don't consume too much memory)
            [db executeNonQuery:@"CREATE TABLE 'delayed_message_stanzas' ( \
                    'id' INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, \
                    'account_id' INTEGER NOT NULL, \
                    'archive_jid' BLOB NOT NULL, \
                    'stanza' VARCHAR(32), \
                    FOREIGN KEY('account_id') REFERENCES 'account'('account_id') ON DELETE CASCADE, \
                    FOREIGN KEY('account_id', 'archive_jid') REFERENCES 'buddylist'('account_id', 'buddy_name') ON DELETE CASCADE \
            );"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.105 withBlock:^{
            [db executeNonQuery:@"ALTER TABLE buddylist ADD COLUMN mentionOnly BOOL DEFAULT FALSE"];
        }];

        [self updateDB:db withDataLayer:dataLayer toVersion:5.106 withBlock:^{
            [db executeNonQuery:@"DROP TABLE signalContactKey;"];
        }];
        
        //remove all cached hashes
        //--> avatar images will be loaded on next non-smacks connect (because of the incoming metadata +notify on full reconnect)
        //and replace the already saved avatar files
        //NOTE: next reconnect is now(!) due to the upgraded db version
        [self updateDB:db withDataLayer:dataLayer toVersion:5.111 withBlock:^{
            [db executeNonQuery:@"UPDATE buddylist SET iconhash='';"];
            [[MLImageManager sharedInstance] removeAllIcons];
        }];
    }];
    NSNumber* newdbversion = [db idReadTransaction:^{
        return [self readDBVersion:db];
    }];
    DDLogInfo(@"Database migrated from old version %@ to version %@", dbversion, newdbversion);
    return ![newdbversion isEqual:dbversion];
}

@end
