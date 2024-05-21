//
//  MLVoIPProcessor.m
//  Monal
//
//  Created by admin on 03.07.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLConstants.h"
#import "Monal-Swift.h"
#import "HelperTools.h"
#import "XMPPIQ.h"
#import "XMPPMessage.h"
#import "xmpp.h"
#import "MLXMPPManager.h"
#import "MLVoIPProcessor.h"
#import "MLCall.h"
#import "MonalAppDelegate.h"
#import "ActiveChatsViewController.h"
#import "MLNotificationQueue.h"
#import "secrets.h"

@import PushKit;
@import CallKit;
@import WebRTC;

static NSMutableDictionary* _pendingCalls;

@interface MLVoIPProcessor() <PKPushRegistryDelegate, CXProviderDelegate>
{
}
@property (nonatomic, strong) CXCallController* _Nullable callController;
@property (nonatomic, strong) CXProvider* _Nullable cxProvider;
@end

@interface MLCall() <WebRTCClientDelegate>
@property (nonatomic, strong) NSString* jmiid;
@property (nonatomic) MLCallDirection direction;

@property (nonatomic, strong) MLXMLNode* _Nullable jmiPropose;
@property (nonatomic, strong) MLXMLNode* _Nullable jmiProceed;
@property (nonatomic, strong) NSString* _Nullable fullRemoteJid;
@property (nonatomic, strong) WebRTCClient* _Nullable webRTCClient;
@property (nonatomic, strong) CXAnswerCallAction* _Nullable providerAnswerAction;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL tieBreak;
@property (nonatomic, strong) AVAudioSession* _Nullable audioSession;
@property (nonatomic, assign) MLCallFinishReason finishReason;

@property (nonatomic, readonly) xmpp* account;
@property (nonatomic, readonly) MLVoIPProcessor* voipProcessor;

-(instancetype) initWithUUID:(NSUUID*) uuid jmiid:(NSString*) jmiid contact:(MLContact*) contact callType:(MLCallType) callType andDirection:(MLCallDirection) direction;
-(void) migrateTo:(MLCall*) otherCall;
-(NSString*) short;
-(void) reportRinging;
-(void) handleEndCallActionWithReason:(MLCallFinishReason) reason;
-(void) sendJmiReject;
-(void) sendJmiPropose;
-(void) sendJmiRinging;
@end


@implementation MLVoIPProcessor

+(void) initialize
{
    _pendingCalls = [NSMutableDictionary new];
}

-(id) init
{
    self = [super init];
    
    CXProviderConfiguration* config = [CXProviderConfiguration new];
    config.maximumCallGroups = 1;
    config.maximumCallsPerCallGroup = 1;
    config.supportedHandleTypes = [NSSet setWithObject:@(CXHandleTypeGeneric)];
    config.supportsVideo = YES;
    config.includesCallsInRecents = YES;
    //see https://stackoverflow.com/a/45823730/3528174
#ifndef QUICKSY
    config.iconTemplateImageData = UIImagePNGRepresentation([UIImage imageNamed:@"CallKitLogo"]);
#else
    config.iconTemplateImageData = UIImagePNGRepresentation([UIImage imageNamed:@"QuicksyCallKitLogo"]);
#endif
    self.cxProvider = [[CXProvider alloc] initWithConfiguration:config];
    [self.cxProvider setDelegate:self queue:dispatch_get_main_queue()];
    self.callController = [[CXCallController alloc] initWithQueue:dispatch_get_main_queue()];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleIncomingVoipCall:) name:kMonalIncomingVoipCall object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleIncomingJMIStanza:) name:kMonalIncomingJMIStanza object:nil];

    return self;
}

-(void) deinit
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(MLCall* _Nullable) getCallForUUID:(NSUUID*) uuid
{
    @synchronized(_pendingCalls) {
        return _pendingCalls[uuid];
    }
}

-(void) addCall:(MLCall*) call
{
    DDLogInfo(@"Adding call to list: %@", call);
    @synchronized(_pendingCalls) {
        _pendingCalls[call.uuid] = call;
    }
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalCallAdded object:call userInfo:@{@"uuid": call.uuid}];
}

-(void) removeCall:(MLCall*) call
{
    DDLogInfo(@"Removing call from list: %@", call);
    @synchronized(_pendingCalls) {
        [_pendingCalls removeObjectForKey:call.uuid];
    }
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalCallRemoved object:call userInfo:@{@"uuid": call.uuid}];
}

-(NSUInteger) pendingCallsCount
{
    return _pendingCalls.count;
}

-(NSDictionary<NSString*, MLCall*>*) getActiveCalls
{
    @synchronized(_pendingCalls) {
        return [_pendingCalls copy];
    }
}

-(MLCall* _Nullable) getActiveCallWithContact:(MLContact*) contact
{
    @synchronized(_pendingCalls) {
        for(NSUUID* uuid in _pendingCalls)
        {
            MLCall* call = [self getCallForUUID:uuid];
            if([call.contact isEqualToContact:contact])
                return call;
        }
    }
    return nil;
}

-(MLCall* _Nullable) getCallForJmiid:(NSString*) jmiid
{
    @synchronized(_pendingCalls) {
        for(NSUUID* uuid in _pendingCalls)
        {
            MLCall* call = [self getCallForUUID:uuid];
            if([call.jmiid isEqualToString:jmiid])
                return call;
        }
    }
    return nil;
}

-(MLCall*) initiateCallWithType:(MLCallType) callType toContact:(MLContact*) contact
{
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:contact.accountId];
    MLAssert(account != nil, @"account is nil in initiateCallWithType:ToContact:!", (@{@"contact": contact}));
    
    NSUUID* uuid = [NSUUID UUID];
    MLCall* call = [[MLCall alloc] initWithUUID:uuid jmiid:uuid.UUIDString contact:contact callType:callType andDirection:MLCallDirectionOutgoing];
    DDLogInfo(@"Initiating %@ call to %@: %@", (callType==MLCallTypeAudio ? @"audio" : @"video"), contact, call);
    [self addCall:call];
    
    CXHandle* handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:contact.contactJid];
    CXStartCallAction* startCallAction = [[CXStartCallAction alloc] initWithCallUUID:call.uuid handle:handle];
    startCallAction.contactIdentifier = call.contact.contactDisplayName;
    startCallAction.video = call.callType == MLCallTypeVideo;
    CXTransaction* transaction = [[CXTransaction alloc] initWithAction:startCallAction];
    [self.callController requestTransaction:transaction completion:^(NSError* error) {
        if(error != nil)
        {
            DDLogError(@"Error requesting start call transaction: %@", error);
            [self removeCall:call];
        }
        else
            DDLogInfo(@"Successfully created outgoing call transaction for CallKit..");
    }];
    return call;
}

-(void) voipRegistration
{
    PKPushRegistry* voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    voipRegistry.delegate = self;
    voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

// Handle updated APNS tokens
-(void) pushRegistry:(PKPushRegistry*) registry didUpdatePushCredentials:(PKPushCredentials*) credentials forType:(NSString*) type
{
    NSString* token = [HelperTools stringFromToken:credentials.token];
    DDLogDebug(@"Ignoring APNS voip token string for type %@: %@", type, token);
}

-(void) pushRegistry:(PKPushRegistry*) registry didInvalidatePushTokenForType:(NSString*) type
{
    DDLogDebug(@"APNS voip didInvalidatePushTokenForType:%@ called and ignored...", type);
}

//called if jmi propose was received by appex
-(void) pushRegistry:(PKPushRegistry*) registry didReceiveIncomingPushWithPayload:(PKPushPayload*) payload forType:(PKPushType) type withCompletionHandler:(void (^)(void)) completion
{
    DDLogInfo(@"Received voip push with payload: %@", payload);
    NSDictionary* userInfo = [HelperTools unserializeData:[HelperTools dataWithBase64EncodedString:payload.dictionaryPayload[@"base64Payload"]]];
    [self processIncomingCall:userInfo withCompletion:completion];
}

//called if jmi propose was received by mainapp
-(void) handleIncomingVoipCall:(NSNotification*) notification
{
    DDLogInfo(@"Received JMI propose directly in mainapp...");
    //handle tie breaking: check for already running call
    //(this is only needed if we are in the mainapp because of an already "running" call we now have to tie break)
    XMPPMessage* messageNode =  notification.userInfo[@"messageNode"];
    NSNumber* accountNo = notification.userInfo[@"accountNo"];
    MLContact* contact = [MLContact createContactFromJid:messageNode.fromUser andAccountNo:accountNo];
    MLCall* existingCall = [self getActiveCallWithContact:contact];
    if(existingCall == nil || existingCall.state == MLCallStateFinished)
        return [self processIncomingCall:notification.userInfo withCompletion:nil];
    
    MLCall* newCall = [self createCallWithJmiPropose:messageNode onAccountNo:accountNo];
    if(newCall == nil)
        return;
    
    //handle tie breaking: both parties call each other "simultaneously"
    DDLogDebug(@"Found existing call, trying to break the tie: %@", existingCall);
    if(existingCall.state < MLCallStateConnecting)          //e.g. MLCallStateDiscovering or MLCallStateRinging
    {
        //determine call sort order
        NSData* existingID = [[existingCall.jmiPropose findFirst:@"{urn:xmpp:jingle-message:0}propose@id"] dataUsingEncoding:NSUTF8StringEncoding];
        NSData* newID = [[newCall.jmiPropose findFirst:@"{urn:xmpp:jingle-message:0}propose@id"] dataUsingEncoding:NSUTF8StringEncoding];
        int result = [HelperTools compareIOcted:existingID with:newID];
        if(result == 0)
            result = [HelperTools compareIOcted:[existingCall.contact.contactJid dataUsingEncoding:NSUTF8StringEncoding] with:[newCall.contact.contactJid dataUsingEncoding:NSUTF8StringEncoding]];
        
        DDLogInfo(@"Tie-breaking new incoming call: existingID=%@, newID=%@, result=%d, existingCall=%@, newCall=%@", existingID, newID, result, existingCall, newCall);
        if(result <= 0)         //keep existingID, reject new call having a higher ID
        {
            //reject new call and do nothing with the existingCall
            newCall.tieBreak = YES;
            [newCall handleEndCallActionWithReason:MLCallFinishReasonDeclined];
        }
        else                    //use newID, hang up existing call having a higher ID
        {
            //hang up existing call (retract it) and process new incoming call
            existingCall.tieBreak = YES;
            [existingCall end];
            [self processIncomingCall:notification.userInfo withCompletion:nil];
        }
        return;
    }
    //handle tie breaking: one party migrates the call to other device
    else if(existingCall.state < MLCallStateFinished)       //call already running
    {
        if(newCall.callType == existingCall.callType)
        {
            DDLogInfo(@"Migrating from new call to existing call: %@", existingCall);
            [existingCall migrateTo:newCall];
            
            //drop new call after migration to make sure it does not interfere with our existing call
            DDLogInfo(@"Dropping newCall '%@' in favor of migrated existingCall '%@' ...", [newCall short], [existingCall short]);
            newCall = nil;
        }
        else
        {
            existingCall.tieBreak = YES;        //will be ignored if call was connected, but it doesn't hurt either
            [existingCall end];
            [self processIncomingCall:notification.userInfo withCompletion:nil];
        }
        return;
    }
    unreachable();
}

-(void) processIncomingCall:(NSDictionary* _Nonnull) userInfo withCompletion:(void (^ _Nullable)(void)) completion
{
    //TODO: handle jmi propose coming from other devices on our account (see TODO in MLMessageProcessor.m)
    XMPPMessage* messageNode =  userInfo[@"messageNode"];
    NSNumber* accountNo = userInfo[@"accountNo"];
    
    MLCall* call = [self createCallWithJmiPropose:messageNode onAccountNo:accountNo];
    if(call == nil)
    {
        //ios will stop delivering voip notifications if an incoming pushkit notification doesn't trigger a visible ringing
        //indication within 5 seconds (one single time is permitted, the second time we get punished indefinitely)
        MLAssert(completion == nil, @"Got nil call but wakeup was via pushkit, this is dangerous!!", userInfo);
        
        //call pushkit completion if given
        if(completion != nil)
            completion();
        return;
    }
    DDLogInfo(@"Now processing new incoming call: %@", call);
    
    //add call to pending calls list
    [self addCall:call];
    
    [self.cxProvider reportNewIncomingCallWithUUID:call.uuid update:[self constructUpdateForCall:call] completion:^(NSError *error) {
        //add our completion handler to handler queue to initiate xmpp connections
        //this must be done in main thread because the app delegate is only allowed in main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
            [appDelegate incomingWakeupWithCompletionHandler:^(UIBackgroundFetchResult result __unused) {
                DDLogWarn(@"VoIP push wakeup handler timed out");
            }];
        });
        
        if(error != nil)
        {
            DDLogError(@"Call disallowed by system: %@", error);
            [call sendJmiReject];
            //remove this call from pending calls
            [self removeCall:call];
        }
        else
        {
            DDLogDebug(@"Call reported successfully using CallKit, initializing xmpp and WebRTC now...");
            
            //initialize webrtc class (ask for external service credentials, gather ice servers etc.) for call as soon as the callkit ui is shown
            //this will be done once the app delegate started to connect our xmpp accounts above
            //do this in an extra thread to not block this callback thread (could be main thread or otherwise restricted by apple)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                DDLogDebug(@"Sending jmi ringing message...");
                [call sendJmiRinging];
                
                //wait for our account to connect before initializing webrtc using XEP-0215 iq stanzas
                //if the user proceeds the call before we are bound, the outgoing proceed message stanza will be queued and sent once we are bound
                //outgoing iq messages are not queued in all cases (e.g. non-smacks reconnect), hence this waiting loop
                while(call.account.accountState < kStateBound)
                    [NSThread sleepForTimeInterval:0.250];
                
                DDLogDebug(@"Account is connected, now really initialize WebRTC...");
                [self initWebRTCForPendingCall:call];
            });
        }
    }];
    
    //call pushkit completion if given
    if(completion != nil)
        completion();
}

-(void) initWebRTCForPendingCall:(MLCall*) call
{
    DDLogInfo(@"Initializing WebRTC for: %@", call);
    NSMutableArray* iceServers = [NSMutableArray new];
    if([call.account.connectionProperties.discoveredStunTurnServers count] > 0)
    {
        for(NSDictionary* service in call.account.connectionProperties.discoveredStunTurnServers)
            [call.account queryExternalServiceCredentialsFor:service completion:^(id data) {
                //this will not include any credentials if we got an error answer for our credentials query (data will be an empty dict)
                //--> just use the server without credentials then
                NSMutableDictionary* serviceWithCredentials = [NSMutableDictionary dictionaryWithDictionary:service];
                [serviceWithCredentials addEntriesFromDictionary:(NSDictionary*)data];
                DDLogDebug(@"Got new external service credentials: %@", serviceWithCredentials);
                //transport is only defined for turn/turns, but not for stun/stuns from M110 onwards
                NSString* transport = @"";
                if([@[@"turn", @"turns"] containsObject:serviceWithCredentials[@"type"]])
                {
                    if(serviceWithCredentials[@"username"] == nil || serviceWithCredentials[@"password"] == nil)
                    {
                        DDLogWarn(@"Invalid turn/turns credentials: missing username or password, ignoring!");
                        return;
                    }
                    if(serviceWithCredentials[@"transport"] != nil)
                        transport = [NSString stringWithFormat:@"?transport=%@", serviceWithCredentials[@"transport"]];
                }
                [iceServers addObject:[[RTCIceServer alloc]
                    initWithURLStrings:@[[NSString stringWithFormat:@"%@:%@:%@%@",
                        serviceWithCredentials[@"type"],
                        [HelperTools isIP:serviceWithCredentials[@"host"]] ? [NSString stringWithFormat:@"[%@]", serviceWithCredentials[@"host"]] : serviceWithCredentials[@"host"],
                        serviceWithCredentials[@"port"],
                        transport
                    ]]
                    username:serviceWithCredentials[@"username"]
                    credential:serviceWithCredentials[@"password"]
                    tlsCertPolicy:RTCTlsCertPolicyInsecureNoCheck
                ]];
                
                //proceed only if all ice servers have been processed
                if([iceServers count] == [call.account.connectionProperties.discoveredStunTurnServers count])
                {
                    DDLogInfo(@"Done processing ICE servers, trying to connect WebRTC session...");
                    [self createWebRTCClientForCall:call usingICEServers:iceServers];
                }
            }];
    }
    else if([[HelperTools defaultsDB] boolForKey: @"webrtcUseFallbackTurn"])
    {
        DDLogInfo(@"No ICE servers detected, trying to connect WebRTC session using our own STUN servers as fallback...");
        //use own stun server as fallback
        [iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:[HelperTools getFailoverStunServers]]];
        
        // request turn credentials
        NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/api/v1/challenge/new" relativeToURL:[HelperTools getFailoverTurnApiServer]]];
        if(@available(iOS 16.1, macCatalyst 16.1, *))
            if([[HelperTools defaultsDB] boolForKey: @"useDnssecForAllConnections"])
                urlRequest.requiresDNSSECValidation = YES;
        [urlRequest setTimeoutInterval:3.0];
        NSURLSession* challengeSession = [HelperTools createEphemeralURLSession];
        [[challengeSession dataTaskWithRequest:urlRequest completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            if(error != nil || [(NSHTTPURLResponse*)response statusCode] != 200)
            {
                DDLogWarn(@"Could not retrieve turn challenge, only using stun: %@", error);
                [self createWebRTCClientForCall:call usingICEServers:iceServers];
                return;
            }
            // parse challenge
            NSError* challengeJsonErr;
            NSDictionary* challenge = [NSJSONSerialization JSONObjectWithData:data options:0 error:&challengeJsonErr];
            if(challengeJsonErr != nil && [challenge objectForKey:@"challenge"] != nil)
            {
                DDLogWarn(@"Could not parse turn challenge, only using stun: %@", challengeJsonErr);
                [self createWebRTCClientForCall:call usingICEServers:iceServers];
                return;
            }
            
            unsigned long validUntil = [challenge[@"validUntil"] unsignedLongValue];
            NSMutableData* challengeHmacInput = [NSMutableData dataWithBytes:&validUntil length:sizeof(validUntil)];
            [challengeHmacInput appendData:[challenge[@"challenge"] dataUsingEncoding:NSUTF8StringEncoding]];
            
            // create challenge response
            NSDictionary* challengeResponseDict = @{
                @"challenge": challenge,
                @"appId": TURN_API_SECRET_ID,
                @"challengeResponse": [HelperTools encodeBase64WithData:[HelperTools sha512HmacForKey:[TURN_API_SECRET dataUsingEncoding:NSUTF8StringEncoding] andData:challengeHmacInput]],
            };
            NSError* challengeRespJsonErr;
            NSData* challengeResp = [NSJSONSerialization dataWithJSONObject:challengeResponseDict options:kNilOptions error:&challengeRespJsonErr];
            if(challengeRespJsonErr != nil)
            {
                DDLogWarn(@"Could not create json challenge reponse, only using stun: %@", challengeRespJsonErr);
                [self createWebRTCClientForCall:call usingICEServers:iceServers];
                return;
            }
            NSMutableURLRequest* responseRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/api/v1/challenge/validate" relativeToURL:[HelperTools getFailoverTurnApiServer]]];
            if(@available(iOS 16.1, macCatalyst 16.1, *))
                if([[HelperTools defaultsDB] boolForKey: @"useDnssecForAllConnections"])
                    responseRequest.requiresDNSSECValidation = YES;

            [responseRequest setHTTPMethod:@"POST"];
            [responseRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
            [responseRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            [responseRequest setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[challengeResp length]] forHTTPHeaderField:@"Content-Length"];
            [responseRequest setTimeoutInterval:3.0];
            [responseRequest setHTTPBody:challengeResp];

            NSURLSession* responseSession = [HelperTools createEphemeralURLSession];
            [[responseSession dataTaskWithRequest:responseRequest completionHandler:^(NSData* turnCredentialsData, NSURLResponse* response, NSError* error) {
                if(error != nil || [(NSHTTPURLResponse*)response statusCode] != 200)
                {
                    DDLogWarn(@"Could not retrieve turn credentials, only using stun: %@", error);
                    [self createWebRTCClientForCall:call usingICEServers:iceServers];
                    return;
                }
                NSError* turnCredentialsErr;
                NSDictionary* turnCredentials = [NSJSONSerialization JSONObjectWithData:turnCredentialsData options:0 error:&turnCredentialsErr];
                if(turnCredentials == nil || turnCredentials[@"username"] == nil || turnCredentials[@"password"] == nil || turnCredentials[@"uris"] == nil)
                {
                    DDLogWarn(@"Could not parse turn credentials, only using stun: %@", turnCredentialsErr);
                    [self createWebRTCClientForCall:call usingICEServers:iceServers];
                    return;
                }
                [iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:[turnCredentials objectForKey:@"uris"] username:[turnCredentials objectForKey:@"username"] credential:[turnCredentials objectForKey:@"password"]]];
                
                [self createWebRTCClientForCall:call usingICEServers:iceServers];
            }] resume];
        }] resume];
    }
    //continue without any stun/turn servers if only p2p but no stun/turn servers could be found on local xmpp server
    //AND no fallback to monal servers was configured
    else
    {
        [self createWebRTCClientForCall:call usingICEServers:@[]];
    }
}

-(void) createWebRTCClientForCall:(MLCall*) call usingICEServers:(NSArray<RTCIceServer*>*) iceServers
{
    BOOL forceRelay = ![[HelperTools defaultsDB] boolForKey:@"webrtcAllowP2P"];
    DDLogInfo(@"Initializing webrtc with forceRelay=%@ using ice servers: %@", bool2str(forceRelay), iceServers);
    MLAssert(call.webRTCClient == nil, @"Call does already have a webrtc client object!", (@{@"old_client": call.webRTCClient}));
    WebRTCClient* webRTCClient = [[WebRTCClient alloc] initWithIceServers:iceServers audioOnly:call.callType==MLCallTypeAudio forceRelay:forceRelay];
    call.webRTCClient = webRTCClient;
    webRTCClient.delegate = call;
}

-(void) handleIncomingJMIStanza:(NSNotification*) notification
{
    XMPPMessage* messageNode =  notification.userInfo[@"messageNode"];
    MLAssert(messageNode != nil, @"messageNode is nil in handleIncomingJMIStanza!", notification.userInfo);
    xmpp* account = notification.object;
    MLAssert(account != nil, @"account is nil in handleIncomingJMIStanza!", notification.userInfo);
    
    return [self handleIncomingJMIStanza:messageNode onAccount:account];
}

-(void) handleIncomingJMIStanza:(XMPPMessage*) messageNode onAccount:(xmpp*) account
{
    NSString* jmiid = [messageNode findFirst:@"{urn:xmpp:jingle-message:0}*@id"];
    MLAssert(jmiid != nil, @"call jmiid invalid!", (@{@"*@id": nilWrapper([messageNode findFirst:@"{urn:xmpp:jingle-message:0}*@id"])}));
    MLCall* call = [self getCallForJmiid:jmiid];
    if(call == nil)
    {
        DDLogWarn(@"Ignoring unexpected JMI stanza for unknown call: %@", messageNode);
        //TODO: log action in history db (see TODO in MLMessageProcessor.m)
        return;
    }
        
    DDLogInfo(@"Got new incoming JMI stanza for call: %@", call);
    if(call.direction == MLCallDirectionIncoming && [messageNode check:@"{urn:xmpp:jingle-message:0}proceed"])
    {
        if(![messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi proceed of incoming call NOT coming from other device on our account...");
            return;
        }
        if(call.jmiProceed != nil)
        {
            DDLogWarn(@"Someone tried to proceed an already proceeded incoming call, ignoring this jmi proceed!");
            return;
        }
        
        [call handleEndCallActionWithReason:MLCallFinishReasonAnsweredElsewhere];
    }
    else if(call.direction == MLCallDirectionOutgoing && [messageNode check:@"{urn:xmpp:jingle-message:0}proceed"])
    {
        if(call.jmiProceed != nil)
        {
            DDLogWarn(@"Someone tried to proceed an already proceeded outgoing call, ignoring this jmi proceed!");
            return;
        }
        
        //order matters here!
        call.fullRemoteJid = messageNode.from;
        call.jmiProceed = messageNode;
    }
    else if(call.direction == MLCallDirectionIncoming && [messageNode check:@"{urn:xmpp:jingle-message:0}ringing"])
    {
        if(![messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi ringing of incoming call NOT coming from other device on our account...");
            return;
        }
        
        DDLogWarn(@"Ignoring jmi ringing of incoming call coming from other device on our account...");
    }
    else if(call.direction == MLCallDirectionOutgoing && [messageNode check:@"{urn:xmpp:jingle-message:0}ringing"])
    {
        if([messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi ringing of outgoing call coming from other device on our account...");
            return;
        }
        
        if(call.jmiPropose == nil)
        {
            DDLogWarn(@"Other device did try to report state ringing for a not yet proposed call, ignoring this jmi ringing!");
            return;
        }
        
        [call reportRinging];
    }
    else if(call.direction == MLCallDirectionIncoming && [messageNode check:@"{urn:xmpp:jingle-message:0}reject"])
    {
        if(![messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi reject of incoming call NOT coming from other device on our account...");
            return;
        }
        if(call.jmiProceed != nil)
        {
            DDLogWarn(@"Other device did try to reject already proceeded call, ignoring this jmi reject!");
            return;
        }
        
        DDLogVerbose(@"Marking incoming call as rejected...");
        [call handleEndCallActionWithReason:MLCallFinishReasonRejected];
    }
    else if(call.direction == MLCallDirectionOutgoing && [messageNode check:@"{urn:xmpp:jingle-message:0}reject"])
    {
        if([messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi reject of outgoing call coming from other device on our account...");
            return;
        }
        if(call.jmiProceed != nil)
        {
            DDLogWarn(@"Remote did try to reject already proceeded call, ignoring this jmi reject!");
            return;
        }
        
        DDLogVerbose(@"Marking outgoing call as rejected...");
        [call handleEndCallActionWithReason:MLCallFinishReasonRejected];
    }
    else if(call.direction == MLCallDirectionIncoming && [messageNode check:@"{urn:xmpp:jingle-message:0}retract"])
    {
        if([messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi retract of incoming call coming from other device on our account...");
            return;
        }
        if(call.jmiProceed != nil)
        {
            DDLogWarn(@"Remote did try to retract already proceeded call");
            return;
        }
        
        [call handleEndCallActionWithReason:MLCallFinishReasonUnanswered];
    }
    //this should never happen: one cannot retract a call initiated on one device using another device
    else if(call.direction == MLCallDirectionOutgoing && [messageNode check:@"{urn:xmpp:jingle-message:0}retract"])
    {
        DDLogError(@"This jmi retract should never happen: one cannot retract a call initiated on one device using another device!");
        return;
    }
    else if([messageNode check:@"{urn:xmpp:jingle-message:0}finish"])
    {
        NSString* reason = [messageNode findFirst:@"{urn:xmpp:jingle-message:0}finish/{urn:xmpp:jingle:1}reason/*$"];
        if(call.jmiProceed != nil)
        {
            DDLogInfo(@"Remote finished call with reason: %@", reason);
            [call end];     //use "end" because this was a successful call
        }
        else
        {
            DDLogWarn(@"Remote did try to finish an not yet established call");
            if([@"connectivity-error" isEqualToString:reason])
                [call handleEndCallActionWithReason:MLCallFinishReasonConnectivityError];
            else
                [call handleEndCallActionWithReason:MLCallFinishReasonAnsweredElsewhere];
        }
    }
    else
        DDLogWarn(@"NOT handling JMI stanza, wrong jmi-type/direction combination: %@", messageNode);
}

#pragma mark - CXProvider delegate

-(void) providerDidReset:(CXProvider*) provider
{
    DDLogDebug(@"CXProvider: providerDidReset with provider=%@", provider);
}

-(void) providerDidBegin:(CXProvider*) provider
{
    DDLogDebug(@"CXProvider: providerDidBegin with provider=%@", provider);
}

-(void) provider:(CXProvider*) provider performStartCallAction:(CXStartCallAction*) action
{
    MLCall* call = [self getCallForUUID:action.callUUID];
    DDLogDebug(@"CXProvider: performStartCallAction with provider=%@, CXStartCallAction=%@, pendingCallsInfo: %@", provider, action, call);
    if(call == nil)
    {
        DDLogWarn(@"Pending call not present anymore: %@", (@{
            @"provider": provider,
            @"action": action,
            @"uuid": action.callUUID,
        }));
        [action fail];
        return;
    }
    
    //update call info to include the right info
    [self.cxProvider reportCallWithUUID:call.uuid updated:[self constructUpdateForCall:call]];
            
    //propose call to contact (e.g. let it ring)
    [call sendJmiPropose];
    
    //initialize webrtc class (ask for external service credentials, gather ice servers etc.) for call as soon as the JMI propose was sent
    [self initWebRTCForPendingCall:call];
    
    [action fulfill];
}

-(void) provider:(CXProvider*) provider performAnswerCallAction:(CXAnswerCallAction*) action
{
    MLCall* call = [self getCallForUUID:action.callUUID];
    DDLogDebug(@"CXProvider: performAnswerCallAction with provider=%@, CXAnswerCallAction=%@, pendingCallsInfo: %@", provider, action, call);
    if(call == nil)
    {
        DDLogWarn(@"Pending call not present anymore: %@", (@{
            @"provider": provider,
            @"action": action,
            @"uuid": action.callUUID,
        }));
        [action fail];
        return;
    }
    call.providerAnswerAction = action;
    
    MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
    [appDelegate.activeChats presentCall:call];
}

-(void) provider:(CXProvider*) provider performEndCallAction:(CXEndCallAction*) action
{
    MLCall* call = [self getCallForUUID:action.callUUID];
    DDLogDebug(@"CXProvider: performEndCallAction with provider=%@, CXEndCallAction=%@, pendingCallsInfo: %@", provider, action, call);
    if(call == nil)
    {
        DDLogWarn(@"Pending call not present anymore: %@", (@{
            @"provider": provider,
            @"action": action,
            @"uuid": action.callUUID,
        }));
        [action fail];
        return;
    }
    
    //handle call termination
    if(call.direction == MLCallDirectionIncoming)
    {
        if(call.isConnected)
            [call handleEndCallActionWithReason:MLCallFinishReasonNormal];
        else if(call.jmiProceed != nil)
            [call handleEndCallActionWithReason:MLCallFinishReasonConnectivityError];
        else
            [call handleEndCallActionWithReason:MLCallFinishReasonDeclined];      //send reject
    }
    else
    {
        if(call.isConnected)
            [call handleEndCallActionWithReason:MLCallFinishReasonNormal];
        else if(call.jmiProceed != nil)
            [call handleEndCallActionWithReason:MLCallFinishReasonConnectivityError];
        else
            [call handleEndCallActionWithReason:MLCallFinishReasonRetracted];     //send retract
    }
    
    [action fulfill];
}

-(void) provider:(CXProvider*) provider performSetMutedCallAction:(CXSetMutedCallAction*) action
{
    MLCall* call = [self getCallForUUID:action.callUUID];
    DDLogDebug(@"CXProvider: performSetMutedCallAction with provider=%@, CXSetMutedCallAction=%@, pendingCallsInfo: %@", provider, action, call);
    if(call == nil)
    {
        DDLogWarn(@"Pending call not present anymore: %@", (@{
            @"provider": provider,
            @"action": action,
            @"uuid": action.callUUID,
        }));
        [action fail];
        return;
    }
    
    call.muted = action.muted;
    [action fulfill];
}

-(void) provider:(CXProvider*) provider didActivateAudioSession:(AVAudioSession*) audioSession
{
    DDLogDebug(@"CXProvider: didActivateAudioSession with provider=%@, audioSession=%@", provider, audioSession);
    @synchronized(_pendingCalls) {
        for(NSUUID* uuid in _pendingCalls)
        {
            MLCall* call = [self getCallForUUID:uuid];
            call.audioSession = audioSession;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
            DDLogVerbose(@"Setting audio state to MLAudioStateCall...");
            appDelegate.audioState = MLAudioStateCall;
        });
    }
}

-(void) provider:(CXProvider*) provider didDeactivateAudioSession:(AVAudioSession*) audioSession
{
    DDLogDebug(@"CXProvider: didDeactivateAudioSession with provider=%@, audioSession=%@", provider, audioSession);
    @synchronized(_pendingCalls) {
        for(NSUUID* uuid in _pendingCalls)
        {
            MLCall* call = [self getCallForUUID:uuid];
            call.audioSession = nil;
        }
        
        //switch back to default audio settings destroyed by callkit
        dispatch_async(dispatch_get_main_queue(), ^{
            [HelperTools configureDefaultAudioSession];
            MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
            DDLogVerbose(@"Setting audio state to MLAudioStateNormal...");
            appDelegate.audioState = MLAudioStateNormal;
        });
    }
}

-(CXCallUpdate*) constructUpdateForCall:(MLCall*) call
{
    CXCallUpdate* update = [CXCallUpdate new];
    update.remoteHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:call.contact.contactJid];
    update.localizedCallerName = call.contact.contactDisplayName;
    update.supportsDTMF = NO;
    update.hasVideo = call.callType == MLCallTypeVideo;
    update.supportsHolding = NO;
    update.supportsGrouping = NO;
    update.supportsUngrouping = NO;
    return update;
}

-(MLCall* _Nullable) createCallWithJmiPropose:(XMPPMessage*) messageNode onAccountNo:(NSNumber*) accountNo
{
    //if the jmi id is a uuid, just use it, otherwise infer a uuid from the given jmi id
    NSUUID* uuid = [messageNode findFirst:@"{urn:xmpp:jingle-message:0}propose@id|uuidcast"];
    NSString* jmiid = [messageNode findFirst:@"{urn:xmpp:jingle-message:0}propose@id"];
    MLAssert(uuid != nil, @"call uuid invalid!", (@{@"propose@id": nilWrapper(jmiid)}));
    
    //check if we are in a loop (both accounts participating in this call on the same monal instance)
    //--> ignore this incoming call if that is true
    if([self getCallForJmiid:jmiid] != nil)
    {
        DDLogWarn(@"Call loop detected, ignoring incoming call...");
        return nil;
    }
    
    MLCallType callType = MLCallTypeAudio;
    if([messageNode check:@"{urn:xmpp:jingle-message:0}propose/{urn:xmpp:jingle:apps:rtp:1}description<media=video>"])
        callType = MLCallTypeVideo;
    
    MLCall* call = [[MLCall alloc] initWithUUID:uuid jmiid:jmiid contact:[MLContact createContactFromJid:messageNode.fromUser andAccountNo:accountNo] callType:callType andDirection:MLCallDirectionIncoming];
    //order matters here!
    call.fullRemoteJid = messageNode.from;
    call.jmiPropose = messageNode;
    return call;
}

@end
