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

@interface MLSignalStore()
@property (nonatomic, strong) NSString *accountId;
@end

@implementation MLSignalStore

-(id) initWithAccountId:(NSString *) accountId{
    
    self.accountId=accountId;
    NSArray *data= [[DataLayer sharedInstance] executeReader:@"select identityPrivateKey, deviceid,identityPublicKey from signalIdentity where account_id=?" andArguments:@[accountId]];
    NSDictionary *row = [data firstObject];
   
    
    if(row)
    {
        
        self.deviceid=[(NSNumber *)[row objectForKey:@"deviceid"] unsignedIntValue];
        
        NSData *idKeyPub = [row objectForKey:@"identityPublicKey"];
        NSData *idKeyPrivate = [row objectForKey:@"identityPrivateKey"];
        
        NSError *error;
        self.identityKeyPair= [[SignalIdentityKeyPair alloc] initWithPublicKey:idKeyPub privateKey:idKeyPrivate error:&error];
      
        if(error)
        {
            NSLog(@"prekey error %@", error);
            return self;
        }
        
        
        self.signedPreKey=[[SignalSignedPreKey alloc] initWithSerializedData:[self loadSignedPreKeyWithId:1] error:&error];
        
        if(error)
        {
            NSLog(@"signed prekey error %@", error);
            return self;
        }
        
        NSArray *keys= [[DataLayer sharedInstance] executeReader:@"select prekeyid, preKey from signalPreKey where account_id=?" andArguments:@[accountId]];
        NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:keys.count];
        
        for (NSDictionary *row in keys)
        {
            SignalPreKey *key = [[SignalPreKey alloc] initWithSerializedData:[row objectForKey:@"preKey"] error:nil];
            [array addObject:key];
        }
        
        self.preKeys=array;
     
    }
 
  
    return self; 
}

-(void) saveValues
{
    [self storeSignedPreKey:self.signedPreKey.serializedData signedPreKeyId:1];
    [self storeIdentityPublicKey:self.identityKeyPair.publicKey andPrivateKey:self.identityKeyPair.privateKey];
    
    for (SignalPreKey *key in self.preKeys)
    {
        [self storePreKey:key.serializedData preKeyId:key.preKeyId];
    }
}

/**
 * Returns a copy of the serialized session record corresponding to the
 * provided recipient ID + device ID tuple.
 * or nil if not found.
 */
- (nullable NSData*) sessionRecordForAddress:(SignalAddress*)address
{
    NSData *record= (NSData *)[[DataLayer sharedInstance] executeScalar:@"select recordData from signalContactSession where account_id=? and contactName=? and contactDeviceId=?" andArguments:@[self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId]]];
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
 
 BOOL success=[[DataLayer sharedInstance] executeNonQuery:@"insert into  signalContactSession (account_id,contactName,contactDeviceId,recordData) values  (?,?,?)" andArguments:@[self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId], recordData]];
    
    return success;
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
  return  [[DataLayer sharedInstance] executeNonQuery:@"delete from signalContactSession where account_id=? and contactName=? and contactDeviceId=?" andArguments:@[self.accountId, address.name, [NSNumber numberWithInteger:address.deviceId]]];
}

/**
 * Returns all known devices with active sessions for a recipient
 */
- (NSArray<NSNumber*>*) allDeviceIdsForAddressName:(NSString*)addressName
{
    NSArray *rows= [[DataLayer sharedInstance] executeReader:@"select contactDeviceId from signalContactSession where account_id=? and contactName=? " andArguments:@[self.accountId, addressName]];

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
    
    NSNumber *count = (NSNumber *) [[DataLayer sharedInstance] executeScalar:@"count * from  signalContactSession where account_id=? and contactName=? " andArguments:@[self.accountId, addressName]];
    
    [[DataLayer sharedInstance] executeNonQuery:@"delete from  signalContactSession where account_id=? and contactName=? " andArguments:@[self.accountId, addressName]];
    
    return count.intValue;
}


/**
 * Load a local serialized PreKey record.
 * return nil if not found
 */
- (nullable NSData*) loadPreKeyWithId:(uint32_t)preKeyId;
{
    NSData *preKeyData= (NSData *)[[DataLayer sharedInstance] executeScalar:@"select prekey from signalPreKey where account_id=? and prekeyid=?" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId]]];
    return preKeyData;
}

/**
 * Store a local serialized PreKey record.
 * return YES if storage successful, else NO
 */
- (BOOL) storePreKey:(NSData*)preKey preKeyId:(uint32_t)preKeyId
{
    BOOL success= [[DataLayer sharedInstance] executeNonQuery:@"insert into  signalPreKey (account_id,prekeyid,preKey) values (?,?,?)" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId], preKey]];
     return success;
}

/**
 * Determine whether there is a committed PreKey record matching the
 * provided ID.
 */
- (BOOL) containsPreKeyWithId:(uint32_t)preKeyId;
{
    NSData *prekey= [self loadPreKeyWithId:preKeyId];
    return prekey?YES:NO;
}

/**
 * Delete a PreKey record from local storage.
 */
- (BOOL) deletePreKeyWithId:(uint32_t)preKeyId
{
    return [[DataLayer sharedInstance] executeNonQuery:@"delete prekey from signalPreKey where account_id=? and prekeyid=?" andArguments:@[self.accountId, [NSNumber numberWithInteger:preKeyId]]];

}

/**
 * Load a local serialized signed PreKey record.
 */
- (nullable NSData*) loadSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
    NSData *key= (NSData *)[[DataLayer sharedInstance] executeScalar:@"select signedPreKey from signalSignedPreKey where account_id=? and signedPreKeyId=?" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId]]];
    return key;
}

/**
 * Store a local serialized signed PreKey record.
 */
- (BOOL) storeSignedPreKey:(NSData*)signedPreKey signedPreKeyId:(uint32_t)signedPreKeyId
{
    BOOL success= [[DataLayer sharedInstance] executeNonQuery:@"insert into  signalSignedPreKey (account_id,signedPreKeyId, signedPreKey) values (?,?,?)" andArguments:@[self.accountId,  [NSNumber numberWithInteger:signedPreKeyId], signedPreKey]];
    
    return success;
}

/**
 * Determine whether there is a committed signed PreKey record matching
 * the provided ID.
 */
- (BOOL) containsSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
    NSData *key= (NSData *)[[DataLayer sharedInstance] executeScalar:@"select signedPreKey from signalSignedPreKey where account_id=? and signedPreKeyId=?" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId]]];
    return key?YES:NO;
}

/**
 * Delete a SignedPreKeyRecord from local storage.
 */
- (BOOL) removeSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
    return [[DataLayer sharedInstance] executeNonQuery:@"delete  from signalSignedPreKey where account_id=? and signedPreKeyId=?" andArguments:@[self.accountId, [NSNumber numberWithInteger:signedPreKeyId]]];
}

/**
 * Get the local client's identity key pair.
 */
- (SignalIdentityKeyPair*) getIdentityKeyPair;
{
    return self.identityKeyPair;
}

- (BOOL) storeIdentityPublicKey:(NSData*)publicKey andPrivateKey:(NSData *) privateKey
{
    BOOL success= [[DataLayer sharedInstance] executeNonQuery:@"insert into  signalIdentity (account_id, deviceid,identityPublicKey, identityPrivateKey) values (?,?,?,?)" andArguments:@[self.accountId, [NSNumber numberWithInteger:self.deviceid], publicKey, privateKey]];
    
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
     return YES;
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
     return YES; //TODO fix logic
}

/**
 * Store a serialized sender key record for a given
 * (groupId + senderId + deviceId) tuple.
 */
- (BOOL) storeSenderKey:(NSData*)senderKey address:(SignalAddress*)address groupId:(NSString*)groupId;
{
    
    BOOL success= [[DataLayer sharedInstance] executeNonQuery:@"select insert into signalContactKey (account_id,contactName,contactDeviceId,groupId,senderKey) values (?,?,?,?,?)" andArguments:@[self.accountId,address.name, [NSNumber numberWithInteger:address.deviceId], groupId,senderKey]];
     return success;
}

/**
 * Returns a copy of the sender key record corresponding to the
 * (groupId + senderId + deviceId) tuple.
 */
- (nullable NSData*) loadSenderKeyForAddress:(SignalAddress*)address groupId:(NSString*)groupId;
{
    NSData *keyData= (NSData *)[[DataLayer sharedInstance] executeScalar:@"select senderKey from signalContactKey where account_id=? and groupId=? and contactDeviceId=? and contactName=?" andArguments:@[self.accountId,groupId, [NSNumber numberWithInteger:address.deviceId], address.name]];
    return keyData;
}


@end
