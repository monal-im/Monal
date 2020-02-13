//
//  MLXMPPManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <Foundation/Foundation.h>
#import "Reachability.h"
#import "xmpp.h"

#define kMonalNetQueue "im.monal.netQueue"
#define kMonalConnectedListQueue "im.monal.connectedListQueue"

extern NSString *const kXmppAccount;

/**
 A singleton to control all of the active XMPP connections
 */
@interface MLXMPPManager : NSObject
{
    dispatch_queue_t _netQueue ;
    dispatch_source_t _pinger;
    NSArray* _accountList;
}

+ (MLXMPPManager* )sharedInstance;

#pragma  mark connectivity
/**
 Checks if there are any enabled acconts and connects them if necessary.  
 */
-(void)connectIfNecessary;

/**
 logout all accounts
 */
-(void)logoutAll;

/**
 disconnects the specified account
 */
-(void) disconnectAccount:(NSString*) accountNo;

/**
 connects the specified account
 */
-(void) connectAccount:(NSString*) accountNo;

#pragma mark XMPP commands
/**
 Remove a contact from an account
 */
-(void) removeContact:(MLContact *) contact;

/**
 Add a contact from an account
 */
-(void) addContact:(MLContact *) contact;

/**
 Gets service details for account
 */
-(void) getServiceDetailsForAccount:(NSInteger) row;

/**
Returns the server set name of the conencted account 
 */
-(NSString*) getNameForConnectedRow:(NSInteger) row;

/**
 Returns the user set name of the conencted account
 */
-(NSString*) getAccountNameForConnectedRow:(NSInteger) row;

/*
 gets the connected account apecified by id. return nil otherwise
 */
-(xmpp*) getConnectedAccountForID:(NSString*) accountNo;

/**
 Returns YES if account is connected
 */
-(BOOL) isAccountForIdConnected:(NSString*) accountNo;

/**
 When the account estblihsed its current connection. 
 */
-(NSDate *) connectedTimeFor:(NSString*) accountNo;

/**
 update the password in the keychan and update memory cache
 */
-(void) updatePassword:(NSString *) password forAccount:(NSString *) accountNo;


#pragma mark MUC commands
/**
 Gets a list of rooms on the confernce server
 */
-(void) getRoomsForAccountRow:(NSInteger) row;


/**
 returns the list of rooms in confrence server
 */
-(NSArray*) getRoomsListForAccountRow:(NSInteger) row;


/**
 Joins the selected Room on the conference server
 */
-(void)  joinRoom:(NSString*) roomName withNick:(NSString *)nick andPassword:(NSString*) password forAccountRow:(NSInteger) row;

-(void)  joinRoom:(NSString*) roomName withNick:(NSString *)nick andPassword:(NSString*) password forAccounId:(NSString *) accountId;
/**
 leaves a specified MUC room. 
 @param roomName room
 @param accountId the accountid number from the database
 */
-(void)  leaveRoom:(NSString*) roomName withNick:(NSString *) nick forAccountId:(NSString*) accountId;

#pragma mark Jingle VOIP

/**
 Call a contact from an account
 */
-(void) callContact:(MLContact*) contact;

/**
 hangup on a contact from an account
 */
-(void) hangupContact:(NSDictionary*) contact;


-(void) approveContact:(MLContact*) contact;

-(void) rejectContact:(MLContact*) contact;

/**
 respond to call with either accept or not. Passes back the notifiaction dictionary
 */
-(void) handleCall:(NSDictionary *) userDic withResponse:(BOOL) accept; 

/**
Sends a message to a specified contact in account. Calls completion handler on success or failure.
 */
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo isEncrypted:(BOOL) encrypted isMUC:(BOOL) isMUC  isUpload:(BOOL) isUpload messageId:(NSString *) messageId
withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion;


/**
 uploads the selected png image Data as [uuid].jpg
 */
-(void)httpUploadJpegData:(NSData*) fileData   toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion;

/**
 opens file and attempts to upload it
 */
-(void)httpUploadFileURL:(NSURL*) fileURL  toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion;

/**
Attempts to upload a file to the  HTTP upload service
 */
-(void)httpUploadData:(NSData *)data withFilename:(NSString*) filename andType:(NSString*)contentType  toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion;


#pragma mark XMPP settings

-(void) setStatusMessage:(NSString*) message;

-(void) setAway:(BOOL) isAway;
-(void) setVisible:(BOOL) isVisible;

-(void) setPriority:(NSInteger) priority;

@property (nonatomic, strong, readonly) NSMutableArray* connectedXMPP;


@property (nonatomic, assign) BOOL hasAPNSToken;

@property (nonatomic, strong) NSString *pushNode;
@property (nonatomic, strong) NSString *pushSecret;

/**
 updates unread
 */
-(void) handleNewMessage:(NSNotification *)notification;

-(void) resetForeground;

/**
 updates delivery status after message has been sent
 */
-(void) handleSentMessage:(NSNotification *)notification;

/**
 updtes client state on server as inactive
 */
-(void) setClientsInactive;

/**
 sets client state on server as active
 */
-(void) setClientsActive;

/**
 fetch a contacts vCard
 */
-(void) getVCard:(MLContact *) contact;

/**
 log out everything but doesnt destroy the stream id
 */
-(void)logoutAllKeepStreamWithCompletion:(void (^)(void))completion;

/**
 Iterates through set and compares with connected accounts. Removes them. useful for active chat. 
 */
-(void) cleanArrayOfConnectedAccounts:(NSMutableArray *) dirtySet;

-(void) setPushNode:(NSString *)node andSecret:(NSString *)secret;



-(void) sendMessageForConnectedAccounts;

-(void) parseMessageForData:(NSData *) data;


@end
