//
//  SignalPreKeyStore.h
//  SignalProtocol-ObjC
//
//  Created by Chris Ballinger on 6/27/16.
//
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN
@protocol SignalPreKeyStore <NSObject>

@required

/**
 * Load a local serialized PreKey record.
 * return nil if not found
 */
- (nullable NSData*) loadPreKeyWithId:(uint32_t)preKeyId;

/**
 * Store a local serialized PreKey record.
 * return YES if storage successful, else NO
 */
- (BOOL) storePreKey:(NSData*)preKey preKeyId:(uint32_t)preKeyId;

/**
 * Determine whether there is a committed PreKey record matching the
 * provided ID.
 */
- (BOOL) containsPreKeyWithId:(uint32_t)preKeyId;

/**
 * Delete a PreKey record from local storage.
 */
- (BOOL) deletePreKeyWithId:(uint32_t)preKeyId;

@end
NS_ASSUME_NONNULL_END