//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import "MLXMPPManager.h"
#import "DataLayer.h"
#import "xmpp.h"


@interface MLXMPPManager()
/**
 convenience functin getting account in connected array with account number/id matching
 */
-(xmpp*) getConnectedAccountForID:(NSString*) accountNo;
@end


@implementation MLXMPPManager

-(void) defaultSettings
{
    BOOL setDefaults =[[NSUserDefaults standardUserDefaults] boolForKey:@"SetDefaults"];
    if(!setDefaults)
    {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"Away"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Visible"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MusicStatus"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Sound"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MessagePreview"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Logging"];
        
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"OfflineContact"];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"SortContacts"];
        
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SetDefaults"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

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
    _connectedListQueue = dispatch_queue_create(kMonalConnectedListQueue, DISPATCH_QUEUE_SERIAL);
   
//    NSTimeInterval timeInterval= 600; // 600 seconds
//    BOOL keepAlive=[[UIApplication sharedApplication] setKeepAliveTimeout:timeInterval handler:^{
//        debug_NSLog(@"began background ping");
//        for(NSDictionary* row in _connectedXMPP)
//        {
//             xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
//            if(xmppAccount.loggedIn)
//                [xmppAccount sendWhiteSpacePing];
//        }
//        
//    }];
//    
//    if(keepAlive)
//    {
//        debug_NSLog(@"installed keep alive timer");
//    }
//    else
//    {
//         debug_NSLog(@"failed to install keep alive timer");
//    }
//    
    [self defaultSettings];

    //set up regular ping
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _pinger = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                     q_background);
     
    dispatch_source_set_timer(_pinger,
                              DISPATCH_TIME_NOW,
                              60ull * NSEC_PER_SEC *5
                              , 1ull * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(_pinger, ^{
         
        
        for(NSDictionary* row in _connectedXMPP)
        {
            xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
            if(xmppAccount.loggedIn)
                [xmppAccount sendPing];
        }
       
    });
    
    dispatch_source_set_cancel_handler(_pinger, ^{
        NSLog(@"pinger canceled");
        dispatch_release(_pinger);
    });
    
    dispatch_resume(_pinger);
    
    
  
    
    return self;
}



-(xmpp*) getConnectedAccountForID:(NSString*) accountNo
{
    
    __block xmpp* toReturn=nil;
    dispatch_sync(_connectedListQueue, ^{
        for (NSDictionary* account in _connectedXMPP)
        {
            xmpp* xmppAccount=[account objectForKey:@"xmppAccount"];
            
            if([xmppAccount.accountNo isEqualToString:accountNo] )
            {
                toReturn= xmppAccount;
            }
        }
    });
    return toReturn;
}

#pragma mark Connection related

-(void) connectAccount:(NSString*) accountNo
{
    dispatch_async(_netQueue, ^{

     _accountList=[[DataLayer sharedInstance] accountList];
    for (NSDictionary* account in _accountList)
    {
        if([[account objectForKey:@"account_id"] integerValue]==[accountNo integerValue])
        {
              [self connectAccountWithDictionary:account];
        }
    }
        
       });
}

-(void) connectAccountWithDictionary:(NSDictionary*)account
{
    xmpp* existing=[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[account objectForKey:@"account_id"]]];
    if(existing)
    {
        if(!existing.loggedIn && !existing.logInStarted)
            dispatch_async(_netQueue,
                           ^{
                               [existing connect];
                           });
        
        return;
    }
    debug_NSLog(@"connecting account %@",[account objectForKey:@"account_name"] )
    
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
    dispatch_sync(_connectedListQueue, ^{
        [_connectedXMPP addObject:accountRow];
    });
        
        dispatch_async(_netQueue,
                       ^{
                           [xmppAccount connect];
                           
                           
                       });
    
    
}


-(void) disconnectAccount:(NSString*) accountNo
{
    dispatch_async(_netQueue, ^{
        dispatch_sync(_connectedListQueue, ^{
            int index=0;
            int pos;
            for (NSDictionary* account in _connectedXMPP)
            { 
                xmpp* xmppAccount=[account objectForKey:@"xmppAccount"];
                if([xmppAccount.accountNo isEqualToString:accountNo] )
                {
                    debug_NSLog(@"got acct cleaning up.. ");
                    Reachability* hostReach=[account objectForKey:@"hostReach"];
                    [hostReach stopNotifier];
                    [ xmppAccount disconnect];
                    debug_NSLog(@"done cleaning up account ");
                    pos=index;
                    break;
                }
                index++;
            }
            
            if((pos>=0) && (pos<[_connectedXMPP count]))
                [_connectedXMPP removeObjectAtIndex:pos];

        });
    });
}





-(void)logoutAll
{
    
    _accountList=[[DataLayer sharedInstance] accountList];
    for (NSDictionary* account in _accountList)
    {
        if([[account objectForKey:@"enabled"] boolValue]==YES)
        {
            [self disconnectAccount:[NSString stringWithFormat:@"%@",[account objectForKey:@ "account_id"]]];
            
        }
    }
}

-(void)connectIfNecessary
{

    _accountList=[[DataLayer sharedInstance] accountList];
    for (NSDictionary* account in _accountList)
    {
        if([[account objectForKey:@"enabled"] boolValue]==YES)
        {
            [self connectAccountWithDictionary:account];
        
        }
    }
}

-(void) reachabilityChanged
{
       dispatch_sync(_connectedListQueue, ^{
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
        if((xmppAccount.disconnected==YES) && (!xmppAccount.logInStarted))
        {
            debug_NSLog(@"logging in");
            dispatch_async(_netQueue,
                           ^{
            [xmppAccount connect];
                           });
        }
        
    }
    }
       });
}


#pragma mark XMPP commands
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo withCompletionHandler:(void (^)(BOOL success)) completion
{
    dispatch_async(_netQueue,
                   ^{
                       BOOL success=NO;
                       xmpp* account=[self getConnectedAccountForID:accountNo];
                       if(account)
                       {
                           success=YES;
                           [account sendMessage:message toContact:contact];
                       }
                       
                       
                       if(completion)
                           completion(success);
                   });
}


-(void) removeContact:(NSDictionary*) contact
{
    NSString* accountNo=[NSString stringWithFormat:@"%@", [contact objectForKey:@"account_id"]];
    xmpp* account =[self getConnectedAccountForID:accountNo];
    if( account)
    {
        [account removeFromRoster:[contact objectForKey:@"buddy_name"]];
    }
    
}

-(void) addContact:(NSDictionary*) contact
{
    NSString* accountNo=[NSString stringWithFormat:@"%@", [contact objectForKey:@"account_id"]];
    xmpp* account =[self getConnectedAccountForID:accountNo];
    if( account)
    {
        [account addToRoster:[contact objectForKey:@"buddy_name"]];
    }
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter]  removeObserver:self];
    if(_pinger)
        dispatch_source_cancel(_pinger);
}

@end

