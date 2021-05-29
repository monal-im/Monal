//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <UserNotifications/UserNotifications.h>

#import "MLConstants.h"
#import "MLXMPPManager.h"
#import "DataLayer.h"
#import "HelperTools.h"
#import "xmpp.h"
#import "MLNotificationQueue.h"
#import "MLOMEMO.h"

@import Network;
@import MobileCoreServices;
@import SAMKeychain;

static const int pingFreqencyMinutes = 5;       //about the same Conversations uses

@interface MLXMPPManager()
{
    nw_path_monitor_t _path_monitor;
    BOOL _hasConnectivity;
    NSMutableArray* _connectedXMPP;
}
@end

@implementation MLXMPPManager

-(void) defaultSettings
{
    BOOL setDefaults = [[HelperTools defaultsDB] boolForKey:@"SetDefaults"];
    if(!setDefaults)
    {
        [[HelperTools defaultsDB] setBool:YES forKey:@"Sound"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"ChatBackgrounds"];

        // Privacy Settings
        [[HelperTools defaultsDB] setBool:YES forKey:@"ShowImages"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"ShowGeoLocation"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"SendLastUserInteraction"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"SendLastChatState"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"SendReceivedMarkers"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"SendDisplayedMarkers"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"ShowURLPreview"];

        // Message Settings / Privacy
        [[HelperTools defaultsDB] setInteger:DisplayNameAndMessage forKey:@"NotificationPrivacySetting"];

        // udp logger
        [[HelperTools defaultsDB] setBool:NO forKey:@"udpLoggerEnabled"];
        [[HelperTools defaultsDB] setObject:@"" forKey:@"udpLoggerHostname"];
        [[HelperTools defaultsDB] setObject:@"" forKey:@"udpLoggerPort"];
        [[HelperTools defaultsDB] setObject:@"" forKey:@"udpLoggerKey"];

        [[HelperTools defaultsDB] setBool:YES forKey:@"SetDefaults"];
        [[HelperTools defaultsDB] setBool:YES forKey:@"DefaulsMigratedToAppGroup"];
        [[HelperTools defaultsDB] synchronize];
    }

    // on upgrade this one needs to be set to yes. Can be removed later.
    [self upgradeBoolUserSettingsIfUnset:@"ShowImages" toDefault:YES];

    // upgrade ChatBackgrounds
    [self upgradeBoolUserSettingsIfUnset:@"ChatBackgrounds" toDefault:YES];

    [self upgradeObjectUserSettingsIfUnset:@"AlertSoundFile" toDefault:@"alert2"];

    // upgrade ShowGeoLocation
    [self upgradeBoolUserSettingsIfUnset:@"ShowGeoLocation" toDefault:YES];

    // upgrade SendLastUserInteraction
    [self upgradeBoolUserSettingsIfUnset:@"SendLastUserInteraction" toDefault:YES];

    // upgrade SendLastChatState
    [self upgradeBoolUserSettingsIfUnset:@"SendLastChatState" toDefault:YES];

    // upgrade received and displayed markers
    [self upgradeBoolUserSettingsIfUnset:@"SendReceivedMarkers" toDefault:YES];
    [self upgradeBoolUserSettingsIfUnset:@"SendDisplayedMarkers" toDefault:YES];
    
    //upgrade url preview
    [self upgradeBoolUserSettingsIfUnset:@"ShowURLPreview" toDefault:YES];

    // upgrade udp logger
    [self upgradeBoolUserSettingsIfUnset:@"udpLoggerEnabled" toDefault:NO];
    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerHostname" toDefault:@""];
    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerPort" toDefault:@""];

    // upgrade ASCII wallpaper name
    if([[[HelperTools defaultsDB] stringForKey:@"BackgroundImage"] isEqualToString:@"Tie_My_Boat_by_Ray_García"] || [[HelperTools defaultsDB] stringForKey:@"BackgroundImage"] == nil) {
        [[HelperTools defaultsDB] setObject:@"Tie_My_Boat_by_Ray_Garcia" forKey:@"BackgroundImage"];
    }

    [self upgradeObjectUserSettingsIfUnset:@"udpLoggerKey" toDefault:@""];

    // upgrade Message Settings / Privacy
    [self upgradeIntegerUserSettingsIfUnset:@"NotificationPrivacySetting" toDefault:DisplayNameAndMessage];
    
    // upgrade filetransfer settings
    [self upgradeBoolUserSettingsIfUnset:@"AutodownloadFiletransfers" toDefault:YES];
#ifdef IS_ALPHA
    [self upgradeIntegerUserSettingsIfUnset:@"AutodownloadFiletransfersMaxSize" toDefault:16*1024*1024];    // 16 MiB
#else
    [self upgradeIntegerUserSettingsIfUnset:@"AutodownloadFiletransfersMaxSize" toDefault:5*1024*1024];     // 5 MiB
#endif
    
    //upgrade syncErrorsDisplayed list
    [self upgradeObjectUserSettingsIfUnset:@"syncErrorsDisplayed" toDefault:@{}];

    [self upgradeFloatUserSettingsIfUnset:@"AutodownloadFiletransfersMobileMaxSize" toDefault:5*1024*1024];     // 5 MiB
    [self upgradeFloatUserSettingsIfUnset:@"AutodownloadFiletransfersWifiMaxSize" toDefault:32*1024*1024];     // 32 MiB

    // upgrade default image quality
    [self upgradeFloatUserSettingsIfUnset:@"ImageUploadQuality" toDefault:0.75];
}

-(void) upgradeBoolUserSettingsIfUnset:(NSString*) settingsName toDefault:(BOOL) defaultVal
{
    NSNumber* currentSettingVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingVal == nil)
    {
        [[HelperTools defaultsDB] setBool:defaultVal forKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

-(void) upgradeIntegerUserSettingsIfUnset:(NSString*) settingsName toDefault:(NSInteger) defaultVal
{
    NSNumber* currentSettingVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingVal == nil)
    {
        [[HelperTools defaultsDB] setInteger:defaultVal forKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

-(void) upgradeFloatUserSettingsIfUnset:(NSString*) settingsName toDefault:(float) defaultVal
{
    NSNumber* currentSettingVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingVal == nil)
    {
        [[HelperTools defaultsDB] setFloat:defaultVal forKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

-(void) upgradeObjectUserSettingsIfUnset:(NSString*) settingsName toDefault:(nullable id) defaultVal
{
    NSNumber* currentSettingVal = [[HelperTools defaultsDB] objectForKey:settingsName];
    if(currentSettingVal == nil)
    {
        [[HelperTools defaultsDB] setObject:defaultVal forKey:settingsName];
        [[HelperTools defaultsDB] synchronize];
    }
}

+ (MLXMPPManager*) sharedInstance
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
    self = [super init];

    _connectedXMPP = [[NSMutableArray alloc] init];
    _hasConnectivity = NO;
    _isBackgrounded = NO;
    _isNotInFocus = NO;
    _onMobile = NO;
    
    [self defaultSettings];
    [self setPushToken:nil];       //load push settings from defaultsDB (can be overwritten later on in mainapp, but *not* in appex)

    //set up regular ping
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _pinger = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q_background);

    dispatch_source_set_timer(_pinger,
                              DISPATCH_TIME_NOW,
                              60ull * NSEC_PER_SEC * pingFreqencyMinutes,
                              60ull * NSEC_PER_SEC);        //allow for better battery optimizations

    dispatch_source_set_event_handler(_pinger, ^{
        //only ping when having connectivity
        if(self->_hasConnectivity)
        {
            for(xmpp* xmppAccount in [self connectedXMPP])
            {
                if(xmppAccount.accountState>=kStateBound) {
                    DDLogInfo(@"began a idle ping");
                    [xmppAccount sendPing:LONG_PING];        //long ping timeout because this is a background/interval ping
                }
            }
        }
    });

    dispatch_source_set_cancel_handler(_pinger, ^{
        DDLogInfo(@"pinger canceled");
    });

    dispatch_resume(_pinger);

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];

    //this processes the sharesheet outbox only, the handler in the NotificationServiceExtension will do more interesting things
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(catchupFinished:) name:kMonalFinishedCatchup object:nil];

    _path_monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(_path_monitor, q_background);
    nw_path_monitor_set_update_handler(_path_monitor, ^(nw_path_t path) {
        DDLogVerbose(@"*** nw_path_monitor: update_handler called");
        if(@available(iOS 13.0, *))
        {
            DDLogDebug(@"*** nw_path_monitor: nw_path_is_constrained=%@", nw_path_is_constrained(path) ? @"YES" : @"NO");
            DDLogDebug(@"*** nw_path_monitor: nw_path_is_expensive=%@", nw_path_is_expensive(path) ? @"YES" : @"NO");
            self->_onMobile = nw_path_is_constrained(path) || nw_path_is_expensive(path);
            DDLogDebug(@"*** nw_path_monitor: on 'mobile' --> %@", self->_onMobile ? @"YES" : @"NO");
        }
        if(nw_path_get_status(path) == nw_path_status_satisfied && !self->_hasConnectivity)
        {
            DDLogVerbose(@"reachable");
            self->_hasConnectivity = YES;
            for(xmpp* xmppAccount in [self connectedXMPP])
            {
                if(![HelperTools isAppExtension])
                {
                    //try to send a ping. if it fails, it will reconnect
                    DDLogVerbose(@"manager pinging");
                    [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
                }
                else
                    [xmppAccount reconnect:0];      //try to immediately reconnect, don't bother pinging
            }
        }
        else if(nw_path_get_status(path) != nw_path_status_satisfied && self->_hasConnectivity)
        {
            DDLogVerbose(@"NOT reachable");
            self->_hasConnectivity = NO;
            //we only want to react on connectivity changes if not in NSE because disconnecting would terminate the NSE
            //we want do do "polling" reconnects in NSE instead to make sure we try as long as possible until the NSE times out
            if(![HelperTools isAppExtension])
            {
                BOOL wasIdle = [self allAccountsIdle];      //we have to check that here because disconnect: makes them idle
                [self disconnectAll];
                if(!wasIdle)
                {
                    DDLogVerbose(@"scheduling background fetching task to start app in background once our connectivity gets restored (will be ignored in appex)");
                    //this will automatically start the app if connectivity gets restored
                    //don't queue this notification because it should be handled immediately
                    [[NSNotificationCenter defaultCenter] postNotificationName:kScheduleBackgroundFetchingTask object:nil];
                }
            }
        }
    });
    nw_path_monitor_start(_path_monitor);

    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if(_pinger)
        dispatch_source_cancel(_pinger);
}

//this returns a copy to iterate on without the need of a synchronized block while iterating
-(NSArray*) connectedXMPP
{
    @synchronized(_connectedXMPP) {
        return [[NSArray alloc] initWithArray:_connectedXMPP];
    }
}

-(void) catchupFinished:(NSNotification*) notification
{
    xmpp* account = notification.object;
    DDLogInfo(@"### MAM/SMACKS CATCHUP FINISHED FOR ACCOUNT NO %@ ###", account.accountNo);
    
    //send sharesheet outbox
    [self sendOutboxForAccount:account];
}

-(BOOL) allAccountsIdle
{
    for(xmpp* xmppAccount in [self connectedXMPP])
        if(!xmppAccount.idle)
            return NO;
    return YES;
}

#pragma mark - app state

-(void) nowNoLongerInFocus
{
    _isBackgrounded = NO;
    _isNotInFocus = YES;
}

-(void) nowBackgrounded
{
    _isBackgrounded = YES;
    _isNotInFocus = YES;
    
    for(xmpp* xmppAccount in [self connectedXMPP])
        [xmppAccount setClientInactive];
}

-(void) nowForegrounded
{
    _isBackgrounded = NO;
    _isNotInFocus = NO;
    
    //*** we don't need to check for a running service extension here because the appdelegate does this already for us ***
    
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        [xmppAccount unfreezed];
        if(_hasConnectivity)
            [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        [xmppAccount setClientActive];
    }
}

#pragma mark - Connection related

-(void) rejectContact:(MLContact*) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    [account rejectFromRoster:contact.contactJid];
}

-(void) approveContact:(MLContact*) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    [account approveToRoster:contact.contactJid];
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
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        if([xmppAccount.accountNo isEqualToString:accountNo])
            return xmppAccount;
    }
    return nil;
}

-(void) connectAccount:(NSString*) accountNo
{
    NSDictionary* account = [[DataLayer sharedInstance] detailsForAccount:accountNo];
    if(!account)
        DDLogError(@"Expected account settings in db for accountNo: %@", accountNo);
    else
        [self connectAccountWithDictionary:account];
}

-(void) connectAccountWithDictionary:(NSDictionary*) account
{
    xmpp* existing = [self getConnectedAccountForID:[NSString stringWithFormat:@"%@", [account objectForKey:kAccountID]]];
    if(existing)
    {
        if(![account[@"enabled"] boolValue])
        {
            DDLogInfo(@"existing but disabled account, ignoring");
            return;
        }
        DDLogInfo(@"existing account, calling unfreezed");
        [existing unfreezed];
        DDLogInfo(@"existing account, just pinging.");
        if(_hasConnectivity)
            [existing sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        else
            DDLogWarn(@"NOT pinging because no connectivity.");
        return;
    }
    DDLogVerbose(@"connecting account %@@%@",[account objectForKey:kUsername], [account objectForKey:kDomain]);

    NSError* error;
    NSString *password = [SAMKeychain passwordForService:kMonalKeychainName account:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]] error:&error];
    error = nil;
    if(error)
    {
        DDLogError(@"Keychain error: %@", [NSString stringWithFormat:@"%@", error]);
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:nil];
    }
    MLXMPPIdentity *identity = [[MLXMPPIdentity alloc] initWithJid:[NSString stringWithFormat:@"%@@%@",[account objectForKey:kUsername],[account objectForKey:kDomain] ] password:password andResource:[account objectForKey:kResource]];

    MLXMPPServer *server = [[MLXMPPServer alloc] initWithHost:[account objectForKey:kServer] andPort:[account objectForKey:kPort] andDirectTLS:[[account objectForKey:kDirectTLS] boolValue]];
    xmpp* xmppAccount = [[xmpp alloc] initWithServer:server andIdentity:identity andAccountNo:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];
    xmppAccount.statusMessage = [account objectForKey:@"statusMessage"];

    if(xmppAccount)
    {
        @synchronized(_connectedXMPP) {
            [_connectedXMPP addObject:xmppAccount];
        }

        if(_hasConnectivity)
        {
            if(![account[@"enabled"] boolValue])
            {
                DDLogInfo(@"existing but disabled account, not connecting");
                return;
            }
            DDLogInfo(@"starting connect");
            [xmppAccount connect];
        }
        else
            DDLogWarn(@"NOT connecting because no connectivity.");
    }
}


-(void) disconnectAccount:(NSString*) accountNo
{
    int index=0;
    int pos=-1;
    xmpp* account;
    @synchronized(_connectedXMPP) {
        for(xmpp* xmppAccount in _connectedXMPP)
        {
            if([xmppAccount.accountNo isEqualToString:accountNo] )
            {
                account = xmppAccount;
                pos=index;
                break;
            }
            index++;
        }

        if((pos>=0) && (pos<[_connectedXMPP count]))
        {
            [_connectedXMPP removeObjectAtIndex:pos];
            DDLogVerbose(@"removed account at pos  %d", pos);
        }
    }
    if(account)
    {
        DDLogVerbose(@"got account and cleaning up.. ");
        [account disconnect:YES];
        account = nil;
        DDLogVerbose(@"done cleaning up account ");
    }
}


-(void) reconnectAll
{
    NSArray* allAccounts = [[DataLayer sharedInstance] accountList];        //this will also "disconnect" disabled account, just to make sure
    for(NSDictionary* account in allAccounts)
    {
        DDLogVerbose(@"Forcefully disconnecting account %@ (%@@%@)", [account objectForKey:kAccountID], [account objectForKey:@"username"], [account objectForKey:@"domain"]);
        xmpp* xmppAccount = [self getConnectedAccountForID:[account objectForKey:kAccountID]];
        [xmppAccount disconnect:YES];
    }
    createTimer(1.0, (^{
        [self connectIfNecessary];
    }));
}

-(void) disconnectAll
{
    DDLogVerbose(@"manager disconnecAll");
    for(xmpp* xmppAccount in [self connectedXMPP])
    {
        //disconnect to prevent endless loops trying to connect
        DDLogVerbose(@"manager disconnecting");
        [xmppAccount disconnect];
    }
    DDLogVerbose(@"manager disconnecAll done");
}

-(void) connectIfNecessary
{
    DDLogVerbose(@"manager connectIfNecessary");
    NSArray* enabledAccountList = [[DataLayer sharedInstance] enabledAccountList];
    for(NSDictionary* account in enabledAccountList)
        [self connectAccountWithDictionary:account];
    DDLogVerbose(@"manager connectIfNecessary done");
}

-(void) updatePassword:(NSString*) password forAccount:(NSString*) accountNo
{
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
    [SAMKeychain setPassword:password forService:kMonalKeychainName account:accountNo];
    xmpp* xmpp = [self getConnectedAccountForID:accountNo];
    [xmpp.connectionProperties.identity updatPassword:password];
}

-(BOOL) isValidPassword:(NSString*) password forAccount:(NSString*) accountNo
{
    return [password isEqualToString:[SAMKeychain passwordForService:kMonalKeychainName account:accountNo]];
}

#pragma mark -  XMPP commands
-(void) sendMessageAndAddToHistory:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypted isUpload:(BOOL) isUpload withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion
{
    NSString* msgid = [[NSUUID UUID] UUIDString];
    xmpp* account = [self getConnectedAccountForID:contact.accountId];

    NSAssert(message, @"Message should not be nil");
    NSAssert(account, @"Account should not be nil");
    NSAssert(contact, @"Contact should not be nil");
    
    NSString* messageType = kMessageTypeText;
    if(isUpload)
        messageType = kMessageTypeFiletransfer;
    
    // Save message to history
    NSNumber* messageDBId = [[DataLayer sharedInstance]
        addMessageHistoryTo:contact.contactJid
                   forAccount:contact.accountId
                  withMessage:message
                 actuallyFrom:(contact.isGroup ? contact.accountNickInGroup : account.connectionProperties.identity.jid)
                       withId:msgid
                    encrypted:encrypted
                  messageType:messageType
                     mimeType:nil
                         size:nil
    ];
    // Send message
    if(messageDBId != nil)
    {
        DDLogInfo(@"Message added to history with id %ld, now sending...", (long)[messageDBId intValue]);
        [self sendMessage:message toContact:contact isEncrypted:encrypted isUpload:NO messageId:msgid withCompletionHandler:^(BOOL successSend, NSString *messageIdSend) {
            if(successSend)
                completion(successSend, messageIdSend);
        }];
        DDLogVerbose(@"Notifying active chats of change for contact %@", contact);
        [[MLNotificationQueue currentQueue] postNotificationName:kMLMessageSentToContact object:self userInfo:@{@"contact":contact}];
    }
    else
        DDLogError(@"Could not add message to history!");
}

-(void)sendMessage:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypted isUpload:(BOOL) isUpload messageId:(NSString*) messageId withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion
{
    BOOL success=NO;
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    if(account)
    {
        success=YES;
        [account sendMessage:message toContact:contact isEncrypted:encrypted isUpload:isUpload andMessageId:messageId];
    }

    if(completion)
        completion(success, messageId);
}

-(void) sendChatState:(BOOL) isTyping fromAccount:(NSString*) accountNo toJid:(NSString*) jid
{
    xmpp* account = [self getConnectedAccountForID:accountNo];
    if(account)
        [account sendChatState:isTyping toJid:jid];
}

#pragma mark - getting details

-(NSString*) getAccountNameForConnectedRow:(NSInteger) row
{
    xmpp* account;
    @synchronized(_connectedXMPP) {
        if(row<[_connectedXMPP count] && row>=0)
            account = [_connectedXMPP objectAtIndex:row];
    }
    if(account)
        return account.connectionProperties.identity.jid;
    return @"";
}

#pragma mark - contact

-(void) removeContact:(MLContact*) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    if(account)
    {
        if(contact.isGroup)
        {
            //if MUC
            [account leaveMuc:contact.contactJid];
        } else  {
            [account removeFromRoster:contact.contactJid];
        }
        //remove from DB
        [[DataLayer sharedInstance] removeBuddy:contact.contactJid forAccount:contact.accountId];
    }
}

-(void) addContact:(MLContact*) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    [account addToRoster:contact.contactJid];
    
    BOOL approve = NO;
    // approve contact ahead of time if possible
    if(account.connectionProperties.supportsRosterPreApproval)
        approve = YES;
    // just in case there was a pending request
    else if([contact.state isEqualToString:kSubTo]  || [contact.state isEqualToString:kSubNone] )
        approve = YES;
    // approve contact requests not catched by the above checks (can that even happen?)
    else if([[DataLayer sharedInstance] hasContactRequestForAccount:account.accountNo andBuddyName:contact.contactJid])
        approve = YES;
    if(approve)
    {
        // delete existing contact request if exists
        [[DataLayer sharedInstance] deleteContactRequest:contact];
        // and approve the new contact
        [self approveContact:contact];
    }
#ifndef DISABLE_OMEMO
    // Request omemo devicelist
    [account.omemo queryOMEMODevices:contact.contactJid];
#endif// DISABLE_OMEMO
}

-(void) getEntitySoftWareVersionForContact:(MLContact *) contact andResource:(NSString*) resource
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    
    NSString* xmppId = @"";
    if ((resource == nil) || ([resource length] == 0)) {
        xmppId = [NSString stringWithFormat:@"%@",contact.contactJid];
    } else {
        xmppId = [NSString stringWithFormat:@"%@/%@",contact.contactJid, resource];
    }
    
    [account getEntitySoftWareVersion:xmppId];
}

-(void) blocked:(BOOL) isBlocked Jid:(MLContact *) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    [account setBlocked:isBlocked forJid:contact.contactJid];
}

-(void) blocked:(BOOL) isBlocked Jid:(NSString *) contact Account:(NSString*) accountNo
{
    xmpp* account = [self getConnectedAccountForID:accountNo];
    [account setBlocked:isBlocked forJid:contact];
}

#pragma mark - Jingle VOIP

-(void) callContact:(MLContact*) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    [account call:contact];
}

-(void) hangupContact:(MLContact*) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
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

#pragma mark message signals

-(void) handleSentMessage:(NSNotification*) notification
{
    NSDictionary* info = notification.userInfo;
    NSString* messageId = [info objectForKey:kMessageId];
    DDLogInfo(@"message %@ sent, setting status accordingly", messageId);
    [[DataLayer sharedInstance] setMessageId:messageId sent:YES];
}

#pragma mark - APNS

-(void) setPushToken:(NSString*) token
{
    if(token && ![token isEqualToString:_pushToken])
    {
        _pushToken = token;
        [[HelperTools defaultsDB] setObject:_pushToken forKey:@"pushToken"];
    }
    else    //use saved one if we are in NSE appex --> we can't get a new token and the old token might still be valid
        _pushToken = [[HelperTools defaultsDB] objectForKey:@"pushToken"];

    //check node and secret values
    if(
        _pushToken &&
        _pushToken.length
    )
    {
        DDLogInfo(@"push token valid, current push settings: token=%@", _pushToken);
        self.hasAPNSToken = YES;
    }
    else
    {
        self.hasAPNSToken = NO;
        DDLogWarn(@"push token invalid, current push settings: token=%@", _pushToken);
    }

    //only try to enable push if we have a node and secret value
    if(self.hasAPNSToken)
        for(xmpp* xmppAccount in [self connectedXMPP])
            [xmppAccount enablePush];
}

#pragma mark - share sheet added

-(void) sendOutboxForAccount:(xmpp*) account
{
    NSMutableArray* outbox = [[[HelperTools defaultsDB] objectForKey:@"outbox"] mutableCopy];
    NSMutableArray* outboxClean = [[[HelperTools defaultsDB] objectForKey:@"outbox"] mutableCopy];

    DDLogInfo(@"Got message outbox: %@", outbox);
    for(NSDictionary* row in outbox)
    {
        NSDictionary* accountDic = [row objectForKey:@"account"] ;
        if([[accountDic objectForKey:kAccountID] integerValue] == [account.accountNo integerValue])
        {
            NSString* accountID = [NSString stringWithFormat:@"%@", [accountDic objectForKey:kAccountID]];
            NSString* recipient = [row objectForKey:@"recipient"];
            NSAssert(recipient != nil, @"Recipient missing");
            NSAssert(recipient != nil, @"Recipient missing");
            BOOL encryptMessages = [[DataLayer sharedInstance] shouldEncryptForJid:recipient andAccountNo:accountID];
            MLContact* contact = [MLContact createContactFromJid:recipient andAccountNo:accountID];
            
            if([row objectForKey:@"comment"]) {
                [self sendMessageAndAddToHistory:[row objectForKey:@"comment"] toContact:contact isEncrypted:encryptMessages isUpload:NO withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) { }];
            }
            if([row objectForKey:@"url"]) {
                [self sendMessageAndAddToHistory:[row objectForKey:@"url"] toContact:contact isEncrypted:encryptMessages isUpload:NO withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) { }];
            }
            
            // remove msg even after error
            [outboxClean removeObject:row];
            [[HelperTools defaultsDB] setObject:outboxClean forKey:@"outbox"];
        }
    }
}

@end
