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
    
    _connectedXMPP=[[NSMutableArray alloc] init];
    _netQueue = dispatch_queue_create(kMonalNetQueue, DISPATCH_QUEUE_CONCURRENT);
    return self; 
}

-(xmpp*) getAccountForID:(NSString*) accountNo
{
    for (NSDictionary* account in _connectedXMPP)
    {
        xmpp* xmppAccount=[account objectForKey:@"xmppAccount"];
        
        if([xmppAccount.accountNo isEqualToString:accountNo] )
       {
           return xmppAccount;
       }
    }
    return nil; 
}


#pragma mark XMPP communication
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo withCompletionHandler:(void (^)(BOOL success)) completion
{
    dispatch_async(_netQueue,
                   ^{
                       BOOL success=NO;
                       xmpp* account=[self getAccountForID:accountNo];
                       if(account)
                       {
                          success=YES;
                        [account sendMessage:message toContact:contact];
                       }
                       
                       
                       if(completion)
                           completion(success);
                   });
}


#pragma mark Connection related
-(void)connectIfNecessary
{

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
            xmppAccount.domain=[account objectForKey:@"domain"];
            xmppAccount.resource=[account objectForKey:@"resource"];
      
            xmppAccount.server=[account objectForKey:@"server"];
            xmppAccount.port=[[account objectForKey:@"other_port"] integerValue];
            xmppAccount.SSL=[[account objectForKey:@"secure"] boolValue];
            xmppAccount.oldStyleSSL=[[account objectForKey:@"oldStyleSSL"] boolValue];
            xmppAccount.selfSigned=[[account objectForKey:@"selfsigned"] boolValue];
            
            xmppAccount.accountNo=[NSString stringWithFormat:@"%@",[account objectForKey:@"account_id"]];
            
            PasswordManager* passMan= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",[account objectForKey:@"account_id"]]];
            xmppAccount.password=[passMan getPassword] ;
            
            if(([xmppAccount.password length]==0) //&& ([tempPass length]==0)
               )
            {
                // no password error
            }
          
            xmppAccount.contactsVC=self.contactVC;
            //sepcifically look for the server since we might not be online or behind firewall
            Reachability* hostReach = [Reachability reachabilityWithHostName:xmppAccount.server ] ;
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged) name:kReachabilityChangedNotification object:nil];
            [hostReach startNotifier];
            
            NSDictionary* accountRow= [[NSDictionary alloc] initWithObjects:@[xmppAccount, hostReach] forKeys:@[@"xmppAccount", @"hostReach"]];
            [_connectedXMPP addObject:accountRow];
            
            dispatch_async(_netQueue,
                   ^{
                       [xmppAccount connect];
                       [[NSRunLoop currentRunLoop]run];

                   });

        
        }
    }
}

-(void) reachabilityChanged
{
    
    for (NSDictionary* row in _connectedXMPP)
    {
    Reachability* hostReach=[row objectForKey:@"hostReach"];
    xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
    if([hostReach currentReachabilityStatus]==NotReachable)
    {
        debug_NSLog(@"not reachable");
       
        if(xmppAccount.loggedIn==YES)
        {
        debug_NSLog(@"logging out");
        dispatch_async(_netQueue,
                       ^{
        [xmppAccount disconnect];
                       });
        }
    }
    else
    {
        debug_NSLog(@"reachable");
        if(xmppAccount.disconnected==YES)
        {
            debug_NSLog(@"logging in");
            dispatch_async(_netQueue,
                           ^{
            [xmppAccount connect];
            [[NSRunLoop currentRunLoop]run];
                           });
        }
        
    }
    }
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter]  removeObserver:self];
}

@end

