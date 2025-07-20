//
//  SworIMAppDelegate.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/16/08.
//  Copyright __MyCompanyName__ 2008. All rights reserved.
//

#import <BackgroundTasks/BackgroundTasks.h>
#import "MonalAppDelegate.h"
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/HelperTools.h>
#import "MLNotificationManager.h"
#import <monalxmpp/DataLayer.h>
#import <monalxmpp/MLImageManager.h>
#import "ActiveChatsViewController.h"
#import <monalxmpp/IPC.h>
#import <monalxmpp/MLProcessLock.h>
#import <monalxmpp/MLFileTransfer.h>
#import <monalxmpp/xmpp.h>
#import <monalxmpp/MLNotificationQueue.h>
#import "MLSettingsAboutViewController.h"
#import <monalxmpp/MLMucProcessor.h>
#import "MBProgressHUD.h"
#import <monalxmpp/MLVoIPProcessor.h>
#import <monalxmpp/MLUDPLogger.h>
#import "MLCrashReporter.h"
#import <Monal-Swift.h>

@import NotificationBannerSwift;
@import UserNotifications;

#import <monalxmpp/MLXMPPManager.h>

#import <AVKit/AVKit.h>

#import "MLBasePaser.h"
#import <monalxmpp/MLXMLNode.h>
#import <monalxmpp/XMPPStanza.h>
#import <monalxmpp/XMPPDataForm.h>
#import "XMPPIQ.h"
#import <monalxmpp/XMPPPresence.h>
#import "XMPPMessage.h"
#import "chatViewController.h"

@import Intents;

#define GRACEFUL_TIMEOUT            20.0
#define BGPROCESS_GRACEFUL_TIMEOUT  60.0

typedef void (^pushCompletion)(UIBackgroundFetchResult result);

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
    BOOL _wasFrozen;
    NotificationBannerQueue* _bannerQueue;
}
@end

@implementation MonalAppDelegate

-(id) init
{
    //someone (suspect: AppKit) resets our exception handler between the call to [MonalAppDelegate initialize] and [MonalAppDelegate init]
    [HelperTools installExceptionHandler];
    
    self = [super init];
    _bgTask = UIBackgroundTaskInvalid;
    _wakeupCompletions = [NSMutableDictionary new];
    DDLogVerbose(@"Setting _shutdownPending to NO...");
    _shutdownPending = NO;
    _wasFrozen = NO;
    _showOneClickButton = YES;
    _bannerQueue = [[NotificationBannerQueue alloc] initWithMaxBannersOnScreenSimultaneously:1];
    
    //register BGTasks as early as possible to make sure a subsequent app termination
    //without proper "bootup" won't crash on unknown bgtask identifiers
    DDLogInfo(@"calling MonalAppDelegate configureBackgroundTasks");
    [self configureBackgroundTasks];
    
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
    DDLogError(@"APNS push reg error %@", error);
    [[MLXMPPManager sharedInstance] removeToken];
    [MLXMPPManager sharedInstance].apnsError = error;
}

#pragma mark - notification actions

-(void) updateUnread
{
    DDLogInfo(@"Updating unread called");
    //make sure unread badge matches application badge
    NSNumber* unreadMsgCnt = [[DataLayer sharedInstance] countUnreadMessages];
    [HelperTools dispatchAsync:YES reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
        NSInteger unread = 0;
        if(unreadMsgCnt != nil)
            unread = [unreadMsgCnt integerValue];
        DDLogInfo(@"Updating unread badge to: %ld", (long)unread);
        [[UNUserNotificationCenter currentNotificationCenter] setBadgeCount:unread withCompletionHandler:nil];
    }];
}

#pragma mark - app life cycle

-(BOOL) application:(UIApplication*) application willFinishLaunchingWithOptions:(NSDictionary*) launchOptions
{
    //resume logging and other core tasks
    [HelperTools signalResumption];
    
    DDLogInfo(@"App launching with options: %@", launchOptions);
    
    //init IPC and ProcessLock
    [IPC initializeForProcess:@"MainApp"];
    [MLProcessLock initializeForProcess:@"MainApp"];
    
    //lock process and disconnect an already running NotificationServiceExtension
    [MLProcessLock lock];
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    
    //do MLFiletransfer cleanup tasks (do this in a new thread to parallelize it with our ping to the appex and don't slow down app startup)
    //this will also migrate our old image cache to new MLFiletransfer cache
    //BUT: don't do this if we are sending the sharesheet outbox
    if(launchOptions[UIApplicationLaunchOptionsURLKey] == nil || ![launchOptions[UIApplicationLaunchOptionsURLKey] isEqual:kMonalOpenURL])
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [MLFiletransfer doStartupCleanup];
        });
    
    //do image manager cleanup in a new thread to not slow down app startup
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [[MLImageManager sharedInstance] cleanupHashes];
    });
    
    // Remove stale promises left in the DB that weren't consumed last time we ran the app
    [MLPromise removeStalePromises];

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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowNotIdle:) name:kMonalNotIdle object:nil];
    
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
        icon:[UNNotificationActionIcon iconWithSystemImageName:@"arrowshape.turn.up.left"] 
        textInputButtonTitle:NSLocalizedString(@"Send", @"")
        textInputPlaceholder:NSLocalizedString(@"Your answer", @"")
    ];
    UNNotificationAction* markAsReadAction = [UNNotificationAction
        actionWithIdentifier:@"MARK_AS_READ_ACTION"
        title:NSLocalizedString(@"Mark as read", @"")
        options:UNNotificationActionOptionNone
        icon:[UNNotificationActionIcon iconWithSystemImageName:@"checkmark.bubble"]
    ];
    UNNotificationAction* approveSubscriptionAction = [UNNotificationAction
        actionWithIdentifier:@"APPROVE_SUBSCRIPTION_ACTION"
        title:NSLocalizedString(@"Approve new contact", @"")
        options:UNNotificationActionOptionNone
        icon:[UNNotificationActionIcon iconWithSystemImageName:@"person.crop.circle.badge.checkmark"]
    ];
    UNNotificationAction* denySubscriptionAction = [UNNotificationAction
        actionWithIdentifier:@"DENY_SUBSCRIPTION_ACTION"
        title:NSLocalizedString(@"Deny new contact", @"")
        options:UNNotificationActionOptionNone
        icon:[UNNotificationActionIcon iconWithSystemImageName:@"person.crop.circle.badge.minus"]
    ];
    UNNotificationAction* blockSubscriptionAction = [UNNotificationAction
        actionWithIdentifier:@"BLOCK_SUBSCRIPTION_ACTION"
        title:NSLocalizedString(@"Block new contact", @"")
        options:UNNotificationActionOptionNone
        icon:[UNNotificationActionIcon iconWithSystemImageName:@"person.crop.circle.badge.xmark"]
    ];
    
    UNAuthorizationOptions authOptions = UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionProvidesAppNotificationSettings;
#if TARGET_OS_MACCATALYST
    authOptions |= UNAuthorizationOptionProvisional;
#endif
    UNNotificationCategory* messageCategory = [UNNotificationCategory
        categoryWithIdentifier:@"message"
        actions:@[replyAction, markAsReadAction]
        intentIdentifiers:@[]
        options:UNNotificationCategoryOptionNone
    ];
    UNNotificationCategory* subscriptionCategory = [UNNotificationCategory
        categoryWithIdentifier:@"subscription"
        actions:@[approveSubscriptionAction, denySubscriptionAction, blockSubscriptionAction]
        intentIdentifiers:@[]
        options:UNNotificationCategoryOptionCustomDismissAction
    ];
    
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
        DDLogInfo(@"Current notification settings: %@", settings);
    }];

    //request auth to show notifications and register our notification categories created above
    [center requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DDLogInfo(@"Got local notification authorization response: granted=%@, error=%@", bool2str(granted), error);
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
                [self->_voipProcessor voipRegistration];
            }
            else
            {
                //delete apns push token --> push will not be registered on our xmpp server anymore
                DDLogWarn(@"Notifications disabled --> deleting APNS push token from user defaults!");
                NSString* oldToken = [[HelperTools defaultsDB] objectForKey:@"pushToken"];
                [[MLXMPPManager sharedInstance] removeToken];
                
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
    [center setNotificationCategories:[NSSet setWithObjects:messageCategory, subscriptionCategory , nil]];

    UINavigationBarAppearance* appearance = [UINavigationBarAppearance new];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = [UIColor systemBackgroundColor];
    
    [[UINavigationBar appearance] setScrollEdgeAppearance:appearance];
    [[UINavigationBar appearance] setStandardAppearance:appearance];
#if TARGET_OS_MACCATALYST
    self.window.windowScene.titlebar.titleVisibility = UITitlebarTitleVisibilityHidden;
#endif
    [[UINavigationBar appearance] setPrefersLargeTitles:YES];

    //handle message notifications by initializing the MLNotificationManager
    [MLNotificationManager sharedInstance];
    
    // Play audio even if phone is in silent mode
    [HelperTools configureDefaultAudioSession];
    self.audioState = MLAudioStateNormal;
    
    DDLogInfo(@"App started: %@", [HelperTools appBuildVersionInfoFor:MLVersionTypeLog]);
    
    //init background/foreground status
    //this has to be done here to make sure we have the correct state when he app got started through notification quick actions
    //NOTE: the connectedXMPP array does not exist at this point --> calling this methods only updates the state without messing with the accounts themselves
    if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
        [[MLXMPPManager sharedInstance] nowBackgrounded];
    else
        [[MLXMPPManager sharedInstance] nowForegrounded];
    
    @synchronized(self) {
        DDLogVerbose(@"Setting _shutdownPending to NO...");
        _shutdownPending = NO;
    }
    [self addBackgroundTask];
    
    //should any accounts connect?
    [self connectIfNecessaryWithOptions:launchOptions];
    
    //handle IPC messages (this should be done *after* calling connectIfNecessary to make sure any disconnectAll messages are handled properly
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(incomingIPC:) name:kMonalIncomingIPC object:nil];
    
#if TARGET_OS_MACCATALYST
    //handle catalyst foregrounding/backgrounding of window
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowHandling:) name:@"NSWindowDidResignKeyNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowHandling:) name:@"NSWindowDidBecomeKeyNotification" object:nil];
#endif
    
    //initialize callkit (mus be done after connectIfNecessary to make sure the list of accounts is already populated when a voip push comes in)
    _voipProcessor = [MLVoIPProcessor new];

    /*
    NSDictionary* options = launchOptions[UIApplicationLaunchOptionsUserActivityDictionaryKey];
    if(options != nil && [@"INSendMessageIntent" isEqualToString:options[UIApplicationLaunchOptionsUserActivityTypeKey]])
    {
        NSUserActivity* userActivity = options[@"UIApplicationLaunchOptionsUserActivityKey"];
        DDLogError(@"intent: %@", userActivity.interaction);
    }
    */
    
    return YES;
}

-(void) updateAppIconIfNeeded
{
    if([UIApplication sharedApplication].supportsAlternateIcons)
    {
        NSString* iconName = nil;
        if([UIApplication sharedApplication].alternateIconName == nil)
            iconName = @"AlphaAppIcon-Christmas";
        DDLogInfo(@"We support alternating app icon sets, switching from '%@' to '%@'...", [UIApplication sharedApplication].alternateIconName, iconName);
        [[UIApplication sharedApplication] setAlternateIconName:iconName completionHandler:^(NSError* _Nullable error) {
            if(error == nil)
                DDLogInfo(@"Successfully switched app icon to '%@'", iconName);
            else
                DDLogError(@"Error switching app icon to '%@': %@", iconName, error);
        }];
    }
    else
        DDLogWarn(@"Can not switch app icon: not supported!");
}

-(BOOL) application:(UIApplication*) application continueUserActivity:(NSUserActivity*) userActivity restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>>* restorableObjects)) restorationHandler
{
    DDLogDebug(@"Got continueUserActivity call...");
    if([userActivity.interaction.intent isKindOfClass:[INStartCallIntent class]])
    {
        DDLogInfo(@"INStartCallIntent interaction: %@", userActivity.interaction);
        INStartCallIntent* intent = (INStartCallIntent*)userActivity.interaction.intent;
        if(intent.contacts.firstObject != nil)
        {
            INPersonHandle* contactHandle = intent.contacts.firstObject.personHandle;
            DDLogInfo(@"INStartCallIntent with contact: %@", contactHandle.value);
            NSArray<MLContact*>* contacts = [[DataLayer sharedInstance] contactListWithJid:contactHandle.value];
            if([contacts count] == 0)
            {
                [self.activeChats showCallContactNotFoundAlert:contactHandle.value];
                return NO;
            }
            //don't display account picker or open call ui if we have an already active call with any of the possible contacts
            //the call ui will be brought into foreground by applicationWillEnterForeground: independently of this
            for(MLContact* contact in contacts)
                if([self.voipProcessor getActiveCallWithContact:contact] != nil)
                    return YES;
            MLCallType callType = MLCallTypeAudio;      //default is audio call
            if(intent.callCapability == INCallCapabilityVideoCall)
                callType = MLCallTypeVideo;
            if([contacts count] > 1)
                [self.activeChats presentAccountPickerForContacts:contacts andCallType:callType];
            else
                [self.activeChats callContact:contacts.firstObject withCallType:callType];
            return YES;
        }
    }
    else if([userActivity.interaction.intent isKindOfClass:[INSendMessageIntent class]])
    {
        DDLogError(@"Got INSendMessageIntent: %@", (INSendMessageIntent*)userActivity.interaction.intent);
    }
    return NO;
}

-(id) application:(UIApplication*) application handlerForIntent:(INIntent*) intent
{
    DDLogError(@"Got intent: %@", intent);
    return nil;
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
        //resume logging and other core tasks
        [HelperTools signalResumption];
        
        DDLogInfo(@"Window got focus (key window)...");
        [MLProcessLock lock];
        @synchronized(self) {
            DDLogVerbose(@"Setting _shutdownPending to NO...");
            _shutdownPending = NO;
        }
        
        //cancel already running background timer, we are now foregrounded again
        [self stopBackgroundTimer];
            
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
    MLAssert(![message[@"name"] isEqualToString:@"Monal.disconnectAll"], @"Got 'Monal.disconnectAll' while in mainapp. This should NEVER happen!", message);
    if([message[@"name"] isEqualToString:@"Monal.connectIfNecessary"])
    {
        DDLogInfo(@"Got connectIfNecessary IPC message");
        //(re)connect all accounts
        [self connectIfNecessaryWithOptions:nil];
    }
}

-(void) applicationDidBecomeActive:(UIApplication*) application
{
    [self updateAppIconIfNeeded];
    
    if([[MLXMPPManager sharedInstance] connectedXMPP].count > 0)
        [self handleSpinner];
    else
    {
        //hide spinner
        [self.activeChats.spinner stopAnimating];
    }
    
    //report pending crashes
    [MLCrashReporter reportPendingCrashes];
}

-(void) setActiveChats:(UIViewController*) activeChats
{
    DDLogDebug(@"Active chats did load...");
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
            //remove everything from our view queue (including currently displayed views)
            //and add intro screens back to the queue, if needed, followed by the view handling the xmpp uri action
            [self.activeChats resetViewQueue];
            [self.activeChats dismissCompleteViewChainWithAnimation:NO andCompletion:^{
                [self.activeChats segueToIntroScreensIfNeeded];
                
                BOOL registerNeeded = [MLXMPPManager sharedInstance].connectedXMPP.count == 0;
                NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
                DDLogVerbose(@"URI path '%@'", components.path);
                DDLogVerbose(@"URI query '%@'", components.query);
                
                NSString* jid = components.path;
                NSDictionary* jidParts = [HelperTools splitJid:jid];
                BOOL isRegister = NO;
                BOOL isRoster = NO;
                BOOL isMucJoin = NO;
                BOOL isIbr = NO;
                NSString* preauthToken = nil;
                NSMutableDictionary<NSNumber*, NSData*>* omemoFingerprints = [NSMutableDictionary new];
                //someone had the really superior (NOT!) idea to split uri query parts by ';' instead of the standard '&'
                //making all existing uri libs useless, see: https://xmpp.org/extensions/xep-0147.html
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
                        isMucJoin = YES;
                    if([name isEqualToString:@"ibr"] && [value isEqualToString:@"y"])
                        isIbr = YES;
                    if([name isEqualToString:@"preauth"])
                        preauthToken = [value copy];
                    if([name hasPrefix:@"omemo-sid-"])
                    {
                        NSNumber* sid = [NSNumber numberWithUnsignedInteger:(NSUInteger)[[name substringFromIndex:10] longLongValue]];
                        NSData* fingerprint = [HelperTools signalIdentityWithHexKey:value];
                        omemoFingerprints[sid] = fingerprint;
                    }
                }
                
                if(!jidParts[@"host"])
                {
                    DDLogError(@"Ignoring xmpp: uri without host jid part!");
                    return;
                }
                
#ifdef IS_QUICKSY
                //make sure we hit the else below, even if (isRegister || (isRoster && registerNeeded)) == YES
                if(NO)
                    ;
#else
                if(isRegister || (isRoster && registerNeeded))
                {
                    NSString* username = nilDefault(jidParts[@"node"], @"");
                    NSString* host = jidParts[@"host"];
                    
                    if(isRoster)
                    {
                        //isRoster variant does not specify a predefined username for the new account, register does (but this is still optional)
                        username = @"";
                        //isRoster variant without ibr does not specify a host to register on, too
                        if(!isIbr)
                            host = @"";
                    }
                    
                    //make sure we don't show the 1-click button if we got a dedicated host and/or username to register on/with
                    self.showOneClickButton = ![@"" isEqualToString:host];
                        
                    //show register view and, if isRoster, add contact as usual after register (e.g. call this method again)
                    weakify(self);
                    [self.activeChats showRegisterWithUsername:username onHost:host withToken:preauthToken usingCompletion:^(NSNumber* accountID) {
                        strongify(self);
                        DDLogVerbose(@"Got accountID for newly registered account: %@", accountID);
                        xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:accountID];
                        DDLogInfo(@"Got newly registered account: %@", account);
                        
                        //this should never happen
                        MLAssert(account != nil, @"Can not use account after register!", (@{
                            @"components": components,
                            @"username": username,
                            @"host": host,
                        }));
                        
                        //add given jid to our roster if in roster mode (e.g. the jid is not the jid we just registered as like in register mode)
                        if(account != nil && isRoster)      //silence memory warning despite assertion above
                            return [self handleXMPPURL:url];
                    }];
                }
#endif
                //I know this if is moot, but I wanted to preserve the different cases:
                //either we already have one or more accounts and the xmpp: uri is of type subscription (ibr does not matter here,
                //because we already have an account) or muc join
                //OR the xmpp: uri is a normal xmpp uri having only a jid we should add as our new contact (preauthToken will be nil in this case)
                else if((!registerNeeded && (isRoster || isMucJoin)) || !registerNeeded)
                {
                    if([MLXMPPManager sharedInstance].connectedXMPP.count == 1)
                    {
                        //the add contacts ui will check if the contact is already present on the selected account
                        xmpp* account = [[MLXMPPManager sharedInstance].connectedXMPP firstObject];
                        [self.activeChats showAddContactWithJid:jid preauthToken:preauthToken prefillAccount:account andOmemoFingerprints:omemoFingerprints];
                    }
                    else
                        //the add contacts ui will check if the contact is already present on the selected account
                        [self.activeChats showAddContactWithJid:jid preauthToken:preauthToken prefillAccount:nil andOmemoFingerprints:omemoFingerprints];
                }
                else
                {
                    DDLogError(@"No account available to handel xmpp: uri!");
                    
                    UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error adding contact or channel", @"") message:NSLocalizedString(@"No account available to handel 'xmpp:' URI!", @"") preferredStyle:UIAlertControllerStyleAlert];
                    [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                    }]];
                    [self.activeChats presentViewController:messageAlert animated:YES completion:nil];
                }
            }];
        });
    });
}

-(BOOL) application:(UIApplication*) app openURL:(NSURL*) url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id>*) options
{
    DDLogInfo(@"Got openURL for '%@' with options: %@", url, options);
    if([url.scheme isEqualToString:@"xmpp"])                //for xmpp uris
    {
        [self handleXMPPURL:url];
        return YES;
    }
    else if([url.scheme isEqualToString:kMonalOpenURL.scheme])      //app opened via sharesheet
    {
        //make sure our outbox content is sent (if the mainapp is still connected and also was in foreground while the sharesheet was used)
        //and open the chat the newest outbox entry was sent to
        //make sure activechats ui is properly initialized when calling this
        createQueuedTimer(0.5, dispatch_get_main_queue(), (^{
            DDLogInfo(@"Got %@ url, trying to send all outboxes...", kMonalOpenURL);
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

-(void) userNotificationCenter:(UNUserNotificationCenter*) center willPresentNotification:(UNNotification*) notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options)) completionHandler
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
        MLContact* fromContact = [MLContact createContactFromJid:response.notification.request.content.userInfo[@"fromContactJid"] andAccountID:response.notification.request.content.userInfo[@"fromContactAccountID"]];
        MLAssert(fromContact, @"fromContact should not be nil");
        NSString* messageId = response.notification.request.content.userInfo[@"messageId"];
        MLAssert(messageId, @"messageId should not be nil");
        xmpp* account = fromContact.account;
        //this can happen if that account got disabled
        if(account == nil)
        {
            //call completion handler directly (we did not handle anything and no connectIfNecessary was called)
            if(completionHandler)
                completionHandler();
            return;
        }
        
        //add our completion handler to handler queue
        [self incomingWakeupWithCompletionHandler:^(UIBackgroundFetchResult result __unused) {
            completionHandler();
        }];
        
        
        //make sure we have an active buddy for this chat
        [[DataLayer sharedInstance] addActiveBuddies:fromContact.contactJid forAccount:fromContact.accountID];
        
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
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:fromContact.contactJid andAccount:fromContact.accountID tillStanzaId:messageId wasOutgoing:NO];
            DDLogDebug(@"Marked as read: %@", unread);
            
            //remove notifications of all read messages (this will cause the MLNotificationManager to update the app badge, too)
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessagesNotice object:account userInfo:@{@"messagesArray":unread}];
            
            //update unread count in active chats list
            [fromContact refresh];      //this will make sure the unread count is correct
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                @"contact": fromContact
            }];
            
            BOOL encrypted = [[DataLayer sharedInstance] shouldEncryptForJid:fromContact.contactJid andAccountID:fromContact.accountID];
            MLMessage* newMLMessage = [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:textResponse.userText havingType:kMessageTypeText toContact:fromContact isEncrypted:encrypted uploadInfo:nil];
            if(newMLMessage)
                DDLogInfo(@"REPLY_ACTION success=YES, messageIdSentObject=%@", newMLMessage.messageDBId);
            else
                DDLogInfo(@"REPLY_ACTION success=NO");
        }
        else if([response.actionIdentifier isEqualToString:@"MARK_AS_READ_ACTION"])
        {
            DDLogInfo(@"MARK_AS_READ_ACTION triggered...");
            NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:fromContact.contactJid andAccount:fromContact.accountID tillStanzaId:messageId wasOutgoing:NO];
            DDLogDebug(@"Marked as read: %@", unread);
            
            //publish MDS display marker and optionally send displayed marker for last unread message (XEP-0333)
            DDLogDebug(@"Sending MDS (and possibly XEP-0333 displayed marker) for messages: %@", unread);
            [account sendDisplayMarkerForMessages:unread];
            
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
    else if([response.notification.request.content.categoryIdentifier isEqualToString:@"subscription"])
    {
        DDLogVerbose(@"notification action '%@' triggered for %@", response.actionIdentifier, response.notification.request.content.userInfo);
        MLContact* fromContact = [MLContact createContactFromJid:response.notification.request.content.userInfo[@"fromContactJid"] andAccountID:response.notification.request.content.userInfo[@"fromContactAccountID"]];
        MLAssert(fromContact, @"fromContact should not be nil");
        xmpp* account = fromContact.account;
        //this can happen if that account got disabled
        if(account == nil)
        {
            //call completion handler directly (we did not handle anything and no connectIfNecessary was called)
            if(completionHandler)
                completionHandler();
            return;
        }
        
        //add our completion handler to handler queue
        [self incomingWakeupWithCompletionHandler:^(UIBackgroundFetchResult result __unused) {
            completionHandler();
        }];
        
        //handle subscription actions
        if([response.actionIdentifier isEqualToString:@"APPROVE_SUBSCRIPTION_ACTION"])
        {
            DDLogInfo(@"APPROVE_SUBSCRIPTION_ACTION triggered...");
            [[MLXMPPManager sharedInstance] addContact:fromContact];
            [self openChatOfContact:fromContact];
        }
        else if([response.actionIdentifier isEqualToString:@"DENY_SUBSCRIPTION_ACTION"] || [response.actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier])
        {
            DDLogInfo(@"DENY_SUBSCRIPTION_ACTION triggered...");
            [[MLXMPPManager sharedInstance] removeContact:fromContact];
        }
        else if([response.actionIdentifier isEqualToString:@"BLOCK_SUBSCRIPTION_ACTION"])
        {
            DDLogInfo(@"BLOCK_SUBSCRIPTION_ACTION triggered...");
            [[MLXMPPManager sharedInstance] removeContact:fromContact];
            [[MLXMPPManager sharedInstance] block:YES contact:fromContact];
        }
        else if([response.actionIdentifier isEqualToString:@"com.apple.UNNotificationDefaultActionIdentifier"])     //open chat of this contact
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                while(self.activeChats == nil)
                    usleep(100000);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [(ActiveChatsViewController*)self.activeChats showAddContact];
                });
            });
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
            [(ActiveChatsViewController*)self.activeChats showNotificationSettings];
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

-(UIInterfaceOrientationMask) application:(UIApplication*) application supportedInterfaceOrientationsForWindow:(UIWindow*) window
{
    return self.orientationLock;
}

#pragma mark - memory
-(void) applicationDidReceiveMemoryWarning:(UIApplication*) application
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
    
    //stop bg processing/refreshing tasks (we are foregrounded now)
    //this will prevent scenarious where one of these tasks times out after the user puts the app into background again
    //in this case a possible syncError notification would be suppressed in checkIfBackgroundTaskIsStillNeeded
    //but since the user openend the app, we want these errors not being suppressed
    @synchronized(self) {
        if(self->_bgProcessing != nil)
        {
            DDLogDebug(@"Stopping bg processing task, we are foregrounded now");
            [DDLog flushLog];
            BGTask* task = self->_bgProcessing;
            self->_bgProcessing = nil;
            [task setTaskCompletedWithSuccess:YES];
            return;
        }
    }
    @synchronized(self) {
        if(self->_bgRefreshing != nil)
        {
            DDLogDebug(@"Stopping bg refreshing task, we are foregrounded now");
            [DDLog flushLog];
            BGTask* task = self->_bgRefreshing;
            self->_bgRefreshing = nil;
            [task setTaskCompletedWithSuccess:YES];
            return;
        }
    }
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
    [MLProcessLock unlock];
    _wasFrozen = YES;
}

-(void) applicationWillEnterForeground:(UIApplication*) application
{
    //resume logging and other core tasks
    [HelperTools signalResumption];
    
    DDLogInfo(@"Entering FG");
    [MLProcessLock lock];
    
    @synchronized(self) {
        DDLogVerbose(@"Setting _shutdownPending to NO...");
        _shutdownPending = NO;
    }
    
    //only show loading HUD if we really got freezed before
    MBProgressHUD* loadingHUD;
    if(_wasFrozen)
    {
        loadingHUD = [MBProgressHUD showHUDAddedTo:[self getTopViewController].view animated:YES];
        loadingHUD.label.text = NSLocalizedString(@"Refreshing...", @"");
        loadingHUD.mode = MBProgressHUDModeIndeterminate;
        loadingHUD.removeFromSuperViewOnHide = YES;
        
        _wasFrozen = NO;
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
            //cancel already running background timer, we are now foregrounded again
            [self stopBackgroundTimer];
            
            [self addBackgroundTask];
            [[MLXMPPManager sharedInstance] nowForegrounded];           //NOTE: this will unfreeze all queues in our accounts
            
            //open call ui using first call if at least one call is present
            NSDictionary* activeCalls = [self.voipProcessor getActiveCalls];
            for(NSUUID* uuid in activeCalls)
            {
                [self.activeChats presentCall:activeCalls[uuid]];
                break;
            }
            
            //trigger view updates (this has to be done because the NotificationServiceExtension could have updated the database some time ago)
            //this must be done *after* [[MLXMPPManager sharedInstance] nowForegrounded] to make sure an already open chat view
            //knows it is now foregrounded (we obviously don't mark messages as read if a chat view is in background while still loaded/"visible")
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
            
            if(loadingHUD != nil)
                loadingHUD.hidden = YES;
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

-(void) applicationWillTerminate:(UIApplication*) application
{
    @synchronized(self) {
        [HelperTools activateTerminationLogging];       //activate logging during shutdown
        DDLogVerbose(@"Setting _shutdownPending to YES...");
        _shutdownPending = YES;
        DDLogWarn(@"|~~| T E R M I N A T I N G |~~|");
        [HelperTools scheduleBackgroundTask:YES];       //make sure delivery will be attempted, if needed (force as soon as possible)
        DDLogInfo(@"|~~| 33%% |~~|");
        [[MLXMPPManager sharedInstance] nowBackgrounded];
        DDLogInfo(@"|~~| 66%% |~~|");
        [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
        DDLogInfo(@"|~~| 99%% |~~|");
        [[MLXMPPManager sharedInstance] disconnectAll];
        DDLogInfo(@"|~~| T E R M I N A T E D |~~|");
        [HelperTools activateTerminationLogging];       //ensure our flush is really successful
        [HelperTools flushLogsWithTimeout:0.025];
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
            //ignore errors with unknown accounts
            //(possibly meaning an account we currently try to create --> the creating ui will take care of this already)
            if(xmppAccount == nil)
                return;
            if(![notification.userInfo[@"isSevere"] boolValue])
                DDLogError(@"Minor XMPP Error(%@): %@", xmppAccount.connectionProperties.identity.jid, notification.userInfo[@"message"]);
            FloatingNotificationBanner* banner = [[MonalFloatingNotificationBanner alloc]
                initWithTitle:xmppAccount.connectionProperties.identity.jid
                subtitle:notification.userInfo[@"message"]
                style:([notification.userInfo[@"isSevere"] boolValue] ? BannerStyleDanger : BannerStyleWarning)
                colors:nil
            ];
            banner.duration = 10.0;     //show for 10 seconds to make sure users can read it
            BannerPosition position = BannerPositionTop;
#if TARGET_OS_MACCATALYST
            //move to bottom, because otherwise the window chrome will cover our text
            position = BannerPositionBottom;
#endif
            [banner showWithQueuePosition:QueuePositionBack bannerPosition:position queue:self->_bannerQueue on:nil];
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

    UICommand* deleteCommand = [UICommand commandWithTitle:@"Archive Conversation" image:nil action:@selector(deleteConversation) propertyList:nil];

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

-(void) handleSpinner
{
    //show/hide spinner (dispatch *async* to main queue to allow for ui changes)
    dispatch_async(dispatch_get_main_queue(), ^{
        if(([[MLXMPPManager sharedInstance] allAccountsIdle] && [MLFiletransfer isIdle]))
            [self.activeChats.spinner stopAnimating];
        else
            [self.activeChats.spinner startAnimating];
    });
}

-(void) nowNotIdle:(NSNotification*) notification
{
    DDLogInfo(@"### SOME ACCOUNT CHANGED TO NON-IDLE STATE ###");
    [self handleSpinner];
}

-(void) nowIdle:(NSNotification*) notification
{
    DDLogInfo(@"### SOME ACCOUNT CHANGED TO IDLE STATE ###");
    [self handleSpinner];
    
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
        
        //if we used a bg fetch/processing task, that means we did not get a push informing us about a waiting message
        //nor did the user interact with our app --> don't show possible sync warnings in this case (but delete old warnings if we are synced now)
        [HelperTools updateSyncErrorsWithDeleteOnly:(self->_bgProcessing != nil || self->_bgRefreshing != nil) andWaitForCompletion:YES];
        
        //use a synchronized block to disconnect only once
        @synchronized(self) {
            if(_backgroundTimer != nil || [_wakeupCompletions count] > 0 || _voipProcessor.pendingCallsCount > 0)
            {
                DDLogInfo(@"### ignoring idle state because background timer or wakeup completion timers or pending calls are still running ###");
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
                DDLogVerbose(@"Setting _shutdownPending to YES...");
                _shutdownPending = YES;
                [HelperTools scheduleBackgroundTask:NO];            //request bg fetch execution in BGFETCH_DEFAULT_INTERVAL seconds
                [[MLXMPPManager sharedInstance] disconnectAll];     //disconnect all accounts to prevent TCP buffer leaking
                [HelperTools dispatchAsync:NO reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
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
                        DDLogError(@"no background tasks running, nothing to stop");
                        [DDLog flushLog];
                    }
                    else
                        [HelperTools signalSuspension];
                }];
            }
        }
    }
}

-(void) addBackgroundTask
{
    [HelperTools dispatchAsync:NO reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
        //don't start uikit bg task if it's already running
        if(self->_bgTask != UIBackgroundTaskInvalid)
            DDLogVerbose(@"Not starting UIKit background task, already running: %d", (int)self->_bgTask);
        else
        {
            DDLogInfo(@"Starting UIKit background task...");
            //indicate we want to do work even if the app is put into background
            self->_bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
                DDLogWarn(@"BG WAKE EXPIRING");
                [DDLog flushLog];
                
                @synchronized(self) {
                    //ui background tasks expire at the same time as background processing/refreshing tasks
                    //--> we have to check if a background processing/refreshing task is running and don't disconnect, if so
                    BOOL stopped = NO;
                    if(self->_bgProcessing == nil && self->_bgRefreshing == nil)
                    {
                        DDLogVerbose(@"Setting _shutdownPending to YES...");
                        self->_shutdownPending = YES;
                        DDLogDebug(@"_bgProcessing == nil && _bgRefreshing == nil --> disconnecting and ending background task");
                        
                        //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
                        [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                        
                        //schedule a BGProcessingTaskRequest to process this further as soon as possible
                        //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                        [HelperTools scheduleBackgroundTask:YES];      //force as soon as possible
                        
                        //disconnect all accounts to prevent TCP buffer leaking
                        [[MLXMPPManager sharedInstance] disconnectAll];
                        
                        //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                        DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                        
                        stopped = YES;
                    }
                    else
                        DDLogDebug(@"_bgProcessing != nil || _bgRefreshing != nil --> not disconnecting");
                    
                    DDLogDebug(@"stopping UIKit _bgTask");
                    [DDLog flushLog];
                    UIBackgroundTaskIdentifier task = self->_bgTask;
                    self->_bgTask = UIBackgroundTaskInvalid;
                    [[UIApplication sharedApplication] endBackgroundTask:task];
                    
                    if(stopped)
                        [HelperTools signalSuspension];
                }
            }];
        }
    }];
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
        
        DDLogVerbose(@"Dispatching to main queue...");
        [HelperTools dispatchAsync:NO reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
            BOOL background = [HelperTools isInBackground];
            DDLogVerbose(@"Waiting for @synchronized(self)...");
            @synchronized(self) {
                DDLogVerbose(@"Now entered @synchronized(self) block...");
                //ui background tasks expire at the same time as background fetching tasks
                //--> we have to check if an ui bg task is running and don't disconnect, if so
                BOOL stopped = NO;
                if(background && self->_voipProcessor.pendingCallsCount == 0 && self->_bgTask == UIBackgroundTaskInvalid)
                {
                    DDLogVerbose(@"Setting _shutdownPending to YES...");
                    self->_shutdownPending = YES;
                    DDLogDebug(@"_bgTask == UIBackgroundTaskInvalid --> disconnecting and ending background task");
                    
                    //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
                    [HelperTools updateSyncErrorsWithDeleteOnly:YES andWaitForCompletion:YES];
                    
                    //schedule a new BGProcessingTaskRequest to process this further as soon as possible
                    //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                    [HelperTools scheduleBackgroundTask:YES];      //force as soon as possible
                    
                    //disconnect all accounts to prevent TCP buffer leaking
                    [[MLXMPPManager sharedInstance] disconnectAll];
                    
                    //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                    DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                    
                    stopped = YES;
                }
                else
                    DDLogDebug(@"!background || _bgTask != UIBackgroundTaskInvalid --> not disconnecting");
                
                DDLogDebug(@"stopping backgroundProcessingTask: %@", task);
                [DDLog flushLog];
                self->_bgProcessing = nil;
                //only signal success, if we are not in background anymore (otherwise we *really* expired without being idle)
                [task setTaskCompletedWithSuccess:!background];
                
                if(stopped)
                    [HelperTools signalSuspension];
            }
        }];
    };
    
    //only proceed with our BGTASK if the NotificationServiceExtension is not running
    [MLProcessLock lock];
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension" withLoopHandler:^{
            [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        }];
    }
    
    //we allow ui bgtasks alongside "modern" bgtasks to extend our runtime in case the "modern" background tasks only provde a few seconds of bgtime
//     if(self->_bgTask != UIBackgroundTaskInvalid)
//     {
//         DDLogDebug(@"stopping UIKit _bgTask, not needed when running a bg task");
//         [DDLog flushLog];
//         UIBackgroundTaskIdentifier task = self->_bgTask;
//         self->_bgTask = UIBackgroundTaskInvalid;
//         [[UIApplication sharedApplication] endBackgroundTask:task];
//     }
    
    if(self->_bgRefreshing != nil)
    {
        DDLogDebug(@"stopping bg refreshing task, not needed when running a (longer running) bg processing task");
        [DDLog flushLog];
        BGTask* refreshingTask = self->_bgRefreshing;
        self->_bgRefreshing = nil;
        [refreshingTask setTaskCompletedWithSuccess:YES];
    }
    
    if(![[MLXMPPManager sharedInstance] hasConnectivity])
        DDLogError(@"BGTASK has *no* connectivity? That's strange!");
    
    [self startBackgroundTimer:BGPROCESS_GRACEFUL_TIMEOUT];
    @synchronized(self) {
        DDLogVerbose(@"Setting _shutdownPending to NO...");
        _shutdownPending = NO;
    }
    //don't use *self* connectIfNecessary, because we don't need an additional UIKit bg task, this one is already a bg task
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
    //request another execution in BGFETCH_DEFAULT_INTERVAL seconds
    [HelperTools scheduleBackgroundTask:NO];
    
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
        
        DDLogVerbose(@"Dispatching to main queue...");
        [HelperTools dispatchAsync:NO reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
            BOOL background = [HelperTools isInBackground];
            DDLogVerbose(@"Waiting for @synchronized(self)...");
            @synchronized(self) {
                DDLogVerbose(@"Now entered @synchronized(self) block...");
                //ui background tasks expire at the same time as background fetching tasks
                //--> we have to check if an ui bg task is running and don't disconnect, if so
                BOOL stopped = NO;
                if(background && self->_voipProcessor.pendingCallsCount == 0 && self->_bgTask == UIBackgroundTaskInvalid)
                {
                    DDLogVerbose(@"Setting _shutdownPending to YES...");
                    self->_shutdownPending = YES;
                    DDLogDebug(@"_bgTask == UIBackgroundTaskInvalid --> disconnecting and ending background task");
                    
                    //this has to be before account disconnects, to detect which accounts are not idle (e.g. have a sync error)
                    [HelperTools updateSyncErrorsWithDeleteOnly:YES andWaitForCompletion:YES];
                    
                    //schedule a new BGProcessingTaskRequest to process this further as soon as possible
                    //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                    [HelperTools scheduleBackgroundTask:YES];      //force as soon as possible
                    
                    //disconnect all accounts to prevent TCP buffer leaking
                    [[MLXMPPManager sharedInstance] disconnectAll];
                    
                    //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                    DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                    
                    stopped = YES;
                }
                else
                    DDLogDebug(@"!background || _bgTask != UIBackgroundTaskInvalid --> not disconnecting");
                
                DDLogDebug(@"stopping backgroundProcessingTask: %@", task);
                [DDLog flushLog];
                self->_bgRefreshing = nil;
                //only signal success, if we are not in background anymore (otherwise we *really* expired without being idle)
                [task setTaskCompletedWithSuccess:!background];
                
                if(stopped)
                    [HelperTools signalSuspension];
            }
        }];
    };
    
    //only proceed with our BGTASK if the NotificationServiceExtension is not running
    [MLProcessLock lock];
    [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
    if([MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
    {
        DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination");
        [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension" withLoopHandler:^{
            [[IPC sharedInstance] sendMessage:@"Monal.disconnectAll" withData:nil to:@"NotificationServiceExtension"];
        }];
    }
    
    //we allow ui bgtasks alongside "modern" bgtasks to extend our runtime in case the "modern" background tasks only provde a few seconds of bgtime
//     if(self->_bgTask != UIBackgroundTaskInvalid)
//     {
//         DDLogDebug(@"stopping UIKit _bgTask, not needed when running a bg task");
//         [DDLog flushLog];
//         UIBackgroundTaskIdentifier task = self->_bgTask;
//         self->_bgTask = UIBackgroundTaskInvalid;
//         [[UIApplication sharedApplication] endBackgroundTask:task];
//     }
    
    if(![[MLXMPPManager sharedInstance] hasConnectivity])
    {
        DDLogError(@"BGTASK has *no* connectivity? That's strange!");
    }
    
    [self startBackgroundTimer:GRACEFUL_TIMEOUT];
    @synchronized(self) {
        DDLogVerbose(@"Setting _shutdownPending to NO...");
        _shutdownPending = NO;
    }
    //don't use *self* connectIfNecessary, because we don't need an additional UIKit bg task, this one is already a bg task
    [[MLXMPPManager sharedInstance] connectIfNecessary];
    
    //request another execution in BGFETCH_DEFAULT_INTERVAL seconds
    [HelperTools scheduleBackgroundTask:NO];
    
    DDLogInfo(@"BGREFRESHING SETUP HANDLER COMPLETED SUCCESSFULLY...");
}

-(void) configureBackgroundTasks
{
    [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBackgroundProcessingTask usingQueue:dispatch_get_main_queue() launchHandler:^(BGTask *task) {
        //resume logging and other core tasks
        [HelperTools signalResumption];
        
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
    
    [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBackgroundRefreshingTask usingQueue:dispatch_get_main_queue() launchHandler:^(BGTask *task) {
        //resume logging and other core tasks
        [HelperTools signalResumption];
        
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
    [HelperTools scheduleBackgroundTask:force];
}

-(void) connectIfNecessaryWithOptions:(NSDictionary*) options
{
    static NSUInteger applicationState;
    static monal_void_block_t cancelEmergencyTimer;
    static monal_void_block_t cancelCurrentTimer = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        applicationState = [UIApplication sharedApplication].applicationState;
        cancelEmergencyTimer = createTimer(16.0, (^{
            DDLogError(@"Emergency: crashlogs are still blocking connect after 16 seconds, connecting anyways!");
            if(cancelCurrentTimer != nil)
                cancelCurrentTimer();
            [MLXMPPManager sharedInstance].isConnectBlocked = NO;
            [[MLXMPPManager sharedInstance] connectIfNecessary];
        }));
    });
    //this method is called by didFinishLaunchingWithOptions: and our ipc handler (but this is currently unused)
    //we block the reconnect while the crash reports have not been processed yet, to avoid a crash loop preventing
    //the user from sending the crash report
    int count = [HelperTools pendingCrashreportCount];
    if(count > 0 && options == nil && applicationState != UIApplicationStateBackground)
    {
        [MLXMPPManager sharedInstance].isConnectBlocked = YES;
        DDLogWarn(@"Blocking connect of connectIfNecessary: crash reports still pending: %d, retrying in 1 second...", count);
        cancelCurrentTimer = createTimer(1.0, (^{ [self connectIfNecessaryWithOptions:options]; }));
    }
    else
    {
        [MLXMPPManager sharedInstance].isConnectBlocked = NO;
        DDLogInfo(@"Now unblocking connect of connectIfNecessary (applicationState%@UIApplicationStateBackground, count=%d, options=%@)...",
                    applicationState == UIApplicationStateBackground ? @"==" : @"!=",
                    count,
                    options
        );
        cancelEmergencyTimer();
    }
    [[MLXMPPManager sharedInstance] connectIfNecessary];
}

-(void) incomingWakeupWithCompletionHandler:(void (^)(UIBackgroundFetchResult result)) completionHandler
{
    //resume logging and other core tasks
    [HelperTools signalResumption];
    
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
    [MLProcessLock lock];
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
                        BOOL stopped = NO;
                        if(background && self->_voipProcessor.pendingCallsCount == 0 && self->_bgTask == UIBackgroundTaskInvalid && self->_bgProcessing == nil && self->_bgRefreshing == nil)
                        {
                            DDLogVerbose(@"Setting _shutdownPending to YES...");
                            self->_shutdownPending = YES;
                            DDLogDebug(@"background && _bgTask == UIBackgroundTaskInvalid && _bgProcessing == nil && _bgRefreshing == nil --> disconnecting and feeding wakeup completion");
                            
                            //this has to be before account disconnects, to detect which accounts are/are not idle (e.g. don't have/have a sync error)
                            BOOL wasIdle = [[MLXMPPManager sharedInstance] allAccountsIdle] && [MLFiletransfer isIdle];
                            [HelperTools updateSyncErrorsWithDeleteOnly:NO andWaitForCompletion:YES];
                            
                            //schedule a new BGProcessingTaskRequest to process this further as soon as possible, if we are not idle
                            //(if we end up here, the graceful shuttdown did not work out because we are not idle --> we need more cpu time)
                            [HelperTools scheduleBackgroundTask:!wasIdle];
                            
                            //disconnect all accounts to prevent TCP buffer leaking
                            [[MLXMPPManager sharedInstance] disconnectAll];
                            
                            //notify about pending app freeze (don't queue this notification because it should be handled IMMEDIATELY and INLINE)
                            DDLogVerbose(@"Posting kMonalWillBeFreezed notification now...");
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalWillBeFreezed object:nil];
                            
                            stopped = YES;
                        }
                        else
                            DDLogDebug(@"NOT (background && _bgTask == UIBackgroundTaskInvalid && _bgProcessing == nil && _bgRefreshing == nil) --> not disconnecting");
                        
                        //call completion (should be done *after* the idle state check because it could freeze the app)
                        DDLogInfo(@"Calling wakeup completion handler...");
                        [DDLog flushLog];
                        [self->_wakeupCompletions removeObjectForKey:completionId];
                        completionHandler(UIBackgroundFetchResultFailed);
                        
                        if(stopped)
                            [HelperTools signalSuspension];
                        
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
    
    [(ActiveChatsViewController*)self.activeChats dismissCompleteViewChainWithAnimation:YES andCompletion:^{
        //open the destination chat only once
        for(NSDictionary* payload in [[DataLayer sharedInstance] getShareSheetPayload])
        {
            DDLogInfo(@"Sending outbox entry: %@", payload);
            xmpp* account = [[MLXMPPManager sharedInstance] getEnabledAccountForID:payload[@"account_id"]];
            if(account == nil)
            {
                UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Sharing failed", @"") message:[NSString stringWithFormat:NSLocalizedString(@"Cannot share something with disabled/deleted account, destination: %@, internal account id: %@", @""), payload[@"recipient"], payload[@"account_id"]] preferredStyle:UIAlertControllerStyleAlert];
                [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                }]];
                [self.activeChats presentViewController:messageAlert animated:YES completion:nil];
                [[DataLayer sharedInstance] deleteShareSheetPayloadWithId:payload[@"id"]];
                continue;
            }
            MLContact* contact = [MLContact createContactFromJid:payload[@"recipient"] andAccountID:account.accountID];
            
            monal_id_block_t cleanup = ^(NSDictionary* payload) {
                [[DataLayer sharedInstance] deleteShareSheetPayloadWithId:payload[@"id"]];
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
                if(self.activeChats.currentChatView != nil)
                {
                    [self.activeChats.currentChatView scrollToBottomAnimated:NO];
                    [self.activeChats.currentChatView hideUploadHUD];
                }
                //send next item (if there is one left)
                [self sendAllOutboxes];
            };
            
            monal_id_block_t sendItem = ^(id dummy __unused){
                BOOL encrypted = [[DataLayer sharedInstance] shouldEncryptForJid:contact.contactJid andAccountID:contact.accountID];
                NSDictionary* mapping = @{
                    @"text": kMessageTypeText,
                    @"url": kMessageTypeUrl,
                    @"geo": kMessageTypeGeo,
                    @"image": kMessageTypeFiletransfer,
                    @"file": kMessageTypeFiletransfer,
                    @"contact":kMessageTypeFiletransfer,
                    @"audiovisual":kMessageTypeFiletransfer,
                };
                NSString* messageType = mapping[nilDefault(payload[@"type"], @"<type key not present>")];

                if(!messageType)
                    unreachable(@"Outbox payload type unknown", payload);
                else if(![messageType isEqual:kMessageTypeFiletransfer])
                {
                    //the payload type is either "text", "url" or "geo"
                    MLMessage* newMLMessage = [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:payload[@"data"] havingType:messageType toContact:contact isEncrypted:encrypted uploadInfo:nil];
                    if(newMLMessage)
                        DDLogInfo(@"SHARESHEET_SEND_DATA success=YES, account=%@, messageIdSentObject=%@", account.accountID, newMLMessage.messageDBId);
                    else
                        DDLogInfo(@"SHARESHEET_SEND_DATA success=NO, account=%@", account.accountID);

                    cleanup(payload);
                }
                else
                {
                    //the payload type is either "image", "file", "contact" or "audiovisual"
                    DDLogInfo(@"Got %@ upload: %@", payload[@"type"], payload[@"data"]);
                    [self.activeChats.currentChatView showUploadHUD];
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        $call(payload[@"data"], $ID(account), $BOOL(encrypted), $ID(completion, (^(NSString* url, NSString* mimeType, NSNumber* size, NSError* error) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if(error != nil)
                                {
                                    DDLogError(@"Failed to upload outbox file: %@", error);
                                    NSMutableDictionary* payloadCopy = [NSMutableDictionary dictionaryWithDictionary:payload];
                                    cleanup(payloadCopy);
                                    
                                    UIAlertController* messageAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Failed to share file", @"") message:[NSString stringWithFormat:NSLocalizedString(@"Error: %@", @""), error] preferredStyle:UIAlertControllerStyleAlert];
                                    [messageAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Close", @"") style:UIAlertActionStyleCancel handler:^(UIAlertAction* action __unused) {
                                    }]];
                                    [self.activeChats presentViewController:messageAlert animated:YES completion:nil];
                                }
                                else
                                {
                                    MLMessage* newMLMessage = [[MLXMPPManager sharedInstance] sendMessageAndAddToHistory:url havingType:messageType toContact:contact isEncrypted:encrypted uploadInfo:@{@"mimeType": mimeType, @"size": size}];
                                    if(newMLMessage)
                                        DDLogInfo(@"SHARESHEET_SEND_DATA success=YES, account=%@, messageIdSentObject=%@", account.accountID, newMLMessage.messageDBId);
                                    else
                                        DDLogInfo(@"SHARESHEET_SEND_DATA success=NO, account=%@", account.accountID);

                                    cleanup(payload);
                                }
                            });
                        })));
                    });
                }
            };
            
            DDLogVerbose(@"Trying to open chat of outbox receiver: %@", contact);
            [[DataLayer sharedInstance] addActiveBuddies:contact.contactJid forAccount:contact.accountID];
            //don't use [self openChatOfContact:withCompletion:] because it's asynchronous and can only handle one contact at a time (e.g. until the asynchronous execution finished)
            //we can invoke the activeChats interface directly instead, because we already did the necessary preparations ourselves
            [(ActiveChatsViewController*)self.activeChats presentChatWithContact:contact andCompletion:sendItem];
            
            //only send one item at a time (this method will be invoked again when sending completed)
            break;
        }
    }];
}

@end
