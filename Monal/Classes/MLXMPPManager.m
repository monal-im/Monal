//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import "MLXMPPManager.h"
#import "DataLayer.h"


#if TARGET_OS_IPHONE
#import "MonalAppDelegate.h"
#import "PasswordManager.h"
#else
#import "STKeyChain.h"
#endif

static const int ddLogLevel = LOG_LEVEL_VERBOSE;
static const int pingFreqencyMinutes =1;

@interface MLXMPPManager()

/**
 convenience function getting account in connected array with account number/id matching
 */
-(xmpp*) getConnectedAccountForID:(NSString*) accountNo;

/**
An array of Dics what have timers to make sure everything was sent
 */
@property (nonatomic, strong) NSMutableArray *timerList;

@end


@implementation MLXMPPManager

-(void) defaultSettings
{
    BOOL setDefaults =[[NSUserDefaults standardUserDefaults] boolForKey:@"SetDefaults"];
    if(!setDefaults)
    {
        //  [[NSUserDefaults standardUserDefaults] setObject:@"" forKey:@"StatusMessage"]; // we dont want anything set
        [[NSUserDefaults standardUserDefaults] setObject:@"5" forKey:@"XMPPPriority"];
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
   
    _netQueue = dispatch_queue_create(kMonalNetQueue, DISPATCH_QUEUE_SERIAL);
    
    [self defaultSettings];
    
    //set up regular ping
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _pinger = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                     q_background);
    
    dispatch_source_set_timer(_pinger,
                              DISPATCH_TIME_NOW,
                              60ull * NSEC_PER_SEC *pingFreqencyMinutes
                              , 1ull * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(_pinger, ^{
        
        
        for(NSDictionary* row in _connectedXMPP)
        {
            xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
            if(xmppAccount.accountState==kStateLoggedIn) {
                DDLogInfo(@"began a ping");
                [xmppAccount sendPing];
            }
        }
        
    });
    
    dispatch_source_set_cancel_handler(_pinger, ^{
        DDLogInfo(@"pinger canceled");
    });
    
    dispatch_resume(_pinger);
    
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];
    
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter]  removeObserver:self];
    if(_pinger)
        dispatch_source_cancel(_pinger);
}

#pragma mark keep alive


-(void) setKeepAlivetimer
{
    #if TARGET_OS_IPHONE

    NSTimeInterval timeInterval= 600; // 600 seconds
    BOOL keepAlive=[[UIApplication sharedApplication] setKeepAliveTimeout:timeInterval handler:^{
        DDLogInfo(@"began bg keep alive ping");
        for(NSDictionary* row in _connectedXMPP)
        {
            xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
            [xmppAccount sendPing];  //sendWhiteSpacePing
        }
        
    }];
    
    if(keepAlive)
    {
        DDLogVerbose(@"installed keep alive timer");
    }
    else
    {
        DDLogVerbose(@"failed to install keep alive timer");
    }
#else
#endif
}

-(void) clearKeepAlive
{
#if TARGET_OS_IPHONE
    [[UIApplication sharedApplication] clearKeepAliveTimeout];
#else
#endif
    
}


-(void) resetForeground
{
    for(NSDictionary* row in _connectedXMPP)
    {
        xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
        xmppAccount.hasShownAlert=NO;
    }
}

-(BOOL) isAccountForIdConnected:(NSString*) accountNo
{
    xmpp* account = [self getConnectedAccountForID:accountNo];
    if(account.accountState==kStateLoggedIn) return YES;
    
    return NO;
}


-(NSDate *) connectedTimeFor:(NSString*) accountNo
{
    xmpp* account = [self getConnectedAccountForID:accountNo];
    return account.connectedTime;
}

-(xmpp*) getConnectedAccountForID:(NSString*) accountNo
{
    xmpp* toReturn=nil;
    for (NSDictionary* account in _connectedXMPP)
    {
        xmpp* xmppAccount=[account objectForKey:@"xmppAccount"];
        
        if([xmppAccount.accountNo isEqualToString:accountNo] )
        {
            toReturn= xmppAccount;
        }
    }
    return toReturn;
}

#pragma mark Connection related

-(void) connectAccount:(NSString*) accountNo
{
    dispatch_async(_netQueue, ^{
        
        _accountList=[[DataLayer sharedInstance] accountList];
        for (NSDictionary* account in _accountList)
        {
            if([[account objectForKey:kAccountID] integerValue]==[accountNo integerValue])
            {
                [self connectAccountWithDictionary:account];
            }
        }
        
    });
}

-(void) connectAccountWithDictionary:(NSDictionary*)account
{
    xmpp* existing=[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];
    if(existing)
    {
        dispatch_async(_netQueue,
                       ^{
                           existing.explicitLogout=NO;
                           [existing reconnect:0];
                       });
        
        return;
    }
    DDLogVerbose(@"connecting account %@",[account objectForKey:kAccountName] );
    
    xmpp* xmppAccount=[[xmpp alloc] init];
    xmppAccount.explicitLogout=NO;
    
    xmppAccount.username=[account objectForKey:kUsername];
    xmppAccount.domain=[account objectForKey:kDomain];
    xmppAccount.resource=[account objectForKey:kResource];
    
    xmppAccount.server=[account objectForKey:kServer];
    xmppAccount.port=[[account objectForKey:kPort] integerValue];
    xmppAccount.SSL=[[account objectForKey:kSSL] boolValue];
    xmppAccount.oldStyleSSL=[[account objectForKey:kOldSSL] boolValue];
    xmppAccount.selfSigned=[[account objectForKey:kSelfSigned] boolValue];
    xmppAccount.oAuth=[[account objectForKey:kOauth] boolValue];
    
    xmppAccount.accountNo=[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]];
#if TARGET_OS_IPHONE
    if(!xmppAccount.oAuth) {
        PasswordManager* passMan= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@-%@@%@",[account objectForKey:kAccountID], [account objectForKey:kUsername],  [account objectForKey:kDomain] ]];
        xmppAccount.password=[passMan getPassword] ;
        if(!xmppAccount.password.length>0) {
            passMan= [[PasswordManager alloc] init:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];
            xmppAccount.password=[passMan getPassword] ;
        }
    }
    
#else
    NSError *error;
    xmppAccount.password =[STKeychain getPasswordForUsername:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]] andServiceName:@"Monal" error:&error];
    
#endif
 
    
    if([xmppAccount.password length]==0 && !xmppAccount.oAuth) //&& ([tempPass length]==0)
    {
        // ask fro temp pass if not oauth
    }

     xmppAccount.contactsVC=self.contactVC;
    
    //sepcifically look for the server since we might not be online or behind firewall
    Reachability* hostReach = [Reachability reachabilityWithHostName:xmppAccount.server ] ;
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged) name:kReachabilityChangedNotification object:nil];
    [hostReach startNotifier];
    
    if(xmppAccount && hostReach) {
        NSDictionary* accountRow= [[NSDictionary alloc] initWithObjects:@[xmppAccount, hostReach] forKeys:@[@"xmppAccount", @"hostReach"]];
        [_connectedXMPP addObject:accountRow];
        
        
        dispatch_async(_netQueue, ^{
            [xmppAccount reconnect:0];
        });
    }
    
}


-(void) disconnectAccount:(NSString*) accountNo
{
    
    dispatch_async(dispatch_get_main_queue(), ^{
        int index=0;
        int pos=-1;
        for (NSDictionary* account in _connectedXMPP)
        {
            xmpp* xmppAccount=[account objectForKey:@"xmppAccount"];
            if([xmppAccount.accountNo isEqualToString:accountNo] )
            {
                DDLogVerbose(@"got account and cleaning up.. ");
                Reachability* hostReach=[account objectForKey:@"hostReach"];
                [hostReach stopNotifier];
                xmppAccount.explicitLogout=YES;
                [ xmppAccount disconnect];
                DDLogVerbose(@"done cleaning up account ");
                pos=index;
                break;
            }
            index++;
        }
        
        if((pos>=0) && (pos<[_connectedXMPP count])) {
            [_connectedXMPP removeObjectAtIndex:pos];
            DDLogVerbose(@"removed account at pos  %d", pos);
        }
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
            xmpp* existing=[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];
            if(existing.accountState<kStateReconnecting){
                [self connectAccountWithDictionary:account];
            }
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
            DDLogVerbose(@"not reachable");
            if(xmppAccount.accountState==kStateLoggedIn)
            {
                DDLogVerbose(@"There will be a ping soon to test. ");
                
                //dont explicitly disconnect since it might be that there was a network inteepution
                //ie moving through cells.  schedule a ping for 1 min and see if that results in a TCP or XMPP error
                
                
                //                dispatch_async(_netQueue,
                //                               ^{
                //                                  [xmppAccount disconnect];
                //
                //
                //                               });
                
                
            }
        }
        else
        {
            DDLogVerbose(@"reachable");
            DDLogVerbose(@"pinging ");
            dispatch_async(_netQueue,
                           ^{
                               //try to send a ping. if it fails, it will reconnect
                               [xmppAccount sendPing];
                           });
            
            
        }
    }
    
}


#pragma mark XMPP commands
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo isMUC:(BOOL) isMUC messageId:(NSString *) messageId 
withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion
{
    dispatch_async(_netQueue,
                   ^{
                       dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                       dispatch_source_t sendTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,q_background
                                                                              );
                       
                       dispatch_source_set_timer(sendTimer,
                                                 dispatch_time(DISPATCH_TIME_NOW, 5ull * NSEC_PER_SEC),
                                                 1ull * NSEC_PER_SEC
                                                 , 1ull * NSEC_PER_SEC);
                       
                       dispatch_source_set_event_handler(sendTimer, ^{
                           DDLogError(@"send message  timed out");
                           int counter=0;
                           int removalCounter=-1;
                           for(NSDictionary *dic in  self.timerList) {
                               if([dic objectForKey:kSendTimer] == sendTimer) {
                                   [[DataLayer sharedInstance] setMessageId:[dic objectForKey:kMessageId] delivered:NO];
                                   [[NSNotificationCenter defaultCenter] postNotificationName:kMonalSendFailedMessageNotice object:self userInfo:dic];
                                   removalCounter=counter;
                                   break;
                               }
                               counter++;
                           }
                           
                           if(removalCounter>=0) {
                               [self.timerList removeObjectAtIndex:removalCounter];
                           }
                           
                           dispatch_source_cancel(sendTimer);
                       });
                       
                       dispatch_source_set_cancel_handler(sendTimer, ^{
                           DDLogError(@"send message timer cancelled");
                       });
                       
                       dispatch_resume(sendTimer);
                       NSDictionary *dic = @{kSendTimer:sendTimer,kMessageId:messageId};
                       [self.timerList addObject:dic];
                       
                       BOOL success=NO;
                       xmpp* account=[self getConnectedAccountForID:accountNo];
                       if(account)
                       {
                           success=YES;
                         
                           [account sendMessage:message toContact:contact isMUC:isMUC andMessageId:messageId];
                       }
                       
                       if(completion)
                           completion(success, messageId);
                   });
}


#pragma mark getting details

-(void) getServiceDetailsForAccount:(NSInteger) row
{
    
    if(row < [_connectedXMPP count] && row>=0) {
    NSDictionary* datarow= [_connectedXMPP objectAtIndex:row];
    dispatch_async(_netQueue,
                   ^{
                       xmpp* account= (xmpp*)[datarow objectForKey:@"xmppAccount"];
                       if(account)
                       {
                           [account getServiceDetails];
                       }
                   }
                   );
    }
}

-(NSString*) getNameForConnectedRow:(NSInteger) row
{
    NSString *toreturn;
    if(row<[_connectedXMPP count] && row>=0) {
        NSDictionary* datarow= [_connectedXMPP objectAtIndex:row];
        xmpp* account= (xmpp*)[datarow objectForKey:@"xmppAccount"];
        toreturn= [NSString stringWithFormat:@"%@@%@",account.username, account.server];
    }
    return toreturn;
}


-(NSString*) getAccountNameForConnectedRow:(NSInteger) row
{
    NSString *toreturn;
    if(row<[_connectedXMPP count] && row>=0) {
        NSDictionary* datarow= [_connectedXMPP objectAtIndex:row];
        xmpp* account= (xmpp*)[datarow objectForKey:@"xmppAccount"];
        toreturn= [NSString stringWithFormat:@"%@@%@",account.username, account.domain];
    }
    return toreturn;
}


-(NSString*) idForConnectedRow:(NSInteger) row
{
    NSString *toreturn;
    if(row<[_connectedXMPP count] && row>=0) {
        NSDictionary* datarow= [_connectedXMPP objectAtIndex:row];
        toreturn= [datarow objectForKey:@"account_id"];
    }
    return toreturn;
}


#pragma mark contact

-(void) removeContact:(NSDictionary*) contact
{
    NSString* accountNo=[NSString stringWithFormat:@"%@", [contact objectForKey:@"account_id"]];
    xmpp* account =[self getConnectedAccountForID:accountNo];
    if( account)
    {
        //if not MUC
        [account removeFromRoster:[contact objectForKey:@"buddy_name"]];
        //if MUC
        
        //remove from DB
        [[DataLayer sharedInstance] removeBuddy:[contact objectForKey:@"buddy_name"] forAccount:[contact objectForKey:@"account_id"]];
        
    }
    
}

-(void) addContact:(NSDictionary*) contact
{
    NSNumber* row =[contact objectForKey:@"row"];
    NSInteger pos= [row integerValue];
    if(pos<[_connectedXMPP count] && pos>=0) {
        NSDictionary* datarow= [_connectedXMPP objectAtIndex:pos];
        xmpp* account= (xmpp*)[datarow objectForKey:@"xmppAccount"];
        if( account)
        {
            [account addToRoster:[contact objectForKey:@"buddy_name"]];
        }
    }
}

#pragma mark MUC commands
//makes xmpp call
-(void) getRoomsForAccountRow:(NSInteger) row
{
    if(row<[_connectedXMPP count] && row>=0) {
        NSDictionary* datarow= [_connectedXMPP objectAtIndex:row];
        xmpp* account= (xmpp*)[datarow objectForKey:@"xmppAccount"];
        [account getConferenceRooms];
    }
    
}


//exposes list
-(NSArray*) getRoomsListForAccountRow:(NSInteger) row
{
    if(row<[_connectedXMPP count] && row>=0) {
        NSDictionary* datarow= [_connectedXMPP objectAtIndex:row];
        xmpp* account= (xmpp*)[datarow objectForKey:@"xmppAccount"];
        return account.roomList;
    }
    else return  nil;
    
}



-(void)  joinRoom:(NSString*) roomName  withPassword:(NSString*) password forAccountRow:(NSInteger) row
{
    if(row<[_connectedXMPP count] && row>=0) {
        NSDictionary* datarow= [_connectedXMPP objectAtIndex:row];
        xmpp* account= (xmpp*)[datarow objectForKey:@"xmppAccount"];
        [account joinRoom:roomName withPassword:password];
    }
}


-(void)  leaveRoom:(NSString*) roomName forAccountRow:(NSInteger) row
{
    if(row<[_connectedXMPP count] && row>=0) {
        NSDictionary* datarow= [_connectedXMPP objectAtIndex:row];
        xmpp* account= (xmpp*)[datarow objectForKey:@"xmppAccount"];
        [account leaveRoom:roomName];
    }
}

-(void)  leaveRoom:(NSString*) roomName forAccountId:(NSString*) accountId
{
    xmpp* account= [self getConnectedAccountForID:accountId];
    [account leaveRoom:roomName];
}

#pragma mark Jingle VOIP
-(void) callContact:(NSDictionary*) contact
{
    xmpp* account =[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[contact objectForKey:@"account_id"]]];
    [account call:contact];
}


-(void) hangupContact:(NSDictionary*) contact
{
    xmpp* account =[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[contact objectForKey:@"account_id"]]];
    [account hangup:contact];
}


#pragma mark XMPP settings

-(void) setStatusMessage:(NSString*) message
{
    for (NSDictionary* row in _connectedXMPP)
    {
        xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
        [xmppAccount setStatusMessageText:message];
    }
}

-(void) setAway:(BOOL) isAway
{
    for (NSDictionary* row in _connectedXMPP)
    {
        xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
        [xmppAccount setAway:isAway];
    }
}

-(void) setVisible:(BOOL) isVisible
{
    for (NSDictionary* row in _connectedXMPP)
    {
        xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
        [xmppAccount setVisible:isVisible];
    }
}

-(void) setPriority:(NSInteger) priority
{
    for (NSDictionary* row in _connectedXMPP)
    {
        xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
        [xmppAccount updatePriority:priority];
    }
}

#pragma mark message signals
-(void) handleNewMessage:(NSNotification *)notification
{
#if TARGET_OS_IPHONE
    MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
    [appDelegate updateUnread];
    
#else
#endif
}


-(void) handleSentMessage:(NSNotification *)notification
{

    NSDictionary *info = notification.userInfo;
    NSString *messageId = [info objectForKey:kMessageId];
    [[DataLayer sharedInstance] setMessageId:messageId delivered:YES];
    DDLogInfo(@"message %@ sent, removing timer",messageId);
    
    int counter=0;
    int removalCounter=-1;
    for (NSDictionary * dic in self.timerList)
    {
        if([[dic objectForKey:kMessageId] isEqualToString:messageId])
        {
            dispatch_source_t sendTimer = [dic objectForKey:kSendTimer];
            dispatch_source_cancel(sendTimer);
            removalCounter=counter;
            break;
        }
        counter++;
    }
    
    if(removalCounter>=0) {
        [self.timerList removeObjectAtIndex:removalCounter];
    }
}

#pragma mark - properties

-(NSMutableArray *)timerList
{
    if(!_timerList)
    {
        _timerList=[[NSMutableArray alloc] init];
    }
    return  _timerList;
}


@end

