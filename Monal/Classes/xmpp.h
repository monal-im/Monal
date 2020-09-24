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
#import "MLXMLNode.h"

#import "jingleCall.h"
#import "MLDNSLookup.h"
#import "MLSignalStore.h"
#import "MLMessageProcessor.h"
#import "MLOMEMO.h"

#ifndef DISABLE_OMEMO
#import "SignalProtocolObjC.h"
#endif

#import "MLMessage.h"
#import "MLContact.h"

#import "MLXMPPConnection.h"


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
FOUNDATION_EXPORT NSString* const kContact;
FOUNDATION_EXPORT NSString* const kCompletion;

typedef void (^xmppCompletion)(BOOL success, NSString *message);
typedef void (^xmppDataCompletion)(NSData *captchaImage, NSDictionary *hiddenFields);

@class MLOMEMO;
@class MLMessageProcessor;

@interface xmpp : NSObject <NSStreamDelegate>

@property (nonatomic, readonly) BOOL idle;

@property (nonatomic, strong) NSString* pushNode;
@property (nonatomic, strong) NSString* pushSecret;

@property (nonatomic, strong) MLXMPPConnection* connectionProperties;

//reg
@property (nonatomic, strong) NSString *regUser;
@property (nonatomic, strong) NSString *regPass;
@property (nonatomic, strong) NSString *regCode;
@property (nonatomic, strong) NSDictionary *regHidden;

@property (nonatomic, strong) jingleCall* call;

// state attributes
@property (nonatomic, strong) NSString* statusMessage;
@property (nonatomic, assign) BOOL awayState;

@property (nonatomic, strong) jingleCall *jingle;

// DB info
@property (nonatomic, strong) NSString* accountNo;

@property (nonatomic, readonly) xmppState accountState;

// discovered properties
@property (nonatomic, assign) BOOL SRVDiscoveryDone;
@property (nonatomic, strong) NSArray* discoveredServersList;
@property (nonatomic, strong) NSMutableArray* usableServersList;

@property (nonatomic, strong) MLOMEMO* omemo;

@property (nonatomic, strong) NSArray* roomList;
@property (nonatomic, strong) NSArray* rosterList;

//calculated
@property (nonatomic, strong, readonly) NSString* versionHash;
@property (nonatomic, strong) NSDate* connectedTime;

extern NSString *const kMessageId;
extern NSString *const kSendTimer;

extern NSString *const kXMPPError;
extern NSString *const kXMPPSuccess;
extern NSString *const kXMPPPresence;

extern NSString* const kAccountState;
extern NSString* const kAccountHibernate;

-(id) initWithServer:(nonnull MLXMPPServer*) server andIdentity:(nonnull MLXMPPIdentity*) identity andAccountNo:(NSString*) accountNo;

-(void) connect;
-(void) disconnect;
-(void) disconnect:(BOOL) explicitLogout;
-(void) reconnect;
-(void) reconnect:(double) wait;

/**
 send a message to a contact with xmpp id
 */
-(void) sendMessage:(NSString* _Nonnull) message toContact:(NSString* _Nonnull) contact isMUC:(BOOL) isMUC isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString *) messageId ;
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
-(void) send:(MLXMLNode* _Nonnull) stanza;
-(void) sendIq:(XMPPIQ* _Nonnull) iq withResponseHandler:(monal_iq_handler_t) resultHandler andErrorHandler:(monal_iq_handler_t) errorHandler;
-(void) sendIq:(XMPPIQ* _Nonnull) iq withDelegate:(id) delegate andMethod:(SEL) method andAdditionalArguments:(NSArray*) args;

/**
 removes a contact from the roster
 */
-(void) removeFromRoster:(NSString* _Nonnull) contact;

/**
 adds a new contact to the roster
 */
-(void) addToRoster:(NSString* _Nonnull) contact;

/**
 adds a new contact to the roster
 */
-(void) approveToRoster:(NSString* _Nonnull) contact;

-(void) rejectFromRoster:(NSString* _Nonnull) contact;

#pragma mark set connection attributes
/**
sets the status message. makes xmpp call
 */
-(void) setStatusMessageText:(NSString*) message;

/**
sets away xmpp call.
 */
-(void) setAway:(BOOL) away;

/**
 request futher service detail
 */
-(void) getServiceDetails;

-(BOOL) isHibernated;

/**
 get list of rooms on conference server
 */
-(void) getConferenceRooms;

/**
 join a room on the conference server
 */
-(void) joinRoom:(NSString* _Nonnull) room withNick:(NSString* _Nullable) nick andPassword:(NSString* _Nullable)password;

/**
 leave specific room. the nick name is the name used in the room.
 it is arbitrary and it may not match any other hame.
 */
-(void) leaveRoom:(NSString* _Nonnull) room withNick:(NSString* _Nullable) nick;

#pragma mark Jingle
/**
 Calls a contact
 */
-(void)call:(MLContact* _Nonnull) contact;

/**
Hangs up current call with contact
 */
-(void)hangup:(MLContact* _Nonnull) contact;

/**
Decline a call request
 */
-(void)declineCall:(NSDictionary* _Nonnull) contact;

/**
 accept call request
 */
-(void)acceptCall:(NSDictionary* _Nonnull) contact;


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


-(void) setMAMQueryMostRecentForJid:(NSString*) jid before:(NSString*) uid withCompletion:(void (^)(NSArray* _Nullable)) completion;
-(void) setMAMPrefs:(NSString*) preference;
-(void) getMAMPrefs;

/**
 enable APNS push with provided tokens
 */
-(void) enablePush;

-(void) mamFinished;

/**
 query a user's vcard
 */
-(void) getVCard:(NSString* _Nonnull) user;

/**
 query a user's software version
 */
-(void) getEntitySoftWareVersion:(NSString* _Nonnull) user;

/**
 XEP-0191 blocking
 */
-(void) setBlocked:(BOOL) blocked forJid:(NSString* _Nonnull) jid;

/**
 An intentional disconnect to trigger APNS. does not close the stream.
 */
-(void) disconnectToResumeWithCompletion:(void (^)(void))completion;


#pragma mark - account management

-(void) changePassword:(NSString* _Nonnull) newPass withCompletion:(xmppCompletion _Nullable) completion;

-(void) requestRegFormWithCompletion:(xmppDataCompletion) completion andErrorCompletion:(xmppCompletion) errorCompletion;
-(void) registerUser:(NSString* _Nonnull) username withPassword:(NSString* _Nonnull) password captcha:(NSString *) captcha andHiddenFields:(NSDictionary *)hiddenFields withCompletion:(xmppCompletion _Nullable) completion;


-(void) addMessageToMamPageArray:(XMPPMessage* _Nonnull) messageNode forOuterMessageNode:(XMPPMessage* _Nonnull) outerMessageNode withBody:(NSString* _Nonnull) body andEncrypted:(BOOL) encrypted andShowAlert:(BOOL) showAlert andMessageType:(NSString* _Nonnull) messageType;
-(NSArray* _Nullable) getOrderedMamPageFor:(NSString* _Nonnull) mamQueryId;

@end
