//
//  MLXMPPManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <Foundation/Foundation.h>
#import "ContactsViewController.h"
#import "Reachability.h"


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
Returns the name of the conencted account 
 */
-(NSString*) getNameForConnectedRow:(NSInteger) row;


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
-(void)  joinRoom:(NSString*) roomName  withPassword:(NSString*) password ForAccountRow:(NSInteger) row;

/**
 leave the specific room for accont
 */
-(void)  leaveRoom:(NSString*) roomName ForAccountRow:(NSInteger) row;


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
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo isMUC:(BOOL) isMUC withCompletionHandler:(void (^)(BOOL success)) completion;

#pragma mark XMPP settings

-(void) setStatusMessage:(NSString*) message;

-(void) setAway:(BOOL) isAway;
-(void) setVisible:(BOOL) isVisible;

-(void) setPriority:(NSInteger) priority;

@property (nonatomic, weak) ContactsViewController* contactVC;
@property (nonatomic, strong, readonly) NSMutableArray* connectedXMPP;

/**
 updates unread
 */
-(void) handleNewMessage:(NSNotification *)notification;

-(void) setKeepAlivetimer;
-(void) clearKeepAlive; 

@end
