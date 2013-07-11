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
 A manager to control all of the active XMPP connections
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

@property (nonatomic, weak) ContactsViewController* contactVC;

@end
