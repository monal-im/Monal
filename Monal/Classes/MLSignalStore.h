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
#define MLOmemoTrusted 200
#define MLOmemoTrustedButRemoved 201
#define MLOmemoTrustedButNoMsgSeenInTime 202

@interface MLSignalStore : NSObject <SignalStore>
@property (nonatomic, assign) u_int32_t deviceid;
@property (nonatomic, strong) SignalIdentityKeyPair* identityKeyPair;
@property (nonatomic, strong) SignalSignedPreKey* signedPreKey;
@property (nonatomic, strong) NSArray<SignalPreKey*>* preKeys;

-(MLSignalStore*) initWithAccountId:(NSString *) accountId;
-(void) saveValues;

-(NSData*) getIdentityForAddress:(SignalAddress*) ddress;
/**
 all devices even those without sessions
 */
-(NSArray<NSNumber*>*) knownDevicesForAddressName:(NSString*) addressName;
-(NSArray<NSNumber*>*) knownDevicesWithValidSessionEntryForName:(NSString*) addrName;
-(NSMutableArray<SignalPreKey*>*) readPreKeys;

-(void) deleteDeviceforAddress:(SignalAddress*) address;

-(void) markDeviceAsDeleted:(SignalAddress*) address;
-(void) removeDeviceDeletedMark:(SignalAddress*) address;
-(void) updateLastSuccessfulDecryptTime:(SignalAddress*) address;
-(void) markSessionAsBroken:(SignalAddress*) address;
-(BOOL) isSessionBrokenForJid:(NSString*) jid andDeviceId:(NSNumber*) deviceId;

-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress*) address;
-(int) getInternalTrustLevel:(SignalAddress*) address identityKey:(NSData*) identityKey;
-(void) untrustAllDevicesFrom:(NSString*) jid;
-(NSNumber*) getTrustLevel:(SignalAddress*) address identityKey:(NSData*) identityKey;

-(int) getHighestPreyKeyId;
-(int) getPreKeyCount;


@end
