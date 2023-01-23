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
@property (nonatomic, strong) NSUUID* uuid;
@property (nonatomic, strong) MLContact* contact;
@property (nonatomic) MLCallDirection direction;

@property (nonatomic, strong) MLXMLNode* _Nullable jmiPropose;
@property (nonatomic, strong) MLXMLNode* _Nullable jmiAccept;
@property (nonatomic, strong) NSString* _Nullable fullRemoteJid;
@property (nonatomic, strong) WebRTCClient* _Nullable webRTCClient;
@property (nonatomic, strong) CXAnswerCallAction* _Nullable providerAnswerAction;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, strong) AVAudioSession* _Nullable audioSession;
@property (nonatomic, assign) MLCallFinishReason finishReason;

@property (nonatomic, readonly) xmpp* account;
@property (nonatomic, readonly) MLVoIPProcessor* voipProcessor;

-(instancetype) initWithUUID:(NSUUID*) uuid contact:(MLContact*) contact andDirection:(MLCallDirection) direction;
-(void) handleEndCallAction;
-(void) sendJmiReject;
-(void) sendJmiPropose;
@end


@implementation MLVoIPProcessor

+(void) initialize
{
    _pendingCalls = [NSMutableDictionary new];
}

-(id) init
{
    self = [super init];
    
    CXProviderConfiguration* config = [[CXProviderConfiguration alloc] init];
    config.maximumCallGroups = 1;
    config.maximumCallsPerCallGroup = 1;
    config.supportedHandleTypes = [NSSet setWithObject:@(CXHandleTypeGeneric)];
    config.supportsVideo = NO;
    config.includesCallsInRecents = YES;
    //TODO: we need a new app icon having a transparent background
    //see https://stackoverflow.com/a/45823730/3528174
#ifdef IS_ALPHA
    config.iconTemplateImageData = UIImagePNGRepresentation([UIImage imageNamed:@"AlphaAppIcon"]);
#else
    config.iconTemplateImageData = UIImagePNGRepresentation([UIImage imageNamed:@"AppIcon"]);
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

-(CXCallUpdate*) constructUpdateForCall:(MLCall*) call
{
    CXCallUpdate* update = [[CXCallUpdate alloc] init];
    update.remoteHandle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:call.contact.contactJid];
    update.localizedCallerName = call.contact.contactDisplayName;
    update.supportsDTMF = NO;
    update.hasVideo = NO;
    update.supportsHolding = NO;
    update.supportsGrouping = NO;
    update.supportsUngrouping = NO;
    return update;
}

-(MLCall*) initiateAudioCallToContact:(MLContact*) contact
{
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:contact.accountId];
    MLAssert(account != nil, @"account is nil in initiateAudioCallToContact!", (@{@"contact": contact}));
    
    MLCall* call = [[MLCall alloc] initWithUUID:[NSUUID UUID] contact:contact andDirection:MLCallDirectionOutgoing];
    DDLogInfo(@"Initiating audio call to %@: %@", contact, call);
    [self addCall:call];
    
    CXHandle* handle = [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:contact.contactJid];
    CXStartCallAction* startCallAction = [[CXStartCallAction alloc] initWithCallUUID:call.uuid handle:handle];
    startCallAction.contactIdentifier = call.contact.contactDisplayName;
    startCallAction.video = NO;
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
    DDLogDebug(@"Ignoring APNS voip token string: %@", token);
}

-(void) pushRegistry:(PKPushRegistry*) registry didInvalidatePushTokenForType:(NSString*) type
{
    DDLogInfo(@"APNS voip didInvalidatePushTokenForType:%@ called and ignored...", type);
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
    [self processIncomingCall:notification.userInfo withCompletion:nil];
}

-(void) processIncomingCall:(NSDictionary* _Nonnull) userInfo withCompletion:(void (^ _Nullable)(void)) completion
{
    //TODO: handle jmi propose coming from other devices on our account (see TODO in MLMessageProcessor.m)
    XMPPMessage* messageNode =  userInfo[@"messageNode"];
    NSNumber* accountNo = userInfo[@"accountNo"];
    NSUUID* uuid = [messageNode findFirst:@"{urn:xmpp:jingle-message:0}propose@id|uuidcast"];
    MLAssert(uuid != nil, @"call uuid invalid!", (@{@"propose@id": nilWrapper([messageNode findFirst:@"{urn:xmpp:jingle-message:0}propose@id"])}));
    
    MLCall* call = [[MLCall alloc] initWithUUID:uuid contact:[MLContact createContactFromJid:messageNode.fromUser andAccountNo:accountNo] andDirection:MLCallDirectionIncoming];
    //order matters here!
    call.fullRemoteJid = messageNode.from;
    call.jmiPropose = messageNode;
    DDLogInfo(@"Now processing new incoming call: %@", call);
    
    //add call to pending calls list
    [self addCall:call];
    
    [self.cxProvider reportNewIncomingCallWithUUID:uuid update:[self constructUpdateForCall:call] completion:^(NSError *error) {
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
            
            //add our completion handler to handler queue to initiate xmpp connections
            //this must be done in main thread because the app delegate is only allowed in main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
                [appDelegate incomingWakeupWithCompletionHandler:^(UIBackgroundFetchResult result __unused) {
                    DDLogWarn(@"VoIP push wakeup handler timed out");
                }];
            });
            
            //initialize webrtc class (ask for external service credentials, gather ice servers etc.) for call as soon as the callkit ui is shown
            //this will be done once the app delegate started to connect our xmpp accounts above
            //do this in an extra thread to not block this callback thread (could be main thread or otherwise restricted by apple)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                //wait for our account to connect before initializing webrtc using XEP-0215 iq stanzas
                //if the user accepts the call before we are bound, the outgoing accept message stanza will be queued and sent once we are bound
                //outgoing iq messages are not queued in all cases (e.g. non-smacks reconnect), hence this waiting loop
                while(call.account.accountState < kStateBound)
                    [NSThread sleepForTimeInterval:0.250];
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
    NSMutableArray* iceServers = [[NSMutableArray alloc] init];
    if([call.account.connectionProperties.discoveredStunTurnServers count] > 0)
    {
        for(NSDictionary* service in call.account.connectionProperties.discoveredStunTurnServers)
            [call.account queryExternalServiceCredentialsFor:service completion:^(id data) {
                //this will not include any credentials if we got an error answer for our credentials query (data will be an empty dict)
                //--> just use the server without credentials then
                NSMutableDictionary* serviceWithCredentials = [NSMutableDictionary dictionaryWithDictionary:service];
                [serviceWithCredentials addEntriesFromDictionary:(NSDictionary*)data];
                DDLogDebug(@"Got new external service credentials: %@", serviceWithCredentials);
                [iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[[NSString stringWithFormat:@"%@:%@:%@", serviceWithCredentials[@"type"], serviceWithCredentials[@"host"], serviceWithCredentials[@"port"]]] username:serviceWithCredentials[@"username"] credential:serviceWithCredentials[@"password"]]];
                
                //proceed only if all ice servers have been processed
                if([iceServers count] == [call.account.connectionProperties.discoveredStunTurnServers count])
                {
                    DDLogInfo(@"Done processing ICE servers, trying to connect WebRTC session...");
                    WebRTCClient* webRTCClient = [[WebRTCClient alloc] initWithIceServers:iceServers];
                    webRTCClient.delegate = call;
                    call.webRTCClient = webRTCClient;
                }
            }];
    }
    else
    {
        //use google stun server as fallback
        //TODO: use own stun/turn server instead
        [iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[
            @"stun:stun.l.google.com:19302",
            @"stun:stun1.l.google.com:19302",
            @"stun:stun2.l.google.com:19302",
            @"stun:stun3.l.google.com:19302",
            @"stun:stun4.l.google.com:19302"
        ]]];
        DDLogInfo(@"No ICE servers detected, trying to connect WebRTC session using googles STUN servers as fallback...");
        WebRTCClient* webRTCClient = [[WebRTCClient alloc] initWithIceServers:iceServers];
        webRTCClient.delegate = call;
        call.webRTCClient = webRTCClient;
    }
}

-(void) handleIncomingJMIStanza:(NSNotification*) notification
{
    XMPPMessage* messageNode =  notification.userInfo[@"messageNode"];
    MLAssert(messageNode != nil, @"messageNode is nil in handleIncomingJMIStanza!", notification.userInfo);
    xmpp* account = notification.object;
    MLAssert(account != nil, @"account is nil in handleIncomingJMIStanza!", notification.userInfo);
    NSUUID* uuid = [messageNode findFirst:@"{urn:xmpp:jingle-message:0}*@id|uuidcast"];
    MLAssert(uuid != nil, @"call uuid invalid!", (@{@"*@id": nilWrapper([messageNode findFirst:@"{urn:xmpp:jingle-message:0}*@id"])}));
    MLCall* call = [self getCallForUUID:uuid];
    if(call == nil)
    {
        DDLogWarn(@"Ignoring unexpected JMI stanza for unknown call: %@", messageNode);
        //TODO: log action in history db (see TODO in MLMessageProcessor.m)
        return;
    }
        
    DDLogInfo(@"Got new incoming JMI stanza for call: %@", call);
    //TODO: handle tie breaking!
    if(call.direction == MLCallDirectionOutgoing && [messageNode check:@"{urn:xmpp:jingle-message:0}accept"])
    {
        if(call.jmiAccept != nil)
        {
            //TODO: handle moving calls between own devices
            DDLogWarn(@"Someone tried to accept an already accepted outgoing call, ignoring this jmi accept!");
            return;
        }
        
        //order matters here!
        call.fullRemoteJid = messageNode.from;
        call.jmiAccept = messageNode;
    }
    else if(call.direction == MLCallDirectionIncoming && [messageNode check:@"{urn:xmpp:jingle-message:0}accept"])
    {
        if(![messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi accept of incoming call NOT coming from other device on our account...");
            return;
        }
        if(call.jmiAccept != nil)
        {
            //TODO: handle moving calls between own devices
            DDLogWarn(@"Someone tried to accept an already accepted incoming call, ignoring this jmi accept!");
            return;
        }
        
        //handle accept on other device
        [self.cxProvider reportCallWithUUID:call.uuid endedAtDate:nil reason:CXCallEndedReasonAnsweredElsewhere];
        call.finishReason = MLCallFinishReasonAnsweredElsewhere;
        [call handleEndCallAction];     //direct call needed after reportCallWithUUID:endedAtDate:reason:
        [self removeCall:call];
    }
    else if(call.direction == MLCallDirectionIncoming && [messageNode check:@"{urn:xmpp:jingle-message:0}reject"])
    {
        if(![messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi reject of incoming call NOT coming from other device on our account...");
            return;
        }
        if(call.jmiAccept != nil)
        {
            DDLogWarn(@"Other device did try to reject already accepted call, ignoring this jmi reject!");
            return;
        }
        else
        {
            DDLogVerbose(@"Marking incoming call as rejected...");
            //see https://developer.apple.com/documentation/callkit/cxcallendedreason?language=objc
            [self.cxProvider reportCallWithUUID:call.uuid endedAtDate:nil reason:CXCallEndedReasonDeclinedElsewhere];
            call.finishReason = MLCallFinishReasonRejected;
            [call handleEndCallAction];     //direct call needed after reportCallWithUUID:endedAtDate:reason:
            [self removeCall:call];
        }
    }
    else if(call.direction == MLCallDirectionOutgoing && [messageNode check:@"{urn:xmpp:jingle-message:0}reject"])
    {
        if([messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi reject of outgoing call coming from other device on our account...");
            return;
        }
        if(call.jmiAccept != nil)
        {
            DDLogWarn(@"Remote did try to reject already accepted call, ignoring this jmi reject!");
            return;
        }
        else
        {
            DDLogVerbose(@"Marking outgoing call as rejected...");
            //see https://developer.apple.com/documentation/callkit/cxcallendedreason?language=objc
            [self.cxProvider reportCallWithUUID:call.uuid endedAtDate:nil reason:CXCallEndedReasonUnanswered];
            call.finishReason = MLCallFinishReasonRejected;
            [call handleEndCallAction];     //direct call needed after reportCallWithUUID:endedAtDate:reason:
            [self removeCall:call];
        }
    }
    else if(call.direction == MLCallDirectionIncoming && [messageNode check:@"{urn:xmpp:jingle-message:0}retract"])
    {
        if([messageNode.fromUser isEqualToString:account.connectionProperties.identity.jid])
        {
            DDLogWarn(@"Ignoring bogus jmi retract of incoming call coming from other device on our account...");
            return;
        }
        if(call.jmiAccept != nil)
        {
            DDLogWarn(@"Remote did try to retract already accepted call");
            return;
        }
        else
        {
            //see https://developer.apple.com/documentation/callkit/cxcallendedreason?language=objc
            [self.cxProvider reportCallWithUUID:call.uuid endedAtDate:nil reason:CXCallEndedReasonRemoteEnded];
            call.finishReason = MLCallFinishReasonUnanswered;
            [call handleEndCallAction];     //direct call needed after reportCallWithUUID:endedAtDate:reason:
            [self removeCall:call];
        }
        
    }
    //this should never happen: one cannot retract a call initiated on one device using another device
    else if(call.direction == MLCallDirectionOutgoing && [messageNode check:@"{urn:xmpp:jingle-message:0}retract"])
    {
        DDLogError(@"This jmi retract should never happen: one cannot retract a call initiated on one device using another device!");
        return;
    }
    else if([messageNode check:@"{urn:xmpp:jingle-message:0}finish"])
    {
        if(call.jmiAccept != nil)
        {
            DDLogInfo(@"Remote finished call with reason: %@", [messageNode findFirst:@"{urn:xmpp:jingle-message:0}finish/{urn:xmpp:jingle:1}reason/*$"]);
            [call end];
        }
        else
        {
            DDLogWarn(@"Remote did try to finish an not yet established call");
            //see https://developer.apple.com/documentation/callkit/cxcallendedreason?language=objc
            [self.cxProvider reportCallWithUUID:call.uuid endedAtDate:nil reason:CXCallEndedReasonUnanswered];
            call.finishReason = MLCallFinishReasonError;
            [call handleEndCallAction];     //direct call needed after reportCallWithUUID:endedAtDate:reason:
            [self removeCall:call];
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
    
    MonalAppDelegate* appDelegate = (MonalAppDelegate *)[[UIApplication sharedApplication] delegate];
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
    [call handleEndCallAction];
    
    //remove this call from pending calls
    [self removeCall:call];
    
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
    }
}

@end
