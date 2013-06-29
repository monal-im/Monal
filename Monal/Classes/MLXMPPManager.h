//
//  MLXMPPManager.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <Foundation/Foundation.h>

/**
 A manager to control all of the active XMPP connections
 */
@interface MLXMPPManager : NSObject
{
    NSArray* _accountList;
}

+ (MLXMPPManager* )sharedInstance;

/**
 Checks if there are any enabled acconts and connects them if necessary.  
 */
-(void)connectIfNecessary;

@end
