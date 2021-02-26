//
//  MLSignalStore.m
//  Monal
//
//  Created by Anurodh Pokharel on 5/3/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLSignalStore.h"
#import "SignalProtocolObjC.h"
#import "DataLayer.h"
#import "MLSQLite.h"

@interface MLSignalStore()
{
    NSString* _dbPath;
}
@property (nonatomic, strong) NSString* accountId;
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

-(id) initWithAccountId:(NSString *) accountId{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* containerUrl = [fileManager containerURLForSecurityApplicationGroupIdentifier:kAppGroup];
    _dbPath = [[containerUrl path] stringByAppendingPathComponent:@"sworim.sqlite"];
    
    self.accountId = accountId;
    NSArray* data = [self.sqliteDatabase executeReader:@"SELECT identityPrivateKey, deviceid, identityPublicKey FROM signalIdentity WHERE account_id=?;" andArguments:@[accountId]];
    NSDictionary* row = [data firstObject];

    if(row)
    {
        self.deviceid = [(NSNumber *)[row objectForKey:@"deviceid"] unsignedIntValue];
        
        NSData* idKeyPub = [row objectForKey:@"identityPublicKey"];
        NSData* idKeyPrivate = [row objectForKey:@"identityPrivateKey"];
        
        NSError* error;
        self.identityKeyPair = [[SignalIdentityKeyPair alloc] initWithPublicKey:idKeyPub privateKey:idKeyPrivate error:nil];
        if(error)
        {
            NSLog(@"prekey error %@", error);
            return self;
        }
        
        self.signedPreKey = [[SignalSignedPreKey alloc] initWithSerializedData:[self loadSignedPreKeyWithId:1] error:&error];
        
        if(error)
        {
            NSLog(@"signed prekey error %@", error);
            return self;
        }
        // remove old keys that should no longer be available
        [self cleanupKeys];
        [self reloadCachedPrekeys];
    }

    return self; 
}

-(void) reloadCachedPrekeys
{
    self.preKeys = [self readPreKeys];
}

-(void) cleanupKeys
{
    // remove old keys that have been remove a long time ago from pubsub
    [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalPreKey WHERE account_id=? AND pubSubRemovalTimestamp IS NOT NULL AND pubSubRemovalTimestamp <= date('now', '-14 day');" andArguments:@[self.accountId]];
    // mark old unused keys to be removed from pubsub
    [self.sqliteDatabase executeNonQuery:@"UPDATE signalPreKey SET pubSubRemovalTimestamp=CURRENT_TIMESTAMP WHERE account_id=? AND keyUsed=0 AND pubSubRemovalTimestamp IS  NULL AND creationTimestamp<= date('now','-14 day');" andArguments:@[self.accountId]];
}

-(NSMutableArray *) readPreKeys
{
    NSArray* keys = [self.sqliteDatabase executeReader:@"SELECT prekeyid, preKey FROM signalPreKey WHERE account_id=? AND keyUsed=0;" andArguments:@[self.accountId]];
    NSMutableArray* array = [[NSMutableArray alloc] initWithCapacity:keys.count];
    
    for (NSDictionary* row in keys)
    {
        SignalPreKey* key = [[SignalPreKey alloc] initWithSerializedData:[row objectForKey:@"preKey"] error:nil];
        [array addObject:key];
    }
    
    return array; 
}

-(int) getHighestPreyKeyId
{
    NSNumber* highestId = [self.sqliteDatabase executeScalar:@"SELECT prekeyid FROM signalPreKey WHERE account_id=? ORDER BY prekeyid DESC LIMIT 1;" andArguments:@[self.accountId]];

    if(highestId==nil) {
        return 0; // Default value -> first preKeyId will be 1
    } else {
        return highestId.intValue;
    }
}

-(int) getPreKeyCount
{
    NSNumber* count = (NSNumber*)[self.sqliteDatabase executeScalar:@"SELECT COUNT(prekeyid) FROM signalPreKey WHERE account_id=? AND pubSubRemovalTimestamp IS NULL AND keyUsed=0;" andArguments:@[self.accountId]];
    return count.intValue;
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
- (nullable NSData*) sessionRecordForAddress:(SignalAddress*)address
{
    NSData *record= (NSData *)[self.sqliteDatabase executeScalar:@"SELECT recordData FROM signalContactSession WHERE account_id=? AND contactName=? AND contactDeviceId=?;" andArguments:@[self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId]]];
    return record;
}

/**
 * Commit to storage the session record for a given
 * recipient ID + device ID tuple.
 *
 * Return YES on success, NO on failure.
 */
- (BOOL) storeSessionRecord:(NSData*)recordData forAddress:(SignalAddress*)address
{
    if([self sessionRecordForAddress:address])
    {
        BOOL success = [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactSession SET recordData=? WHERE account_id=? AND contactName=? AND contactDeviceId=?;" andArguments:@[recordData, self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId]]];
        return success;
    }
    else {
        BOOL success = [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalContactSession (account_id, contactName, contactDeviceId, recordData) VALUES (?, ?, ?, ?);" andArguments:@[self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId], recordData]];
        return success;
    }
}

/**
 * Determine whether there is a committed session record for a
 * recipient ID + device ID tuple.
 */
- (BOOL) sessionRecordExistsForAddress:(SignalAddress*)address;
{
    NSData *preKeyData= [self sessionRecordForAddress:address];
    return preKeyData?YES:NO;
}

/**
 * Remove a session record for a recipient ID + device ID tuple.
 */
- (BOOL) deleteSessionRecordForAddress:(SignalAddress*)address
{
  return  [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactSession WHERE account_id=? AND contactName=? AND contactDeviceId=?;" andArguments:@[self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId]]];
}

/**
 * Returns all known devices with active sessions for a recipient
 */
- (NSArray<NSNumber*>*) allDeviceIdsForAddressName:(NSString*)addressName
{
    NSArray *rows= [self.sqliteDatabase executeReader:@"SELECT DISTINCT contactDeviceId FROM signalContactSession WHERE account_id=? AND contactName=?;" andArguments:@[self.accountId, addressName]];

    NSMutableArray *devices = [[NSMutableArray alloc] initWithCapacity:rows.count];
    
    for(NSDictionary *row in rows)
    {
        NSNumber *number= [row objectForKey:@"contactDeviceId"];
        [devices addObject:number];
    }
    
    return devices;
}

- (NSArray<NSNumber*>*) knownDevicesForAddressName:(NSString*)addressName
{
    if(!addressName) return nil;
    
    NSArray* rows = [self.sqliteDatabase executeReader:@"SELECT DISTINCT contactDeviceId FROM signalContactIdentity WHERE account_id=? AND contactName=? AND removedFromDeviceList IS NULL;" andArguments:@[self.accountId, addressName]];
    
    NSMutableArray *devices = [[NSMutableArray alloc] initWithCapacity:rows.count];
    
    for(NSDictionary *row in rows)
    {
        NSNumber *number= [row objectForKey:@"contactDeviceId"];
        [devices addObject:number];
    }
    
    return devices;
}

/**
 * Remove the session records corresponding to all devices of a recipient ID.
 *
 * @return the number of deleted sessions on success, negative on failure
 */
- (int) deleteAllSessionsForAddressName:(NSString*)addressName
{
    [self.sqliteDatabase beginWriteTransaction];
    NSNumber* count = (NSNumber *) [self.sqliteDatabase executeScalar:@"COUNT * FROM  signalContactSession WHERE account_id=? AND contactName=?;" andArguments:@[self.accountId, addressName]];
    
    [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactSession WHERE account_id=? AND contactName=?;" andArguments:@[self.accountId, addressName]];
    
    [self.sqliteDatabase endWriteTransaction];
    return count.intValue;
}


/**
 * Load a local serialized PreKey record.
 * return nil if not found
 */
- (nullable NSData*) loadPreKeyWithId:(uint32_t)preKeyId;
{
    DDLogDebug(@"Loading prekey %lu", (unsigned long)preKeyId);
    NSData* preKeyData = (NSData *)[self.sqliteDatabase executeScalar:@"SELECT prekey FROM signalPreKey WHERE account_id=? AND prekeyid=? AND keyUsed=0;" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId]]];
    return preKeyData;
}

/**
 * Store a local serialized PreKey record.
 * return YES if storage successful, else NO
 */
- (BOOL) storePreKey:(NSData*)preKey preKeyId:(uint32_t)preKeyId
{
    DDLogDebug(@"Storing prekey %lu", (unsigned long)preKeyId);
    // Only store new preKeys
    NSNumber* preKeyCnt = (NSNumber*)[self.sqliteDatabase executeScalar:@"SELECT count(*) FROM signalPreKey WHERE account_id=? AND prekeyid=? AND preKey=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId], preKey]];
    if(preKeyCnt.intValue > 0)
        return YES;

    BOOL success = [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalPreKey (account_id, prekeyid, preKey) VALUES (?, ?, ?);" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId], preKey]];
    return success;
}

/**
 * Determine whether there is a committed PreKey record matching the
 * provided ID.
 */
- (BOOL) containsPreKeyWithId:(uint32_t)preKeyId;
{
    NSData* prekey = [self loadPreKeyWithId:preKeyId];
    return prekey ? YES : NO;
}

/**
 * Delete a PreKey record from local storage.
 */
- (BOOL) deletePreKeyWithId:(uint32_t)preKeyId
{
    DDLogDebug(@"Marking prekey %lu as deleted", (unsigned long)preKeyId);
    // only mark the key for deletion -> key should be removed from pubSub
    BOOL ret = [self.sqliteDatabase executeNonQuery:@"UPDATE signalPreKey SET pubSubRemovalTimestamp=CURRENT_TIMESTAMP, keyUsed=1 WHERE account_id=? AND prekeyid=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId]]];
    [self reloadCachedPrekeys];
    return ret;
}

/**
 * Load a local serialized signed PreKey record.
 */
- (nullable NSData*) loadSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
    DDLogDebug(@"Loading signed prekey %lu", (unsigned long)signedPreKeyId);
    NSData *key= (NSData *)[self.sqliteDatabase executeScalar:@"SELECT signedPreKey FROM signalSignedPreKey WHERE account_id=? AND signedPreKeyId=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId]]];
    return key;
}

/**
 * Store a local serialized signed PreKey record.
 */
- (BOOL) storeSignedPreKey:(NSData*)signedPreKey signedPreKeyId:(uint32_t)signedPreKeyId
{
    DDLogDebug(@"Storing signed prekey %lu", (unsigned long)signedPreKeyId);
    BOOL success = [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalSignedPreKey (account_id, signedPreKeyId, signedPreKey) VALUES (?, ?, ?) ON CONFLICT(account_id, signedPreKeyId) DO UPDATE SET signedPreKey=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId], signedPreKey, signedPreKey]];
    
    return success;
}

/**
 * Determine whether there is a committed signed PreKey record matching
 * the provided ID.
 */
- (BOOL) containsSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
    NSData* key = (NSData *)[self.sqliteDatabase executeScalar:@"SELECT signedPreKey FROM signalSignedPreKey WHERE account_id=? AND signedPreKeyId=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId]]];
    return key?YES:NO;
}

/**
 * Delete a SignedPreKeyRecord from local storage.
 */
- (BOOL) removeSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
    DDLogDebug(@"Removing signed prekey %lu", (unsigned long)signedPreKeyId);
    return [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalSignedPreKey WHERE account_id=? AND signedPreKeyId=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId]]];
}

/**
 * Get the local client's identity key pair.
 */
- (SignalIdentityKeyPair*) getIdentityKeyPair;
{
    return self.identityKeyPair;
}

-(BOOL) identityPublicKeyExists:(NSData*)publicKey andPrivateKey:(NSData *) privateKey
{
    NSNumber* pubKeyCnt = (NSNumber*)[self.sqliteDatabase executeScalar:@"SELECT COUNT(*) FROM signalIdentity WHERE account_id=? AND deviceid=? AND identityPublicKey=? AND identityPrivateKey=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:self.deviceid], publicKey, privateKey]];
    return pubKeyCnt.boolValue;
}

- (BOOL) storeIdentityPublicKey:(NSData*)publicKey andPrivateKey:(NSData *) privateKey
{
    if([self identityPublicKeyExists:publicKey andPrivateKey:privateKey])
        return YES;

    BOOL success = [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalIdentity (account_id, deviceid, identityPublicKey, identityPrivateKey) values (?, ?, ?, ?);" andArguments:@[self.accountId, [NSNumber numberWithInteger:self.deviceid], publicKey, privateKey]];
    return success;
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
- (BOOL) saveIdentity:(SignalAddress*)address identityKey:(nullable NSData*)identityKey;
{
    [self.sqliteDatabase beginWriteTransaction];
    NSData* dbIdentity= (NSData *)[self.sqliteDatabase executeScalar:@"SELECT IDENTITY FROM signalContactIdentity WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    if(dbIdentity)
    {
        [self.sqliteDatabase endWriteTransaction];
        return YES;
    }
    BOOL success = [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalContactIdentity (account_id, contactName, contactDeviceId, identity, trustLevel) values (?, ?, ?, ?, 1);" andArguments:@[self.accountId,address.name,[NSNumber numberWithInteger:address.deviceId], identityKey]];
    [self.sqliteDatabase endWriteTransaction];
    return success;
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
- (BOOL) isTrustedIdentity:(SignalAddress*)address identityKey:(NSData*)identityKey;
{
    int trustLevel = [self getTrustLevel:address identityKey:identityKey].intValue;
    return (trustLevel == MLOmemoTrusted || trustLevel == MLOmemoToFU);
}

-(NSData *) getIdentityForAddress:(SignalAddress*)address
{
    return (NSData *)[self.sqliteDatabase executeScalar:@"SELECT identity FROM signalContactIdentity WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
}

/*
 * ToFU independent trust update
 * true -> trust
 * false -> don't trust
 * -> after calling updateTrust once ToFU will be over
 */
-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress*)address
{
    [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET trustLevel=? WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[[NSNumber numberWithInt:(trust ? MLOmemoInternalTrusted : MLOmemoInternalNotTrusted)], self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
}

-(void) markDeviceAsDeleted:(SignalAddress*)address
{
    [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET removedFromDeviceList=CURRENT_TIMESTAMP WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
}

-(void) removeDeviceDeletedMark:(SignalAddress*)address
{
    [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET removedFromDeviceList=NULL WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
}

-(void) updateLastSuccessfulDecryptTime:(SignalAddress*)address
{
    [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET lastReceivedMsg=CURRENT_TIMESTAMP WHERE account_id=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
}

-(int) getInternalTrustLevel:(SignalAddress*)address identityKey:(NSData*)identityKey
{
    return ((NSNumber*)[self.sqliteDatabase executeScalar:(@"SELECT trustLevel FROM signalContactIdentity WHERE account_id=? AND contactDeviceId=? AND contactName=? AND identity=?;") andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name, identityKey]]).intValue;
}

-(void) untrustAllDevicesFrom:(NSString*) jid
{
    [self.sqliteDatabase executeNonQuery:@"UPDATE signalContactIdentity SET trustLevel=? WHERE account_id=? AND contactName=?;" andArguments:@[[NSNumber numberWithInt:MLOmemoInternalNotTrusted], self.accountId, jid]];
}

-(NSNumber*) getTrustLevel:(SignalAddress*)address identityKey:(NSData*)identityKey;
{
    return (NSNumber*)[self.sqliteDatabase executeScalar:(@"SELECT \
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
}

/**
 * Store a serialized sender key record for a given
 * (groupId + senderId + deviceId) tuple.
 */
-(BOOL) storeSenderKey:(nonnull NSData*)senderKey address:(nonnull SignalAddress*)address groupId:(nonnull NSString*)groupId;
{
    BOOL success = [self.sqliteDatabase executeNonQuery:@"INSERT INTO signalContactKey (account_id, contactName, contactDeviceId, groupId, senderKey) VALUES (?, ?, ?, ?, ?);" andArguments:@[self.accountId,address.name, [NSNumber numberWithInteger:address.deviceId], groupId,senderKey]];
     return success;
}

/**
 * Returns a copy of the sender key record corresponding to the
 * (groupId + senderId + deviceId) tuple.
 */
- (nullable NSData*) loadSenderKeyForAddress:(SignalAddress*)address groupId:(NSString*)groupId;
{
    NSData* keyData = (NSData *)[self.sqliteDatabase executeScalar:@"SELECT senderKey FROM signalContactKey WHERE account_id=? AND groupId=? AND contactDeviceId=? AND contactName=?;" andArguments:@[self.accountId,groupId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    return keyData;
}

-(void) deleteDeviceforAddress:(SignalAddress*)address
{
     [self.sqliteDatabase executeNonQuery:@"DELETE FROM signalContactIdentity WHERE account_id=? AND contactDeviceId=? AND contactName=?" andArguments:@[self.accountId, [NSNumber numberWithInteger:address.deviceId], address.name]];
 }

@end
