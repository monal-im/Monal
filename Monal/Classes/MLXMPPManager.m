//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import "MLXMPPManager.h"
#import "DataLayer.h"

#import "MLMessageProcessor.h"
#import "ParseMessage.h"

#if TARGET_OS_IPHONE
#import "MonalAppDelegate.h"
@import MobileCoreServices;
#endif

#import "SAMKeychain.h"

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

#if TARGET_OS_IPHONE
static const int pingFreqencyMinutes =10;
#else
static const int pingFreqencyMinutes =3;
#endif

static const int sendMessageTimeoutSeconds =10;

NSString *const kXmppAccount= @"xmppAccount";

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
        [[NSUserDefaults standardUserDefaults] setObject:@"50" forKey:@"XMPPPriority"];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"Away"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Visible"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MusicStatus"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Sound"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MessagePreview"];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"Logging"];

        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"OfflineContact"];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"SortContacts"];

        [[NSUserDefaults standardUserDefaults] setObject:[[NSUUID UUID] UUIDString] forKey:@"DeviceUUID"];

        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SetDefaults"];

        [[NSUserDefaults standardUserDefaults] setBool:YES  forKey: @"ShowImages"];
        [[NSUserDefaults standardUserDefaults] setBool:YES  forKey: @"ChatBackgrounds"];

        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    //on upgrade this one needs to be set to yes. Can be removed later.
    NSNumber *imagesTest= [[NSUserDefaults standardUserDefaults] objectForKey: @"ShowImages"];

    if(!imagesTest)
    {
          [[NSUserDefaults standardUserDefaults] setBool:YES  forKey: @"ShowImages"];
          [[NSUserDefaults standardUserDefaults] synchronize];
    }

    //upgrade
    NSNumber *background =   [[NSUserDefaults standardUserDefaults] objectForKey: @"ChatBackgrounds"];
    if(!background)
    {
        [[NSUserDefaults standardUserDefaults] setBool:YES  forKey: @"ChatBackgrounds"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    NSNumber *sounds =  [[NSUserDefaults standardUserDefaults] objectForKey: @"AlertSoundFile"];
    if(!sounds)
    {
        [[NSUserDefaults standardUserDefaults] setObject:@"alert2" forKey:@"AlertSoundFile"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

     NSNumber *priority =  [[NSUserDefaults standardUserDefaults] objectForKey: @"XMPPPriority"];

    if(priority.integerValue==0) {
        [[NSUserDefaults standardUserDefaults] setObject:@"50" forKey:@"XMPPPriority"];
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
        for(NSDictionary* row in self->_connectedXMPP)
        {
            xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
            if(xmppAccount.accountState>=kStateBound) {
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

     [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(autoJoinRoom:) name:kMLHasConnectedNotice object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sendOutbox:) name:kMLHasConnectedNotice object:nil];


    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter]  removeObserver:self];
    if(_pinger)
        dispatch_source_cancel(_pinger);
}



#pragma mark - client state

-(void) setClientsInactive {
    for(NSDictionary* row in _connectedXMPP)
    {
        xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
        if(xmppAccount.supportsClientState && xmppAccount.accountState>=kStateLoggedIn) {
            [xmppAccount sendLastAck:NO];
            [xmppAccount setClientInactive];
        }
    }
}

-(void) setClientsActive {
    for(NSDictionary* row in _connectedXMPP)
    {
        xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
        if(xmppAccount.supportsClientState && xmppAccount.accountState>=kStateLoggedIn) {
            [xmppAccount setClientActive];
        }

        if(xmppAccount.accountState>=kStateLoggedIn)
        {
            [xmppAccount sendPing];
        }
        else  {
            [xmppAccount reconnect];
        }
    }
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
    if(account.accountState>=kStateBound) return YES;

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

#pragma mark - Connection related

-(void) connectAccount:(NSString*) accountNo
{
    [[DataLayer sharedInstance] accountListWithCompletion:^(NSArray *result) {
        dispatch_async(self->_netQueue, ^{
            self->_accountList=result;
            for (NSDictionary* account in self->_accountList)
            {
                if([[account objectForKey:kAccountID] integerValue]==[accountNo integerValue])
                {
                    [self connectAccountWithDictionary:account];
                    break;
                }
            }
        });

    }];
}

-(void) connectAccountWithDictionary:(NSDictionary*)account
{
    xmpp* existing=[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];
    if(existing)
    {
         DDLogVerbose(@"existing account just reconnecitng.");
        existing.explicitLogout=NO;
        [existing reconnect:0];

        return;
    }
    DDLogVerbose(@"connecting account %@",[account objectForKey:kAccountName] );

    xmpp* xmppAccount=[[xmpp alloc] init];
    xmppAccount.explicitLogout=NO;
    xmppAccount.pushNode=self.pushNode;
    xmppAccount.pushSecret=self.pushSecret;

    xmppAccount.username=[account objectForKey:kUsername];
    xmppAccount.domain=[account objectForKey:kDomain];

    xmppAccount.resource=[account objectForKey:kResource];

    xmppAccount.server=[account objectForKey:kServer];
    xmppAccount.port=[[account objectForKey:kPort] integerValue];
    xmppAccount.SSL=[[account objectForKey:kSSL] boolValue];
    xmppAccount.oldStyleSSL=[[account objectForKey:kOldSSL] boolValue];
    xmppAccount.selfSigned=[[account objectForKey:kSelfSigned] boolValue];
    xmppAccount.oAuth=[[account objectForKey:kOauth] boolValue];
    xmppAccount.airDrop=[[account objectForKey:kAirdrop] boolValue];
    if(xmppAccount.oldStyleSSL && !xmppAccount.SSL ) xmppAccount.SSL=YES; //tehcnically a config error but  understandable

    xmppAccount.accountNo=[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]];

    xmppAccount.password = [SAMKeychain passwordForService:@"Monal" account:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];

    if([xmppAccount.password length]==0 && !xmppAccount.oAuth) //&& ([tempPass length]==0)
    {
        // ask fro temp pass if not oauth
    }

    [xmppAccount setupSignal];

    //sepcifically look for the server since we might not be online or behind firewall
    Reachability* hostReach = [Reachability reachabilityWithHostName:xmppAccount.server ] ;


    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged) name:kReachabilityChangedNotification object:nil];
    [hostReach startNotifier];

    if(xmppAccount && hostReach) {
        NSDictionary* accountDic= [[NSDictionary alloc] initWithObjects:@[xmppAccount, hostReach] forKeys:@[@"xmppAccount", @"hostReach"]];
        [_connectedXMPP addObject:accountDic];
         DDLogVerbose(@"reachability starting reconnect");
        [xmppAccount reconnect:0];
    }

}


-(void) disconnectAccount:(NSString*) accountNo
{

    dispatch_async(dispatch_get_main_queue(), ^{
        int index=0;
        int pos=-1;
        for (NSDictionary* account in self->_connectedXMPP)
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

        if((pos>=0) && (pos<[self->_connectedXMPP count])) {
            [self->_connectedXMPP removeObjectAtIndex:pos];
            DDLogVerbose(@"removed account at pos  %d", pos);
        }
    });

}


-(void)logoutAll
{

    [[DataLayer sharedInstance] accountListWithCompletion:^(NSArray *result) {
        self->_accountList=result;
        for (NSDictionary* account in self->_accountList)
        {
            if([[account objectForKey:@"enabled"] boolValue]==YES)
            {
                [self disconnectAccount:[NSString stringWithFormat:@"%@",[account objectForKey:@ "account_id"]]];

            }
        }
    }];

}

-(void)logoutAllKeepStreamWithCompletion:(void (^)(void))completion
{
    [[DataLayer sharedInstance] accountListWithCompletion:^(NSArray *result) {
        _accountList=result;
        for (NSDictionary* account in _accountList)
        {
            if([[account objectForKey:@"enabled"] boolValue]==YES)
            {

                [_connectedXMPP enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    NSDictionary* account=(NSDictionary *) obj;
                    xmpp* xmppAccount=[account objectForKey:@"xmppAccount"];
                    DDLogVerbose(@"got account and cleaning up.. keeping stream ");
                    if(idx<_connectedXMPP.count){
                        [xmppAccount disconnectToResumeWithCompletion:nil];
                    } else  {
                        [xmppAccount disconnectToResumeWithCompletion:completion];
                    }
                    DDLogVerbose(@"done cleaning up account. ");
                }];

            }
        }
    }];

}


-(void)connectIfNecessary
{

    [[DataLayer sharedInstance] accountListWithCompletion:^(NSArray *result) {
        dispatch_async(self->_netQueue,
                       ^{
                           self->_accountList=result;
                           for (NSDictionary* account in self->_accountList)
                           {
                               if([[account objectForKey:@"enabled"] boolValue]==YES)
                               {
                                   xmpp* existing=[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];
                                   if(existing.accountState<kStateReconnecting){
                                       [self connectAccountWithDictionary:account];
                                   }
                               }
                           }
                       });
    }];

}

-(void) updatePassword:(NSString *) password forAccount:(NSString *) accountNo
{
#if TARGET_OS_IPHONE
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
#endif
     [SAMKeychain setPassword:password forService:@"Monal" account:accountNo];
    xmpp* xmpp =[self getConnectedAccountForID:accountNo];
    xmpp.password=password;

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
            if(xmppAccount.accountState>=kStateBound)
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

            //try to send a ping. if it fails, it will reconnect
            [xmppAccount sendPing];



        }
    }

}


#pragma mark -  XMPP commands
-(void)sendMessage:(NSString*) message toContact:(NSString*)contact fromAccount:(NSString*) accountNo isEncrypted:(BOOL) encrypted isMUC:(BOOL) isMUC  isUpload:(BOOL) isUpload messageId:(NSString *) messageId
withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion
{
    dispatch_async(_netQueue,
                   ^{
                       dispatch_source_t sendTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,self->_netQueue);

                       dispatch_source_set_timer(sendTimer,
                                                 dispatch_time(DISPATCH_TIME_NOW, sendMessageTimeoutSeconds*NSEC_PER_SEC),
                                                  DISPATCH_TIME_FOREVER,
                                                 5ull * NSEC_PER_SEC);

                       dispatch_source_set_event_handler(sendTimer, ^{
                           DDLogError(@"send message  timed out");
                           int counter=0;
                           int removalCounter=-1;
                           for(NSDictionary *dic in  self.timerList) {
                               if([dic objectForKey:kSendTimer] == sendTimer) {
                                   [[DataLayer sharedInstance] setMessageId:[dic objectForKey:kMessageId] delivered:NO];
                                   if(self) { // chekcing for possible zombie
                                       [[NSNotificationCenter defaultCenter] postNotificationName:kMonalSendFailedMessageNotice object:self userInfo:dic];
                                   }
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
                           [account sendMessage:message toContact:contact isMUC:isMUC isEncrypted:encrypted isUpload:isUpload andMessageId:messageId];
                       }

                       if(completion)
                           completion(success, messageId);
                   });
}


#pragma  mark - HTTP upload

-(void)httpUploadJpegData:(NSData*) fileData   toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion{

    NSString *fileName = [NSString stringWithFormat:@"%@.jpg",[NSUUID UUID].UUIDString];

    //get file type
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)@"jpg", NULL);
    NSString *mimeType = (__bridge NSString *)(UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType));

    [self httpUploadData:fileData withFilename:fileName andType:mimeType toContact:contact onAccount:accountNo withCompletionHandler:completion];

}

-(void)httpUploadFileURL:(NSURL*) fileURL  toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion{

    //get file name
    NSString *fileName =  fileURL.pathComponents.lastObject;

    //get file type
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)fileURL.pathExtension, NULL);
    NSString *mimeType = (__bridge NSString *)(UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType));

    //get data
    NSData *fileData = [[NSData alloc] initWithContentsOfURL:fileURL];

    [self httpUploadData:fileData withFilename:fileName andType:mimeType toContact:contact onAccount:accountNo withCompletionHandler:completion];

}


-(void)httpUploadData:(NSData *)data withFilename:(NSString*) filename andType:(NSString*)contentType  toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion
{
    if(!data || !filename || !contentType || !contact || !accountNo)
    {
        NSError *error = [NSError errorWithDomain:@"Empty" code:0 userInfo:@{}];
        if(completion) completion(nil, error);
        return;
    }

    xmpp* account=[self getConnectedAccountForID:accountNo];
    if(account)
    {
        NSDictionary *params =@{kData:data,kFileName:filename, kContentType:contentType, kContact:contact};
        [account requestHTTPSlotWithParams:params andCompletion:completion];
    }


}


#pragma mark - getting details

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


#pragma mark - contact

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

-(void) getVCard:(NSDictionary *) contact
{
    xmpp* account =[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[contact objectForKey:kAccountID]]];
    [account getVCard:[contact objectForKey:@"buddy_name"]];
}

#pragma mark - MUC commands
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

-(void)  joinRoom:(NSString*) roomName  withNick:(NSString *)nick andPassword:(NSString*) password forAccounId:(NSInteger) accountId
{
    xmpp* account= [self getConnectedAccountForID:[NSString stringWithFormat:@"%ld",accountId]];
    [account joinRoom:roomName withNick:nick andPassword:password];

}




-(void)  joinRoom:(NSString*) roomName  withNick:(NSString *)nick andPassword:(NSString*) password forAccountRow:(NSInteger) row
{
    if(row<[_connectedXMPP count] && row>=0) {
        NSDictionary* datarow= [_connectedXMPP objectAtIndex:row];
        xmpp* account= (xmpp*)[datarow objectForKey:@"xmppAccount"];
        [account joinRoom:roomName withNick:nick andPassword:password];
    }
}

-(void)  leaveRoom:(NSString*) roomName withNick:(NSString *) nick forAccountId:(NSString*) accountId
{
    xmpp* account= [self getConnectedAccountForID:accountId];
    [account leaveRoom:roomName withNick:nick];
    [[DataLayer sharedInstance] removeBuddy:roomName forAccount:accountId];
}

-(void) autoJoinRoom:(NSNotification *) notification
{
    NSDictionary *dic = notification.object;

    [[DataLayer sharedInstance] mucFavoritesForAccount:[dic objectForKey:@"AccountNo"] withCompletion:^(NSMutableArray *results) {

        for(NSDictionary *row in results)
        {
            NSNumber *autoJoin =[row objectForKey:@"autojoin"] ;
            if(autoJoin.boolValue) {
                [self joinRoom:[row objectForKey:@"room"] withNick:[row objectForKey:@"nick"] andPassword:[row objectForKey:@""] forAccounId:[[row objectForKey:@"account_id"] integerValue]];
            }
        }

    }];
}

#pragma mark - Jingle VOIP
-(void) callContact:(NSDictionary*) contact
{
    xmpp* account =[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[contact objectForKey:kAccountID]]];
    [account call:contact];
}


-(void) hangupContact:(NSDictionary*) contact
{
    xmpp* account =[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[contact objectForKey:kAccountID]]];
    [account hangup:contact];
}

-(void) handleCall:(NSDictionary *) userDic withResponse:(BOOL) accept
{
    //find account
     xmpp* account =[self getConnectedAccountForID:[NSString stringWithFormat:@"%@",[userDic objectForKey:kAccountID]]];

    if(accept) {
        [account acceptCall:userDic];
    }
    else  {
         [account declineCall:userDic];
    }

}


#pragma mark - XMPP settings

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
    dispatch_async(dispatch_get_main_queue(), ^{
    MonalAppDelegate* appDelegate= (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
    [appDelegate updateUnread];
    });
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

-(void) cleanArrayOfConnectedAccounts:(NSMutableArray *)dirtySet
{
    //yes, this is ineffecient but the size shouldnt ever be huge
    NSMutableIndexSet *indexSet=[[NSMutableIndexSet alloc] init];
    for(NSDictionary *account in self.connectedXMPP)
    {
        xmpp *xmppAccount = [account objectForKey:@"xmppAccount"];
        NSInteger pos=0;
        for(NSDictionary *dic in dirtySet)
        {
            if([[dic objectForKey:kContactName] isEqualToString:xmppAccount.fulluser] )
            {
                [indexSet addIndex:pos];
            }
            pos++;
        }

    }

    [dirtySet removeObjectsAtIndexes:indexSet];
}


#pragma mark - APNS

-(void) setPushNode:(NSString *)node andSecret:(NSString *)secret
{
    self.pushNode=node;
    self.pushSecret=secret;

    [[NSUserDefaults standardUserDefaults] setObject:node forKey:@"pushNode"];
    [[NSUserDefaults standardUserDefaults] setObject:secret forKey:@"pushSecret"];

    for(NSDictionary  *row in _connectedXMPP)
    {
        xmpp* xmppAccount=[row objectForKey:@"xmppAccount"];
        xmppAccount.pushNode=node;
        xmppAccount.pushSecret=secret;
        [xmppAccount enablePush];
    }
}

#pragma mark - share sheet added

-(void) sendOutbox: (NSNotification *) notification {
    NSDictionary *dic = notification.object;
    NSString *account= [dic objectForKey:@"AccountNo"];

    [self sendOutboxForAccount:account];
}


- (void) sendOutboxForAccount:(NSString *) account{
    NSUserDefaults *groupDefaults= [[NSUserDefaults alloc] initWithSuiteName:@"group.monal"];
    NSMutableArray *outbox=[[groupDefaults objectForKey:@"outbox"] mutableCopy];
    NSMutableArray *outboxClean=[[groupDefaults objectForKey:@"outbox"] mutableCopy];

    for (NSDictionary *row in outbox)
    {
        NSDictionary *accountDic = [row objectForKey:@"account"] ;
        if([[accountDic objectForKey:@"account_id"] integerValue] == [account integerValue])
        {
            NSString* msgid=[[NSUUID UUID] UUIDString];
            [[DataLayer sharedInstance] addMessageHistoryFrom:[NSString stringWithFormat:@"%@", [accountDic objectForKey:@"account_id"]] to:[row objectForKey:@"recipient"] forAccount:[accountDic objectForKey:@"account_id"] withMessage:[row objectForKey:@"url"]  actuallyFrom:[NSString stringWithFormat:@"%@", [accountDic objectForKey:@"account_id"]]  withId:msgid encrypted:NO withCompletion:^(BOOL success, NSString *messageType) {

            }];

            [self sendMessage:[row objectForKey:@"url"] toContact:[row objectForKey:@"recipient"] fromAccount:[NSString stringWithFormat:@"%@", [accountDic objectForKey:@"account_id"]]  isEncrypted:NO isMUC:NO  isUpload:NO messageId:msgid withCompletionHandler:^(BOOL success, NSString *messageId) {

                if(success) {
                    if(((NSString *)[row objectForKey:@"comment"]).length>0) {
                        [self sendMessage:[row objectForKey:@"comment"] toContact:[row objectForKey:@"recipient"]  fromAccount:[NSString stringWithFormat:@"%@", [accountDic objectForKey:@"account_id"]]  isEncrypted:NO isMUC:NO isUpload:YES messageId:[[NSUUID UUID] UUIDString] withCompletionHandler:^(BOOL success, NSString *messageId) {

                        }];
                    }
                    [outboxClean removeObject:row];
                       [groupDefaults setObject:outboxClean forKey:@"outbox"];
                }
            }];
        }
    }


}

-(void) sendMessageForConnectedAccounts
{
    for (NSDictionary* account in _connectedXMPP)
    {
         xmpp* xmppAccount=[account objectForKey:@"xmppAccount"];
        [self sendOutboxForAccount:xmppAccount.accountNo];
    }
}


#pragma mark - handling air drop
-(void) parseMessageForData:(NSData *) data
{
    //parse message
    ParseMessage *messageNode = [[ParseMessage alloc] initWithData:data];
    NSArray *cleanParts= [messageNode.to componentsSeparatedByString:@"/"];
    NSString *jid= cleanParts[0];

    NSArray *parts =[jid componentsSeparatedByString:@"@"];
    NSString* user =parts[0];

    if(parts.count>1){
        NSString *domain= parts[1];

        [[DataLayer sharedInstance] accountForUser:user andDomain:domain withCompletion:^(NSString *accountNo) {
            if(accountNo) {
                dispatch_async(dispatch_get_main_queue(), ^{

                    MLSignalStore *monalSignalStore = [[MLSignalStore alloc] initWithAccountId:accountNo];

                    //signal store
                    SignalStorage *signalStorage = [[SignalStorage alloc] initWithSignalStore:monalSignalStore];
                    //signal context
                    SignalContext *signalContext= [[SignalContext alloc] initWithStorage:signalStorage];

                    //process message
                    MLMessageProcessor *messageProcessor = [[MLMessageProcessor alloc] initWithAccount:accountNo jid:jid signalContex:signalContext andSignalStore:monalSignalStore];
                    messageProcessor.postPersistAction = ^(BOOL success, BOOL encrypted, BOOL showAlert,  NSString *body, NSString *newMessageType) {
                        if(success)
                        {
                            [[DataLayer sharedInstance] addActiveBuddies:messageNode.from forAccount:accountNo withCompletion:nil];

                            if(messageNode.from  ) {
                                NSString* actuallyFrom= messageNode.actualFrom;
                                if(!actuallyFrom) actuallyFrom=messageNode.from;

                                NSString* messageText=messageNode.messageText;
                                if(!messageText) messageText=@"";

                                BOOL shouldRefresh = NO;
                                if(messageNode.delayTimeStamp)  shouldRefresh =YES;

                                NSArray *jidParts= [jid componentsSeparatedByString:@"/"];

                                NSString *recipient;
                                if([jidParts count]>1) {
                                    recipient= jidParts[0];
                                }

                                NSDictionary* userDic=@{@"from":messageNode.from,
                                                        @"actuallyfrom":actuallyFrom,
                                                        @"messageText":body,
                                                        @"to":messageNode.to?messageNode.to:recipient,
                                                        @"messageid":messageNode.idval?messageNode.idval:@"",
                                                        @"accountNo":accountNo,
                                                        @"showAlert":[NSNumber numberWithBool:showAlert],
                                                        @"shouldRefresh":[NSNumber numberWithBool:shouldRefresh],
                                                        @"messageType":newMessageType?newMessageType:kMessageTypeText,
                                                        @"muc_subject":messageNode.subject?messageNode.subject:@"",
                                                        @"encrypted":[NSNumber numberWithBool:encrypted],
                                                        @"delayTimeStamp":messageNode.delayTimeStamp?messageNode.delayTimeStamp:@""
                                                        };

                                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalNewMessageNotice object:self userInfo:userDic];
                            }
                        }
                        else {
                            DDLogError(@"error adding message from data");
                        }
                    };
                    [messageProcessor processMessage:messageNode];

                });
            }
        }];
    }
}

@end
