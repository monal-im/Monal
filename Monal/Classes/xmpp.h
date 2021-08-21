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

FOUNDATION_EXPORT NSString* const kFileName;
FOUNDATION_EXPORT NSString* const kContentType;
FOUNDATION_EXPORT NSString* const kData;

@class MLPubSub;
@class MLXMLNode;
@class XMPPDataForm;
@class XMPPStanza;
@class XMPPIQ;
@class XMPPMessage;
@class XMPPPresence;
@class MLOMEMO;
@class MLMessageProcessor;

typedef void (^xmppCompletion)(BOOL success, NSString* _Nullable message);
typedef void (^xmppDataCompletion)(NSData *captchaImage, NSDictionary *hiddenFields);
typedef void (^monal_iq_handler_t)(XMPPIQ* _Nullable);

@interface xmpp : NSObject <NSStreamDelegate>

@property (nonatomic, readonly) BOOL idle;

@property (nonatomic, strong) MLXMPPConnection* connectionProperties;

//reg
@property (nonatomic, strong) NSString *regUser;
@property (nonatomic, strong) NSString *regPass;
@property (nonatomic, strong) NSString *regCode;
@property (nonatomic, strong) NSDictionary *regHidden;

// state attributes
@property (nonatomic, strong) NSString* statusMessage;

// DB info
@property (nonatomic, strong) NSString* accountNo;

@property (nonatomic, readonly) xmppState accountState;
@property (nonatomic, readonly) BOOL reconnectInProgress;

// discovered properties
@property (nonatomic, strong) NSArray* discoveredServersList;
@property (nonatomic, strong) NSMutableArray* usableServersList;

@property (nonatomic, strong) MLOMEMO* omemo;
@property (nonatomic, strong) MLPubSub* pubsub;

//calculated
@property (nonatomic, strong) NSDate* connectedTime;
@property (nonatomic, strong, readonly) MLXMLNode* capsIdentity;
@property (nonatomic, strong, readonly) NSSet* capsFeatures;
@property (nonatomic, strong, readonly) NSString* capsHash;

-(id) initWithServer:(nonnull MLXMPPServer*) server andIdentity:(nonnull MLXMPPIdentity*) identity andAccountNo:(NSString*) accountNo;

-(void) unfreezed;
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
-(void) sendMessage:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString*) messageId;
-(void) sendMessage:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString*) messageId withLMCId:(NSString* _Nullable) LMCId;
-(void) sendChatState:(BOOL) isTyping toJid:(NSString*) jid;

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
-(void) removeFromRoster:(NSString*) contact;

/**
 adds a new contact to the roster
 */
-(void) addToRoster:(NSString*) contact;

/**
 adds a new contact to the roster
 */
-(void) approveToRoster:(NSString*) contact;

-(void) rejectFromRoster:(NSString*) contact;

-(void) updateRosterItem:(NSString*) jid withName:(NSString*) name;

-(void) checkJidType:(NSString*) jid withCompletion:(void (^)(NSString* type, NSString* _Nullable errorMessage)) completion;

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

-(void) changePassword:(NSString*) newPass withCompletion:(xmppCompletion _Nullable) completion;

-(void) requestRegFormWithCompletion:(xmppDataCompletion) completion andErrorCompletion:(xmppCompletion) errorCompletion;
-(void) registerUser:(NSString*) username withPassword:(NSString*) password captcha:(NSString *) captcha andHiddenFields:(NSDictionary *)hiddenFields withCompletion:(xmppCompletion _Nullable) completion;

-(void) publishRosterName:(NSString* _Nullable) rosterName;

#pragma mark - internal stuff for processors

-(void) addMessageToMamPageArray:(NSDictionary*) messageDictionary;
-(NSMutableArray*) getOrderedMamPageFor:(NSString*) mamQueryId;
-(void) bindResource:(NSString*) resource;
-(void) initSession;
-(void) sendDisplayMarkerForMessage:(MLMessage*) msg;
-(void) publishAvatar:(UIImage*) image;
-(void) publishStatusMessage:(NSString*) message;
-(void) delayIncomingMessageStanzasForArchiveJid:(NSString*) archiveJid;

+(NSMutableDictionary*) invalidateState:(NSDictionary*) dic;
-(void) updateIqHandlerTimeouts;

@end

NS_ASSUME_NONNULL_END
