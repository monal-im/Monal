//
//  MLXMPPManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <Foundation/Foundation.h>
#import "xmpp.h"
#import "ContactsViewController.h"
#import "Reachability.h"


#define kMonalNetQueue "im.monal.netQueue"

/**
 A singleton to control all of the active XMPP connections
 */
@interface MLXMPPManager : NSObject
{
    NSArray* _accountList;
    dispatch_queue_t _netQueue ;
    NSMutableArray* _connectedXMPP;
    
}

+ (MLXMPPManager* )sharedInstance;

/**
 Checks if there are any enabled acconts and connects them if necessary.  
 */
-(void)connectIfNecessary;

/**
 Checks if there are any enabled acconts and connects them if necessary.
 */
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo withCompletionHandler:(void (^)(BOOL success)) completion;

/**
convenience functin getting account in array with account number/id matching
 */
-(xmpp*) getAccountForID:(NSString*) accountNo;

@property (nonatomic, weak) ContactsViewController* contactVC;

@end
