//
//  MLXMPPManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class xmpp;
@class MLContact;

/**
 A singleton to control all of the active XMPP connections
 */
@interface MLXMPPManager : NSObject
{
	dispatch_source_t _pinger;
}

+(MLXMPPManager*) sharedInstance;

-(BOOL) allAccountsIdle;

-(MLContact* _Nullable) sendAllOutboxes;

#pragma  mark connectivity
/**
 Checks if there are any enabled acconts and connects them if necessary.  
 */
-(void) connectIfNecessary;

/**
 logout all accounts
 */
-(void) reconnectAll;

-(void) disconnectAll;

/**
 disconnects the specified account
 */
-(void) disconnectAccount:(NSNumber*) accountNo;

/**
 connects the specified account
 */
-(void) connectAccount:(NSNumber*) accountNo;

#pragma mark XMPP commands
/**
 Remove a contact from an account
 */
-(void) removeContact:(MLContact*) contact;

/**
 Add a contact from an account
 */
-(void) addContact:(MLContact*) contact;
-(void) addContact:(MLContact*) contact withPreauthToken:(NSString* _Nullable) preauthToken;

/**
 Block  a jid
 */
-(void) blocked:(BOOL) isBlocked Jid:(MLContact *) contact;
-(void) blocked:(BOOL) isBlocked Jid:(NSString *) contact Account:(NSNumber*) accountNo;

/**
 Returns the user set name of the conencted account
 */
-(NSString*) getAccountNameForConnectedRow:(NSUInteger) row;

/*
 gets the connected account apecified by id. return nil otherwise
 */
-(xmpp* _Nullable) getConnectedAccountForID:(NSNumber*) accountNo;

/**
 Returns YES if account is connected
 */
-(BOOL) isAccountForIdConnected:(NSNumber*) accountNo;

/**
 When the account estblihsed its current connection. 
 */
-(NSDate *) connectedTimeFor:(NSNumber*) accountNo;

/**
 update the password in the keychan and update memory cache
 */
-(BOOL) isValidPassword:(NSString*) password forAccount:(NSNumber*) accountNo;
-(void) updatePassword:(NSString*) password forAccount:(NSNumber*) accountNo;

-(void) approveContact:(MLContact*) contact;
-(void) rejectContact:(MLContact*) contact;

/**
Sends a message to a specified contact in account. Calls completion handler on success or failure.
 */
-(void) sendMessageAndAddToHistory:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypted isUpload:(BOOL) isUpload withCompletionHandler:(void (^ _Nullable)(BOOL success, NSString* messageId)) completion;
-(void)sendMessage:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypted isUpload:(BOOL) isUpload messageId:(NSString*) messageId withCompletionHandler:(void (^ _Nullable)(BOOL success, NSString* messageId)) completion;
-(void) sendChatState:(BOOL) isTyping fromAccount:(NSNumber*) accountNo toJid:(NSString*) jid;

#pragma mark XMPP settings

@property (nonatomic, strong, readonly) NSMutableArray* connectedXMPP;
@property (nonatomic, readonly) BOOL hasConnectivity;

@property (nonatomic, assign) BOOL hasAPNSToken;
@property (nonatomic, strong) NSString* pushToken;

@property (nonatomic, readonly) BOOL isBackgrounded;
@property (nonatomic, readonly) BOOL isNotInFocus;

@property (nonatomic, readonly) BOOL onMobile;

/**
 updates delivery status after message has been sent
 */
-(void) handleSentMessage:(NSNotification*) notification;

-(void) noLongerInFocus;

/**
 updates client state on server as inactive
 */
-(void) nowBackgrounded;

/**
 sets client state on server as active
 */
-(void) nowForegrounded;

/**
 fetch entity software version
 */
-(void) getEntitySoftWareVersionForContact:(MLContact*) contact andResource:(NSString*) resource;

-(void) setPushToken:(NSString* _Nullable) token;
#ifndef IS_ALPHA
-(void) unregisterPush;
#endif

@end

NS_ASSUME_NONNULL_END
