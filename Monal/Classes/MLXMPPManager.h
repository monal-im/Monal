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

#if TARGET_OS_IPHONE
#import "ContactsViewController.h"
#else
#endif

#define kMonalNetQueue "im.monal.netQueue"
#define kMonalConnectedListQueue "im.monal.connectedListQueue"

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
-(void) removeContact:(NSDictionary*) contact;

/**
 Add a contact from an account
 */
-(void) addContact:(NSDictionary*) contact;

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


/**
 Returns YES if account is connected
 */
-(BOOL) isAccountForIdConnected:(NSString*) accountNo;

/**
 When the account estblihsed its current connection. 
 */
-(NSDate *) connectedTimeFor:(NSString*) accountNo;

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
-(void)  joinRoom:(NSString*) roomName  withPassword:(NSString*) password forAccountRow:(NSInteger) row;

/**
 leave the specific MUC room
 @param roomName
 @param row the row of the account in the connected accounts list
 */
-(void)  leaveRoom:(NSString*) roomName forAccountRow:(NSInteger) row;

/**
 leaves a specified MUC room. 
 @param roomName
 @param accountID the accountid number from the database
 */
-(void)  leaveRoom:(NSString*) roomName forAccountId:(NSString*) accountId;

#pragma mark Jingle VOIP

/**
 Call a contact from an account
 */
-(void) callContact:(NSDictionary*) contact;

/**
 hangup on a contact from an account
 */
-(void) hangupContact:(NSDictionary*) contact;

/**
 Checks if there are any enabled acconts and connects them if necessary.
 */
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo isMUC:(BOOL) isMUC messageId:(NSString *) messageId withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion;

#pragma mark XMPP settings

-(void) setStatusMessage:(NSString*) message;

-(void) setAway:(BOOL) isAway;
-(void) setVisible:(BOOL) isVisible;

-(void) setPriority:(NSInteger) priority;

#if TARGET_OS_IPHONE
@property (nonatomic, weak) ContactsViewController* contactVC;
#else
@property (nonatomic, weak) MLContactsViewController* contactVC;
#endif

@property (nonatomic, strong, readonly) NSMutableArray* connectedXMPP;

/**
 updates unread
 */
-(void) handleNewMessage:(NSNotification *)notification;

-(void) setKeepAlivetimer;
-(void) clearKeepAlive;

-(void) resetForeground;

/**
 updates delivery status after message has been sent
 */
-(void) handleSentMessage:(NSNotification *)notification;



@end
