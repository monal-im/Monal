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
    NSArray* _accountList;
    dispatch_queue_t _netQueue ;
    NSMutableArray* _connectedXMPP;
    dispatch_source_t _pinger;
    
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
 Checks if there are any enabled acconts and connects them if necessary.
 */
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo withCompletionHandler:(void (^)(BOOL success)) completion;

#pragma mark XMPP settings

-(void) setStatusMessage:(NSString*) message;

-(void) setAway:(BOOL) isAway;
-(void) setVisible:(BOOL) isVisible;

-(void) setPriority:(NSInteger) priority;

@property (nonatomic, weak) ContactsViewController* contactVC;

@end
