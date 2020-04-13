//
//  xmpp.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <Foundation/Foundation.h>
#import "MLXMLNode.h"
#import "EncodingTools.h"

#import "MLConstants.h"
#import "MLXMPPConstants.h"
#import "jingleCall.h"
#import "MLDNSLookup.h"
#import "MLSignalStore.h"

#ifndef DISABLE_OMEMO
#import "SignalProtocolObjC.h"
#endif

#import "MLMessage.h"
#import "MLContact.h"

#import "MLXMPPConnection.h"

typedef NS_ENUM (NSInteger, xmppState) {
    kStateLoggedOut =-1,
    kStateDisconnected , // has connected once
    kStateReconnecting ,
    kStateHasStream ,
    kStateLoggedIn ,
    kStateBound //is operating normally
};

typedef NS_ENUM (NSInteger, xmppRegistrationState) {
    kStateRequestingForm =-1,
    kStateSubmittingForm,
    kStateFormResponseReceived,
    kStateRegistered
};

FOUNDATION_EXPORT NSString *const kFileName;
FOUNDATION_EXPORT NSString *const kContentType;
FOUNDATION_EXPORT NSString *const kData;
FOUNDATION_EXPORT NSString *const kContact;
FOUNDATION_EXPORT NSString *const kCompletion;

typedef void (^xmppCompletion)(BOOL success, NSString *message);
typedef void (^xmppDataCompletion)(NSData *captchaImage, NSDictionary *hiddenFields);

@interface xmpp : NSObject

@property (nonatomic,strong) NSString* pushNode;
@property (nonatomic,strong) NSString* pushSecret;

@property (nonatomic,strong) MLXMPPConnection* connectionProperties;

//reg
@property (nonatomic,assign) BOOL registrationSubmission;
@property (nonatomic,assign) BOOL registration;
@property (nonatomic,assign) xmppRegistrationState registrationState;

@property (nonatomic,strong) NSString *regUser;
@property (nonatomic,strong) NSString *regPass;
@property (nonatomic,strong) NSString *regCode;
@property (nonatomic,strong) NSDictionary *regHidden;
@property (nonatomic, strong) xmppDataCompletion regFormCompletion;


@property (nonatomic,strong) jingleCall* call;

// state attributes
@property (nonatomic,assign) NSInteger priority;
@property (nonatomic,strong) NSString* statusMessage;
@property (nonatomic,assign) BOOL awayState;
@property (nonatomic,assign) BOOL visibleState;

@property (nonatomic,assign) BOOL hasShownAlert;

@property (nonatomic, strong) jingleCall *jingle;

// DB info
@property (nonatomic,strong) NSString* accountNo;

//we should have an enumerator for this
@property (nonatomic,assign) BOOL explicitLogout;
@property (nonatomic,assign,readonly) BOOL loginError;

@property (nonatomic, readonly) xmppState accountState;

// discovered properties
@property (nonatomic,strong)  NSArray* discoveredServersList;
@property (nonatomic,strong)  NSMutableArray* usableServersList;

@property (nonatomic,strong)  NSArray*  roomList;
@property (nonatomic, strong) NSArray* rosterList;
@property (nonatomic, assign) BOOL staleRoster; //roster is stale if it resumed in the background


@property (nonatomic,assign) BOOL airDrop;

//calculated
@property (nonatomic,strong, readonly) NSString* versionHash;

@property (nonatomic,strong) NSDate* connectedTime;

#ifndef DISABLE_OMEMO
@property (nonatomic, strong) SignalContext *signalContext;
@property (nonatomic, strong) MLSignalStore *monalSignalStore;
#endif

extern NSString *const kMessageId;
extern NSString *const kSendTimer;

extern NSString *const kXMPPError;
extern NSString *const kXMPPSuccess;
extern NSString *const kXMPPPresence;


-(id) initWithServer:(nonnull MLXMPPServer *) server andIdentity:(nonnull MLXMPPIdentity *)identity;

-(void) connectWithCompletion:(xmppCompletion) completion;
-(void) connect;
-(void) disconnect;

/**
 send a message to a contact with xmpp id
 */
-(void) sendMessage:(NSString*) message toContact:(NSString*) contact isMUC:(BOOL) isMUC isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString *) messageId ;

/**
 crafts a whitepace ping and sends it
 */
-(void) sendWhiteSpacePing;

/**
 crafts a  ping and sends it
 */
-(void) sendPing;

/**
 ack any stanzas we have
 */
-(void) sendLastAck;

/**
 Adds the stanza to the output Queue
 */
-(void) send:(MLXMLNode *_Nonnull) stanza;

/**
 removes a contact from the roster
 */
-(void) removeFromRoster:(NSString *_Nonnull) contact;

/**
 adds a new contact to the roster
 */
-(void) addToRoster:(NSString *_Nonnull) contact;

/**
 adds a new contact to the roster
 */
-(void) approveToRoster:(NSString *_Nonnull) contact;

-(void) rejectFromRoster:(NSString *_Nonnull) contact;

/**
 sets up a background task to reconnect if needed. dEfault wait of 5s
 */
-(void) reconnect;

/**
 reconnect called with a specified wait. if never logged in then wait is 0.
 */
-(void) reconnect:(NSInteger) scheduleWait;



#pragma mark set connection attributes
/**
sets the status message. makes xmpp call
 */
-(void) setStatusMessageText:(NSString *) message;

/**
sets away xmpp call.
 */
-(void) setAway:(BOOL) away;

/**
 sets visibility xmpp call.
 */
-(void) setVisible:(BOOL) visible;

/**
 sets priority. makes xmpp call. this is differnt from setting the property value itself.
 */
-(void) updatePriority:(NSInteger) priority;

/**
 request futher service detail
 */
-(void) getServiceDetails;

/**
 get list of rooms on conference server
 */
-(void) getConferenceRooms;

/**
 join a room on the conference server
 */
-(void) joinRoom:(NSString*) room withNick:(NSString*) nick andPassword:(NSString *)password;

/**
 leave specific room. the nick name is the name used in the room.
 it is arbitrary and it may not match any other hame.
 */
-(void) leaveRoom:(NSString*) room withNick:(NSString *) nick;

#pragma mark Jingle
/**
 Calls a contact
 */
-(void)call:(MLContact*) contact;

/**
Hangs up current call with contact
 */
-(void)hangup:(MLContact*) contact;

/**
Decline a call request
 */
-(void)declineCall:(NSDictionary*) contact;

/**
 accept call request
 */
-(void)acceptCall:(NSDictionary*) contact;


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


-(void) setMAMQueryMostRecentForJid:(NSString *)jid;

/*
 query message archive.
 */
-(void) setMAMQueryFromStart:(NSDate *) startDate after:(NSString *) after  andJid:(NSString *)jid;


//-(void) queryMAMSinceLastStanzaForContact:(NSString *) contactJid;
-(void) queryMAMSinceLastMessageDateForContact:(NSString *) contactJid; 

-(void) setMAMPrefs:(NSString *) preference;
-(void) getMAMPrefs;

/**
 enable APNS push with provided tokens
 */
-(void) enablePush;

/**
 query a user's vcard
 */
-(void) getVCard:(NSString *) user;

#ifndef DISABLE_OMEMO

-(void) subscribeOMEMODevicesFrom:(NSString *) jid;
/** OMEMO */
-(void) queryOMEMODevicesFrom:(NSString *) jid;
#endif

/**
 An intentional disconnect to trigger APNS. does not close the stream.
 */
-(void) disconnectToResumeWithCompletion:(void (^)(void))completion;

-(void) setupSignal;


#pragma mark - account management

-(void) changePassword:(NSString *) newPass withCompletion:(xmppCompletion) completion;

-(void) registerUser:(NSString *) username withPassword:(NSString *) password captcha:(NSString *) captcha andHiddenFields:(NSDictionary *)hiddenFields withCompletion:(xmppCompletion) completion;

@end
