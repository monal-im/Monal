//
//  XMPPIQ.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "XMPPStanza.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString* const kiqGetType;
FOUNDATION_EXPORT NSString* const kiqSetType;
FOUNDATION_EXPORT NSString* const kiqResultType;
FOUNDATION_EXPORT NSString* const kiqErrorType;

@interface XMPPIQ : XMPPStanza

-(id) initWithType:(NSString*) iqType;
-(id) initWithType:(NSString*) iqType to:(NSString*) to;
-(id) initAsResponseTo:(XMPPIQ*) iq;
-(id) initAsErrorTo:(XMPPIQ*) iq;

-(void) setRegisterOnAppserverWithToken:(NSString*) token;
-(void) setUnregisterOnAppserver;
-(void) setPushEnableWithNode:(NSString*) node onAppserver:(NSString*) jid;
#ifndef IS_ALPHA
-(void) setPushEnableWithNode:(NSString*) node andSecret:(NSString*) secret onAppserver:(NSString*) jid;
#endif
-(void) setPushDisable:(NSString*) node;

/**
 Makes an iq to bind with a resouce. Passing nil will set no resource.
 */
-(void) setBindWithResource:(NSString*) resource;

/**
 set to attribute
 */
-(void) setiqTo:(NSString*) to;

/**
 makes iq of ping type
 */
-(void) setPing;

-(void) setPurgeOfflineStorage;

/**
 gets MAM prefernces
 */
-(void) mamArchivePref;

/*
 updates MAM pref
 @param pref can only be aways, never or roster
 */
-(void) updateMamArchivePrefDefault:(NSString *) pref;

-(void) setMAMQueryLatestMessagesForJid:(NSString* _Nullable) jid before:(NSString* _Nullable) uid;
-(void) setMAMQueryAfter:(NSString*) uid;
-(void) setCompleteMAMQuery;
-(void) setMAMQueryForLatestId;

-(void) setMucListQueryFor:(NSString*) listType;

#pragma mark disco

/**
 makes a disco info response for the server.
 @param node param passed is the xmpp node attribute that came in with the iq get
 */
-(void) setDiscoInfoWithFeatures:(NSSet*) features identity:(MLXMLNode*) identity andNode:(NSString*) node;

/**
 sets up a disco info query node
 */
-(void) setDiscoInfoNode;

/**
 sets up a disco info query node
 */
-(void) setDiscoItemNode;

#pragma mark roster

/**
gets Entity SoftWare Version
 */
-(void) getEntitySoftWareVersionTo:(NSString*) to;

/**
removes a contact from the roster
 */
-(void) setRemoveFromRoster:(NSString*) jid;

-(void) setUpdateRosterItem:(NSString*) jid withName:(NSString*) name;

/**
 Requests a full roster from the server. A null version will not set the ver attribute
 */
-(void) setRosterRequest:(NSString* _Nullable) version;

/**
 makes iq  with version element
 */
-(void) setVersion;

/**
 sets up an iq that requests a http upload slot
 */
-(void) httpUploadforFile:(NSString*) file ofSize:(NSNumber*) filesize andContentType:(NSString*) contentType;

#pragma mark MUC

/**
 create instant room
 */
-(void) setInstantRoom;

-(void) setVcardAvatarWithData:(NSData*) imageData andType:(NSString*) imageType;
-(void) setVcardQuery;

#pragma mark - account

-(void) submitRegToken:(NSString*) token;
-(void) getRegistrationFields;
-(void) registerUser:(NSString*) user withPassword:(NSString*) newPass captcha:(NSString*) captcha andHiddenFields:(NSDictionary*) hiddenFields;
-(void) changePasswordForUser:(NSString*) user newPassword:(NSString*) newPass;

-(void) setBlocked:(BOOL) blocked forJid:(NSString*) blockedJid;
-(void) requestBlockList;

@end

NS_ASSUME_NONNULL_END
