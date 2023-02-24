//
//  MLSignalStore.h
//  Monal
//
//  Created by Anurodh Pokharel on 5/3/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
@import SignalProtocolObjC;

#define MLOmemoInternalNotTrusted 0
#define MLOmemoInternalToFU 1
#define MLOmemoInternalTrusted 2

#define MLOmemoNotTrusted 0
#define MLOmemoToFU 100
#define MLOmemoToFUButRemoved 101
#define MLOmemoToFUButNoMsgSeenInTime 102
#define MLOmemoTrusted 200
#define MLOmemoTrustedButRemoved 201
#define MLOmemoTrustedButNoMsgSeenInTime 202

@interface MLSignalStore : NSObject <SignalStore>
@property (nonatomic, assign) u_int32_t deviceid;
@property (nonatomic, assign) NSString* _Nonnull accountJid;
@property (nonatomic, strong) SignalIdentityKeyPair* _Nullable identityKeyPair;
@property (nonatomic, strong) SignalSignedPreKey* _Nullable signedPreKey;
@property (nonatomic, strong) NSArray<SignalPreKey*>* _Nullable preKeys;

-(MLSignalStore* _Nonnull) initWithAccountId:(NSNumber* _Nonnull) accountId andAccountJid:(NSString* _Nonnull) accountJid;
-(void) saveValues;

-(NSData* _Nullable) getIdentityForAddress:(SignalAddress* _Nonnull) address;
-(BOOL) saveIdentity:(SignalAddress* _Nonnull) address identityKey:(NSData* _Nullable) identityKey;
/**
 all non deleted devices (even those without sessions or a broken session)
 */
-(NSArray<NSNumber*>* _Nullable) knownDevicesForAddressName:(NSString* _Nullable) addressName;
/**
 all non deleted devices with a valid (non broken) session
 */
-(NSArray<NSNumber*>* _Nonnull) knownDevicesWithValidSession:(NSString* _Nonnull) jid;
/**
 * all non deleted devices with a broken sessions where a bundle fetch is advised
 */
-(NSArray<NSNumber*>* _Nonnull) knownDevicesWithPendingBrokenSessionHandling:(NSString* _Nonnull) jid;

-(NSMutableArray<SignalPreKey*>* _Nonnull) readPreKeys;

-(void) deleteDeviceforAddress:(SignalAddress* _Nonnull) address;

-(void) markDeviceAsDeleted:(SignalAddress* _Nonnull) address;
-(void) removeDeviceDeletedMark:(SignalAddress* _Nonnull) address;
-(void) updateLastSuccessfulDecryptTime:(SignalAddress* _Nonnull) address;
-(void) markSessionAsBroken:(SignalAddress* _Nonnull) address;
-(void) markBundleAsFixed:(SignalAddress* _Nonnull) address;
-(BOOL) isSessionBrokenForJid:(NSString* _Nonnull) jid andDeviceId:(NSNumber* _Nonnull) deviceId;
-(void) markBundleAsBroken:(SignalAddress* _Nonnull) address;

// MUC session management
-(BOOL) sessionsExistForBuddy:(NSString* _Nonnull) buddyJid;
-(BOOL) checkIfSessionIsStillNeeded:(NSString* _Nonnull) buddyJid;
-(NSSet<NSString*>* _Nonnull) removeDanglingMucSessions;

-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress* _Nonnull) address;
-(int) getInternalTrustLevel:(SignalAddress* _Nonnull) address identityKey:(NSData* _Nonnull) identityKey;
-(void) untrustAllDevicesFrom:(NSString* _Nonnull) jid;
-(NSNumber* _Nonnull) getTrustLevel:(SignalAddress* _Nonnull) address identityKey:(NSData* _Nonnull) identityKey;

-(int) getHighestPreyKeyId;
-(unsigned int) getPreKeyCount;

-(void) cleanupKeys;
-(void) reloadCachedPrekeys;
@end
