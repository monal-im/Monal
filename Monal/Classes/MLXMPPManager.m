//
//  MLXMPPManager.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/27/13.
//
//

#import <BackgroundTasks/BackgroundTasks.h>

#import "MLXMPPManager.h"
#import "DataLayer.h"

#import "MLMessageProcessor.h"
#import "ParseMessage.h"

#if TARGET_OS_IPHONE
#import "MonalAppDelegate.h"
#endif

@import Network;
@import MobileCoreServices;
@import SAMKeychain;

static const NSString* kBackgroundFetchingTask = @"im.monal.fetch";

//this is in seconds
#define SHORT_PING 4.0
#define LONG_PING 16.0

static const int pingFreqencyMinutes = 5;       //about the same Conversations uses
static const int sendMessageTimeoutSeconds = 10;

@interface MLXMPPManager()
{
    nw_path_monitor_t _path_monitor;
    UIBackgroundTaskIdentifier _bgTask;
    BGTask* _bgFetch;
    BOOL _hasConnectivity;
    void (^_pushCompletion)(UIBackgroundFetchResult result);
    monal_void_block_t _cancelPushTimer;
}

/**
An array of Dics what have timers to make sure everything was sent
 */
@property (nonatomic, strong) NSMutableArray *timerList;

@end


@implementation MLXMPPManager

-(void) defaultSettings
{
    BOOL setDefaults = [DEFAULTS_DB boolForKey:@"SetDefaults"];
    if(!setDefaults)
    {
        // [DEFAULTS_DB setObject:@"" forKey:@"StatusMessage"];   // we dont want anything set
        [DEFAULTS_DB setBool:NO forKey:@"Away"];
        [DEFAULTS_DB setBool:YES forKey:@"MusicStatus"];
        [DEFAULTS_DB setBool:YES forKey:@"Sound"];
        [DEFAULTS_DB setBool:YES forKey:@"MessagePreview"];
        [DEFAULTS_DB setBool:YES forKey:@"Logging"];

        [DEFAULTS_DB setBool:YES forKey:@"OfflineContact"];
        [DEFAULTS_DB setBool:NO forKey:@"SortContacts"];

        [DEFAULTS_DB setBool:YES forKey:@"SetDefaults"];

        [DEFAULTS_DB setBool:YES forKey:@"ShowImages"];
        [DEFAULTS_DB setBool:YES forKey:@"ShowGeoLocation"];
        [DEFAULTS_DB setBool:YES forKey:@"ChatBackgrounds"];

        [DEFAULTS_DB synchronize];
    }

    // on upgrade this one needs to be set to yes. Can be removed later.
    NSNumber *imagesTest= [DEFAULTS_DB objectForKey:@"ShowImages"];

    if(imagesTest==nil)
    {
          [DEFAULTS_DB setBool:YES  forKey:@"ShowImages"];
          [DEFAULTS_DB synchronize];
    }

    // upgrade
    NSNumber *background = [DEFAULTS_DB objectForKey:@"ChatBackgrounds"];
    if(background==nil)
    {
        [DEFAULTS_DB setBool:YES  forKey:@"ChatBackgrounds"];
        [DEFAULTS_DB synchronize];
    }

    NSNumber *sounds = [DEFAULTS_DB objectForKey:@"AlertSoundFile"];
    if(sounds==nil)
    {
        [DEFAULTS_DB setObject:@"alert2" forKey:@"AlertSoundFile"];
        [DEFAULTS_DB synchronize];
    }

    // upgrade ShowGeoLocation
    NSNumber* mapLocationTest = [DEFAULTS_DB objectForKey:@"ShowGeoLocation"];
    if(mapLocationTest==nil)
    {
        [DEFAULTS_DB setBool:YES forKey:@"ShowGeoLocation"];
        [DEFAULTS_DB synchronize];
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
    self=[super init];

    _connectedXMPP = [[NSMutableArray alloc] init];
    _bgTask = UIBackgroundTaskInvalid;
    _hasConnectivity = NO;
    
    if(@available(iOS 13.0, *))
    {
        DDLogInfo(@"calling configureBackgroundFetchingTask");
        [self configureBackgroundFetchingTask];
    }

    _netQueue = dispatch_queue_create(kMonalNetQueue, DISPATCH_QUEUE_SERIAL);

    [self defaultSettings];

    //set up regular ping
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _pinger = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q_background);

    dispatch_source_set_timer(_pinger,
                              DISPATCH_TIME_NOW,
                              60ull * NSEC_PER_SEC * pingFreqencyMinutes,
                              60ull * NSEC_PER_SEC);        //allow for better battery optimizations

    dispatch_source_set_event_handler(_pinger, ^{
        //only ping when having connectivity
        if(_hasConnectivity)
        {
            for(xmpp* xmppAccount in _connectedXMPP)
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

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNewMessage:) name:kMonalNewMessageNotice object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSentMessage:) name:kMonalSentMessageNotice object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(autoJoinRoom:) name:kMLHasConnectedNotice object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sendOutbox:) name:kMLHasConnectedNotice object:nil];

    _path_monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(_path_monitor, q_background);
    nw_path_monitor_set_update_handler(_path_monitor, ^(nw_path_t path) {
        DDLogVerbose(@"*** nw_path_monitor update_handler called");
        if(nw_path_get_status(path) == nw_path_status_satisfied)
        {
            DDLogVerbose(@"reachable");
            _hasConnectivity = YES;
            for(xmpp* xmppAccount in _connectedXMPP)
            {
                //try to send a ping. if it fails, it will reconnect
                DDLogVerbose(@"manager pinging");
                [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
            }
        }
        else
        {
            DDLogVerbose(@"NOT reachable");
            _hasConnectivity = NO;
            BOOL wasIdle = [self allAccountsIdle];      //we have to check that here because diconnect: makes them non-idle (no catchup done yet etc.)
            for(xmpp* xmppAccount in _connectedXMPP)
            {
                //disconnect to prevent endless loops trying to connect
                DDLogVerbose(@"manager disconnecting");
                [xmppAccount disconnect];
            }
            if(!wasIdle)
            {
                DDLogVerbose(@"scheduling background fetching task to start app in background once our connectivity gets restored");
                [self scheduleBackgroundFetchingTask];      //this will automatically start the app if connectivity gets restored
            }
        }
    });
    nw_path_monitor_start(_path_monitor);

    //this is only for debugging purposes, the real handler has to be added to the NotificationServiceExtension
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(catchupFinished:) name:kMonalFinishedCatchup object:nil];

    //process idle state changes
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nowIdle:) name:kMonalIdle object:nil];

    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if(_pinger)
        dispatch_source_cancel(_pinger);
}

-(void) catchupFinished:(NSNotification*) notification
{
    DDLogVerbose(@"### MAM/SMACKS CATCHUP FINISHED ###");
}

-(void) nowIdle:(NSNotification*) notification
{
    dispatch_async(self->_netQueue, ^{
        DDLogVerbose(@"### SOME ACCOUNT CHANGED TO IDLE STATE ###");
        [DDLog flushLog];
        if(![HelperTools isAppExtension])
        {
            DDLogVerbose(@"### NOT EXTENSION --> checking if background is still needed ###");
            [self checkIfBackgroundTaskIsStillNeeded];
        }
        else
            DDLogVerbose(@"### IN EXTENSION --> ignoring in MLXMPPManager ###");
    });
}

-(BOOL) allAccountsIdle
{
    for(xmpp* xmppAccount in _connectedXMPP)
    {
        if(!xmppAccount.idle)
            return NO;
    }
    return YES;
}

-(BOOL) isInBackground
{
    __block BOOL inBackground = NO;
    if([HelperTools isAppExtension])
        inBackground = YES;
    else
    {
#if TARGET_OS_IPHONE
        void (^block)(void) = ^{
            if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
                inBackground = YES;
        };
        if(dispatch_get_current_queue() == dispatch_get_main_queue())
            block();
        else
            dispatch_sync(dispatch_get_main_queue(), block);
#endif
    }
    return inBackground;
}

-(void) checkIfBackgroundTaskIsStillNeeded
{
#if TARGET_OS_IPHONE
    if(![HelperTools isAppExtension])
    {
        if([self allAccountsIdle] && _pushCompletion)
        {
            DDLogInfo(@"### All accounts idle, calling push completion handler ###");
            if(_cancelPushTimer)
                _cancelPushTimer();
            _pushCompletion(UIBackgroundFetchResultNewData);
            _pushCompletion = nil;
            _cancelPushTimer = nil;
        }
        if([self allAccountsIdle] && [self isInBackground])
        {
            DDLogInfo(@"### All accounts idle, stopping all background tasks ###");
            [DDLog flushLog];
            BOOL stopped = NO;
            if(_bgTask != UIBackgroundTaskInvalid)
            {
                DDLogVerbose(@"stopping UIKit _bgTask");
                [DDLog flushLog];
                [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
                _bgTask = UIBackgroundTaskInvalid;
                stopped = YES;
            }
            if(_bgFetch)
            {
                DDLogVerbose(@"stopping backgroundFetchingTask");
                [DDLog flushLog];
                [_bgFetch setTaskCompletedWithSuccess:YES];
                stopped = YES;
            }
            if(!stopped)
                DDLogVerbose(@"no background tasks running, nothing to stop");
            [DDLog flushLog];
            
            /*
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                DDLogVerbose(@"disconnecting all accounts (we don't need idle connections that could get killed any time anyways)");
                for(xmpp* xmppAccount in _connectedXMPP)
                    [xmppAccount disconnect];
            });
            */
        }
    }
#endif
}

-(void) handleBackgroundFetchingTask:(BGTask*) task API_AVAILABLE(ios(13.0))
{
    DDLogVerbose(@"RUNNING BGTASK");
    _bgFetch = task;
    task.expirationHandler = ^{
        DDLogError(@"*** BGTASK EXPIRED ***");
        _bgFetch = nil;
        [task setTaskCompletedWithSuccess:NO];
        [self scheduleBackgroundFetchingTask];      //schedule new one if neccessary
        [DDLog flushLog];
    };
    unsigned long tick = 0;
    while(1)
    {
        DDLogVerbose(@"BGTASK TICK: %ul", tick++);
        [DDLog flushLog];
        [NSThread sleepForTimeInterval:1.000];
    }
}

-(void) configureBackgroundFetchingTask
{
    if(@available(iOS 13.0, *))
    {
        [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBackgroundFetchingTask usingQueue:nil launchHandler:^(BGTask *task) {
            DDLogVerbose(@"RUNNING BGTASK LAUNCH HANDLER");
            [self handleBackgroundFetchingTask:task];
        }];
    } else {
        // No fallback unfortunately
    }
}

-(void) scheduleBackgroundFetchingTask
{
#if TARGET_OS_IPHONE
    if(![HelperTools isAppExtension])
    {
        if(@available(iOS 13.0, *))
        {
            dispatch_sync(dispatch_get_main_queue(), ^{
                NSError *error = NULL;
                // cancel existing task (if any)
                [BGTaskScheduler.sharedScheduler cancelTaskRequestWithIdentifier:kBackgroundFetchingTask];
                // new task
                //BGProcessingTaskRequest* request = [[BGProcessingTaskRequest alloc] initWithIdentifier:kBackgroundFetchingTask];
                //request.requiresNetworkConnectivity = YES;
                BGAppRefreshTaskRequest* request = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:kBackgroundFetchingTask];
                request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:40];        //begin nearly immediately (if we have network connectivity)
                BOOL success = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
                if(!success) {
                    // Errorcodes https://stackoverflow.com/a/58224050/872051
                    DDLogError(@"Failed to submit BGTask request: %@", error);
                } else {
                    DDLogVerbose(@"Success submitting BGTask request %@", request);
                }
            });
        }
        else
        {
            // No fallback unfortunately
            DDLogError(@"BGTask needed but NOT supported!");
        }
    }
#endif
}

-(void) incomingPushWithCompletionHandler:(void (^)(UIBackgroundFetchResult result)) completionHandler
{
    DDLogError(@"got incomingPushWithCompletionHandler");
    if(![self isInBackground])
    {
        DDLogError(@"Ignoring incomingPushWithCompletionHandler: because app is in FG!");
        completionHandler(UIBackgroundFetchResultNoData);
        return;
    }
    // should any accounts reconnect?
    _pushCompletion = completionHandler;
    [self pingAllAccounts];
    _cancelPushTimer = [HelperTools startTimer:25.0 withHandler:^{
        DDLogWarn(@"### Push timer triggered!! ###");
        _pushCompletion(UIBackgroundFetchResultFailed);
        _pushCompletion = nil;
        _cancelPushTimer = nil;
    }];
}

#pragma mark - client state

-(void) setClientsInactive
{
    //don't block main thread here
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for(xmpp* xmppAccount in _connectedXMPP)
            [xmppAccount setClientInactive];
        [self checkIfBackgroundTaskIsStillNeeded];
    });
}

-(void) setClientsActive
{
#if TARGET_OS_IPHONE
    if(![HelperTools isAppExtension])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            //start indicating we want to do work even when the app is put into background
            if(_bgTask == UIBackgroundTaskInvalid)
            {
                _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
                    DDLogWarn(@"BG WAKE EXPIRING");
                    [DDLog flushLog];
                    
                    //schedule a BGProcessingTaskRequest to process this further as soon as possible
                    if(@available(iOS 13.0, *))
                    {
                        DDLogInfo(@"calling scheduleBackgroundFetchingTask");
                        [self scheduleBackgroundFetchingTask];
                    }
                    
                    [DDLog flushLog];
                    [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
                    _bgTask = UIBackgroundTaskInvalid;
                }];
            }
        });
    }
#endif
    
    //don't block main thread here
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for(xmpp* xmppAccount in _connectedXMPP)
        {
            [xmppAccount setClientActive];
            if(_hasConnectivity)
                [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        }
    });
}

-(void) pingAllAccounts
{
    //don't block main thread here
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for(xmpp* xmppAccount in _connectedXMPP)
            if(_hasConnectivity)
                [xmppAccount sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
    });
}

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
    for(xmpp* xmppAccount in _connectedXMPP)
    {
        if([xmppAccount.accountNo isEqualToString:accountNo])
            return xmppAccount;
    }
    return nil;
}

#pragma mark - Connection related

-(void) connectAccount:(NSString*) accountNo
{
    [[DataLayer sharedInstance] detailsForAccount:accountNo withCompletion:^(NSArray *result) {
        dispatch_async(self->_netQueue, ^{
            NSArray *accounts = result;
            if(accounts.count == 1) {
                NSDictionary* account=[accounts objectAtIndex:0];
                [self connectAccountWithDictionary:account];
            } else {
                DDLogVerbose(@"Expected account settings in db for accountNo: %@", accountNo);
            }
        });
    }];
}

-(void) connectAccountWithDictionary:(NSDictionary*)account
{
    xmpp* existing=[self getConnectedAccountForID:[NSString stringWithFormat:@"%@", [account objectForKey:kAccountID]]];
    if(existing)
    {
        DDLogVerbose(@"existing account just pinging.");
        if(_hasConnectivity)
            [existing sendPing:SHORT_PING];     //short ping timeout to quickly check if connectivity is still okay
        else
            DDLogVerbose(@"NOT pinging because no connectivity.");
        return;
    }
    DDLogVerbose(@"connecting account %@@%@",[account objectForKey:kUsername], [account objectForKey:kDomain]);

    NSError* error;
    NSString *password = [SAMKeychain passwordForService:@"Monal" account:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]] error:&error];
    error = nil;
    if(error)
    {
        DDLogError(@"Keychain error: %@", [NSString stringWithFormat:@"%@", error]);
        @throw [NSException exceptionWithName:@"NSError" reason:[NSString stringWithFormat:@"%@", error] userInfo:nil];
    }
    MLXMPPIdentity *identity = [[MLXMPPIdentity alloc] initWithJid:[NSString stringWithFormat:@"%@@%@",[account objectForKey:kUsername],[account objectForKey:kDomain] ] password:password andResource:[account objectForKey:kResource]];

    MLXMPPServer *server = [[MLXMPPServer alloc] initWithHost:[account objectForKey:kServer] andPort:[account objectForKey:kPort] andDirectTLS:[[account objectForKey:kDirectTLS] boolValue]];
    server.selfSignedCert=[[account objectForKey:kSelfSigned] boolValue];

    xmpp* xmppAccount=[[xmpp alloc] initWithServer:server andIdentity:identity andAccountNo:[NSString stringWithFormat:@"%@",[account objectForKey:kAccountID]]];
    xmppAccount.pushNode=self.pushNode;
    xmppAccount.pushSecret=self.pushSecret;

#ifndef DISABLE_OMEMO
    [xmppAccount setupSignal];
#endif

    if(xmppAccount) {
        [_connectedXMPP addObject:xmppAccount];
        if(_hasConnectivity)
        {
            DDLogVerbose(@"starting connect");
            [xmppAccount connect];
        }
        else
            DDLogVerbose(@"NOT connecting because no connectivity.");
    }
}


-(void) disconnectAccount:(NSString*) accountNo
{
    dispatch_async(self->_netQueue, ^{
        int index=0;
        int pos=-1;
        for(xmpp* xmppAccount in _connectedXMPP)
        {
            if([xmppAccount.accountNo isEqualToString:accountNo] )
            {
                DDLogVerbose(@"got account and cleaning up.. ");
                [xmppAccount disconnect:YES];
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


-(void) logoutAll
{
    [[DataLayer sharedInstance] accountListEnabledWithCompletion:^(NSArray* result) {
        dispatch_async(self->_netQueue, ^{
            for(NSDictionary* account in result) {
                DDLogVerbose(@"Disconnecting account %@@%@", [account objectForKey:@"username"], [account objectForKey:@"domain"]);
                [self disconnectAccount:[NSString stringWithFormat:@"%@", [account objectForKey:kAccountID]]];
            }
        });
    }];
}

-(void) connectIfNecessary
{
    [[DataLayer sharedInstance] accountListEnabledWithCompletion:^(NSArray* result) {
        dispatch_async(self->_netQueue, ^{
            for(NSDictionary* account in result)
                [self connectAccountWithDictionary:account];
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
    [xmpp.connectionProperties.identity updatPassword:password];
}

#pragma mark -  XMPP commands
-(void) sendMessageAndAddToHistory:(NSString*) message toContact:(NSString*)recipient fromAccount:(NSString*) accountID fromJID:(NSString*) fromJID isEncrypted:(BOOL) encrypted isMUC:(BOOL) isMUC  isUpload:(BOOL) isUpload withCompletionHandler:(void (^)(BOOL success, NSString *messageId)) completion {
    NSString* msgid = [[NSUUID UUID] UUIDString];

    // Save message to history
    [[DataLayer sharedInstance] addMessageHistoryFrom:fromJID to:recipient forAccount:accountID withMessage:message actuallyFrom:fromJID withId:msgid encrypted:encrypted withCompletion:^(BOOL successHist, NSString *messageTypeHist) {
        // Send message
        if(successHist) {
            [self sendMessage:message toContact:recipient fromAccount:accountID isEncrypted:encrypted isMUC:NO  isUpload:NO messageId:msgid withCompletionHandler:^(BOOL successSend, NSString *messageIdSend) {
                if(successSend) completion(successSend, messageIdSend);
            }];
        }
    }];
}

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

-(void) sendChatState:(BOOL) isTyping fromAccount:(NSString*) accountNo toJid:(NSString*) jid
{
    dispatch_async(_netQueue, ^{
        xmpp* account = [self getConnectedAccountForID:accountNo];
        if(account)
            [account sendChatState:isTyping toJid:jid];
    });
}


#pragma  mark - HTTP upload

-(void) httpUploadJpegData:(NSData*) fileData   toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion{

    NSString *fileName = [NSString stringWithFormat:@"%@.jpg",[NSUUID UUID].UUIDString];

    //get file type
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)@"jpg", NULL);
    NSString *mimeType = (__bridge_transfer NSString *)(UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType));
    CFRelease(UTI);
    [self httpUploadData:fileData withFilename:fileName andType:mimeType toContact:contact onAccount:accountNo withCompletionHandler:completion];
}

-(void) httpUploadFileURL:(NSURL*) fileURL  toContact:(NSString*)contact onAccount:(NSString*) accountNo  withCompletionHandler:(void (^)(NSString *url,  NSError *error)) completion{

    //get file name
    NSString *fileName =  fileURL.pathComponents.lastObject;

    //get file type
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)fileURL.pathExtension, NULL);
    NSString *mimeType = (__bridge NSString *)(UTTypeCopyPreferredTagWithClass (UTI, kUTTagClassMIMEType));
    CFRelease(UTI);
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
    if(row < [_connectedXMPP count] && row>=0)
    {
        xmpp* account =  [_connectedXMPP objectAtIndex:row];
        dispatch_async(_netQueue, ^{
            if(account)
            {
                [account getServiceDetails];
            }
        });
    }
}

-(NSString*) getAccountNameForConnectedRow:(NSInteger) row
{
    if(row<[_connectedXMPP count] && row>=0)
    {
        xmpp* account = [_connectedXMPP objectAtIndex:row];
        return account.connectionProperties.identity.jid;
    }
    return @"";
}

#pragma mark - contact

-(void) removeContact:(MLContact *) contact
{
    xmpp* account = [self getConnectedAccountForID:contact.accountId];
    if(account)
    {

        if(contact.isGroup)
        {
            //if MUC
            [account leaveRoom:contact.contactJid withNick:contact.accountNickInGroup];
        } else  {
            [account removeFromRoster:contact.contactJid];
        }
        //remove from DB
        [[DataLayer sharedInstance] removeBuddy:contact.contactJid forAccount:contact.accountId];
    }
}

-(void) addContact:(MLContact *) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
     [account addToRoster:contact.contactJid];
}

-(void) getVCard:(MLContact *) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    [account getVCard:contact.contactJid];
}

-(void) blocked:(BOOL) isBlockd Jid:(MLContact *) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    [account setBlocked:isBlockd forJid:contact.contactJid];
}

#pragma mark - MUC commands

-(void)  joinRoom:(NSString*) roomName  withNick:(NSString *)nick andPassword:(NSString*) password forAccounId:(NSString *) accountId
{
    xmpp* account= [self getConnectedAccountForID:accountId];
    [account joinRoom:roomName withNick:nick andPassword:password];
}


-(void)  joinRoom:(NSString*) roomName  withNick:(NSString *)nick andPassword:(NSString*) password forAccountRow:(NSInteger) row
{
    if(row<[_connectedXMPP count] && row>=0) {
        xmpp* account = [_connectedXMPP objectAtIndex:row];
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
                dispatch_async(self->_netQueue, ^{
                         [self joinRoom:[row objectForKey:@"room"] withNick:[row objectForKey:@"nick"] andPassword:[row objectForKey:@""] forAccounId:[NSString stringWithFormat:@"%@", [row objectForKey:kAccountID]]];
                });
            }
        }

    }];
}

#pragma mark - Jingle VOIP
-(void) callContact:(MLContact*) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
    [account call:contact];
}


-(void) hangupContact:(MLContact*) contact
{
    xmpp* account =[self getConnectedAccountForID:contact.accountId];
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
    for(xmpp* xmppAccount in _connectedXMPP)
        [xmppAccount setStatusMessageText:message];
}

-(void) setAway:(BOOL) isAway
{
    for(xmpp* xmppAccount in _connectedXMPP)
        [xmppAccount setAway:isAway];
}

#pragma mark message signals
-(void) handleNewMessage:(NSNotification *)notification
{
#if TARGET_OS_IPHONE
    if(![HelperTools isAppExtension])
        dispatch_async(dispatch_get_main_queue(), ^{
            MonalAppDelegate* appDelegate = (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
            [appDelegate updateUnread];
        });
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

-(void) cleanArrayOfConnectedAccounts:(NSMutableArray*) dirtySet
{
    //yes, this is ineffecient but the size shouldnt ever be huge
    NSMutableIndexSet *indexSet=[[NSMutableIndexSet alloc] init];
    for(xmpp* xmppAccount in _connectedXMPP)
    {
        NSInteger pos=0;
        for(MLContact* row in dirtySet)
        {
            if([row.contactJid isEqualToString:xmppAccount.connectionProperties.identity.jid])
                [indexSet addIndex:pos];
            pos++;
        }

    }

    [dirtySet removeObjectsAtIndexes:indexSet];
}


#pragma mark - APNS

-(void) setPushNode:(NSString *)node andSecret:(NSString *)secret
{
    self.pushNode=node;
    [DEFAULTS_DB setObject:self.pushNode forKey:@"pushNode"];
    
    if(secret)
    {
        self.pushSecret=secret;
        [DEFAULTS_DB setObject:self.pushSecret forKey:@"pushSecret"];
    }
    else    //use saved one (push server not reachable via http(s)) --> the old secret might still be valid
        self.pushSecret=[DEFAULTS_DB objectForKey:@"pushSecret"];

    for(xmpp* xmppAccount in _connectedXMPP)
    {
        xmppAccount.pushNode=self.pushNode;
        xmppAccount.pushSecret=self.pushSecret;
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
    NSUserDefaults* groupDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAppGroup];
    NSMutableArray* outbox = [[groupDefaults objectForKey:@"outbox"] mutableCopy];
    NSMutableArray* outboxClean = [[groupDefaults objectForKey:@"outbox"] mutableCopy];

    for (NSDictionary* row in outbox)
    {
        NSDictionary* accountDic = [row objectForKey:@"account"] ;
        if([[accountDic objectForKey:kAccountID] integerValue] == [account integerValue])
        {
            NSString* accountID = [NSString stringWithFormat:@"%@", [accountDic objectForKey:kAccountID]];
            NSString* recipient = [row objectForKey:@"recipient"];
            NSAssert(recipient != nil, @"Recipient missing");
            NSAssert(recipient != nil, @"Recipient missing");
            BOOL encryptMessages = [[DataLayer sharedInstance] shouldEncryptForJid:recipient andAccountNo:accountID];
            NSString* fromJID = [NSString stringWithFormat:@"%@@%@", [accountDic objectForKey:@"username"], [accountDic objectForKey:@"domain"]];

            [self sendMessageAndAddToHistory:[row objectForKey:@"url"] toContact:recipient fromAccount:accountID fromJID:fromJID isEncrypted:encryptMessages isMUC:NO isUpload:NO withCompletionHandler:^(BOOL successSendObject, NSString* messageIdSentObject) {
                if(successSendObject) {
                    NSString* comment = (NSString*)[row objectForKey:@"comment"];
                    if(comment.length > 0) {
                        [self sendMessageAndAddToHistory:comment toContact:recipient fromAccount:accountID fromJID:fromJID isEncrypted:encryptMessages isMUC:NO isUpload:NO withCompletionHandler:^(BOOL successSendComment, NSString* messageIdSendComment) {
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
    for(xmpp* xmppAccount in _connectedXMPP)
        [self sendOutboxForAccount:xmppAccount.accountNo];
}

@end
