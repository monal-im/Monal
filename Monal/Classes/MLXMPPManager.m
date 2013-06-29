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

-(id) init
{
    self=[super init];
    _netQueue = dispatch_queue_create(kMonalNetQueue, DISPATCH_QUEUE_CONCURRENT);
    return self; 
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
            
            if([[account objectForKey:@"password"] isEqualToString:@""])
                {
                    //need to request a password
                }
            
        xmpp* xmppAccount=[[xmpp alloc] init];
            
            xmppAccount.username=[account objectForKey:@"username"];
            xmppAccount.password=[account objectForKey:@"password"];
            xmppAccount.domain=[account objectForKey:@"domain"];
            xmppAccount.resource=[account objectForKey:@"resource"];
      
            xmppAccount.server=[account objectForKey:@"server"];
            xmppAccount.port=[[account objectForKey:@"other_port"] integerValue];
            xmppAccount.SSL=[[account objectForKey:@"secure"] boolValue];
            dispatch_async(_netQueue,
                   ^{
                       [xmppAccount connect];
                       [[NSRunLoop currentRunLoop]run];

                   });

        
        }
    }
}


@end

