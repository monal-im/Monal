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


#if TARGET_OS_IPHONE
#import "ContactsViewController.h"
#else
#import "MLContactsViewController.h"
#endif

#import "MLConstants.h"
#import "jingleCall.h"
#import "MLDNSLookup.h"
#import "MLSignalStore.h"
#ifndef DISABLE_OMEMO
#import "SignalProtocolObjC.h"
#endif

typedef NS_ENUM (NSInteger, xmppState) {
    kStateLoggedOut =-1,
    kStateDisconnected , // has connected once
    kStateReconnecting ,
    kStateHasStream ,
    kStateLoggedIn ,
    kStateBound //is operating normally
};

FOUNDATION_EXPORT NSString *const kFileName;
FOUNDATION_EXPORT NSString *const kContentType;
FOUNDATION_EXPORT NSString *const kData;
FOUNDATION_EXPORT NSString *const kContact;
FOUNDATION_EXPORT NSString *const kCompletion;

typedef void (^xmppCompletion)(BOOL success, NSString *message);

@interface xmpp : NSObject <NSStreamDelegate>
{
    NSInputStream *_iStream;
    NSOutputStream *_oStream;
    NSMutableString* _inputBuffer;
    NSMutableArray* _outputQueue;
    
    NSArray* _stanzaTypes;
    
    BOOL _startTLSComplete;
    BOOL _streamHasSpace;
    
    //does not reset at disconnect
    BOOL _loggedInOnce;
    BOOL _hasRequestedServerInfo;
    
    BOOL _brokenServerSSL;
}

#pragma  mark properties

@property (nonatomic,strong) NSString* pushNode;
@property (nonatomic,strong) NSString* pushSecret;

@property (nonatomic,readonly) NSString* fulluser; // combination of username@domain

// connection attributes
@property (nonatomic,strong) NSString* username;
@property (nonatomic,strong) NSString* domain;
@property (nonatomic,strong, readonly) NSString* jid;
@property (nonatomic,strong) NSString* password;
@property (nonatomic,strong) NSString* server;
@property (nonatomic,assign) NSInteger port;
@property (nonatomic,strong) NSString* resource;
@property (nonatomic,assign) BOOL SSL;
@property (nonatomic,assign) BOOL oldStyleSSL;
@property (nonatomic,assign) BOOL selfSigned;
@property (nonatomic,assign) BOOL oAuth;
@property (nonatomic,assign) BOOL registration;

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
@property (nonatomic,strong)  NSArray* discoveredServerList;
@property (nonatomic,strong)  NSMutableArray*  discoveredServices;
@property (nonatomic,strong)  NSString*  conferenceServer;
@property (nonatomic,strong)  NSArray*  roomList;
@property (nonatomic, strong) NSArray* rosterList;
@property (nonatomic, assign) BOOL staleRoster; //roster is stale if it resumed in the background


@property (nonatomic,strong)  NSString*  uploadServer;
@property (nonatomic, readonly) BOOL supportsHTTPUpload;
// client state
@property (nonatomic, readonly) BOOL supportsClientState;

//message archive
@property (nonatomic, readonly) BOOL supportsMam2;

@property (nonatomic, readonly) BOOL supportsSM3;
@property (nonatomic, readonly) BOOL supportsPush;
@property (nonatomic, readonly) BOOL pushEnabled;
@property (nonatomic, readonly) BOOL usingCarbons2;
@property (nonatomic, readonly) BOOL supportsRosterVersion;

//calculated
@property (nonatomic,strong, readonly) NSString* versionHash;

#if TARGET_OS_IPHONE
@property (nonatomic,weak) ContactsViewController* contactsVC;
#else
@property (nonatomic,weak) MLContactsViewController* contactsVC;
#endif
//UI

@property (nonatomic,strong) NSDate* connectedTime;

#ifndef DISABLE_OMEMO
@property (nonatomic, strong) SignalContext *signalContext;
@property (nonatomic, strong) MLSignalStore *monalSignalStore;
#endif

extern NSString *const kId;
extern NSString *const kMessageId;
extern NSString *const kSendTimer;



extern NSString *const kXMPPError;
extern NSString *const kXMPPSuccess;
extern NSString *const kXMPPPresence;



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
 Adds the stanza to the output Queue
 */
-(void) send:(MLXMLNode*) stanza;

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
-(void) setStatusMessageText:(NSString*) message;

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
-(void)call:(NSDictionary*) contact;

/**
Hangs up current call with contact
 */
-(void)hangup:(NSDictionary*) contact;

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

/*
 query message archive.
 */
-(void) setMAMQueryFromStart:(NSDate *) startDate toDate:(NSDate *) endDate  andJid:(NSString *)jid;


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

-(void) requestRegFormWithCompletion:(void(^)(NSData *captchaImage)) completion;

-(void) registerUser:(NSString *) username withPassword:(NSString *) password andCaptcha:(NSString *) captcha withCompletion:(xmppCompletion) completion;

@end
