//
//  xmpp.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"

#import "HelperTools.h"

#import "MLMessage.h"
#import "MLContact.h"

#import "MLXMPPConnection.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM (NSInteger, xmppState) {
    kStateLoggedOut = -1,
    kStateDisconnected,		// has connected once
    kStateReconnecting,
    kStateConnected,
    kStateHasStream,
    kStateLoggedIn,
    kStateBinding,
    kStateBound		//is operating normally
};

typedef NS_ENUM (NSInteger, xmppRegistrationState) {
    kStateRequestingForm = -1,
    kStateSubmittingForm,
    kStateFormResponseReceived,
    kStateRegistered
};

typedef NS_ENUM (NSInteger, xmppPipeliningState) {
    kPipelinedNothing = -1,
    kPipelinedAuth,
    kPipelinedResumeOrBind
};

FOUNDATION_EXPORT NSString* const kFileName;
FOUNDATION_EXPORT NSString* const kContentType;
FOUNDATION_EXPORT NSString* const kData;

@class AnyPromise;
@class MLPubSub;
@class MLXMLNode;
@class XMPPDataForm;
@class XMPPStanza;
@class XMPPIQ;
@class XMPPMessage;
@class XMPPPresence;
@class MLOMEMO;
@class MLMessageProcessor;
@class MLMucProcessor;

@class RTCSessionDescription;
@class RTCIceCandidate;

typedef void (^xmppCompletion)(BOOL success, NSString* _Nullable message);
typedef void (^xmppDataCompletion)(NSData *captchaImage, NSDictionary *hiddenFields);
typedef void (^monal_iq_handler_t)(XMPPIQ* _Nullable);

@interface xmpp : NSObject <NSStreamDelegate>

@property (nonatomic, readonly) BOOL idle;
@property (nonatomic, readonly) BOOL parseQueueFrozen;

@property (nonatomic, strong) MLXMPPConnection* connectionProperties;

//reg
@property (nonatomic, strong) NSString *regUser;
@property (nonatomic, strong) NSString *regPass;
@property (nonatomic, strong) NSString *regCode;
@property (nonatomic, strong) NSDictionary *regHidden;

// state attributes
@property (nonatomic, strong) NSString* statusMessage;

// DB info
@property (nonatomic, strong) NSNumber* accountID;

@property (nonatomic, readonly) xmppState accountState;
@property (nonatomic, readonly) BOOL reconnectInProgress;
@property (nonatomic, readonly) BOOL isDoingFullReconnect;
@property (atomic, assign) BOOL hasSeenOmemoDeviceListAfterOwnDeviceid;

// discovered properties
@property (nonatomic, strong) NSArray* discoveredServersList;
@property (nonatomic, strong) NSMutableArray* usableServersList;

@property (nonatomic, strong) MLOMEMO* omemo;
@property (nonatomic, strong) MLPubSub* pubsub;
@property (nonatomic, strong) MLMucProcessor* mucProcessor;

//calculated
@property (nonatomic, strong) NSDate* connectedTime;
@property (nonatomic, strong, readonly) MLXMLNode* capsIdentity;
@property (nonatomic, strong, readonly) NSSet* capsFeatures;
@property (nonatomic, strong, readonly) NSString* capsHash;
@property (nullable, nonatomic, strong, readonly) NSArray* supportedChannelBindingTypes;

-(id) initWithServer:(nonnull MLXMPPServer*) server andIdentity:(nonnull MLXMPPIdentity*) identity andAccountID:(NSNumber*) accountID;

-(void) freezeParseQueue;
-(void) unfreezeParseQueue;
-(void) freeze;
-(void) unfreeze;

-(void) connect;
-(void) disconnect;
-(void) disconnect:(BOOL) explicitLogout;
-(void) reconnect;
-(void) reconnect:(double) wait;

-(void) setPubSubNotificationsForNodes:(NSArray* _Nonnull) nodes persistState:(BOOL) persistState;

-(void) accountStatusChanged;

/**
 send a message to a contact with xmpp id
 */
-(void) retractMessage:(MLMessage*) msg;
-(void) moderateMessage:(MLMessage*) msg withReason:(NSString*) reason;
-(void) sendMessage:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString*) messageId;
-(void) sendMessage:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString*) messageId withLMCId:(NSString* _Nullable) LMCId;
-(void) sendChatState:(BOOL) isTyping toContact:(nonnull MLContact*) contact;

/**
 crafts a  ping and sends it
 */
-(void) sendPing:(double) timeout;

/**
 ack any stanzas we have
 */
-(void) sendLastAck;


/**
 Adds the stanza to the output Queue
 */
-(void) send:(MLXMLNode*) stanza;
-(void) sendIq:(XMPPIQ*) iq withResponseHandler:(monal_iq_handler_t) resultHandler andErrorHandler:(monal_iq_handler_t) errorHandler;
-(void) sendIq:(XMPPIQ*) iq withHandler:(MLHandler* _Nullable) handler;

/**
 removes a contact from the roster
 */
-(void) removeFromRoster:(MLContact*) contact;

/**
 adds a new contact to the roster
 */
-(void) addToRoster:(MLContact*) contact withPreauthToken:(NSString* _Nullable) preauthToken;

-(void) updateRosterItem:(MLContact*) contact withName:(NSString*) name;

-(AnyPromise*) checkJidType:(NSString*) jid;

/**
 join a room on the conference server
 */
-(void) joinMuc:(NSString* _Nonnull) room;

/**
 leave specific room. the nick name is the name used in the room.
 it is arbitrary and it may not match any other hame.
 */
-(void) leaveMuc:(NSString* _Nonnull) room;

/*
 notifies the server client is in foreground
 */
-(void) setClientActive;

/*
 notifies the server client is in foreground
 */
-(void) setClientInactive;

/*
 HTTP upload
*/
 -(void) requestHTTPSlotWithParams:(NSDictionary *)params andCompletion:(void(^)(NSString *url,  NSError *error)) completion;


-(void) setMAMQueryMostRecentForContact:(MLContact*) contact before:(NSString* _Nullable) uid withCompletion:(void (^)(NSArray* _Nullable, NSString* _Nullable error)) completion;
-(void) setMAMPrefs:(NSString*) preference;
-(void) getMAMPrefs;

/**
 enable APNS push with provided tokens
 */
-(void) enablePush;
-(void) disablePush;

-(void) mamFinishedFor:(NSString*) archiveJid;

/**
 query a user's software version
 */
-(void) getEntitySoftWareVersion:(NSString*) user;

/**
 XEP-0191 blocking
 */
-(void) setBlocked:(BOOL) blocked forJid:(NSString*) jid;
-(void) fetchBlocklist;
-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids;


#pragma mark - account management

-(AnyPromise*) changePassword:(NSString*) newPass;

-(void) requestRegFormWithToken:(NSString* _Nullable) token andCompletion:(xmppDataCompletion) completion andErrorCompletion:(xmppCompletion) errorCompletion;
-(void) registerUser:(NSString*) username withPassword:(NSString*) password captcha:(NSString* _Nullable) captcha andHiddenFields:(NSDictionary* _Nullable) hiddenFields withCompletion:(xmppCompletion _Nullable) completion;

-(void) publishRosterName:(NSString* _Nullable) rosterName;

#pragma mark - internal stuff for processors

-(BOOL) shouldTriggerSyncErrorForImportantUnackedOutgoingStanzas;
-(void) addMessageToMamPageArray:(NSDictionary*) messageDictionary;
-(NSMutableArray*) getOrderedMamPageFor:(NSString*) mamQueryId;
-(void) bindResource:(NSString*) resource;
-(void) initSession;
-(void) sendDisplayMarkerForMessages:(NSArray<MLMessage*>*) unread;
-(void) publishAvatar:(UIImage*) image;
-(void) publishStatusMessage:(NSString*) message;
-(void) delayIncomingMessageStanzasForArchiveJid:(NSString*) archiveJid;

+(NSMutableDictionary*) invalidateState:(NSDictionary*) dic;
-(void) updateIqHandlerTimeouts;

-(void) addReconnectionHandler:(MLHandler*) handler;

-(void) removeFromServerWithCompletion:(void (^)(NSString* _Nullable error)) completion;

-(void) queryExternalServicesOn:(NSString*) jid;
-(void) queryExternalServiceCredentialsFor:(NSDictionary*) service completion:(monal_id_block_t) completion;

-(void) createInvitationWithCompletion:(monal_id_block_t) completion;

-(void) markCapsQueryCompleteFor:(NSString*) ver;

-(void) updateMdsData:(NSDictionary*) mdsData;

@end

NS_ASSUME_NONNULL_END
