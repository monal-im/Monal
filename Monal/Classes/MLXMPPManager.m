//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import "MLXMPPManager.h"
#import "DataLayer.h"

@implementation MLXMPPManager


+ (MLXMPPManager* )sharedInstance
{
    static dispatch_once_t once;
    static MLXMPPManager* sharedInstance; 
    dispatch_once(&once, ^{
        sharedInstance = [[MLXMPPManager alloc] init] ;
       
    });
    return sharedInstance;
}

-(void)connectIfNecessary
{
    
//    hostReach = [[Reachability reachabilityWithHostName: @"www.apple.com"] retain];
//	[hostReach startNotifier];
//
    
    _accountList=[[DataLayer sharedInstance] accountList];
    for (NSDictionary* account in _accountList)
    {
        if([[account objectForKey:@"enabled"] boolValue]==YES)
        {
            debug_NSLog(@"enabling account %@",[account objectForKey:@"account_name"] )
        }
    }
}


@end

