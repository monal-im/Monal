//
//  XMPPIQ.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/30/13.
//
//

#import "MLXMLNode.h"


FOUNDATION_EXPORT NSString *const kiqGetType;
FOUNDATION_EXPORT NSString *const kiqSetType;
FOUNDATION_EXPORT NSString *const kiqResultType;
FOUNDATION_EXPORT NSString *const kiqErrorType;

@interface XMPPIQ : MLXMLNode

-(id) initWithId:(NSString*) iqid andType:(NSString*) iqType;
-(id) initWithType:(NSString*) iqType;

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

/**
Queries the last page of messages (most recent) for a recipient
 */
-(void) setMAMQueryLatestMessagesForJid:(NSString*) jid before:(NSString*) uid;

/*
 @param after stanza id (uid)
*/
 -(void) setMAMQueryFromStart:(NSDate *) startDate after:(NSString *) uid  withMax:(NSString *) maxResults  andJid:(NSString *)jid;


#pragma mark disco
/**
 makes a disco info response for the server.
 @param node param passed is the xmpp node attribute that came in with the iq get
 */
-(void) setDiscoInfoWithFeaturesAndNode:(NSString*) node;

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
gets vcard info 
 */
-(void) getVcardTo:(NSString*) to;

/**
removes a contact from the roster
 */
-(void) setRemoveFromRoster:(NSString*) jid;

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
-(void) setJingleTerminateTo:(NSString*) jid andResource:(NSString*) resource withValues:(NSDictionary*) info;


-(void) setBlocked:(BOOL) blocked forJid:(NSString* _Nonnull) blockedJid;


#pragma mark Signal

-(void) subscribeDevices:(NSString*) jid;

/**
 publishes a device.
 */
-(void) publishDevices:(NSArray*) devices;

/**
 publishes signal keys and prekeys
 */
-(void) publishKeys:(NSDictionary *) keys andPreKeys:(NSArray *) prekeys withDeviceId:(NSString*) deviceid;


#pragma mark - pubsub

-(void) requestBundles:(NSString*) deviceid;
-(void) requestDevices;


-(void) requestNode:(NSString*) node;

#pragma mark - account
-(void) changePasswordForUser:(NSString *) user newPassword:(NSString *)newPsss;
-(void) getRegistrationFields;
-(void) registerUser:(NSString *) user withPassword:(NSString *) newPass captcha:(NSString *) captcha andHiddenFields:(NSDictionary *)hiddenFields;

@end
