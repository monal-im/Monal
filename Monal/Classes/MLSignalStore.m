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
@property (nonatomic, strong) NSDictionary *signaltmp ;

@property (nonatomic, assign) uint32 deviceid;
@property (nonatomic, assign) NSString *accountId;

@property (nonatomic, strong) SignalIdentityKeyPair *identityKeyPair;
@property (nonatomic, strong) SignalSignedPreKey *signedPreKey;
@property (nonatomic, strong) NSArray *preKeys;
@end

@implementation MLSignalStore

-(id) initWithAccountId:(NSString *) accountId{
    
    NSArray *data= [[DataLayer sharedInstance] executeReader:@"select * from signalIdentity where account_id=?" andArguments:@[accountId]];

    
    NSDictionary *row = [data firstObject];
    
    if(row)
    {
        NSData *idKeyPub = [row objectForKey:@"identityPublicKey"];
        NSData *idKeyPrivate = [row objectForKey:@"identityPrivateKey"];
        
        NSError *error;
        self.identityKeyPair= [[SignalIdentityKeyPair alloc] initWithPublicKey:idKeyPub privateKey:idKeyPrivate error:&error];
        
        if(error)
        {
            NSLog(@"prekey error %@", error);
        }
        
        self.deviceid=[(NSNumber *)[row objectForKey:@"deviceid"] unsignedIntValue];
    }
    
    self.accountId=accountId;
    
    return self; 
}

/**
 * Returns a copy of the serialized session record corresponding to the
 * provided recipient ID + device ID tuple.
 * or nil if not found.
 */
- (nullable NSData*) sessionRecordForAddress:(SignalAddress*)address
{
   // fetch return
    
    return nil;
}

/**
 * Commit to storage the session record for a given
 * recipient ID + device ID tuple.
 *
 * Return YES on success, NO on failure.
 */
- (BOOL) storeSessionRecord:(NSData*)recordData forAddress:(SignalAddress*)address
{
    //save data
    NSDictionary *sess =@{@"name":address.name,
                          @"deviceid":[NSNumber numberWithInt:address.deviceId],
                          @"data":recordData
                          };
    
    [[NSUserDefaults standardUserDefaults] setObject:sess forKey:@"sess"];
    
    return YES;
}

/**
 * Determine whether there is a committed session record for a
 * recipient ID + device ID tuple.
 */
- (BOOL) sessionRecordExistsForAddress:(SignalAddress*)address;
{
     return NO;
}

/**
 * Remove a session record for a recipient ID + device ID tuple.
 */
- (BOOL) deleteSessionRecordForAddress:(SignalAddress*)address
{
     return NO;
}

/**
 * Returns all known devices with active sessions for a recipient
 */
- (NSArray<NSNumber*>*) allDeviceIdsForAddressName:(NSString*)addressName
{
    NSDictionary *dic =  [[NSUserDefaults standardUserDefaults] objectForKey:@"sess"];
    NSNumber *deviceid= [dic objectForKey:@"deviceid"];
    return @[deviceid];
}

/**
 * Remove the session records corresponding to all devices of a recipient ID.
 *
 * @return the number of deleted sessions on success, negative on failure
 */
- (int) deleteAllSessionsForAddressName:(NSString*)addressName
{
    return 0;
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
     return NO;
}

/**
 * Determine whether there is a committed PreKey record matching the
 * provided ID.
 */
- (BOOL) containsPreKeyWithId:(uint32_t)preKeyId;
{
     return YES;
}

/**
 * Delete a PreKey record from local storage.
 */
- (BOOL) deletePreKeyWithId:(uint32_t)preKeyId
{
     return YES;
}

/**
 * Load a local serialized signed PreKey record.
 */
- (nullable NSData*) loadSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
    NSData* toreturn= self.signedPreKey.serializedData;
    return toreturn;
}

/**
 * Store a local serialized signed PreKey record.
 */
- (BOOL) storeSignedPreKey:(NSData*)signedPreKey signedPreKeyId:(uint32_t)signedPreKeyId
{
     return YES;
}

/**
 * Determine whether there is a committed signed PreKey record matching
 * the provided ID.
 */
- (BOOL) containsSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
     return NO;
}

/**
 * Delete a SignedPreKeyRecord from local storage.
 */
- (BOOL) removeSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
    return YES;
}

/**
 * Get the local client's identity key pair.
 */
- (SignalIdentityKeyPair*) getIdentityKeyPair;
{
    return self.identityKeyPair;
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
     return YES;
}

/**
 * Store a serialized sender key record for a given
 * (groupId + senderId + deviceId) tuple.
 */
- (BOOL) storeSenderKey:(NSData*)senderKey address:(SignalAddress*)address groupId:(NSString*)groupId;
{
     return NO;
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
