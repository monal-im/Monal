//
//  MLSignalStore.m
//  Monal
//
//  Created by Anurodh Pokharel on 5/3/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLConstants.h"
#import "MLSignalStore.h"
#import "SignalProtocolObjC.h"
#import "DataLayer.h"
#import "MLSQLite.h"

@interface MLSignalStore()
{
    NSString* _dbPath;
}
@property (nonatomic, strong) NSNumber* accountId;
@property (readonly, strong) MLSQLite* sqliteDatabase;
@end

@implementation MLSignalStore

+(void) initialize
{
    //TODO: WE USE THE SAME DATABASE FILE AS THE DataLayer --> this should probably be migrated into the datalayer or use its own sqlite database
    
    //make sure the datalayer has migrated the database file to the app group location first
    [DataLayer initialize];
}

//this is the getter of our readonly "sqliteDatabase" property always returning the thread-local instance of the MLSQLite class
-(MLSQLite*) sqliteDatabase
{
    //always return thread-local instance of sqlite class (this is important for performance!)
    return [MLSQLite sharedInstanceForFile:_dbPath];
}

-(MLSignalStore*) initWithAccountId:(NSNumber*) accountId andAccountJid:(NSString* _Nonnull) accountJid
{
    self = [super init];
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    _dbPath = [[containerUrl path] stringByAppendingPathComponent:@"sworim.sqlite"];
    
    self.accountId = accountId;
    NSArray* data = [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeReader:@"SELECT identityPrivateKey, deviceid, identityPublicKey FROM signalIdentity WHERE account_id=?;" andArguments:@[accountId]];
    }];
    NSDictionary* row = [data firstObject];

    if(row)
    {
        self.deviceid = [(NSNumber *)[row objectForKey:@"deviceid"] unsignedIntValue];
        self.accountJid = accountJid;
        
        NSData* idKeyPub = [row objectForKey:@"identityPublicKey"];
        NSData* idKeyPrivate = [row objectForKey:@"identityPrivateKey"];
        
        NSError* error;
        self.identityKeyPair = [[SignalIdentityKeyPair alloc] initWithPublicKey:idKeyPub privateKey:idKeyPrivate error:nil];
        if(error)
        {
            DDLogError(@"prekey error %@", error);
            return self;
        }
        
        self.signedPreKey = [[SignalSignedPreKey alloc] initWithSerializedData:[self loadSignedPreKeyWithId:1] error:&error];
        if(error)
        {
            DDLogError(@"signed prekey error %@", error);
            return self;
        }
        // remove old keys that should no longer be available
        [self cleanupKeys];
        [self reloadCachedPrekeys];
    }
    else
        self.deviceid = 0;

    return self; 
}

-(void) reloadCachedPrekeys
{
    self.preKeys = [self readPreKeys];
}

-(void) cleanupKeys
{
    [self.sqliteDatabase voidWriteTransaction:^{
        // remove old keys that have been remove a long time ago from pubsub
        [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalPreKey WHERE account_id=? AND pubSubRemovalTimestamp IS NOT NULL AND pubSubRemovalTimestamp <= date('now', '-14 day');" andArguments:@[self.accountId]];
        // mark old unused keys to be removed from pubsub
        [self.sqliteDatabase executeNonQuery:@"UPDATE signalPreKey SET pubSubRemovalTimestamp=CURRENT_TIMESTAMP WHERE account_id=? AND keyUsed=0 AND pubSubRemovalTimestamp IS  NULL AND creationTimestamp<= date('now','-14 day');" andArguments:@[self.accountId]];
    }];
}

-(NSMutableArray<SignalPreKey*>*) readPreKeys
{
    NSArray* keys = [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeReader:@"SELECT prekeyid, preKey FROM signalPreKey WHERE account_id=? AND keyUsed=0;" andArguments:@[self.accountId]];
    }];
    
    NSMutableArray<SignalPreKey*>* array = [[NSMutableArray alloc] initWithCapacity:keys.count];
    for (NSDictionary* row in keys)
    {
        SignalPreKey* key = [[SignalPreKey alloc] initWithSerializedData:[row objectForKey:@"preKey"] error:nil];
        [array addObject:key];
    }
    return array; 
}

-(int) getHighestPreyKeyId
{
    NSNumber* highestId = [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:@"SELECT prekeyid FROM signalPreKey WHERE account_id=? ORDER BY prekeyid DESC LIMIT 1;" andArguments:@[self.accountId]];
    }];

    if(highestId == nil) {
        return 0; // Default value -> first preKeyId will be 1
    } else {
        return highestId.intValue;
    }
}

-(unsigned int) getPreKeyCount
{
    NSNumber* count = [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:@"SELECT COUNT(prekeyid) FROM signalPreKey WHERE account_id=? AND pubSubRemovalTimestamp IS NULL AND keyUsed=0;" andArguments:@[self.accountId]];
    }];
    return count.unsignedIntValue;
}

-(void) saveValues
{
    [self storeSignedPreKey:self.signedPreKey.serializedData signedPreKeyId:1];
    [self storeIdentityPublicKey:self.identityKeyPair.publicKey andPrivateKey:self.identityKeyPair.privateKey];
    
    for (SignalPreKey *key in self.preKeys)
    {
        [self storePreKey:key.serializedData preKeyId:key.preKeyId];
    }
    [self reloadCachedPrekeys];
}

/**
 * Returns a copy of the serialized session record corresponding to the
 * provided recipient ID + device ID tuple.
 * or nil if not found.
 */
- (NSData* _Nullable) sessionRecordForAddress:(SignalAddress*) address
{
    return [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:@"SELECT recordData FROM signalContactSession WHERE account_id=? AND contactName=? AND contactDeviceId=?;" andArguments:@[self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId]]];
    }];
}

/**
 * Commit to storage the session record for a given
 * recipient ID + device ID tuple.
 *
 * Return YES on success, NO on failure.
 */
-(BOOL) storeSessionRecord:(NSData*) recordData forAddress:(SignalAddress*) address
{
    return [self.sqliteDatabase boolWriteTransaction:^{
        if([self sessionRecordForAddress:address])
            return [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactSession SET recordData=? WHERE account_id=? AND contactName=? AND contactDeviceId=?;" andArguments:@[recordData, self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId]]];
        else
            return [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalContactSession (account_id, contactName, contactDeviceId, recordData) VALUES (?, ?, ?, ?);" andArguments:@[self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId], recordData]];
    }];
}

/**
 * Determine whether there is a committed session record for a
 * recipient ID + device ID tuple.
 */
- (BOOL) sessionRecordExistsForAddress:(SignalAddress*) address;
{
    NSData* preKeyData = [self sessionRecordForAddress:address];
    return preKeyData ? YES : NO;
}

/**
 * Remove a session record for a recipient ID + device ID tuple.
 */
- (BOOL) deleteSessionRecordForAddress:(SignalAddress*) address
{
    return [self.sqliteDatabase boolWriteTransaction:^{
        return [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactSession WHERE account_id=? AND contactName=? AND contactDeviceId=?;" andArguments:@[self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId]]];
    }];
}

/**
 * Returns all known devices with active sessions for a recipient
 */
- (NSArray<NSNumber*>*) allDeviceIdsForAddressName:(NSString*) jid
{
    return [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalarReader:@"SELECT DISTINCT contactDeviceId FROM signalContactSession WHERE account_id=? AND contactName=?;" andArguments:@[self.accountId, jid]];
    }];
}

-(NSArray<NSNumber*>*) knownDevicesForAddressName:(NSString*) jid
{
    if(!jid)
        return nil;
    
    return [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalarReader:@"SELECT DISTINCT contactDeviceId FROM signalContactIdentity WHERE account_id=? AND contactName=? AND removedFromDeviceList IS NULL;" andArguments:@[self.accountId, jid]];
    }];
}

-(NSArray<NSNumber*>*) knownDevicesWithValidSessionEntryForName:(NSString*) addrName
{
    if(!addrName)
        return nil;

    return [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalarReader:@"SELECT DISTINCT sci.contactDeviceId FROM signalContactIdentity as sci INNER JOIN signalContactSession as scs ON sci.account_id=scs.account_id AND sci.contactName=scs.contactName AND sci.contactDeviceId=scs.contactDeviceId WHERE sci.account_id=? AND sci.contactName=? AND sci.removedFromDeviceList IS NULL AND sci.brokenSession=false;" andArguments:@[self.accountId, addrName]];
    }];
}

/**
 * Remove the session records corresponding to all devices of a recipient ID.
 *
 * @return the number of deleted sessions on success, negative on failure
 */
-(int) deleteAllSessionsForAddressName:(NSString*) addressName
{
    return [[self.sqliteDatabase idWriteTransaction:^{
        NSNumber* count = (NSNumber*) [self.sqliteDatabase executeScalar:@"COUNT * FROM  signalContactSession WHERE account_id=? AND contactName=?;" andArguments:@[self.accountId, addressName]];
        [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactSession WHERE account_id=? AND contactName=?;" andArguments:@[self.accountId, addressName]];
        return count;
    }] intValue];
}

/**
 * Load a local serialized PreKey record.
 * return nil if not found
 */
- (nullable NSData*) loadPreKeyWithId:(uint32_t) preKeyId;
{
    DDLogDebug(@"Loading prekey %lu", (unsigned long)preKeyId);
    return [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:@"SELECT prekey FROM signalPreKey WHERE account_id=? AND prekeyid=? AND keyUsed=0;" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId]]];
    }];
}

/**
 * Store a local serialized PreKey record.
 * return YES if storage successful, else NO
 */
-(BOOL) storePreKey:(NSData*) preKey preKeyId:(uint32_t) preKeyId
{
    DDLogDebug(@"Storing prekey %lu", (unsigned long)preKeyId);
    return [self.sqliteDatabase boolWriteTransaction:^{
        // Only store new preKeys
        NSNumber* preKeyCnt = [self.sqliteDatabase executeScalar:@"SELECT count(*) FROM signalPreKey WHERE account_id=? AND prekeyid=? AND preKey=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId], preKey]];
        if(preKeyCnt.intValue > 0)
            return YES;
        return [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalPreKey (account_id, prekeyid, preKey) VALUES (?, ?, ?);" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId], preKey]];
    }];
}

/**
 * Determine whether there is a committed PreKey record matching the
 * provided ID.
 */
-(BOOL) containsPreKeyWithId:(uint32_t) preKeyId;
{
    NSData* prekey = [self loadPreKeyWithId:preKeyId];
    return prekey ? YES : NO;
}

/**
 * Delete a PreKey record from local storage.
 */
-(BOOL) deletePreKeyWithId:(uint32_t) preKeyId
{
    DDLogDebug(@"Marking prekey %lu as deleted", (unsigned long)preKeyId);
    // only mark the key for deletion -> key should be removed from pubSub
    return [self.sqliteDatabase boolWriteTransaction:^{
        BOOL ret = [self.sqliteDatabase executeNonQuery:@"UPDATE signalPreKey SET pubSubRemovalTimestamp=CURRENT_TIMESTAMP, keyUsed=1 WHERE account_id=? AND prekeyid=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId]]];
        [self reloadCachedPrekeys];
        return ret;
    }];
}

/**
 * Load a local serialized signed PreKey record.
 */
-(nullable NSData*) loadSignedPreKeyWithId:(uint32_t) signedPreKeyId
{
    DDLogDebug(@"Loading signed prekey %lu", (unsigned long)signedPreKeyId);
    return [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:@"SELECT signedPreKey FROM signalSignedPreKey WHERE account_id=? AND signedPreKeyId=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId]]];
    }];
}

/**
 * Store a local serialized signed PreKey record.
 */
- (BOOL) storeSignedPreKey:(NSData*) signedPreKey signedPreKeyId:(uint32_t) signedPreKeyId
{
    DDLogDebug(@"Storing signed prekey %lu", (unsigned long)signedPreKeyId);
    return [self.sqliteDatabase boolWriteTransaction:^{
        return [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalSignedPreKey (account_id, signedPreKeyId, signedPreKey) VALUES (?, ?, ?) ON CONFLICT(account_id, signedPreKeyId) DO UPDATE SET signedPreKey=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId], signedPreKey, signedPreKey]];
    }];
}

/**
 * Determine whether there is a committed signed PreKey record matching
 * the provided ID.
 */
- (BOOL) containsSignedPreKeyWithId:(uint32_t) signedPreKeyId
{
    return [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:@"SELECT signedPreKey FROM signalSignedPreKey WHERE account_id=? AND signedPreKeyId=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId]]];
    }] ? YES : NO;
}

/**
 * Delete a SignedPreKeyRecord from local storage.
 */
- (BOOL) removeSignedPreKeyWithId:(uint32_t) signedPreKeyId
{
    DDLogDebug(@"Removing signed prekey %lu", (unsigned long)signedPreKeyId);
    return [self.sqliteDatabase boolWriteTransaction:^{
        return [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalSignedPreKey WHERE account_id=? AND signedPreKeyId=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId]]];
    }];
}

/**
 * Get the local client's identity key pair.
 */
-(SignalIdentityKeyPair*) getIdentityKeyPair;
{
    return self.identityKeyPair;
}

-(BOOL) identityPublicKeyExists:(NSData*) publicKey andPrivateKey:(NSData *) privateKey
{
    return [[self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:@"SELECT COUNT(*) FROM signalIdentity WHERE account_id=? AND deviceid=? AND identityPublicKey=? AND identityPrivateKey=?;" andArguments:@[self.accountId, [NSNumber numberWithUnsignedInt:self.deviceid], publicKey, privateKey]];
    }] boolValue];
}

- (BOOL) storeIdentityPublicKey:(NSData*) publicKey andPrivateKey:(NSData*) privateKey
{
    return [self.sqliteDatabase boolWriteTransaction:^{
        if([self identityPublicKeyExists:publicKey andPrivateKey:privateKey])
            return YES;

        return [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalIdentity (account_id, deviceid, identityPublicKey, identityPrivateKey) values (?, ?, ?, ?);" andArguments:@[self.accountId, [NSNumber numberWithInteger:self.deviceid], publicKey, privateKey]];
    }];
}


/**
 * Return the local client's registration ID.
 *
 * Clients should maintain a registration ID, a random number
 * between 1 and 16380 that's generated once at install time.
 *
 * return negative on failure
 */
- (uint32_t) getLocalRegistrationId;
{
    return self.deviceid;
}

/**
 * Save a remote client's identity key
 * <p>
 * Store a remote client's identity key as trusted.
 * The value of key_data may be null. In this case remove the key data
 * from the identity store, but retain any metadata that may be kept
 * alongside it.
 */
- (BOOL) saveIdentity:(SignalAddress*) address identityKey:(nullable NSData*) identityKey;
{
    return [self.sqliteDatabase boolWriteTransaction:^{
        NSData* dbIdentity= (NSData *)[self.sqliteDatabase executeScalar:@"SELECT IDENTITY FROM signalContactIdentity WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
        if(dbIdentity)
            return YES;
        // if at least one fingerprint isn't TOFU new fingerprints shouldn't be trusted
        // if all fingerprints are TOFU -> trust new ones with TOFU as well
        return [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalContactIdentity \
            (account_id, contactName, contactDeviceId, identity, trustLevel) \
            VALUES (?, ?, ?, ?, \
                (SELECT CASE \
                    WHEN COUNT(contactDeviceId) == 0 THEN 1 \
                    ELSE 0 \
                END \
                FROM signalContactIdentity \
                WHERE \
                    account_id=? \
                    AND contactName=? \
                    AND trustLevel!=1 \
                ) \
            );" andArguments:@[self.accountId,address.name, [NSNumber numberWithInteger:address.deviceId], identityKey, self.accountId, address.name]];
    }];
}

/**
 * Verify a remote client's identity key.
 *
 * Determine whether a remote client's identity is trusted.  Convention is
 * that the TextSecure protocol is 'trust on first use.'  This means that
 * an identity key is considered 'trusted' if there is no entry for the recipient
 * in the local store, or if it matches the saved key for a recipient in the local
 * store.  Only if it mismatches an entry in the local store is it considered
 * 'untrusted.'
 */
-(BOOL) isTrustedIdentity:(SignalAddress*) address identityKey:(NSData*) identityKey;
{
    int trustLevel = [self getTrustLevel:address identityKey:identityKey].intValue;
    return (trustLevel == MLOmemoTrusted || trustLevel == MLOmemoToFU);
}

-(NSData*) getIdentityForAddress:(SignalAddress*) address
{
    return [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:@"SELECT identity FROM signalContactIdentity WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    }];
}

/*
 * ToFU independent trust update
 * true -> trust
 * false -> don't trust
 * -> after calling updateTrust once ToFU will be over
 */
-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress*) address
{
    [self.sqliteDatabase voidWriteTransaction:^{
        [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET trustLevel=? WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[[NSNumber numberWithInt:(trust ? MLOmemoInternalTrusted : MLOmemoInternalNotTrusted)], self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    }];
}

-(void) markDeviceAsDeleted:(SignalAddress*) address
{
    [self.sqliteDatabase voidWriteTransaction:^{
        [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET removedFromDeviceList=CURRENT_TIMESTAMP WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    }];
}

-(void) removeDeviceDeletedMark:(SignalAddress*) address
{
    [self.sqliteDatabase voidWriteTransaction:^{
        [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET removedFromDeviceList=NULL WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    }];
}

/*
 * update lastReceivedMsg to CURRENT_TIMESTAMP
 * reset brokenSession to faöse
 */
-(void) updateLastSuccessfulDecryptTime:(SignalAddress*) address
{
    [self.sqliteDatabase voidWriteTransaction:^{
        [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET lastReceivedMsg=CURRENT_TIMESTAMP, brokenSession=false WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    }];
}

-(void) markSessionAsBroken:(SignalAddress*) address
{
    [self.sqliteDatabase voidWriteTransaction:^{
        [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET brokenSession=true WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    }];
}

-(void) markSessionAsFunctional:(SignalAddress*) address
{
    [self.sqliteDatabase voidWriteTransaction:^{
        [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET brokenSession=false WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    }];
}

-(BOOL) isSessionBrokenForJid:(NSString*) jid andDeviceId:(NSNumber*) deviceId
{
    return [self.sqliteDatabase boolReadTransaction:^{
        return [[self.sqliteDatabase executeScalar:@"SELECT brokenSession FROM signalContactIdentity WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, deviceId, jid]] boolValue];
    }];
}

-(int) getInternalTrustLevel:(SignalAddress*) address identityKey:(NSData*) identityKey
{
    return [[self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:(@"SELECT trustLevel FROM signalContactIdentity WHERE account_id=? AND contactDeviceId=? AND contactName=? AND identity=?;") andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name, identityKey]];
    }] intValue];
}

-(void) untrustAllDevicesFrom:(NSString*) jid
{
    if([jid isEqualToString:self.accountJid] == NO)
    {
        // untrust all devices
        [self.sqliteDatabase voidWriteTransaction:^{
            [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET trustLevel=? WHERE account_id=? AND contactName=?;" andArguments:@[[NSNumber numberWithInt:MLOmemoInternalNotTrusted], self.accountId, jid]];
        }];
    }
    else
    {
        // untrust all of our own devices except our own device id
        [self.sqliteDatabase voidWriteTransaction:^{
            [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET trustLevel=? WHERE account_id=? AND contactName=? AND contactDeviceId!=?;" andArguments:@[[NSNumber numberWithInt:MLOmemoInternalNotTrusted], self.accountId, jid, [NSNumber numberWithUnsignedInt:self.deviceid]]];
        }];
    }
}

-(NSNumber*) getTrustLevel:(SignalAddress*) address identityKey:(NSData*) identityKey
{
    return [self.sqliteDatabase idReadTransaction:^{
        return [self.sqliteDatabase executeScalar:(@"SELECT \
                CASE \
                    WHEN (trustLevel=0) THEN 0 \
                    WHEN (trustLevel=1) THEN 100 \
                    WHEN (COUNT(*)=0) THEN 100 \
                    WHEN (trustLevel=2 AND removedFromDeviceList IS NULL AND (lastReceivedMsg IS NULL OR lastReceivedMsg >= date('now', '-90 day'))) THEN 200 \
                    WHEN (trustLevel=2 AND removedFromDeviceList IS NOT NULL) THEN 201 \
                    WHEN (trustLevel=2 AND removedFromDeviceList IS NULL AND (lastReceivedMsg < date('now', '-90 day'))) THEN 202 \
                    ELSE 0 \
                END \
                FROM signalContactIdentity \
                WHERE account_id=? AND contactDeviceId=? AND contactName=? AND identity=?; \
                ") andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name, identityKey]];
    }];
}

-(void) deleteDeviceforAddress:(SignalAddress*) address
{
    [self.sqliteDatabase voidWriteTransaction:^{
        [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactIdentity WHERE account_id=? AND contactDeviceId=? AND contactName=?" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    }];
 }

// MUC session management

// return true if we found at least one fingerprint for the given buddyJid
-(BOOL) sessionsExistForBuddy:(NSString*) buddyJid
{
    return [self.sqliteDatabase boolWriteTransaction:^{
        NSNumber* contactDevicesExist = [self.sqliteDatabase executeScalar:@"SELECT COUNT(contactDeviceId) FROM signalContactIdentity WHERE account_id=? AND contactName=?;" andArguments:@[self.accountId, buddyJid]];
        return (BOOL)(contactDevicesExist.intValue > 0);
    }];
}

// delete the fingerprints and session for the given buddyJid if the jid is neither a 1:1 buddy nor a group member
-(BOOL) checkIfSessionIsStillNeeded:(NSString*) buddyJid
{
    return [self.sqliteDatabase boolWriteTransaction:^{
        // delete fingerprints from buddyJid if the buddyJid is neither a buddy, a self chat, nor a group member
        NSNumber* buddyJidCnt = [self.sqliteDatabase executeScalar:@"SELECT \
                (bCnt.buddyListCnt + mucCnt.roomCnt + accountCnt) \
            FROM \
                ( \
                    SELECT \
                        COUNT(buddy_name) AS buddyListCnt \
                    FROM buddylist \
                    WHERE \
                        account_id=? \
                        AND buddy_name=? \
                        AND Muc=0 \
                ) AS bCnt, \
                ( \
                    SELECT \
                        COUNT(m.room) AS roomCnt \
                    FROM muc_members AS m \
                    INNER JOIN buddylist AS b \
                    ON m.account_id = b.account_id \
                    AND b.buddy_name = m.member_jid \
                    WHERE \
                        b.account_id=? \
                        AND m.member_jid=? \
                        AND b.Muc=1 \
                        AND b.muc_type='group' \
                ) AS mucCnt, \
                ( \
                    SELECT \
                        COUNT(account_id) AS accountCnt \
                    FROM account \
                    WHERE \
                        (username || '@' || domain) = ? \
                        AND account_id = ? \
                ) AS accountCnt" andArguments:@[self.accountId, buddyJid, self.accountId, buddyJid, self.accountId, buddyJid]];

        BOOL buddyStillNeeded = buddyJidCnt.intValue > 0;
        if(buddyStillNeeded == NO)
        {
            [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactIdentity \
                WHERE \
                    account_id=? \
                    AND contactName=? \
             " andArguments:@[self.accountId, buddyJid]];
            [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactSession \
                WHERE \
                    account_id=? \
                    AND contactName=? \
             " andArguments:@[self.accountId, buddyJid]];
        }
        return buddyStillNeeded;
    }];
}

// delete all fingerprints and sessions from contacts that are neither a buddy nor a group member
// return jids of dangling sessions
-(NSSet<NSString*>*) removeDanglingMucSessions
{
    return [self.sqliteDatabase idWriteTransaction:^{
        // create a list of all sessions
        NSArray<NSString*>* jidsWithSession = [self.sqliteDatabase executeScalarReader:@"SELECT DISTINCT contactName \
                FROM signalContactIdentity \
                WHERE \
                account_id = ? \
        " andArguments:@[self.accountId]];
        NSMutableSet<NSString*>* danglingJids = [[NSMutableSet alloc] init];
        for(NSString* jid in jidsWithSession) {
            // check if the session is still needed
            if([self checkIfSessionIsStillNeeded:jid] == NO) {
                [danglingJids addObject:jid];
                // delete old session
                [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactIdentity \
                    WHERE \
                        account_id = ? \
                        AND contactName = ? \
                " andArguments:@[self.accountId, jid]];
                [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactSession \
                    WHERE \
                        account_id = ? \
                        AND contactName = ? \
                " andArguments:@[self.accountId, jid]];
            }
        }
        return danglingJids;
    }];
}

/**
 * Store a serialized sender key record for a given
 * (groupId + senderId + deviceId) tuple.
 */
-(BOOL) storeSenderKey:(nonnull NSData*) senderKey address:(nonnull SignalAddress*) address groupId:(nonnull NSString*) groupId;
{
    return false;
}

/**
 * Returns a copy of the sender key record corresponding to the
 * (groupId + senderId + deviceId) tuple.
 */
- (nullable NSData*) loadSenderKeyForAddress:(SignalAddress*) address groupId:(NSString*) groupId;
{
    return nil;
}

@end
