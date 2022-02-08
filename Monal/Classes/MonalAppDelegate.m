//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import <BackgroundTasks/BackgroundTasks.h>

#import "MonalAppDelegate.h"
#import "MLConstants.h"
#import "HelperTools.h"
#import "MLNotificationManager.h"
#import "DataLayer.h"
#import "MLImageManager.h"
#import "ActiveChatsViewController.h"
#import "IPC.h"
#import "MLProcessLock.h"
#import "MLFiletransfer.h"
#import "xmpp.h"
#import "MLNotificationQueue.h"
#import "MLSettingsAboutViewController.h"
#import "MLMucProcessor.h"

@import NotificationBannerSwift;

#import "MLXMPPManager.h"
#import "UIColor+Theme.h"

#import <AVKit/AVKit.h>

#import "MLBasePaser.h"
#import "MLXMLNode.h"
#import "XMPPStanza.h"
#import "XMPPDataForm.h"
#import "XMPPIQ.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"

#define GRACEFUL_TIMEOUT 20.0

typedef void (^pushCompletion)(UIBackgroundFetchResult result);
static NSString* kBackgroundFetchingTask = @"im.monal.fetch";

@interface MonalAppDelegate()
{
    NSMutableDictionary* _wakeupCompletions;
    UIBackgroundTaskIdentifier _bgTask;
    BGTask* _bgFetch;
    monal_void_block_t _backgroundTimer;
    MLContact* _contactToOpen;
}
@property (nonatomic, weak) ActiveChatsViewController* activeChats;
@end

@implementation MonalAppDelegate

// **************************** xml parser and query language tests ****************************
-(void) runParserTests
{
    NSString* xml = @"<?xml version='1.0'?>\n\
        <stream:stream xmlns:stream='http://etherx.jabber.org/streams' version='1.0' xmlns='jabber:client' xml:lang='en' from='xmpp.eightysoft.de' id='a344b8bb-518e-4456-9140-d15f66c1d2db'>\n\
        <stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>SCRAM-SHA-1</mechanism><mechanism>PLAIN</mechanism></mechanisms></stream:features>\n\
        <iq id='18382ACA-EF9D-4BC9-8779-7901C63B6631' to='thilo@xmpp.eightysoft.de/Monal-iOS.ef313600' xmlns='jabber:client' type='result' from='luloku@conference.xmpp.eightysoft.de'><query xmlns='http://jabber.org/protocol/disco#info'><feature var='http://jabber.org/protocol/muc#request'/><feature var='muc_hidden'/><feature var='muc_unsecured'/><feature var='muc_membersonly'/><feature var='muc_unmoderated'/><feature var='muc_persistent'/><identity type='text' name='testchat gruppe' category='conference'/><feature var='urn:xmpp:mam:2'/><feature var='urn:xmpp:sid:0'/><feature var='muc_nonanonymous'/><feature var='http://jabber.org/protocol/muc'/><feature var='http://jabber.org/protocol/muc#stable_id'/><feature var='http://jabber.org/protocol/muc#self-ping-optimization'/><feature var='jabber:iq:register'/><feature var='vcard-temp'/><x type='result' xmlns='jabber:x:data'><field type='hidden' var='FORM_TYPE'><value>http://jabber.org/protocol/muc#roominfo</value></field><field label='Description' var='muc#roominfo_description' type='text-single'><value/></field><field label='Number of occupants' var='muc#roominfo_occupants' type='text-single'><value>2</value></field><field label='Allow members to invite new members' var='{http://prosody.im/protocol/muc}roomconfig_allowmemberinvites' type='boolean'><value>0</value></field><field label='Allow users to invite other users' var='muc#roomconfig_allowinvites' type='boolean'><value>0</value></field><field label='Title' var='muc#roomconfig_roomname' type='text-single'><value>testchat gruppe</value></field><field type='boolean' var='muc#roomconfig_changesubject'/><field type='text-single' var='{http://modules.prosody.im/mod_vcard_muc}avatar#sha1'/><field type='text-single' var='muc#roominfo_lang'><value/></field></x></query></iq>\n\
    ";
    
    DDLogInfo(@"creating parser delegate");
    MLBasePaser* delegate = [[MLBasePaser alloc] initWithCompletion:^(MLXMLNode* _Nullable parsedStanza) {
        if(parsedStanza != nil)
        {
            DDLogInfo(@"Got new parsed stanza: %@", parsedStanza);
            for(NSString* query in @[
                @"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/protocol/muc#roominfo}result@muc#roomconfig_roomname\\",
            ])
            {
                id result = [parsedStanza find:query];
                DDLogDebug(@"Query: '%@', result: '%@'", query, result);
            }
        }
    }];
    
    //create xml parser, configure our delegate and feed it with data
    NSXMLParser* xmlParser = [[NSXMLParser alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    [xmlParser setShouldProcessNamespaces:YES];
    [xmlParser setShouldReportNamespacePrefixes:NO];
    [xmlParser setShouldResolveExternalEntities:NO];
    [xmlParser setDelegate:delegate];
    DDLogInfo(@"calling parse");
    [xmlParser parse];     //blocking operation
    DDLogInfo(@"parse ended");
}

-(id) init
{
    self = [super init];
    _bgTask = UIBackgroundTaskInvalid;
    _wakeupCompletions = [[NSMutableDictionary alloc] init];
    
    //[self runParserTests];
    return self;
}

#pragma mark -  APNS notificaion

-(void) application:(UIApplication*) application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*) deviceToken
{
    NSString* token = [HelperTools stringFromToken:deviceToken];
    DDLogInfo(@"APNS token string: %@", token);
    [[MLXMPPManager sharedInstance] setPushToken:token];
}

-(void) application:(UIApplication*) application didFailToRegisterForRemoteNotificationsWithError:(NSError*) error
{
    DDLogError(@"push reg error %@", error);
}

#pragma mark - notification actions

-(void) updateUnread
{
    //make sure unread badge matches application badge
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger unread = 0;
        if(unreadMsgCnt)
            unread = [unreadMsgCnt integerValue];
        DDLogInfo(@"Updating unread badge to: %ld", (long)unread);
        [UIApplication sharedApplication].applicationIconBadgeNumber = unread;
    });
}

#pragma mark - app life cycle

-(BOOL) application:(UIApplication*) application willFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    //migrate defaults db to shared app group
    if(![[HelperTools defaultsDB] boolForKey:@"DefaulsMigratedToAppGroup"])
    {
        DDLogInfo(@"Migrating [NSUserDefaults standardUserDefaults] to app group container...");
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"ChatBackgrounds"] forKey:@"ChatBackgrounds"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowGeoLocation"] forKey:@"ShowGeoLocation"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"Sound"] forKey:@"Sound"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"SetDefaults"] forKey:@"SetDefaults"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeenIntro"] forKey:@"HasSeenIntro"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasSeenLogin"] forKey:@"HasSeenLogin"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowImages"] forKey:@"ShowImages"];
        [[HelperTools defaultsDB] setBool:[[NSUserDefaults standardUserDefaults] boolForKey:@"HasUpgradedPushiOS13"] forKey:@"HasUpgradedPushiOS13"];
        [[HelperTools defaultsDB] setObject:[[NSUserDefaults standardUserDefaults] objectForKey:@"BackgroundImage"] forKey:@"BackgroundImage"];
        [[HelperTools defaultsDB] setObject:[[NSUserDefaults standardUserDefaults] objectForKey:@"AlertSoundFile"] forKey:@"AlertSoundFile"];
        
        [[HelperTools defaultsDB] setBool:YES forKey:@"DefaulsMigratedToAppGroup"];
        [[HelperTools defaultsDB] synchronize];
        DDLogInfo(@"Migration complete and written to disk");
    }
    DDLogInfo(@"App launching with options: %@", launchOptions);
    
    //init IPC and ProcessLock
    [IPC initializeForProcess:@"MainApp"];
    
    //lock process and disconnect an already running NotificationServiceExtension
    [MLProcessLock lock];
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    
    //do MLFiletransfer cleanup tasks (do this in a new thread to parallelize it with our ping to the appex and don't slow down app startup)
    //this will also migrate our old image cache to new MLFiletransfer cache
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [MLFiletransfer doStartupCleanup];
    });
    
    //do image manager cleanup in a new thread to not slow down app startup
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[MLImageManager sharedInstance] cleanupHashes];
    });
    
    //only proceed with launching if the NotificationServiceExtension is *not* running
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension" withLoopHandler:^{
            [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        }];
    }
    
    return YES;
}

-(BOOL) application:(UIApplication*) application didFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    //this will use the cached values in defaultsDB, if possible
    [[MLXMPPManager sharedInstance] setPushToken:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleBackgroundFetchingTask) name:kScheduleBackgroundFetchingTask object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(filetransfersNowIdle:) name:kMonalFiletransfersIdle object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showConnectionStatus:) name:kXMPPError object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:kMonalUpdateUnread object:nil];
    
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    
    //create notification categories with actions
    UNNotificationAction* replyAction = [UNTextInputNotificationAction
        actionWithIdentifier:@"REPLY_ACTION"
        title:NSLocalizedString(@"Reply", @"")
        options:UNNotificationActionOptionNone
        textInputButtonTitle:NSLocalizedString(@"Send", @"")
        textInputPlaceholder:NSLocalizedString(@"Your answer", @"")
    ];
    UNNotificationAction* markAsReadAction = [UNNotificationAction
        actionWithIdentifier:@"MARK_AS_READ_ACTION"
        title:NSLocalizedString(@"Mark as read", @"")
        options:UNNotificationActionOptionNone
    ];
    if(@available(iOS 15.0, macCatalyst 15.0, *))
    {
        replyAction = [UNTextInputNotificationAction
            actionWithIdentifier:@"REPLY_ACTION"
            title:NSLocalizedString(@"Reply", @"")
            options:UNNotificationActionOptionNone
            icon:[UNNotificationActionIcon iconWithSystemImageName:@"arrowshape.turn.up.left"] 
            textInputButtonTitle:NSLocalizedString(@"Send", @"")
            textInputPlaceholder:NSLocalizedString(@"Your answer", @"")
        ];
        markAsReadAction = [UNNotificationAction
            actionWithIdentifier:@"MARK_AS_READ_ACTION"
            title:NSLocalizedString(@"Mark as read", @"")
            options:UNNotificationActionOptionNone
            icon:[UNNotificationActionIcon iconWithSystemImageName:@"message"]
        ];
    }
    UNNotificationCategory* messageCategory;
    UNAuthorizationOptions authOptions = UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionCriticalAlert | UNAuthorizationOptionAnnouncement;
    messageCategory = [UNNotificationCategory
        categoryWithIdentifier:@"message"
        actions:@[replyAction, markAsReadAction]
        intentIdentifiers:@[]
        options:UNNotificationCategoryOptionAllowAnnouncement
    ];

    //request auth to show notifications and register our notification categories created above
    [center requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DDLogInfo(@"Got local notification authorization response: granted=%@, error=%@", granted ? @"YES" : @"NO", error);
            BOOL oldGranted = [[HelperTools defaultsDB] boolForKey:@"notificationsGranted"];
            [[HelperTools defaultsDB] setBool:granted forKey:@"notificationsGranted"];
            if(granted == YES)
            {
                if(!oldGranted)
                {
                    //this is only needed for better UI (settings --> noifications should reflect the proper state)
                    //both invalidations are needed because we don't know the timing of this notification granting handler
                    DDLogInfo(@"Invalidating all account states...");
                    [[DataLayer sharedInstance] invalidateAllAccountStates];        //invalidate states for account objects not yet created
                    [[MLXMPPManager sharedInstance] reconnectAll];                  //invalidate for account objects already created
                }
                
                //activate push
                DDLogInfo(@"Registering for APNS...");
                [[UIApplication sharedApplication] registerForRemoteNotifications];
            }
            else
            {
                //delete apns push token --> push will not be registered on our xmpp server anymore
                DDLogWarn(@"Notifications disabled --> deleting APNS push token from user defaults!");
                NSString* oldToken = [[HelperTools defaultsDB] objectForKey:@"pushToken"];
                [[HelperTools defaultsDB] removeObjectForKey:@"pushToken"];
                [[MLXMPPManager sharedInstance] setPushToken:nil];
                
                //unregister from push appserver
                if((oldToken != nil && oldToken.length != 0) || oldGranted)
                {
                    DDLogWarn(@"Unregistering node from appserver!");

                    [[MLXMPPManager sharedInstance] unregisterPush];
                    //this is only needed for better UI (settings --> noifications should reflect the proper state)
                    //both invalidations are needed because we don't know the timing of this notification granting handler
                    DDLogInfo(@"Invalidating all account states...");
                    [[DataLayer sharedInstance] invalidateAllAccountStates];        //invalidate states for account objects not yet created
                    [[MLXMPPManager sharedInstance] reconnectAll];                  //invalidate for account objects already created
                }
            }
        });
    }];
    [center setNotificationCategories:[NSSet setWithObjects:messageCategory, nil]];

    UINavigationBarAppearance* appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = [UIColor systemBackgroundColor];
    
    [[UINavigationBar appearance] setScrollEdgeAppearance:appearance];
    [[UINavigationBar appearance] setStandardAppearance:appearance];
#if TARGET_OS_MACCATALYST
    self.window.windowScene.titlebar.titleVisibility = UITitlebarTitleVisibilityHidden;
#else
    [[UITabBar appearance] setTintColor:[UIColor monaldarkGreen]];
    [[UINavigationBar appearance] setTintColor:[UIColor monalGreen]];
#endif
    [[UINavigationBar appearance] setPrefersLargeTitles:YES];

    //handle message notifications by initializing the MLNotificationManager
    [MLNotificationManager sharedInstance];
    
    //register BGTask
    DDLogInfo(@"calling MonalAppDelegate configureBackgroundFetchingTask");
    [self configureBackgroundFetchingTask];
    // Play audio even if phone is in silent mode
    NSError* audioSessionError;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&audioSessionError];
    if(audioSessionError != nil)
    {
        DDLogWarn(@"Couldn't set AVAudioSession to AVAudioSessionCategoryPlayback: %@", audioSessionError);
    }

    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDict objectForKey:@"CFBundleShortVersionString"];
    NSString* buildDate = [NSString stringWithUTF8String:__DATE__];
    NSString* buildTime = [NSString stringWithUTF8String:__TIME__];
    DDLogInfo(@"App started: %@", [NSString stringWithFormat:NSLocalizedString(@"Version %@ (%@ %@ UTC)", @""), version, buildDate, buildTime]);
    
    //init background/foreground status
    //this has to be done here to make sure we have the correct state when he app got started through notification quick actions
    if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
        [[MLXMPPManager sharedInstance] nowBackgrounded];
    else
        [[MLXMPPManager sharedInstance] nowForegrounded];
    
    //should any accounts connect?
    [self connectIfNecessary];
    
    //handle IPC messages (this should be done *after* calling connectIfNecessary to make sure any disconnectAll messages are handled properly
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(incomingIPC:) name:kMonalIncomingIPC object:nil];
    
#if TARGET_OS_MACCATALYST
    //handle catalyst foregrounding/backgrounding of window
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowHandling:) name:@"NSWindowDidResignKeyNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowHandling:) name:@"NSWindowDidBecomeKeyNotification" object:nil];
#endif

    return YES;
}

#if TARGET_OS_MACCATALYST
-(void) windowHandling:(NSNotification*) notification
{
    if([notification.name isEqualToString:@"NSWindowDidResignKeyNotification"])
    {
        DDLogInfo(@"Window lost focus (key window)...");
        [self updateUnread];
        if(NSProcessInfo.processInfo.isLowPowerModeEnabled)
        {
            DDLogInfo(@"LowPowerMode is active: nowReallyBackgrounded to reduce power consumption");
            [self nowReallyBackgrounded];
        }
        else
            [[MLXMPPManager sharedInstance] nowNoLongerInFocus];
    }
    else if([notification.name isEqualToString:@"NSWindowDidBecomeKeyNotification"])
    {
        DDLogInfo(@"Window got focus (key window)...");
        [self addBackgroundTask];
        [[MLXMPPManager sharedInstance] nowForegrounded];
    }
}
#endif

-(void) incomingIPC:(NSNotification*) notification
{
    NSDictionary* message = notification.userInfo;
    //another process tells us to disconnect all accounts
    //this could happen if we are connecting (or even connected) in the background and the NotificationServiceExtension got started
    //BUT: only do this if we are in background (we should never receive this if we are foregrounded)
    if([message[@"name"] isEqualToString:@"Monal.disconnectAll"])
    {
        DDLogInfo(@"Got disconnectAll IPC message");
        MLAssert([HelperTools isInBackground]==YES, @"Got 'Monal.disconnectAll' while in foreground. This should NEVER happen!", message);
        //disconnect all (currently connecting or already connected) accounts
        [[MLXMPPManager sharedInstance] disconnectAll];
    }
    else if([message[@"name"] isEqualToString:@"Monal.connectIfNecessary"])
    {
        DDLogInfo(@"Got connectIfNecessary IPC message");
        //(re)connect all accounts
        [self connectIfNecessary];
    }
}

-(void) applicationDidBecomeActive:(UIApplication*) application
{
    //[UIApplication sharedApplication].applicationIconBadgeNumber=0;
}

-(void) setActiveChatsController: (UIViewController*) activeChats
{
    self.activeChats = (ActiveChatsViewController*)activeChats;
    [self openChatOfContact:_contactToOpen];
}

#pragma mark - handling urls

/**
 xmpp:romeo@montague.net?message;subject=Test%20Message;body=Here%27s%20a%20test%20message
 xmpp:coven@chat.shakespeare.lit?join;password=cauldronburn
 
 xmpp:example.com?register;preauth=3c7efeafc1bb10d034
 xmpp:romeo@example.com?register;preauth=3c7efeafc1bb10d034
 xmpp:contact@example.com?roster;preauth=3c7efeafc1bb10d034
 xmpp:contact@example.com?roster;preauth=3c7efeafc1bb10d034;ibr=y
         
 @link https://xmpp.org/extensions/xep-0147.html
 @link https://docs.modernxmpp.org/client/invites/
 */
-(void) handleXMPPURL:(NSURL*) url
{
    //TODO just uses fist enabled account. maybe change in the future
    xmpp* account = [[MLXMPPManager sharedInstance].connectedXMPP firstObject];
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    DDLogVerbose(@"URI path '%@'", components.path);
    DDLogVerbose(@"URI query '%@'", components.query);
    
    NSString* jid = components.path;
    NSDictionary* jidParts = [HelperTools splitJid:jid];
    BOOL isRegister = NO;
    BOOL isRoster = NO;
    BOOL isGroupJoin = NO;
    BOOL isIbr = NO;
    NSString* preauthToken = nil;
    //someone had the really superior (NOT!) idea to split uri query parts by ';' instead of the standard '&' making all existing uri libs useless
    //see: https://xmpp.org/extensions/xep-0147.html
    //blame this author: Peter Saint-Andre
    NSArray* queryItems = [components.query componentsSeparatedByString:@";"];
    for(NSString* item in queryItems)
    {
        NSArray* itemParts = [item componentsSeparatedByString:@"="];
        NSString* name = itemParts[0];
        NSString* value = @"";
        if([itemParts count] > 1)
            value = itemParts[1];
        DDLogVerbose(@"URI part '%@' = '%@'", name, value);
        if([name isEqualToString:@"register"])
            isRegister = YES;
        if([name isEqualToString:@"roster"])
            isRoster = YES;
        if([name isEqualToString:@"join"])
            isGroupJoin = YES;
        if([name isEqualToString:@"ibr"] && [value isEqualToString:@"y"])
            isIbr = YES;
        if([name isEqualToString:@"preauth"])
            preauthToken = [value copy];
    }
    
    if(!jidParts[@"host"])
    {
        DDLogError(@"Ignoring xmpp: uri without host jid part!");
        return;
    }
    
    if(isRegister || (isRoster && account==nil && isIbr))
    {
        NSString* username = nilDefault(jidParts[@"node"], @"");
        NSString* host = jidParts[@"host"];
        
        if(isRoster)
            username = @"";         //roster does not specify a predefined username for the new account, register does (optional)
        
        //this should never happen
        MLAssert(self.activeChats != nil, @"Can not handle register invite, active chats not loaded!", (@{
           @"components": components,
           @"username": username,
           @"host": host,
        }));
        
        weakify(self);
        [self.activeChats showRegisterWithUsername:username onHost:host withToken:preauthToken usingCompletion:^{
            strongify(self);
            xmpp* account = [[MLXMPPManager sharedInstance].connectedXMPP firstObject];
            
            //this should never happen
            MLAssert(account != nil, @"Can not use account after register!", (@{
                @"components": components,
                @"username": username,
                @"host": host,
            }));
            
            if(account != nil)      //silence memory warning despite assertion above
            {
                MLContact* contact = [MLContact createContactFromJid:jid andAccountNo:account.accountNo];
                //will handle group joins and normal contacts transparently and even implement roster subscription pre-approval
                [[MLXMPPManager sharedInstance] addContact:contact withPreauthToken:preauthToken];
                [[DataLayer sharedInstance] addActiveBuddies:jid forAccount:account.accountNo];
                [self openChatOfContact:contact];
            }
        }];
        return;
    }
    
    if(isRoster && account)
    {
        MLContact* contact = [MLContact createContactFromJid:jid andAccountNo:account.accountNo];
        //will handle group joins and normal contacts transparently and even implement roster subscription pre-approval
        [[MLXMPPManager sharedInstance] addContact:contact withPreauthToken:preauthToken];
        [[DataLayer sharedInstance] addActiveBuddies:jid forAccount:account.accountNo];
        [self openChatOfContact:contact];
        return;
    }
    
    if(isGroupJoin && account)
    {
        MLContact* contact = [MLContact createContactFromJid:jid andAccountNo:account.accountNo];
        [[MLXMPPManager sharedInstance] addContact:contact];    //will handle group joins and normal contacts transparently
        //wait for join to finish before opening contact
        NSString* accountNo = account.accountNo;        //needed because of retain cycle
        [account.mucProcessor addUIHandler:^(id _data) {
            [[DataLayer sharedInstance] addActiveBuddies:jid forAccount:accountNo];
            [self openChatOfContact:contact];
        } forMuc:jid];
        return;
    }
    
    //fallback: only add to local roster, but don't subscribe
    //TODO: show toast in chatView that informs the user that this contact was not added to his contact list
    if(account)
    {
        [[DataLayer sharedInstance] addActiveBuddies:jid forAccount:account.accountNo];
        MLContact* contact = [MLContact createContactFromJid:jid andAccountNo:account.accountNo];
        [self openChatOfContact:contact];
    }
    
    DDLogError(@"No account available to handel xmpp: uri!");
}

-(BOOL) application:(UIApplication*) app openURL:(NSURL*) url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id>*) options
{
    if([url.scheme isEqualToString:@"xmpp"])                //for xmpp uris
    {
        [self handleXMPPURL:url];
        return YES;
    }
    else if([url.scheme isEqualToString:@"monalOpen"])      //app opened via sharesheet
    {
        //make sure our outbox content is sent (if the mainapp is still connected and also was in foreground while the sharesheet was used)
        //and open the chat the newest outbox entry was sent to
        MLContact* lastRecipientContact = [[MLXMPPManager sharedInstance] sendAllOutboxes];
        [[DataLayer sharedInstance] addActiveBuddies:lastRecipientContact.contactJid forAccount:lastRecipientContact.accountId];
        DDLogVerbose(@"Trying to open chat for %@", lastRecipientContact.contactJid);
        [self openChatOfContact:lastRecipientContact];
        return YES;
    }
    return NO;
}




#pragma mark  - user notifications

-(void) application:(UIApplication*) application didReceiveRemoteNotification:(NSDictionary*) userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result)) completionHandler
{
    DDLogVerbose(@"got didReceiveRemoteNotification: %@", userInfo);
    [self incomingWakeupWithCompletionHandler:completionHandler];
}

- (void)userNotificationCenter:(UNUserNotificationCenter*) center willPresentNotification:(UNNotification*) notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options)) completionHandler;
{
    DDLogInfo(@"userNotificationCenter:willPresentNotification:withCompletionHandler called");
    //show local notifications while the app is open and ignore remote pushes
    if([notification.request.trigger isKindOfClass:[UNPushNotificationTrigger class]]) {
        completionHandler(UNNotificationPresentationOptionNone);
    } else {
        completionHandler(UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner);
    }
}

-(void) userNotificationCenter:(UNUserNotificationCenter*) center didReceiveNotificationResponse:(UNNotificationResponse*) response withCompletionHandler:(void (^)(void)) completionHandler
{
    if([response.notification.request.content.categoryIdentifier isEqualToString:@"message"])
    {
        DDLogVerbose(@"notification action '%@' triggered for %@", response.actionIdentifier, response.notification.request.content.userInfo);
        
        //add our completion handler to handler queue
        [self incomingWakeupWithCompletionHandler:^(UIBackgroundFetchResult result) {
            completionHandler();
        }];
        
        MLContact* fromContact = [MLContact createContactFromJid:response.notification.request.content.userInfo[@"fromContactJid"] andAccountNo:response.notification.request.content.userInfo[@"fromContactAccountId"]];
        NSString* messageId = response.notification.request.content.userInfo[@"messageId"];
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:fromContact.accountId];
        NSAssert(fromContact, @"fromContact should not be nil");
        NSAssert(messageId, @"messageId should not be nil");
        NSAssert(account, @"account should not be nil");
        
        //make sure we have an active buddy for this chat
        [[DataLayer sharedInstance] addActiveBuddies:fromContact.contactJid forAccount:fromContact.accountId];
        
        //handle message actions
        if([response.actionIdentifier isEqualToString:@"REPLY_ACTION"])
        {
            DDLogInfo(@"REPLY_ACTION triggered...");
            UNTextInputNotificationResponse* textResponse = (UNTextInputNotificationResponse*) response;
            if(!textResponse.userText.length)
            {
                DDLogWarn(@"User tried to send empty text response!");
                return;
            }
            
            //mark messages as read because we are replying
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:fromContact.contactJid andAccount:fromContact.accountId tillStanzaId:messageId wasOutgoing:NO];
            DDLogDebug(@"Marked as read: %@", unread);
            
            //remove notifications of all read messages (this will cause the MLNotificationManager to update the app badge, too)
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessagesNotice object:account userInfo:@{@"messagesArray":unread}];
            
            //update unread count in active chats list
            [fromContact refresh];      //this will make sure the unread count is correct
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": fromContact
            }];
            
            BOOL encrypted = [[DataLayer sharedInstance] shouldEncryptForJid:fromContact.contactJid andAccountNo:fromContact.accountId];
            [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:textResponse.userText toContact:fromContact isEncrypted:encrypted isUpload:NO withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                DDLogInfo(@"REPLY_ACTION success=%@, messageIdSentObject=%@", successSendObject ? @"YES" : @"NO", messageIdSentObject);
            }];
        }
        else if([response.actionIdentifier isEqualToString:@"MARK_AS_READ_ACTION"])
        {
            DDLogInfo(@"MARK_AS_READ_ACTION triggered...");
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:fromContact.contactJid andAccount:fromContact.accountId tillStanzaId:messageId wasOutgoing:NO];
            DDLogDebug(@"Marked as read: %@", unread);
            
            //send displayed marker for last unread message (XEP-0333)
            //but only for 1:1 or group-type mucs,not for channe-type mucs (privacy etc.)
            MLMessage* lastUnreadMessage = [unread lastObject];
            if(lastUnreadMessage && (!fromContact.isGroup || [@"group" isEqualToString:fromContact.mucType]))
            {
                DDLogDebug(@"Sending XEP-0333 displayed marker for message '%@'", lastUnreadMessage.messageId);
                [account sendDisplayMarkerForMessage:lastUnreadMessage];
            }
            
            //remove notifications of all read messages (this will cause the MLNotificationManager to update the app badge, too)
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessagesNotice object:account userInfo:@{@"messagesArray":unread}];
            
            //update unread count in active chats list
            [fromContact refresh];      //this will make sure the unread count is correct
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": fromContact
            }];
        }
        else if([response.actionIdentifier isEqualToString:@"com.apple.UNNotificationDefaultActionIdentifier"])     //open chat of this contact
            [self openChatOfContact:fromContact];
    }
    else
    {
        //call completion handler directly (we did not handle anything and no connectIfNecessary was called)
        if(completionHandler)
            completionHandler();
    }
}

-(void) openChatOfContact:(MLContact* _Nullable) contact
{
    if(contact != nil)
        _contactToOpen = contact;
    
    if(self.activeChats != nil && _contactToOpen != nil)
    {
        // the timer makes sure the view is properly initialized when opning the chat
        createQueuedTimer(0.5, dispatch_get_main_queue(), (^{
            if(_contactToOpen != nil)
            {
                DDLogDebug(@"Opening chat for contact %@", [contact contactJid]);
                // open new chat
                [(ActiveChatsViewController*)self.activeChats presentChatWithContact:_contactToOpen];
            }
            else
                DDLogDebug(@"_contactToOpen changed to nil, not opening chat for contact %@", [contact contactJid]);
            _contactToOpen = nil;
        }));
    }
    else
        DDLogDebug(@"Not opening chat for contact %@", [contact contactJid]);
}

#pragma mark - memory
-(void) applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    DDLogWarn(@"Got memory warning!");
}

#pragma mark - backgrounding

-(void) startBackgroundTimer
{
    //cancel old background timer if still running and start a new one
    //this timer will fire after GRACEFUL_TIMEOUT seconds in background and disconnect gracefully (e.g. when fully idle the next time)
    if(_backgroundTimer)
        _backgroundTimer();
    _backgroundTimer = createTimer(GRACEFUL_TIMEOUT, ^{
        //mark timer as *not* running
        _backgroundTimer = nil;
        //retry background check (now handling idle state because no running background timer is blocking it)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self checkIfBackgroundTaskIsStillNeeded];
        });
    });
}

-(void) stopBackgroundTimer
{
    if(_backgroundTimer)
        _backgroundTimer();
    _backgroundTimer = nil;
}

-(void) applicationWillEnterForeground:(UIApplication *)application
{
    DDLogInfo(@"Entering FG");
    
    //TODO: show "loading..." animation/modal
    
    //only proceed with foregrounding if the NotificationServiceExtension is not running
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension" withLoopHandler:^{
            [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        }];
    }
    
    //trigger view updates (this has to be done because the NotificationServiceExtension could have updated the database some time ago)
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:self userInfo:nil];
    
    //cancel already running background timer, we are now foregrounded again
    [self stopBackgroundTimer];
    
    [self addBackgroundTask];
    [[MLXMPPManager sharedInstance] nowForegrounded];
}

-(void) applicationWillResignActive:(UIApplication *)application
{
}

-(void) nowReallyBackgrounded
{
    [self addBackgroundTask];
    [[MLXMPPManager sharedInstance] nowBackgrounded];
    [self startBackgroundTimer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self checkIfBackgroundTaskIsStillNeeded];
    });
}

-(void) applicationDidEnterBackground:(UIApplication*) application
{
    UIApplicationState state = [application applicationState];
    if(state == UIApplicationStateInactive)
        DDLogInfo(@"Screen lock / incoming call");
    else if(state == UIApplicationStateBackground)
        DDLogInfo(@"Entering BG");
    
    [self updateUnread];
#if TARGET_OS_MACCATALYST
    if(NSProcessInfo.processInfo.isLowPowerModeEnabled)
    {
        DDLogInfo(@"LowPowerMode is active: nowReallyBackgrounded to reduce power consumption");
        [self nowReallyBackgrounded];
    }
    else
        [[MLXMPPManager sharedInstance] nowNoLongerInFocus];
#else
    [self nowReallyBackgrounded];
#endif
}

-(void) applicationWillTerminate:(UIApplication *)application
{
    DDLogWarn(@"|~~| T E R M I N A T I N G |~~|");
    [self scheduleBackgroundFetchingTask];        //make sure delivery will be attempted, if needed
    DDLogInfo(@"|~~| 20%% |~~|");
    [self updateUnread];
    DDLogInfo(@"|~~| 40%% |~~|");
    [[HelperTools defaultsDB] synchronize];
    DDLogInfo(@"|~~| 60%% |~~|");
    [[MLXMPPManager sharedInstance] nowBackgrounded];
    DDLogInfo(@"|~~| 80%% |~~|");
    [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
    DDLogInfo(@"|~~| 100%% |~~|");
    [[MLXMPPManager sharedInstance] disconnectAll];
    //wait for all pending intent donations of incoming messages to makeure those get a proper notification displayed
    //(pending donations will never be honored with a notification otherwise)
    [[MLNotificationManager sharedInstance] waitForDonations];
    DDLogInfo(@"|~~| T E R M I N A T E D |~~|");
    [DDLog flushLog];
}

#pragma mark - error feedback

-(void) showConnectionStatus:(NSNotification*) notification
{
    //this will show an error banner but only if our app is foregrounded
    if(![HelperTools isNotInFocus])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            xmpp* xmppAccount = notification.object;
            if(![notification.userInfo[@"isSevere"] boolValue])
                DDLogError(@"Minor XMPP Error(%@): %@", xmppAccount.connectionProperties.identity.jid, notification.userInfo[@"message"]);
            NotificationBanner* banner = [[NotificationBanner alloc] initWithTitle:xmppAccount.connectionProperties.identity.jid subtitle:notification.userInfo[@"message"] leftView:nil rightView:nil style:([notification.userInfo[@"isSevere"] boolValue] ? BannerStyleDanger : BannerStyleWarning) colors:nil];
            banner.duration = 10.0;     //show for 10 seconds to make sure users can read it
            NotificationBannerQueue* queue = [[NotificationBannerQueue alloc] initWithMaxBannersOnScreenSimultaneously:2];
            [banner showWithQueuePosition:QueuePositionBack bannerPosition:BannerPositionTop queue:queue on:nil];
        });
    }
}

#pragma mark - mac menu
-(void) buildMenuWithBuilder:(id<UIMenuBuilder>) builder
{
    [super buildMenuWithBuilder:builder];
    //monal
    UIKeyCommand* preferencesCommand = [UIKeyCommand commandWithTitle:@"Preferences..." image:nil action:@selector(showSettings) input:@"," modifierFlags:UIKeyModifierCommand propertyList:nil];

    UIMenu* preferencesMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.preferences" options:UIMenuOptionsDisplayInline children:@[preferencesCommand]];
    [builder insertSiblingMenu:preferencesMenu afterMenuForIdentifier:UIMenuAbout];

    //file
    UIKeyCommand* newCommand = [UIKeyCommand commandWithTitle:@"New Message" image:nil action:@selector(showNew) input:@"N" modifierFlags:UIKeyModifierCommand propertyList:nil];

    UIMenu* newMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.new" options:UIMenuOptionsDisplayInline children:@[newCommand]];
    [builder insertChildMenu:newMenu atStartOfMenuForIdentifier:UIMenuFile];

    UIKeyCommand* detailsCommand = [UIKeyCommand commandWithTitle:@"Details..." image:nil action:@selector(showDetails) input:@"I" modifierFlags:UIKeyModifierCommand propertyList:nil];

    UIMenu* detailsMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.detail" options:UIMenuOptionsDisplayInline children:@[detailsCommand]];
    [builder insertSiblingMenu:detailsMenu afterMenuForIdentifier:@"im.monal.new"];

    UIKeyCommand* deleteCommand = [UIKeyCommand commandWithTitle:@"Delete Conversation" image:nil action:@selector(deleteConversation) input:@"\b" modifierFlags:UIKeyModifierCommand propertyList:nil];

    UIMenu* deleteMenu = [UIMenu menuWithTitle:@"" image:nil identifier:@"im.monal.delete" options:UIMenuOptionsDisplayInline children:@[deleteCommand]];
    [builder insertSiblingMenu:deleteMenu afterMenuForIdentifier:@"im.monal.detail"];

    [builder removeMenuForIdentifier:UIMenuHelp];

    [builder replaceChildrenOfMenuForIdentifier:UIMenuAbout fromChildrenBlock:^NSArray<UIMenuElement *> * _Nonnull(NSArray<UIMenuElement *> * _Nonnull items) {
        UICommand* itemCommand = (UICommand*)items.firstObject;
        UICommand* aboutCommand = [UICommand commandWithTitle:itemCommand.title image:nil action:@selector(aboutWindow) propertyList:nil];
        NSArray* menuItems = @[aboutCommand];
        return menuItems;
    }];
}

-(void) aboutWindow
{
    UIStoryboard* settingStoryBoard = [UIStoryboard storyboardWithName:@"Settings" bundle:nil];
    MLSettingsAboutViewController* settingAboutViewController = [settingStoryBoard instantiateViewControllerWithIdentifier:@"SettingsAboutViewController"];
    UINavigationController* navigationController = [[UINavigationController alloc] initWithRootViewController:settingAboutViewController];
    [self.window.rootViewController presentViewController:navigationController animated:NO completion:nil];
}

-(void) showNew
{
    [self.activeChats showContacts];
}

-(void) deleteConversation
{
    [self.activeChats deleteConversation];
}

-(void) showSettings
{
    [self.activeChats showSettings];
}

-(void) showDetails
{
    [self.activeChats showDetails];
}

#pragma mark - background tasks

-(void) nowIdle:(NSNotification*) notification
{
    DDLogInfo(@"### SOME ACCOUNT CHANGED TO IDLE STATE ###");
    //dispatch *async* to main queue to avoid deadlock between receiveQueue ---sync--> im.monal.disconnect ---sync--> receiveQueue
    dispatch_async(dispatch_get_main_queue(), ^{
        [self checkIfBackgroundTaskIsStillNeeded];
    });
}

-(void) filetransfersNowIdle:(NSNotification*) notification
{
    DDLogInfo(@"### FILETRANSFERS CHANGED TO IDLE STATE ###");
    //dispatch *async* to main queue to avoid deadlock between receiveQueue ---sync--> im.monal.disconnect ---sync--> receiveQueue
    dispatch_async(dispatch_get_main_queue(), ^{
        [self checkIfBackgroundTaskIsStillNeeded];
    });
}

//this method will either be called from an anonymous timer thread or from the main thread
-(void) checkIfBackgroundTaskIsStillNeeded
{
    if([[MLXMPPManager sharedInstance] allAccountsIdle] && [MLFiletransfer isIdle])
    {
        DDLogInfo(@"### ALL ACCOUNTS IDLE AND FILETRANSFERS COMPLETE NOW ###");
        [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
        
        //use a synchronized block to disconnect only once
        @synchronized(self) {
            if(_backgroundTimer != nil || [_wakeupCompletions count] > 0)
            {
                DDLogInfo(@"### ignoring idle state because background timer or wakeup completion timers are still running ###");
                return;
            }
            
            DDLogInfo(@"### checking if background is still needed ###");
            BOOL background = [HelperTools isInBackground];
            if(background)
            {
                DDLogInfo(@"### All accounts idle, disconnecting and stopping all background tasks ###");
                [DDLog flushLog];
                [[MLXMPPManager sharedInstance] disconnectAll];       //disconnect all accounts to prevent TCP buffer leaking
                [HelperTools dispatchSyncReentrant:^{
                    //wait for all pending intent donations of incoming messages to makeure those get a proper notification displayed
                    //(pending donations will never be honored with a notification otherwise)
                    [[MLNotificationManager sharedInstance] waitForDonations];
                    
                    BOOL stopped = NO;
                    if(_bgTask != UIBackgroundTaskInvalid)
                    {
                        DDLogDebug(@"stopping UIKit _bgTask");
                        [DDLog flushLog];
                        [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
                        _bgTask = UIBackgroundTaskInvalid;
                        stopped = YES;
                    }
                    if(_bgFetch)
                    {
                        DDLogDebug(@"stopping backgroundFetchingTask");
                        [DDLog flushLog];
                        [_bgFetch setTaskCompletedWithSuccess:YES];
                        _bgFetch = nil;
                        stopped = YES;
                    }
                    if(!stopped)
                        DDLogDebug(@"no background tasks running, nothing to stop");
                    [DDLog flushLog];
                    
                    //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                } onQueue:dispatch_get_main_queue()];
            }
        }
    }
}

-(void) addBackgroundTask
{
    [HelperTools dispatchSyncReentrant:^{
        if(_bgTask == UIBackgroundTaskInvalid)
        {
            //indicate we want to do work even if the app is put into background
            _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
                DDLogWarn(@"BG WAKE EXPIRING");
                [DDLog flushLog];
                
                @synchronized(self) {
                    //ui background tasks expire at the same time as background fetching tasks
                    //--> we have to check if a background fetching task is running and don't disconnect, if so
                    if(_bgFetch == nil)
                    {
                        //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
                        [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                        
                        //disconnect all accounts to prevent TCP buffer leaking
                        [[MLXMPPManager sharedInstance] disconnectAll];
                        
                        //schedule a BGProcessingTaskRequest to process this further as soon as possible
                        //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                        DDLogInfo(@"calling scheduleBackgroundFetchingTask");
                        [self scheduleBackgroundFetchingTask];
                        
                    }
                    //wait for all pending intent donations of incoming messages to makeure those get a proper notification displayed
                    //(pending donations will never be honored with a notification otherwise)
                    [[MLNotificationManager sharedInstance] waitForDonations];
                    [DDLog flushLog];
                    [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
                    _bgTask = UIBackgroundTaskInvalid;
                }
                
                //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
            }];
        }
    } onQueue:dispatch_get_main_queue()];
}

-(void) handleBackgroundFetchingTask:(BGTask*) task
{
    DDLogInfo(@"RUNNING BGTASK");
    
    _bgFetch = task;
    weakify(task);
    task.expirationHandler = ^{
        strongify(task);
        DDLogWarn(@"*** BGTASK EXPIRED ***");
        [DDLog flushLog];
        
        BOOL background = [HelperTools isInBackground];
        
        @synchronized(self) {
            //ui background tasks expire at the same time as background fetching tasks
            //--> we have to check if an ui bg task is running and don't disconnect, if so
            if(background && _bgTask == UIBackgroundTaskInvalid)
            {
                //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
                [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                
                //disconnect all accounts to prevent TCP buffer leaking
                [[MLXMPPManager sharedInstance] disconnectAll];
                
                //schedule a new BGProcessingTaskRequest to process this further as soon as possible
                //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                [self scheduleBackgroundFetchingTask];
            }
            
            //wait for all pending intent donations of incoming messages to makeure those get a proper notification displayed
            //(pending donations will never be honored with a notification otherwise)
            [[MLNotificationManager sharedInstance] waitForDonations];
            
            //only signal success, if we are not in background anymore (otherwise we *really* expired without being idle)
            [DDLog flushLog];
            [task setTaskCompletedWithSuccess:!background];
            _bgFetch = nil;
        }
        
        if(background)
        {
            //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
        }
    };
    
    //only proceed with our BGTASK if the NotificationServiceExtension is not running
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension" withLoopHandler:^{
            [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        }];
    }
    
    if([[MLXMPPManager sharedInstance] hasConnectivity])
    {
        for(xmpp* xmppAccount in [[MLXMPPManager sharedInstance] connectedXMPP])
        {
            //try to send a ping. if it fails, it will reconnect
            DDLogVerbose(@"app delegate pinging");
            [xmppAccount unfreezed];
            [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        }
    }
    else
        DDLogWarn(@"BGTASK has *no* connectivity? That's strange!");
    
    //log bgtask ticks (and stop when the task expires)
    unsigned long tick = 0;
    while(_bgFetch != nil)
    {
        DDLogVerbose(@"BGTASK TICK: %lu", tick++);
        [DDLog flushLog];
        [NSThread sleepForTimeInterval:1.000];
    }
}

-(void) configureBackgroundFetchingTask
{
    [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBackgroundFetchingTask usingQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0) launchHandler:^(BGTask *task) {
        DDLogDebug(@"RUNNING BGTASK LAUNCH HANDLER");
        if(![HelperTools isInBackground])
        {
            DDLogDebug(@"Already in foreground, stopping bgtask");
            [_bgFetch setTaskCompletedWithSuccess:YES];
        }
        else
            [self handleBackgroundFetchingTask:task];
    }];
}

-(void) scheduleBackgroundFetchingTask
{
    [HelperTools dispatchSyncReentrant:^{
        NSError *error = NULL;
        // cancel existing task (if any)
        [BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:kBackgroundFetchingTask];
        // new task
        //BGAppRefreshTaskRequest* request = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:kBackgroundFetchingTask];
        BGProcessingTaskRequest* request = [[BGProcessingTaskRequest alloc] initWithIdentifier:kBackgroundFetchingTask];
        //do the same like the corona warn app from germany which leads to this hint: https://developer.apple.com/forums/thread/134031
        request.requiresNetworkConnectivity = YES;
        request.requiresExternalPower = NO;
        //this is needed because nil will start a new bg task before the old one did terminate
        //this triggers a bug in ios which will not give bg time to the new task despite already started and leave monal
        //freezed after being through half of the connection process
        request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:30];
        BOOL success = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
        if(!success) {
            // Errorcodes https://stackoverflow.com/a/58224050/872051
            DDLogError(@"Failed to submit BGTask request: %@", error);
        } else {
            DDLogVerbose(@"Success submitting BGTask request %@", request);
        }
    } onQueue:dispatch_get_main_queue()];
}

-(void) connectIfNecessary
{
    [self addBackgroundTask];
    [[MLXMPPManager sharedInstance] connectIfNecessary];
}

-(void) incomingWakeupWithCompletionHandler:(void (^)(UIBackgroundFetchResult result)) completionHandler
{
    if(![HelperTools isInBackground])
    {
        DDLogWarn(@"Ignoring incomingWakeupWithCompletionHandler: because app is in FG!");
        completionHandler(UIBackgroundFetchResultNoData);
        return;
    }
    
    NSString* completionId = [[NSUUID UUID] UUIDString];
    DDLogInfo(@"got incomingWakeupWithCompletionHandler with ID %@", completionId);
    
    //only proceed with handling wakeup if the NotificationServiceExtension is not running
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension" withLoopHandler:^{
            [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        }];
    }
    
    //don't use *self* connectIfNecessary] because we already have a background task here
    //that gets stopped once we call the completionHandler
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
    //register push completion handler and associated timer (use the GRACEFUL_TIMEOUT here, too)
    @synchronized(self) {
        _wakeupCompletions[completionId] = @{
            @"handler": completionHandler,
            @"timer": createTimer(GRACEFUL_TIMEOUT, (^{
                DDLogWarn(@"### Wakeup timer triggered for ID %@ ###", completionId);
                dispatch_async(dispatch_get_main_queue(), ^{
                    @synchronized(self) {
                        if([_wakeupCompletions objectForKey:completionId] != nil)
                        {
                            DDLogInfo(@"Handling wakeup completion %@", completionId);
                            
                            //we have to check if an ui bg task or background fetching task is running and don't disconnect, if so
                            BOOL background = [HelperTools isInBackground];
                            if(background && (_bgTask == UIBackgroundTaskInvalid || _bgFetch != nil))
                            {
                                //this has to be before account disconnects, to detect which accounts are/are not idle (e.g. don't have/have a sync error)
                                BOOL wasIdle = [[MLXMPPManager sharedInstance] allAccountsIdle] && [MLFiletransfer isIdle];
                                [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                                
                                //disconnect all accounts to prevent TCP buffer leaking
                                [[MLXMPPManager sharedInstance] disconnectAll];
                                
                                //schedule a new BGProcessingTaskRequest to process this further as soon as possible, if we are not idle
                                //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                                if(!wasIdle)
                                    [self scheduleBackgroundFetchingTask];
                            }
                            
                            if(background)
                            {
                                //wait for all pending intent donations of incoming messages to makeure those get a proper notification displayed
                                //(pending donations will never be honored with a notification otherwise)
                                [[MLNotificationManager sharedInstance] waitForDonations];
                            }
                            
                            //call completion (should be done *after* the idle state check because it could freeze the app)
                            DDLogInfo(@"Calling wakeup completion handler...");
                            [DDLog flushLog];
                            completionHandler(UIBackgroundFetchResultFailed);
                            [_wakeupCompletions removeObjectForKey:completionId];
                            
                            if(background)
                            {
                                //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                            }
                        }
                        else
                            DDLogWarn(@"Wakeup completion %@ got already handled and was removed from list!", completionId);
                    }
                });
            }))
        };
        DDLogInfo(@"Added timer %@ to wakeup completion list...", completionId);
    }
}

@end
