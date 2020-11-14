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

-(id) initWithId:(NSString*) iqid andType:(NSString*) iqType;
-(id) initWithType:(NSString*) iqType;
-(id) initWithType:(NSString*) iqType to:(NSString*) to;
-(id) initAsResponseTo:(XMPPIQ*) iq withType:(NSString*) iqType;

-(NSString*) getId;
-(void) setId:(NSString*) id;

-(void) setPushEnableWithNode:(NSString *) node andSecret:(NSString *) secret;
-(void) setPushDisableWithNode:(NSString *) node;

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

/**
 gets MAM prefernces
 */
-(void) mamArchivePref;

/*
 updates MAM pref
 @param pref can only be aways, never or roster
 */
-(void) updateMamArchivePrefDefault:(NSString *) pref;

-(void) setMAMQueryLatestMessagesForJid:(NSString*) jid before:(NSString*) uid;
-(void) setMAMQueryAfter:(NSString*) uid;
-(void) setMAMQueryForLatestId;

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

-(void) setUpdateRosterItem:(NSString* _Nonnull) jid withName:(NSString* _Nonnull) name;

/**
 Requests a full roster from the server. A null version will not set the ver attribute
 */
-(void) setRosterRequest:(NSString *) version;

/**
 makes iq  with version element
 */
-(void) setVersion;

/**
 sets up an iq that requests a http upload slot
 */
-(void) httpUploadforFile:(NSString *) file ofSize:(NSNumber *) filesize andContentType:(NSString *) contentType;


#pragma mark MUC
/**
 create instant room
 */
-(void) setInstantRoom;

#pragma mark Jingle


/**
 Dictionary info has initiator, responder, sid, ownip, localport1, localport2
 */
-(void) setJingleInitiateTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info;
/**
 Dictionary info has initiator, responder, sid, ownip, localport1, localport2
 */
-(void) setJingleAcceptTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info;
/**
 Dictionary info has initiator, responder, sid
 */
-(void) setJingleDeclineTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info;
/**
 Dictionary info has initiator, responder, sid, ownip
 */
-(void) setJingleTerminateTo:(NSString* _Nullable) jid andResource:(NSString* _Nullable) resource withValues:(NSDictionary* _Nullable) info;


-(void) setBlocked:(BOOL) blocked forJid:(NSString* _Nonnull) blockedJid;

#pragma mark - account
-(void) changePasswordForUser:(NSString* _Nonnull) user newPassword:(NSString* _Nonnull) newPsss;
-(void) getRegistrationFields;
-(void) registerUser:(NSString* _Nonnull) user withPassword:(NSString* _Nonnull) newPass captcha:(NSString* _Nonnull) captcha andHiddenFields:(NSDictionary* _Nonnull) hiddenFields;

@end

NS_ASSUME_NONNULL_END
