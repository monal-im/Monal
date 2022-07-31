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
#import "MBProgressHUD.h"

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
#import "chatViewController.h"

#define GRACEFUL_TIMEOUT            20.0
#define BGPROCESS_GRACEFUL_TIMEOUT  60.0

typedef void (^pushCompletion)(UIBackgroundFetchResult result);
static NSString* kBackgroundProcessingTask = @"im.monal.process";
static NSString* kBackgroundRefreshingTask = @"im.monal.refresh";

@interface MonalAppDelegate()
{
    NSMutableDictionary* _wakeupCompletions;
    UIBackgroundTaskIdentifier _bgTask;
    BGTask* _bgProcessing;
    BGTask* _bgRefreshing;
    monal_void_block_t _backgroundTimer;
    MLContact* _contactToOpen;
    monal_id_block_t _completionToCall;
    BOOL _shutdownPending;
    BOOL _wasFreezed;
}
@end

@implementation MonalAppDelegate

// **************************** xml parser and query language tests ****************************
-(void) runParserTests
{
    NSString* xml = @"<?xml version='1.0'?>\n\
        <stream:stream xmlns:stream='http://etherx.jabber.org/streams' version='1.0' xmlns='jabber:client' xml:lang='en' from='example.org' id='a344b8bb-518e-4456-9140-d15f66c1d2db'>\n\
        <stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>SCRAM-SHA-1</mechanism><mechanism>PLAIN</mechanism></mechanisms></stream:features>\n\
        <iq id='18382ACA-EF9D-4BC9-8779-7901C63B6631' to='user1@example.org/Monal-iOS.ef313600' xmlns='jabber:client' type='result' from='luloku@conference.example.org'><query xmlns='http://jabber.org/protocol/disco#info'><feature var='http://jabber.org/protocol/muc#request'/><feature var='muc_hidden'/><feature var='muc_unsecured'/><feature var='muc_membersonly'/><feature var='muc_unmoderated'/><feature var='muc_persistent'/><identity type='text' name='testchat gruppe' category='conference'/><feature var='urn:xmpp:mam:2'/><feature var='urn:xmpp:sid:0'/><feature var='muc_nonanonymous'/><feature var='http://jabber.org/protocol/muc'/><feature var='http://jabber.org/protocol/muc#stable_id'/><feature var='http://jabber.org/protocol/muc#self-ping-optimization'/><feature var='jabber:iq:register'/><feature var='vcard-temp'/><x type='result' xmlns='jabber:x:data'><field type='hidden' var='FORM_TYPE'><value>http://jabber.org/protocol/muc#roominfo</value></field><field label='Description' var='muc#roominfo_description' type='text-single'><value/></field><field label='Number of occupants' var='muc#roominfo_occupants' type='text-single'><value>2</value></field><field label='Allow members to invite new members' var='{http://prosody.im/protocol/muc}roomconfig_allowmemberinvites' type='boolean'><value>0</value></field><field label='Allow users to invite other users' var='muc#roomconfig_allowinvites' type='boolean'><value>0</value></field><field label='Title' var='muc#roomconfig_roomname' type='text-single'><value>testchat gruppe</value></field><field type='boolean' var='muc#roomconfig_changesubject'/><field type='text-single' var='{http://modules.prosody.im/mod_vcard_muc}avatar#sha1'/><field type='text-single' var='muc#roominfo_lang'><value/></field></x></query></iq>\n\
    ";
    
    DDLogInfo(@"creating parser delegate");
    MLBasePaser* delegate = [[MLBasePaser alloc] initWithCompletion:^(MLXMLNode* _Nullable parsedStanza) {
        if(parsedStanza != nil)
        {
            DDLogInfo(@"Got new parsed stanza: %@", parsedStanza);
            for(NSString* query in @[
                @"{http://jabber.org/protocol/disco#info}query/\\{http://jabber.org/protocol/muc#roominfo}result@muc#roomconfig_roomname\\",
                @"/{jabber:client}iq/{http://jabber.org/protocol/pubsub}pubsub/items<node~eu\\.siacs\\.conversations\\.axolotl\\.bundles:[0-9]+>@node",
            ])
            {
//yes, but this is not insecure because these are string literals boxed into an NSArray above rather than containing unchecked user input
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
                id result = [parsedStanza find:query];
#pragma clang diagnostic pop
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
    DDLogVerbose(@"Setting _shutdownPending to NO...");
    _shutdownPending = NO;
    _wasFreezed = NO;
    
    //[self runParserTests];
    return self;
}

#pragma mark -  APNS notification

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
    //BUT: don't do this if we are sending the sharesheet outbox
    if(launchOptions[UIApplicationLaunchOptionsURLKey] == nil || ![launchOptions[UIApplicationLaunchOptionsURLKey] isEqual:[NSURL URLWithString:@"monalOpen://"]])
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [MLFiletransfer doStartupCleanup];
        });
    
    //do image manager cleanup in a new thread to not slow down app startup
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleScheduleBackgroundTaskNotification:) name:kScheduleBackgroundTask object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(filetransfersNowIdle:) name:kMonalFiletransfersIdle object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showConnectionStatus:) name:kXMPPError object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnread) name:kMonalUpdateUnread object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(prepareForFreeze:) name:kMonalWillBeFreezed object:nil];
    
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
    UNAuthorizationOptions authOptions = UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionCriticalAlert | UNAuthorizationOptionAnnouncement | UNAuthorizationOptionProvidesAppNotificationSettings;
#if TARGET_OS_MACCATALYST
    authOptions |= UNAuthorizationOptionProvisional;
#endif
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
                
                if((oldToken != nil && oldToken.length != 0) || oldGranted)
                {
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
    DDLogInfo(@"calling MonalAppDelegate configureBackgroundTasks");
    [self configureBackgroundTasks];
    
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
    //NOTE: the connectedXMPP array does not exist at this point --> calling this methods only updates the state without messing with the accounts themselves
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
            [[MLXMPPManager sharedInstance] noLongerInFocus];
    }
    else if([notification.name isEqualToString:@"NSWindowDidBecomeKeyNotification"])
    {
        DDLogInfo(@"Window got focus (key window)...");
        @synchronized(self) {
            DDLogVerbose(@"Setting _shutdownPending to NO...");
            _shutdownPending = NO;
        }
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
        MLAssert(NO, @"Got 'Monal.disconnectAll' while in mainapp. This should NEVER happen!", message);
    else if([message[@"name"] isEqualToString:@"Monal.connectIfNecessary"])
    {
        DDLogInfo(@"Got connectIfNecessary IPC message");
        //(re)connect all accounts
        [self connectIfNecessary];
    }
}

-(void) applicationDidBecomeActive:(UIApplication*) application
{
    if([[MLXMPPManager sharedInstance] connectedXMPP].count > 0)
    {
        //show spinner
        [self.activeChats.spinner startAnimating];
    }
    else
    {
        //hide spinner
        [self.activeChats.spinner stopAnimating];
    }
}

-(void) setActiveChats:(UIViewController*) activeChats
{
    _activeChats = (ActiveChatsViewController*)activeChats;
    [self openChatOfContact:_contactToOpen withCompletion:_completionToCall];
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
    //make sure we have the active chats ui loaded and accessible
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while(self.activeChats == nil)
            usleep(100000);
        dispatch_async(dispatch_get_main_queue(), ^{
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
                
                weakify(self);
                [self.activeChats showRegisterWithUsername:username onHost:host withToken:preauthToken usingCompletion:^(NSNumber* accountNo) {
                    strongify(self);
                    DDLogVerbose(@"Got accountNo for newly registered account: %@", accountNo);
                    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:accountNo];
                    DDLogInfo(@"Got newly registered account: %@", account);
                    
                    //this should never happen
                    MLAssert(account != nil, @"Can not use account after register!", (@{
                        @"components": components,
                        @"username": username,
                        @"host": host,
                    }));
                    
                    if(account != nil)      //silence memory warning despite assertion above
                    {
                        MLContact* contact = [MLContact createContactFromJid:jid andAccountNo:account.accountNo];
                        DDLogInfo(@"Adding contact to roster: %@", contact);
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
                DDLogInfo(@"Adding contact to roster: %@", contact);
                //will handle group joins and normal contacts transparently and even implement roster subscription pre-approval
                [[MLXMPPManager sharedInstance] addContact:contact withPreauthToken:preauthToken];
                [[DataLayer sharedInstance] addActiveBuddies:jid forAccount:account.accountNo];
                [self openChatOfContact:contact];
                return;
            }
            
            if(isGroupJoin && account)
            {
                MLContact* contact = [MLContact createContactFromJid:jid andAccountNo:account.accountNo];
                contact.isGroup = YES;                                  //this is a group --> tell addContact: to join this group
                //wait for join to finish before opening contact
                NSNumber* accountNo = account.accountNo;                //needed because of retain cycle
                [account.mucProcessor addUIHandler:^(id _data) {
                    NSDictionary* data = (NSDictionary*)_data;
                    if(![data[@"success"] boolValue])
                    {
                        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error entering groupchat", @"") message:data[@"errorMessage"] preferredStyle:UIAlertControllerStyleAlert];
                        [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                        }]];
                        [self.activeChats presentViewController:messageAlert animated:YES completion:nil];
                        [[MLXMPPManager sharedInstance] removeContact:contact];
                        return;
                    }
                    [[DataLayer sharedInstance] addActiveBuddies:jid forAccount:accountNo];
                    [self openChatOfContact:contact];
                } forMuc:jid];
                [[MLXMPPManager sharedInstance] addContact:contact];    //will handle group joins and normal contacts transparently
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
        });
    });
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
        //make sure activechats ui is properly initialized when calling this
        createQueuedTimer(0.5, dispatch_get_main_queue(), (^{
            DDLogInfo(@"Got monalOpen:// url, trying to send all outboxes...");
            [self sendAllOutboxes];
        }));
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
        [self incomingWakeupWithCompletionHandler:^(UIBackgroundFetchResult result __unused) {
            completionHandler();
        }];
        
        MLContact* fromContact = [MLContact createContactFromJid:response.notification.request.content.userInfo[@"fromContactJid"] andAccountNo:response.notification.request.content.userInfo[@"fromContactAccountId"]];
        NSString* messageId = response.notification.request.content.userInfo[@"messageId"];
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:fromContact.accountId];
        MLAssert(fromContact, @"fromContact should not be nil");
        MLAssert(messageId, @"messageId should not be nil");
        MLAssert(account, @"account should not be nil");
        
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
            [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:textResponse.userText toContact:fromContact isEncrypted:encrypted uploadInfo:nil withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
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

-(void) userNotificationCenter:(UNUserNotificationCenter*) center openSettingsForNotification:(UNNotification*) notification
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        while(self.activeChats == nil)
            usleep(100000);
        dispatch_async(dispatch_get_main_queue(), ^{
            [(ActiveChatsViewController*)self.activeChats showPrivacySettings];
        });
    });
}

-(void) openChatOfContact:(MLContact* _Nullable) contact
{
    return [self openChatOfContact:contact withCompletion:nil];
}

-(void) openChatOfContact:(MLContact* _Nullable) contact withCompletion:(monal_id_block_t _Nullable) completion
{
    if(contact != nil)
        _contactToOpen = contact;
    if(completion != nil)
        _completionToCall = completion;
    
    if(self.activeChats != nil && _contactToOpen != nil)
    {
        // the timer makes sure the view is properly initialized when opning the chat
        createQueuedTimer(0.5, dispatch_get_main_queue(), (^{
            if(self->_contactToOpen != nil)
            {
                DDLogDebug(@"Opening chat for contact %@", [contact contactJid]);
                // open new chat
                [(ActiveChatsViewController*)self.activeChats presentChatWithContact:self->_contactToOpen andCompletion:self->_completionToCall];
            }
            else
                DDLogDebug(@"_contactToOpen changed to nil, not opening chat for contact %@", [contact contactJid]);
            self->_contactToOpen = nil;
            self->_completionToCall = nil;
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

-(void) startBackgroundTimer:(double) timeout
{
    //cancel old background timer if still running and start a new one
    //this timer will fire after timeout seconds in background and disconnect gracefully (e.g. when fully idle the next time)
    if(_backgroundTimer)
        _backgroundTimer();
    _backgroundTimer = createTimer(timeout, ^{
        //mark timer as *not* running
        self->_backgroundTimer = nil;
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

-(UIViewController*) getTopViewController
{
    UIViewController* topViewController = self.window.rootViewController;
    while(topViewController.presentedViewController)
        topViewController = topViewController.presentedViewController;
    return topViewController;
}

-(void) prepareForFreeze:(NSNotification*) notification
{
    for(xmpp* account in [MLXMPPManager sharedInstance].connectedXMPP)
        [account freeze];
    _wasFreezed = YES;
    @synchronized(self) {
        DDLogVerbose(@"Setting _shutdownPending to NO...");
        _shutdownPending = NO;
    }
}

-(void) applicationWillEnterForeground:(UIApplication*) application
{
    DDLogInfo(@"Entering FG");
    @synchronized(self) {
        DDLogVerbose(@"Setting _shutdownPending to NO...");
        _shutdownPending = NO;
    }
    
    //only show loading HUD if we really got freezed before
    MBProgressHUD* loadingHUD;
    if(_wasFreezed)
    {
        loadingHUD = [MBProgressHUD showHUDAddedTo:[self getTopViewController].view animated:YES];
        loadingHUD.label.text = NSLocalizedString(@"Refreshing...", @"");
        loadingHUD.mode = MBProgressHUDModeIndeterminate;
        loadingHUD.removeFromSuperViewOnHide = YES;
        
        _wasFreezed = NO;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //make sure the progress HUD is displayed before freezing the main thread
        //only proceed with foregrounding if the NotificationServiceExtension is not running
        [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
        {
            DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
            [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension" withLoopHandler:^{
                [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
            }];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if(loadingHUD != nil)
                loadingHUD.hidden = YES;
            
            //trigger view updates (this has to be done because the NotificationServiceExtension could have updated the database some time ago)
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
            
            //cancel already running background timer, we are now foregrounded again
            [self stopBackgroundTimer];
            
            [self addBackgroundTask];
            [[MLXMPPManager sharedInstance] nowForegrounded];           //NOTE: this will unfreeze all queues in our accounts
        });
    });
}

-(void) nowReallyBackgrounded
{
    [self addBackgroundTask];
    [[MLXMPPManager sharedInstance] nowBackgrounded];
    [self startBackgroundTimer:GRACEFUL_TIMEOUT];
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
        [[MLXMPPManager sharedInstance] noLongerInFocus];
#else
    [self nowReallyBackgrounded];
#endif
}

-(void) applicationWillTerminate:(UIApplication *)application
{
    @synchronized(self) {
        DDLogVerbose(@"Setting _shutdownPending to YES...");
        _shutdownPending = YES;
        DDLogWarn(@"|~~| T E R M I N A T I N G |~~|");
        [self scheduleBackgroundTask:YES];        //make sure delivery will be attempted, if needed (force as soon as possible)
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
        DDLogInfo(@"|~~| T E R M I N A T E D |~~|");
        [DDLog flushLog];
    }
}

#pragma mark - error feedback

-(void) showConnectionStatus:(NSNotification*) notification
{
    //this will show an error banner but only if our app is foregrounded
    DDLogWarn(@"Got xmpp error %@", notification);
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
    else
        DDLogWarn(@"Not showing error banner: app not in focus!");
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
        
        //hide spinner
        [self.activeChats.spinner stopAnimating];
        
        //use a synchronized block to disconnect only once
        @synchronized(self) {
            if(_backgroundTimer != nil || [_wakeupCompletions count] > 0)
            {
                DDLogInfo(@"### ignoring idle state because background timer or wakeup completion timers are still running ###");
                return;
            }
            if(_shutdownPending)
            {
                DDLogInfo(@"### ignoring idle state because a shutdown is already pending ###");
                return;
            }
            
            DDLogInfo(@"### checking if background is still needed ###");
            BOOL background = [HelperTools isInBackground];
            if(background)
            {
                DDLogInfo(@"### All accounts idle, disconnecting and stopping all background tasks ###");
                [DDLog flushLog];
                DDLogVerbose(@"Setting _shutdownPending to YES...");
                _shutdownPending = YES;
                [[MLXMPPManager sharedInstance] disconnectAll];     //disconnect all accounts to prevent TCP buffer leaking
                [self scheduleBackgroundTask:NO];           //request bg fetch execution in BGFETCH_DEFAULT_INTERVAL seconds
                [HelperTools dispatchSyncReentrant:^{
                    BOOL stopped = NO;
                    //make sure this will be done only once, even if we have an uikit bgtask and a bg fetch running simultaneously
                    if(self->_bgTask != UIBackgroundTaskInvalid || self->_bgProcessing != nil || self->_bgRefreshing != nil)
                    {
                        //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                        DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                    }
                    if(self->_bgTask != UIBackgroundTaskInvalid)
                    {
                        DDLogDebug(@"stopping UIKit _bgTask");
                        [DDLog flushLog];
                        UIBackgroundTaskIdentifier task = self->_bgTask;
                        self->_bgTask = UIBackgroundTaskInvalid;
                        [[UIApplication sharedApplication] endBackgroundTask:task];
                        stopped = YES;
                    }
                    if(self->_bgProcessing != nil)
                    {
                        DDLogDebug(@"stopping backgroundProcessingTask");
                        [DDLog flushLog];
                        BGTask* task = self->_bgProcessing;
                        self->_bgProcessing = nil;
                        [task setTaskCompletedWithSuccess:YES];
                        stopped = YES;
                    }
                    if(self->_bgRefreshing != nil)
                    {
                        DDLogDebug(@"stopping backgroundRefreshingTask");
                        [DDLog flushLog];
                        BGTask* task = self->_bgRefreshing;
                        self->_bgRefreshing = nil;
                        [task setTaskCompletedWithSuccess:YES];
                        stopped = YES;
                    }
                    if(!stopped)
                    {
                        DDLogDebug(@"no background tasks running, nothing to stop");
                        [DDLog flushLog];
                    }
                } onQueue:dispatch_get_main_queue()];
            }
        }
    }
}

-(void) addBackgroundTask
{
    [HelperTools dispatchSyncReentrant:^{
        //log both cases if present
        if(self->_bgTask != UIBackgroundTaskInvalid)
            DDLogVerbose(@"Not starting UIKit background task, already running: %d", (int)self->_bgTask);
        if(self->_bgProcessing != nil)
            DDLogVerbose(@"Not starting UIKit background task, bg task already running: %@", self->_bgProcessing);
        if(self->_bgRefreshing != nil)
            DDLogVerbose(@"Not starting UIKit background task, bg task already running: %@", self->_bgRefreshing);
        //don't start uikit bg task if it's already running or a bg fetch is running already
        if(self->_bgTask == UIBackgroundTaskInvalid && self->_bgProcessing == nil && self->_bgRefreshing == nil)
        {
            DDLogInfo(@"Starting UIKit background task...");
            //indicate we want to do work even if the app is put into background
            self->_bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
                DDLogWarn(@"BG WAKE EXPIRING");
                [DDLog flushLog];
                
                @synchronized(self) {
                    //ui background tasks expire at the same time as background processing/refreshing tasks
                    //--> we have to check if a background processing/refreshing task is running and don't disconnect, if so
                    if(self->_bgProcessing == nil && self->_bgRefreshing == nil)
                    {
                        DDLogVerbose(@"Setting _shutdownPending to YES...");
                        self->_shutdownPending = YES;
                        DDLogDebug(@"_bgProcessing == nil && _bgRefreshing == nil --> disconnecting and ending background task");
                        
                        //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
                        [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                        
                        //disconnect all accounts to prevent TCP buffer leaking
                        [[MLXMPPManager sharedInstance] disconnectAll];
                        
                        //schedule a BGProcessingTaskRequest to process this further as soon as possible
                        //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                        [self scheduleBackgroundTask:YES];      //force as soon as possible
                        
                        //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                        DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                    }
                    else
                        DDLogDebug(@"_bgProcessing != nil || _bgRefreshing != nil --> not disconnecting");
                    
                    DDLogDebug(@"stopping UIKit _bgTask");
                    [DDLog flushLog];
                    UIBackgroundTaskIdentifier task = self->_bgTask;
                    self->_bgTask = UIBackgroundTaskInvalid;
                    [[UIApplication sharedApplication] endBackgroundTask:task];
                }
            }];
        }
    } onQueue:dispatch_get_main_queue()];
}

-(void) handleBackgroundProcessingTask:(BGTask*) task
{
    DDLogInfo(@"RUNNING BGPROCESSING SETUP HANDLER");
    
    _bgProcessing = task;
    weakify(task);
    task.expirationHandler = ^{
        strongify(task);
        DDLogWarn(@"*** BGPROCESSING EXPIRED ***");
        [DDLog flushLog];
        
        BOOL background = [HelperTools isInBackground];
        
        DDLogVerbose(@"Waiting for @synchronized(self)...");
        @synchronized(self) {
            DDLogVerbose(@"Now entered @synchronized(self) block...");
            //ui background tasks expire at the same time as background fetching tasks
            //--> we have to check if an ui bg task is running and don't disconnect, if so
            if(background && self->_bgTask == UIBackgroundTaskInvalid)
            {
                DDLogVerbose(@"Setting _shutdownPending to YES...");
                self->_shutdownPending = YES;
                DDLogDebug(@"_bgTask == UIBackgroundTaskInvalid --> disconnecting and ending background task");
                
                //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
                [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                
                //disconnect all accounts to prevent TCP buffer leaking
                [[MLXMPPManager sharedInstance] disconnectAll];
                
                //schedule a new BGProcessingTaskRequest to process this further as soon as possible
                //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                [self scheduleBackgroundTask:YES];      //force as soon as possible
                
                //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
            }
            else
                DDLogDebug(@"_bgTask != UIBackgroundTaskInvalid --> not disconnecting");
            
            DDLogDebug(@"stopping backgroundProcessingTask: %@", task);
            [DDLog flushLog];
            self->_bgProcessing = nil;
            //only signal success, if we are not in background anymore (otherwise we *really* expired without being idle)
            [task setTaskCompletedWithSuccess:!background];
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
    
    if(self->_bgTask != UIBackgroundTaskInvalid)
    {
        DDLogDebug(@"stopping UIKit _bgTask, not needed when running a bg task");
        [DDLog flushLog];
        UIBackgroundTaskIdentifier task = self->_bgTask;
        self->_bgTask = UIBackgroundTaskInvalid;
        [[UIApplication sharedApplication] endBackgroundTask:task];
    }
    
    if(self->_bgRefreshing != nil)
    {
        DDLogDebug(@"stopping bg refreshing task, not needed when running a (longer running) bg processing task");
        [DDLog flushLog];
        BGTask* refreshingTask = self->_bgRefreshing;
        self->_bgRefreshing = nil;
        [refreshingTask setTaskCompletedWithSuccess:YES];
    }
    
    if([[MLXMPPManager sharedInstance] hasConnectivity])
    {
        [self startBackgroundTimer:BGPROCESS_GRACEFUL_TIMEOUT];
        @synchronized(self) {
            DDLogVerbose(@"Setting _shutdownPending to NO...");
            _shutdownPending = NO;
        }
        //don't use *self* connectIfNecessary, because we don't need an additional UIKit bg task, this one is already a bg task
        [[MLXMPPManager sharedInstance] connectIfNecessary];
    }
    else
        DDLogWarn(@"BGTASK has *no* connectivity? That's strange!");
    
    //request another execution in BGFETCH_DEFAULT_INTERVAL seconds
    [self scheduleBackgroundTask:NO];
    
    DDLogInfo(@"BGPROCESSING SETUP HANDLER COMPLETED SUCCESSFULLY...");
}

-(void) handleBackgroundRefreshingTask:(BGTask*) task
{
    DDLogInfo(@"RUNNING BGREFRESHING SETUP HANDLER");
    
    _bgRefreshing = task;
    weakify(task);
    task.expirationHandler = ^{
        strongify(task);
        DDLogWarn(@"*** BGREFRESHING EXPIRED ***");
        [DDLog flushLog];
        
        BOOL background = [HelperTools isInBackground];
        
        DDLogVerbose(@"Waiting for @synchronized(self)...");
        @synchronized(self) {
            DDLogVerbose(@"Now entered @synchronized(self) block...");
            //ui background tasks expire at the same time as background fetching tasks
            //--> we have to check if an ui bg task is running and don't disconnect, if so
            if(background && self->_bgTask == UIBackgroundTaskInvalid)
            {
                DDLogVerbose(@"Setting _shutdownPending to YES...");
                self->_shutdownPending = YES;
                DDLogDebug(@"_bgTask == UIBackgroundTaskInvalid --> disconnecting and ending background task");
                
                //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
                [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                
                //disconnect all accounts to prevent TCP buffer leaking
                [[MLXMPPManager sharedInstance] disconnectAll];
                
                //schedule a new BGProcessingTaskRequest to process this further as soon as possible
                //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                [self scheduleBackgroundTask:YES];      //force as soon as possible
                
                //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
            }
            else
                DDLogDebug(@"_bgTask != UIBackgroundTaskInvalid --> not disconnecting");
            
            DDLogDebug(@"stopping backgroundProcessingTask: %@", task);
            [DDLog flushLog];
            self->_bgRefreshing = nil;
            //only signal success, if we are not in background anymore (otherwise we *really* expired without being idle)
            [task setTaskCompletedWithSuccess:!background];
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
    
    if(self->_bgTask != UIBackgroundTaskInvalid)
    {
        DDLogDebug(@"stopping UIKit _bgTask, not needed when running a bg task");
        [DDLog flushLog];
        UIBackgroundTaskIdentifier task = self->_bgTask;
        self->_bgTask = UIBackgroundTaskInvalid;
        [[UIApplication sharedApplication] endBackgroundTask:task];
    }
    
    if([[MLXMPPManager sharedInstance] hasConnectivity])
    {
        [self startBackgroundTimer:GRACEFUL_TIMEOUT];
        @synchronized(self) {
            DDLogVerbose(@"Setting _shutdownPending to NO...");
            _shutdownPending = NO;
        }
        //don't use *self* connectIfNecessary, because we don't need an additional UIKit bg task, this one is already a bg task
        [[MLXMPPManager sharedInstance] connectIfNecessary];
    }
    else
        DDLogWarn(@"BGTASK has *no* connectivity? That's strange!");
    
    //request another execution in BGFETCH_DEFAULT_INTERVAL seconds
    [self scheduleBackgroundTask:NO];
    
    DDLogInfo(@"BGREFRESHING SETUP HANDLER COMPLETED SUCCESSFULLY...");
}

-(void) configureBackgroundTasks
{
    [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBackgroundProcessingTask usingQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0) launchHandler:^(BGTask *task) {
        DDLogDebug(@"RUNNING BGPROCESSING LAUNCH HANDLER");
        DDLogInfo(@"BG time available: %f", [UIApplication sharedApplication].backgroundTimeRemaining);
        if(![HelperTools isInBackground])
        {
            DDLogDebug(@"Already in foreground, stopping bgtask");
            [task setTaskCompletedWithSuccess:YES];
            return;
        }
        @synchronized(self) {
            if(self->_bgProcessing != nil)
            {
                DDLogDebug(@"Already running a bg processing task, stopping second bg processing task");
                [task setTaskCompletedWithSuccess:YES];
                return;
            }
        }
        [self handleBackgroundProcessingTask:task];
    }];
    
    [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBackgroundRefreshingTask usingQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0) launchHandler:^(BGTask *task) {
        DDLogDebug(@"RUNNING BGREFRESHING LAUNCH HANDLER");
        DDLogInfo(@"BG time available: %f", [UIApplication sharedApplication].backgroundTimeRemaining);
        if(![HelperTools isInBackground])
        {
            DDLogDebug(@"Already in foreground, stopping bgtask");
            [task setTaskCompletedWithSuccess:YES];
            return;
        }
        @synchronized(self) {
            if(self->_bgProcessing != nil)
            {
                DDLogDebug(@"Already running bg processing task, stopping new bg refreshing task");
                [task setTaskCompletedWithSuccess:YES];
                return;
            }
        }
        @synchronized(self) {
            if(self->_bgRefreshing != nil)
            {
                DDLogDebug(@"Already running a bg refreshing task, stopping second bg refreshing task");
                [task setTaskCompletedWithSuccess:YES];
                return;
            }
        }
        [self handleBackgroundRefreshingTask:task];
    }];
}

-(void) handleScheduleBackgroundTaskNotification:(NSNotification*) notification
{
    BOOL force = YES;
    if(notification.userInfo)
        force = [notification.userInfo[@"force"] boolValue];
    [self scheduleBackgroundTask:force];
}

-(void) scheduleBackgroundTask:(BOOL) force
{
    DDLogInfo(@"Scheduling new BackgroundTask with force=%s...", force ? "yes" : "no");
    [HelperTools dispatchSyncReentrant:^{
        NSError* error;
        if(force)
        {
            // cancel existing task (if any)
            //[BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:kBackgroundProcessingTask];
            // new task
            BGProcessingTaskRequest* processingRequest = [[BGProcessingTaskRequest alloc] initWithIdentifier:kBackgroundProcessingTask];
            //do the same like the corona warn app from germany which leads to this hint: https://developer.apple.com/forums/thread/134031
            processingRequest.earliestBeginDate = nil;
            processingRequest.requiresNetworkConnectivity = YES;
            processingRequest.requiresExternalPower = NO;
            if(![[BGTaskScheduler sharedScheduler] submitTaskRequest:processingRequest error:&error])
            {
                // Errorcodes https://stackoverflow.com/a/58224050/872051
                DDLogError(@"Failed to submit BGTask request %@: %@", processingRequest, error);
            }
            else
                DDLogVerbose(@"Success submitting BGTask request %@", processingRequest);
        }
        else
        {
            // cancel existing task (if any)
            //[BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:kBackgroundRefreshingTask];
            // new task
            BGAppRefreshTaskRequest* refreshingRequest = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:kBackgroundRefreshingTask];
            //do the same like the corona warn app from germany which leads to this hint: https://developer.apple.com/forums/thread/134031
            refreshingRequest.earliestBeginDate = nil;
            //refreshingRequest.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:BGFETCH_DEFAULT_INTERVAL];
            if(![[BGTaskScheduler sharedScheduler] submitTaskRequest:refreshingRequest error:&error])
            {
                // Errorcodes https://stackoverflow.com/a/58224050/872051
                DDLogError(@"Failed to submit BGTask request %@: %@", refreshingRequest, error);
            }
            else
                DDLogVerbose(@"Success submitting BGTask request %@", refreshingRequest);
        }
    } onQueue:dispatch_get_main_queue()];
}

-(void) connectIfNecessary
{
    @synchronized(self) {
        DDLogVerbose(@"Setting _shutdownPending to NO...");
        _shutdownPending = NO;
    }
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
    //we need the wakeup completion handling even if a uikit bgtask or bgprocessing or bgrefreshing is running because we want to keep
    //the connection for a few seconds to allow message receipts to come in instead of triggering the appex
    
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
                        DDLogInfo(@"Handling wakeup completion %@", completionId);
                        BOOL background = [HelperTools isInBackground];
                        
                        //we have to check if an ui bg task or background processing/refreshing task is running and don't disconnect, if so
                        if(background && self->_bgTask == UIBackgroundTaskInvalid && self->_bgProcessing == nil && self->_bgRefreshing == nil)
                        {
                            DDLogVerbose(@"Setting _shutdownPending to YES...");
                            self->_shutdownPending = YES;
                            DDLogDebug(@"background && _bgTask == UIBackgroundTaskInvalid && _bgProcessing == nil && _bgRefreshing == nil --> disconnecting and feeding wakeup completion");
                            
                            //this has to be before account disconnects, to detect which accounts are/are not idle (e.g. don't have/have a sync error)
                            BOOL wasIdle = [[MLXMPPManager sharedInstance] allAccountsIdle] && [MLFiletransfer isIdle];
                            [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                            
                            //disconnect all accounts to prevent TCP buffer leaking
                            [[MLXMPPManager sharedInstance] disconnectAll];
                            
                            //schedule a new BGProcessingTaskRequest to process this further as soon as possible, if we are not idle
                            //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                            [self scheduleBackgroundTask:!wasIdle];
                            
                            //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                            DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                        }
                        else
                            DDLogDebug(@"NOT (background && _bgTask == UIBackgroundTaskInvalid && _bgProcessing == nil && _bgRefreshing == nil) --> not disconnecting");
                        
                        //call completion (should be done *after* the idle state check because it could freeze the app)
                        DDLogInfo(@"Calling wakeup completion handler...");
                        [DDLog flushLog];
                        [self->_wakeupCompletions removeObjectForKey:completionId];
                        completionHandler(UIBackgroundFetchResultFailed);
                        
                        //trigger disconnect if we are idle and no timer is blocking us now
                        if(self->_bgTask != UIBackgroundTaskInvalid || self->_bgProcessing != nil || self->_bgRefreshing != nil)
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [self checkIfBackgroundTaskIsStillNeeded];
                            });
                    }
                });
            }))
        };
        DDLogInfo(@"Added timer %@ to wakeup completion list...", completionId);
    }
}


#pragma mark - share sheet added

//send all sharesheet outboxes (this method will be called by AppDelegate if opened via monalOpen:// url)
-(void) sendAllOutboxes
{
    //delay outbox sending until we have an active chats ui
    if(self.activeChats == nil)
    {
        createQueuedTimer(0.5, dispatch_get_main_queue(), (^{
            [self sendAllOutboxes];
        }));
        return;
    }
    
    for(NSDictionary* payload in [[DataLayer sharedInstance] getShareSheetPayload])
    {
        DDLogInfo(@"Sending outbox entry: %@", payload);
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:payload[@"account_id"]];
        
        if(account == nil)
        {
            UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Sharing failed", @"") message:[NSString stringWithFormat:NSLocalizedString(@"Cannot share something with disabled/deleted account, destination: %@, internal account id: %@", @""), payload[@"recipient"], payload[@"account_id"]] preferredStyle:UIAlertControllerStyleAlert];
            [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
            }]];
            [self.activeChats presentViewController:messageAlert animated:YES completion:nil];
            [[DataLayer sharedInstance] deleteShareSheetPayloadWithId:payload[@"id"]];
            continue;
        }
        
        MLContact* contact = [MLContact createContactFromJid:payload[@"recipient"] andAccountNo:account.accountNo];
        DDLogVerbose(@"Trying to open chat of outbox receiver: %@", contact);
        [[DataLayer sharedInstance] addActiveBuddies:contact.contactJid forAccount:contact.accountId];
        //don't use [self openChatOfContact:withCompletion:] because it's asynchronous and can only handle one contact at a time (e.g. until the asynchronous execution finished)
        //we can invoke the activeChats interface directly instead, because we already did the necessary preparations ourselves
        [(ActiveChatsViewController*)self.activeChats presentChatWithContact:contact andCompletion:^(NSNumber* _Nonnull status) {
            //this should always succeed (@NO is only returned if contact is nil or the contact is not an active buddy
            //if([status boolValue] && self.activeChats.currentChatViewController != nil)
            
            monal_id_block_t sendCommentAndCleanup = ^(NSDictionary* payload) {
                if([payload[@"comment"] length] > 0)
                {
                    MLContact* contact = [MLContact createContactFromJid:payload[@"recipient"] andAccountNo:account.accountNo];
                    BOOL encrypted = [[DataLayer sharedInstance] shouldEncryptForJid:contact.contactJid andAccountNo:contact.accountId];
                    [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:payload[@"comment"] toContact:contact isEncrypted:encrypted uploadInfo:nil withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                        DDLogInfo(@"SHARESHEET_SEND_COMMENT success=%@, account=%@, messageIdSentObject=%@", successSendObject ? @"YES" : @"NO", account.accountNo, messageIdSentObject);
                        [[DataLayer sharedInstance] deleteShareSheetPayloadWithId:payload[@"id"]];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
                            if(self.activeChats.currentChatViewController != nil)
                            {
                                [self.activeChats.currentChatViewController scrollToBottom];
                                [self.activeChats.currentChatViewController hideUploadHUD];
                            }
                        });
                    }];
                }
                else
                {
                    [[DataLayer sharedInstance] deleteShareSheetPayloadWithId:payload[@"id"]];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
                        if(self.activeChats.currentChatViewController != nil)
                        {
                            [self.activeChats.currentChatViewController scrollToBottom];
                            [self.activeChats.currentChatViewController hideUploadHUD];
                        }
                    });
                }
            };
            
            BOOL encrypted = [[DataLayer sharedInstance] shouldEncryptForJid:contact.contactJid andAccountNo:contact.accountId];
            if([payload[@"type"] isEqualToString:@"geo"] || [payload[@"type"] isEqualToString:@"url"] || [payload[@"type"] isEqualToString:@"text"])
            {
                [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:payload[@"data"] toContact:contact isEncrypted:encrypted uploadInfo:nil withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                    DDLogInfo(@"SHARESHEET_SEND_DATA success=%@, account=%@, messageIdSentObject=%@", successSendObject ? @"YES" : @"NO", account.accountNo, messageIdSentObject);
                    sendCommentAndCleanup(payload);
                }];
            }
            else if([payload[@"type"] isEqualToString:@"image"] || [payload[@"type"] isEqualToString:@"file"] || [payload[@"type"] isEqualToString:@"contact"] || [payload[@"type"] isEqualToString:@"audiovisual"])
            {
                DDLogInfo(@"Got %@ upload: %@", payload[@"type"], payload[@"data"]);
                [self.activeChats.currentChatViewController showUploadHUD];
                $call(payload[@"data"], $ID(account), $BOOL(encrypted), $ID(completion, (^(NSString* url, NSString* mimeType, NSNumber* size, NSError* error) {
                    if(error != nil)
                    {
                        DDLogError(@"Failed to upload outbox file: %@", error);
                        NSMutableDictionary* payloadCopy = [NSMutableDictionary dictionaryWithDictionary:payload];
                        payloadCopy[@"comment"] = @"";      //make sure we don't send any comment in sendCommentAndCleanup() if uploading the file failed
                        sendCommentAndCleanup(payloadCopy);
                        
                        UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Failed to share file", @"") message:[NSString stringWithFormat:NSLocalizedString(@"Error: %@", @""), error] preferredStyle:UIAlertControllerStyleAlert];
                        [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                        }]];
                        [self.activeChats presentViewController:messageAlert animated:YES completion:nil];
                    }
                    else
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:url toContact:contact isEncrypted:encrypted uploadInfo:@{@"mimeType": mimeType, @"size": size} withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                                DDLogInfo(@"SHARESHEET_SEND_DATA success=%@, account=%@, messageIdSentObject=%@", successSendObject ? @"YES" : @"NO", account.accountNo, messageIdSentObject);
                                sendCommentAndCleanup(payload);
                            }];
                        });
                })));
            }
            else
                MLAssert(NO, @"Outbox payload type unknown", payload);
        }];
    }
}

@end
