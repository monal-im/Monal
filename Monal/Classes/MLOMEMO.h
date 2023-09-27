//
//  MLOMEMO.h
//  Monal
//
//  Created by Friedrich Altheide on 21.06.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OmemoState.h"

NS_ASSUME_NONNULL_BEGIN

@class MLSignalStore;
@class SignalAddress;
@class xmpp;
@class XMPPMessage;
@class XMPPIQ;
@class MLXMLNode;

@interface MLOMEMO : NSObject
@property (nonatomic, strong) OmemoState* state;
@property (nonatomic) unsigned long openBundleFetchCnt;
@property (nonatomic) unsigned long closedBundleFetchCnt;

-(MLOMEMO*) initWithAccount:(xmpp*) account;
-(void) activate;

/*
 * encrypting / decrypting messages
 */
-(MLXMLNode* _Nullable) encryptString:(NSString* _Nullable) message toDeviceids:(NSDictionary<NSString*, NSSet<NSNumber*>*>*) contactDeviceMap;
-(void) encryptMessage:(XMPPMessage*) messageNode withMessage:(NSString* _Nullable) message toContact:(NSString*) toContact;
-(NSString* _Nullable) decryptOmemoEnvelope:(MLXMLNode*) envelope forSenderJid:(NSString*) senderJid andReturnErrorString:(BOOL) returnErrorString;
-(NSString* _Nullable) decryptMessage:(XMPPMessage*) messageNode withMucParticipantJid:(NSString* _Nullable) mucParticipantJid;

-(NSSet<NSNumber*>*) knownDevicesForAddressName:(NSString*) addressName;
-(BOOL) isTrustedIdentity:(SignalAddress*)address identityKey:(NSData*)identityKey;
-(void) addIdentityManually:(SignalAddress*) address identityKey:(NSData* _Nonnull) identityKey;
-(void) updateTrust:(BOOL) trust forAddress:(SignalAddress*)address;
-(NSNumber*) getTrustLevel:(SignalAddress*)address identityKey:(NSData*)identityKey;
-(NSData*) getIdentityForAddress:(SignalAddress*) address;
-(BOOL) isSessionBrokenForJid:(NSString*) jid andDeviceId:(NSNumber*) rid;
-(void) deleteDeviceForSource:(NSString*) source andRid:(NSNumber*) rid;

-(void) subscribeAndFetchDevicelistIfNoSessionExistsForJid:(NSString*) buddyJid;
-(void) checkIfSessionIsStillNeeded:(NSString*) buddyJid isMuc:(BOOL) isMuc;
-(NSNumber*) getDeviceId;

-(void) untrustAllDevicesFrom:(NSString*) jid;

//debug button in contactdetails ui
-(void) clearAllSessionsForJid:(NSString*) jid;
@end

NS_ASSUME_NONNULL_END
