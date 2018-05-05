//
//  MLSignalStore.m
//  Monal
//
//  Created by Anurodh Pokharel on 5/3/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "MLSignalStore.h"

@implementation MLSignalStore

/**
 * Returns a copy of the serialized session record corresponding to the
 * provided recipient ID + device ID tuple.
 * or nil if not found.
 */
- (nullable NSData*) sessionRecordForAddress:(SignalAddress*)address
{
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
    return NO;
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
     return nil;
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
    return nil;
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
     return NO;
}

/**
 * Delete a PreKey record from local storage.
 */
- (BOOL) deletePreKeyWithId:(uint32_t)preKeyId
{
     return NO;
}

/**
 * Load a local serialized signed PreKey record.
 */
- (nullable NSData*) loadSignedPreKeyWithId:(uint32_t)signedPreKeyId
{
    return nil;
}

/**
 * Store a local serialized signed PreKey record.
 */
- (BOOL) storeSignedPreKey:(NSData*)signedPreKey signedPreKeyId:(uint32_t)signedPreKeyId
{
     return NO;
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
     return NO;
}

/**
 * Get the local client's identity key pair.
 */
- (SignalIdentityKeyPair*) getIdentityKeyPair;
{
    return nil;
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
    return 1;
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
     return NO;
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
     return NO;
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
    return nil; 
}


@end
