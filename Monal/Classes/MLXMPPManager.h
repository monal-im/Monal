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
    dispatch_queue_t _connectedListQueue ;
    NSMutableArray* _connectedXMPP;
    
}

+ (MLXMPPManager* )sharedInstance;

/**
 Checks if there are any enabled acconts and connects them if necessary.  
 */
-(void)connectIfNecessary;

/**
 logout all accounts
 */
-(void)logoutAll;

/**
 Checks if there are any enabled acconts and connects them if necessary.
 */
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo withCompletionHandler:(void (^)(BOOL success)) completion;


/**
 disconnects the specified account
 */
-(void) disconnectAccount:(NSString*) accountNo;

/**
 connects the specified account
 */
-(void) connectAccount:(NSString*) accountNo;



@property (nonatomic, weak) ContactsViewController* contactVC;

@end
