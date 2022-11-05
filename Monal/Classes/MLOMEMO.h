//
//  MLOMEMO.h
//  Monal
//
//  Created by Friedrich Altheide on 21.06.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MLSignalStore;
@class SignalAddress;
@class xmpp;
@class XMPPMessage;
@class XMPPIQ;

@interface MLOMEMO : NSObject {
    NSLock* signalLock;
}
@property (nonatomic, strong) MLSignalStore* monalSignalStore;
@property (nonatomic) unsigned long openBundleFetchCnt;
@property (nonatomic) unsigned long closedBundleFetchCnt;

-(MLOMEMO*) initWithAccount:(xmpp*) account;

/*
 * handle omemo iq's
 */
-(void) sendOMEMOBundle;
-(void) queryOMEMOBundleFrom:(NSString*) jid andDevice:(NSString*) deviceid;
-(void) sendOMEMODeviceWithForce:(BOOL) force;
-(void) processOMEMODevices:(NSSet<NSNumber*>*) receivedDevices from:(NSString*) source;

/*
 * encrypting / decrypting messages
 */
-(void) encryptMessage:(XMPPMessage*) messageNode withMessage:(NSString* _Nullable) message toContact:(NSString*) toContact;
-(NSString* _Nullable) decryptMessage:(XMPPMessage*) messageNode withMucParticipantJid:(NSString* _Nullable) mucParticipantJid;
-(void) sendKeyTransportElement:(NSString*) jid removeBrokenSessionForRid:(NSNumber* _Nullable) rid;

-(BOOL) knownDevicesForAddressNameExist:(NSString*) addressName;
-(NSArray<NSNumber*>*) knownDevicesForAddressName:(NSString*) addressName;
-(void) deleteDeviceForSource:(NSString*) source andRid:(unsigned int) rid;
-(BOOL) isTrustedIdentity:(SignalAddress*)address identityKey:(NSData*)identityKey;
-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress*)address;
-(NSData*) getIdentityForAddress:(SignalAddress*)address;
-(NSNumber*) getTrustLevel:(SignalAddress*)address identityKey:(NSData*)identityKey;

-(void) queryOMEMODevices:(NSString*) jid;

-(void) subscribeAndFetchDevicelistIfNoSessionExistsForJid:(NSString*) buddyJid;
-(void) checkIfSessionIsStillNeeded:(NSString*) buddyJid isMuc:(BOOL) isMuc;

-(void) sendLocalDevicesIfNeeded;
-(void) untrustAllDevicesFrom:(NSString*)jid;

-(void) clearAllSessionsForJid:(NSString*) jid;
-(void) unsubscribeFromDanglingJids:(NSSet<NSString*>*) danglingJids;
@end

NS_ASSUME_NONNULL_END
