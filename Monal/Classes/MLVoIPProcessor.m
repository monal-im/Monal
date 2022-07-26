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

@import PushKit;
@import CallKit;
@import WebRTC;

static NSMutableDictionary* _pendingCalls;

@interface WebRTCDelegate : NSObject <WebRTCClientDelegate>
@property (atomic, strong) NSUUID* uuid;
@property (atomic, weak) MLVoIPProcessor* voipProcessor;
@end

@interface MLVoIPProcessor() <PKPushRegistryDelegate, CXProviderDelegate>
{
    
}
@property (nonatomic, strong) CXProvider* _Nullable cxprovider;
@property (nonatomic, strong) CXCallController* _Nullable callController;
-(void) acceptCall:(NSUUID*) uuid;
-(void) retractCall:(NSUUID*) uuid;
-(void) rejectCall:(NSUUID*) uuid;
-(void) finishCall:(NSUUID*) uuid withReason:(NSString*) reason;
@end


@implementation WebRTCDelegate

-(instancetype) initWithUUID:(NSUUID*) uuid andVoIPProcessor:(MLVoIPProcessor*) voipProcessor
{
    self = [super init];
    self.uuid = uuid;
    self.voipProcessor = voipProcessor;
    return self;
}

-(void) webRTCClient:(WebRTCClient*) webRTCClient didDiscoverLocalCandidate:(RTCIceCandidate*) candidate
{
    DDLogDebug(@"Discovered local ICE candidate: %@", candidate);
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[self.uuid] != nil, @"Pending call not present anymore!", (@{
            @"uuid": self.uuid,
            @"candidate": candidate,
        }));
        
        XMPPMessage* messageNode = _pendingCalls[self.uuid][@"messageNode"];
        MLAssert(messageNode != nil, @"messageNode not found in pending calls when discovering local ice candidate!", (@{@"uuid": uuid}));
        NSString* remoteJid = _pendingCalls[self.uuid][@"acceptedByRemote"];
        MLAssert(remoteJid != nil, @"remoteJid not found in pending calls when discovering local ice candidate!", (@{@"uuid": uuid}));
        xmpp* account = _pendingCalls[self.uuid][@"account"];
        MLAssert(account != nil, @"account not found in pending calls when discovering local ice candidate!", (@{@"uuid": uuid}));
        
        NSString* localCallID = [messageNode findFirst:@"{urn:xmpp:jingle-message:1}propose@id"];
        [account sendCandidate:candidate forCallID:localCallID toFullJid:remoteJid];
    }
}
    
-(void) webRTCClient:(WebRTCClient*) client didChangeConnectionState:(RTCIceConnectionState) state
{
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[self.uuid] != nil, @"Pending call not present anymore!", (@{
            @"uuid": self.uuid,
            @"state": @(state),
        }));
        
        switch(state)
        {
            case RTCIceConnectionStateConnected:
            case RTCIceConnectionStateCompleted:
                DDLogInfo(@"New WebRTC ICE state: connected");
                
                //at this stage this means the call is incoming (--> fulfill callkit answer action to update ui to reflect connected call)
                if(_pendingCalls[self.uuid][@"answerAction"] != nil)
                {
                    //inform callkit of established connection
                    [_pendingCalls[self.uuid][@"answerAction"] fulfill];
                }
                //otherwise the call was outgoing (--> initialize callkit ui for outgoing call, we are connected now)
                else
                {
                    XMPPMessage* messageNode = _pendingCalls[self.uuid][@"messageNode"];
                    CXHandle* handle = [[CXHandle alloc] initWithType:CXHandleTypeEmailAddress value:messageNode.fromUser];
                    CXStartCallAction* startCallAction = [[CXStartCallAction alloc] initWithCallUUID:self.uuid handle:handle];
                    CXTransaction* transaction = [[CXTransaction alloc] initWithAction:startCallAction];
                    [self.voipProcessor.callController requestTransaction:transaction completion:^(NSError* error) {
                        @synchronized(_pendingCalls) {
                            if(_pendingCalls[self.uuid] == nil)
                                return;
                            
                            if(error != nil)
                            {
                                DDLogError(@"Error requesting call transaction, retracting call: %@", error);
                                [self.voipProcessor retractCall:self.uuid];
                                return;
                            }
                        }
                    }];
                }
                break;
            case RTCIceConnectionStateDisconnected:
                DDLogInfo(@"New WebRTC ICE state: disconnected");
                [self.voipProcessor.cxprovider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonRemoteEnded];
                [self.voipProcessor finishCall:self.uuid withReason:@"success"];
                break;
            case RTCIceConnectionStateFailed:
            case RTCIceConnectionStateClosed:
                DDLogInfo(@"New WebRTC ICE state: closed");
                [self.voipProcessor.cxprovider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
                [self.voipProcessor finishCall:self.uuid withReason:@"success"];
                break;
            case RTCIceConnectionStateNew:
                DDLogInfo(@"New WebRTC ICE state: new");
                break;
            case RTCIceConnectionStateChecking:
                DDLogInfo(@"New WebRTC ICE state: checking");
                break;
            case RTCIceConnectionStateCount:
                DDLogInfo(@"New WebRTC ICE state: count");
                break;
            default:
                DDLogInfo(@"New WebRTC ICE state: UNKNOWN");
                break;
        }
    }
}
    
-(void) webRTCClient:(WebRTCClient*) client didReceiveData:(NSData*) data
{
    DDLogDebug(@"Received WebRTC data: %@", data);
}

@end


@implementation MLVoIPProcessor

+(void) initialize
{
    _pendingCalls = [[NSMutableDictionary alloc] init];
}

-(id) init
{
    self = [super init];
    
    _cxprovider = [[CXProvider alloc] initWithConfiguration:[[CXProviderConfiguration alloc] init]];
    [self.cxprovider setDelegate:self queue:dispatch_get_main_queue()];
    _callController = [[CXCallController alloc] initWithQueue:dispatch_get_main_queue()];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleIncomingVoipCall:) name:kMonalIncomingVoipCall object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleIncomingJMIStanza:) name:kMonalIncomingJMIStanza object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processIncomingSDP:) name:kMonalIncomingSDP object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processIncomingICECandidate:) name:kMonalIncomingICECandidate object:nil];

    return self;
}

-(void) deinit
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(NSUUID* _Nullable) getUUIDForCallID:(NSString*) callID onAccount:(xmpp* _Nullable) account
{
    @synchronized(_pendingCalls) {
        for(NSUUID* uuid in _pendingCalls)
        {
            NSString* localCallID = [_pendingCalls[uuid][@"messageNode"] findFirst:@"{urn:xmpp:jingle-message:1}propose@id"];
            if([callID isEqualToString:localCallID])
            {
                if(account != nil)
                    MLAssert(_pendingCalls[uuid][@"account"] == account, @"account of pending call matching call id does not match current account", (@{@"callID": callID}));
                return uuid;
            }
        }
    }
    return nil;
}

-(void) voipRegistration
{
    PKPushRegistry* voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    voipRegistry.delegate = self;
    voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

-(NSUInteger) pendingCallsCount
{
    return _pendingCalls.count;
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

-(void) processIncomingICECandidate:(NSNotification*) notification
{
    DDLogInfo(@"Got new incoming ICE candidate...");
    
    xmpp* account = notification.object;
    NSDictionary* userInfo = notification.userInfo;
    XMPPIQ* iqNode = userInfo[@"iqNode"];
    
    NSString* rawSDP = [[NSString alloc] initWithData:[iqNode findFirst:@"{urn:tmp:monal:webrtc:candidate:1}candidate#|base64"] encoding:NSUTF8StringEncoding];
    NSNumber* sdpMLineIndex = [iqNode findFirst:@"{urn:tmp:monal:webrtc:candidate:1}candidate@sdpMLineIndex|int"];
    NSString* sdpMid = [[NSString alloc] initWithData:[iqNode findFirst:@"{urn:tmp:monal:webrtc:candidate:1}candidate@sdpMid|base64"] encoding:NSUTF8StringEncoding];;
    RTCIceCandidate* incomingCandidate = [[RTCIceCandidate alloc] initWithSdp:rawSDP sdpMLineIndex:[sdpMLineIndex intValue] sdpMid:sdpMid];
    NSString* callID = [iqNode findFirst:@"{urn:tmp:monal:webrtc:candidate:1}candidate@id"];
    
    //search pending calls for callID
    @synchronized(_pendingCalls) {
        NSUUID* uuid = [self getUUIDForCallID:callID onAccount:account];
        if(uuid == nil)
        {
            DDLogWarn(@"Ignoring incoming ICE candidate for unknown call: %@", callID);
            return;
        }
        DDLogInfo(@"%@: Got remote ICE candidate for call %@: %@", account, callID, incomingCandidate);
        WebRTCClient* webRTCClient = _pendingCalls[uuid][@"webRTCClient"];
        [webRTCClient setRemoteCandidate:incomingCandidate completion:^(id error) {
            if(error)
            {
                DDLogError(@"Got error while passing new remote ICE candidate to webRTCClient: %@", error);
                XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
                [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"wait"} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"internal-server-error" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
                ] andData:nil]];
                [account send:errorIq];
            }
            else
            {
                DDLogDebug(@"Successfully passed new remote ICE candidate to webRTCClient...");
                [account send:[[XMPPIQ alloc] initAsResponseTo:iqNode]];
            }
        }];
    }
    
    //not found --> ignore incoming sdp and respond with error
    DDLogWarn(@"Could not find pending call for remote sdp offer, responding with error...");
    XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
    [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"wait"} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"unexpected-request" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
    ] andData:nil]];
    [account send:errorIq];
}

-(void) processIncomingSDP:(NSNotification*) notification
{
    DDLogInfo(@"Got new incoming SDP...");
    
    xmpp* account = notification.object;
    NSDictionary* userInfo = notification.userInfo;
    XMPPIQ* iqNode = userInfo[@"iqNode"];
    
    NSString* rawSDP = [[NSString alloc] initWithData:[iqNode findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp#|base64"] encoding:NSUTF8StringEncoding];
    NSString* type = [iqNode findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp@type"];
    RTCSessionDescription* resultSDP = [[RTCSessionDescription alloc] initWithType:[RTCSessionDescription typeForString:type] sdp:rawSDP];
    NSString* callID = [iqNode findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp@id"];
    
    //search pending calls for callID
    @synchronized(_pendingCalls) {
        NSUUID* uuid = [self getUUIDForCallID:callID onAccount:account];
        if(uuid == nil)
        {
            DDLogWarn(@"Ignoring incoming SDP for unknown call: %@", callID);
            return;
        }
        DDLogInfo(@"%@: Got remote SDP for call %@: %@", account, callID, resultSDP);
        WebRTCClient* webRTCClient = _pendingCalls[uuid][@"webRTCClient"];
        [webRTCClient setRemoteSdp:resultSDP completion:^(id error) {
            if(error)
            {
                DDLogError(@"Got error while passing remote SDP to webRTCClient: %@", error);
                XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
                [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"wait"} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"internal-server-error" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
                ] andData:nil]];
                [account send:errorIq];
            }
            else
            {
                DDLogDebug(@"Successfully passed SDP to webRTCClient...");
                //it seems we have to create an offer and ignore it before we can create the desired answer
                WebRTCClient* webRTCClient = _pendingCalls[uuid][@"webRTCClient"];
                [webRTCClient offerWithCompletion:^(RTCSessionDescription* sdp) {
                    [webRTCClient answerWithCompletion:^(RTCSessionDescription* localSdp) {
                        XMPPIQ* responseIq = [[XMPPIQ alloc] initAsResponseTo:iqNode];
                        [responseIq addChildNode:[[MLXMLNode alloc] initWithElement:@"sdp" andNamespace:@"urn:tmp:monal:webrtc:sdp:1" withAttributes:@{
                            @"id": callID,
                            @"type": [RTCSessionDescription stringForType:localSdp.type]
                        } andChildren:@[] andData:[HelperTools encodeBase64WithString:localSdp.sdp]]];
                        [account send:responseIq];
                    }];
                }];
            }
        }];
    }
    
    //not found --> ignore incoming sdp and respond with error
    DDLogWarn(@"Could not find pending call for remote sdp offer, responding with error...");
    XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
    [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"wait"} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"unexpected-request" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
    ] andData:nil]];
    [account send:errorIq];
}

-(void) connectIncomingVoIPCall:(NSUUID*) uuid
{
    DDLogInfo(@"Now connecting incoming VoIP call %@...", uuid);
    //TODO: in our non-jingle protocol we only have to accept the call via XEP-0353 and the initiator (e.g. remote) will then initialize the webrtc session via IQs
    [self acceptCall:uuid];
}

-(void) connectOutgoingVoIPCall:(NSUUID*) uuid
{
    DDLogInfo(@"Now connecting outgoing VoIP call %@...", uuid);
    //TODO: in our non-jingle protocol the initiator (e.g. we) has to initialize the webrtc session by sending the proper IQs
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[uuid] != nil, @"uuid not found in pending calls when trying to connect outgoing call!", (@{@"uuid": uuid}));
        XMPPMessage* messageNode = _pendingCalls[uuid][@"messageNode"];
        MLAssert(messageNode != nil, @"messageNode not found in pending calls when trying to connect outgoing call!", (@{@"uuid": uuid}));
        NSString* remoteJid = _pendingCalls[uuid][@"acceptedByRemote"];
        MLAssert(remoteJid != nil, @"remoteJid not found in pending calls when trying to connect outgoing call!", (@{@"uuid": uuid}));
        xmpp* account = _pendingCalls[uuid][@"account"];
        MLAssert(account != nil, @"account not found in pending calls when trying to connect outgoing call!", (@{@"uuid": uuid}));
        WebRTCClient* webRTCClient = _pendingCalls[uuid][@"webRTCClient"];
        MLAssert(webRTCClient != nil, @"webRTCClient not found in pending calls when trying to connect outgoing call!", (@{@"uuid": uuid}));
        
        [webRTCClient offerWithCompletion:^(RTCSessionDescription* sdp) {
            DDLogDebug(@"WebRTC reported local SDP offer, sending to '%@'...", remoteJid);
            [account sendSDP:sdp forCallID:[messageNode findFirst:@"{urn:xmpp:jingle-message:1}propose@id"] toFullJid:remoteJid];
        }];
    }
}

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
    DDLogDebug(@"CXProvider: performStartCallAction with provider=%@, CXStartCallAction=%@", provider, action);
}

-(void) provider:(CXProvider*) provider performAnswerCallAction:(CXAnswerCallAction*) action
{
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[action.callUUID] != nil, @"Pending call not present anymore!", (@{
            @"action": action,
            @"uuid": action.callUUID
        }));
        
        DDLogDebug(@"CXProvider: performAnswerCallAction with provider=%@, CXAnswerCallAction=%@, pendingCallsInfo: %@", provider, action, _pendingCalls[action.callUUID]);
        _pendingCalls[action.callUUID][@"answerAction"] = action;
        
        //don't try to connect voip call if webrtc isn't initialized yet (will be done once initialized)
        if(!_pendingCalls[action.callUUID][@"webRTCClient"])
            return;
    }
    
    //webrtc was already initialized --> connect voip call
    DDLogDebug(@"webrtc was already initialized --> connect voip call");
    [self connectIncomingVoIPCall:action.callUUID];
}

-(void) provider:(CXProvider*) provider performEndCallAction:(CXEndCallAction*) action
{
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[action.callUUID] != nil, @"Pending call not present anymore!", (@{
            @"action": action,
            @"uuid": action.callUUID
        }));
        
        DDLogDebug(@"CXProvider: performEndCallAction with provider=%@, CXEndCallAction=%@, pendingCallsInfo: %@", provider, action, _pendingCalls[action.callUUID]);
        
        //the CXEndCallAction means either the call was rejected (if not yet accepted) or it was terminated normally (if the call was accepted)
        if(_pendingCalls[action.callUUID][@"answerAction"] == nil)
            [self rejectCall:action.callUUID];
        else
            [self finishCall:action.callUUID withReason:@"success"];
        
        //end webrtc call if already established or in the process of establishing
        if(_pendingCalls[action.callUUID][@"webRTCClient"])
        {
            WebRTCClient* webRTCClient = _pendingCalls[action.callUUID][@"webRTCClient"];
            [webRTCClient.peerConnection close];
        }
        
    }
    [action fulfill];
}

-(void) provider:(CXProvider*) provider didActivateAudioSession:(AVAudioSession*) audioSession
{
    DDLogDebug(@"CXProvider: didActivateAudioSession with provider=%@, audioSession=%@", provider, audioSession);
    [[RTCAudioSession sharedInstance] lockForConfiguration];
    [[RTCAudioSession sharedInstance] audioSessionDidActivate:audioSession];
    [[RTCAudioSession sharedInstance] setIsAudioEnabled:YES];
    [[RTCAudioSession sharedInstance] unlockForConfiguration];
}

-(void) provider:(CXProvider*) provider didDeactivateAudioSession:(AVAudioSession*) audioSession
{
    DDLogDebug(@"CXProvider: didDeactivateAudioSession with provider=%@, audioSession=%@", provider, audioSession);
    [[RTCAudioSession sharedInstance] lockForConfiguration];
    [[RTCAudioSession sharedInstance] audioSessionDidDeactivate:audioSession];
    [[RTCAudioSession sharedInstance] setIsAudioEnabled:NO];
    [[RTCAudioSession sharedInstance] unlockForConfiguration];
}

-(void) initWebRTCForPendingCall:(NSUUID*) uuid
{
    xmpp* account;
    BOOL incoming;
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[uuid] != nil, @"Pending call not present anymore!", (@{
            @"uuid": uuid,
        }));
        
        account = _pendingCalls[uuid][@"account"];
        incoming = [account.connectionProperties.identity.jid isEqualToString:((XMPPMessage*)_pendingCalls[uuid][@"messageNode"]).toUser];
    }
    
    DDLogInfo(@"Initializing WebRTC for pending %@ call %@...", incoming ? @"incoming" : @"outgoing", uuid);
    
    monal_id_block_t performCommonActions = ^(id client) {
        WebRTCClient* webRTCClient = client;
        if(incoming)
        {
            @synchronized(_pendingCalls) {
                if(!_pendingCalls[uuid])
                {
                    DDLogWarn(@"Pending incoming call not present anymore, ignoring...");
                    return;
                }
                _pendingCalls[uuid][@"webRTCClient"] = webRTCClient;
                
                //for incoming calls: don't try to connect voip call if call wasn't accepted by user yet (will be done once accepted)
                if(!_pendingCalls[uuid][@"answerAction"])
                {
                    DDLogInfo(@"Not connecting incoming call, because not yet accepted by local user...");
                    return;
                }
            }
            //call was already accepted --> connect voip call
            DDLogDebug(@"incoming: call was already accepted --> connect voip call");
            [self connectIncomingVoIPCall:uuid];
        }
        else
        {
            @synchronized(_pendingCalls) {
                if(!_pendingCalls[uuid])
                {
                    DDLogWarn(@"Pending outgoing call not present anymore, ignoring...");
                    return;
                }
                _pendingCalls[uuid][@"webRTCClient"] = webRTCClient;
                
                //for outgoing calls: don't try to connect voip call if call wasn't accepted by remote yet (will be done once accepted)
                if(_pendingCalls[uuid][@"acceptedByRemote"] == nil)
                {
                    DDLogInfo(@"Not connecting outgoing call, because not yet accepted by remote user...");
                    return;
                }
            }
            //call was already accepted --> connect voip call
            DDLogDebug(@"outgoing: call was already accepted --> connect voip call");
            [self connectOutgoingVoIPCall:uuid];
        }
    };
    
    NSMutableArray* iceServers = [[NSMutableArray alloc] init];
    if([account.connectionProperties.discoveredStunTurnServers count] > 0)
    {
        for(NSDictionary* service in account.connectionProperties.discoveredStunTurnServers)
        {
            [account queryExternalServiceCredentialsFor:service completion:^(id data) {
                //this will not include any credentials if we got an error answer for our credentials query (data will be an empty dict)
                //--> just use the server without credentials then
                NSMutableDictionary* serviceWithCredentials = [NSMutableDictionary dictionaryWithDictionary:service];
                [serviceWithCredentials addEntriesFromDictionary:(NSDictionary*)data];
                DDLogDebug(@"Got new external service credentials: %@", serviceWithCredentials);
                [iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[[NSString stringWithFormat:@"%@:%@:%@", serviceWithCredentials[@"type"], serviceWithCredentials[@"host"], serviceWithCredentials[@"port"]]] username:serviceWithCredentials[@"username"] credential:serviceWithCredentials[@"password"]]];
                
                //proceed only if all ice servers have been processed
                if([iceServers count] == [account.connectionProperties.discoveredStunTurnServers count])
                {
                    DDLogInfo(@"Done processing ICE servers, trying to connect WebRTC session...");
                    WebRTCClient* webRTCClient = [[WebRTCClient alloc] initWithIceServers:iceServers];
                    webRTCClient.delegate = [[WebRTCDelegate alloc] initWithUUID:uuid andVoIPProcessor:self];
                    performCommonActions(webRTCClient);
                }
            }];
        }
    }
    else
    {
        //use google stun server as fallback
        [iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[
            @"stun:stun.l.google.com:19302",
            @"stun:stun1.l.google.com:19302",
            @"stun:stun2.l.google.com:19302",
            @"stun:stun3.l.google.com:19302",
            @"stun:stun4.l.google.com:19302"
        ]]];
        DDLogInfo(@"No ICE servers detected, trying to connect WebRTC session using googles STUN servers as fallback...");
        WebRTCClient* webRTCClient = [[WebRTCClient alloc] initWithIceServers:iceServers];
        webRTCClient.delegate = [[WebRTCDelegate alloc] initWithUUID:uuid andVoIPProcessor:self];
        performCommonActions(webRTCClient);
    }
}

-(void) processIncomingCall:(NSDictionary* _Nonnull) userInfo withCompletion:(void (^ _Nullable)(void)) completion
{
    XMPPMessage* messageNode =  userInfo[@"messageNode"];
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:userInfo[@"accountNo"]];
    MLAssert(account != nil, @"account is nil in processIncomingCall!", userInfo);
    
    //save mapping from callkit uuid to our own call info
    NSUUID* uuid = [NSUUID UUID];
    
    @synchronized(_pendingCalls) {
        _pendingCalls[uuid] = [NSMutableDictionary dictionaryWithDictionary:@{
            @"messageNode": messageNode,
            @"account": account,
            @"contact": [MLContact createContactFromJid:messageNode.fromUser andAccountNo:account.accountNo],
        }];
        
        DDLogInfo(@"Now processing new incoming call: %@", _pendingCalls[uuid]);
    }
    
    CXCallUpdate* update = [[CXCallUpdate alloc] init];
    update.remoteHandle = [[CXHandle alloc] initWithType:CXHandleTypeEmailAddress value:messageNode.fromUser];
    [self.cxprovider reportNewIncomingCallWithUUID:uuid update:update completion:^(NSError *error) {
        if(error != nil)
        {
            DDLogError(@"Call disallowed by system: %@", error);
            [self rejectCall:uuid];
        }
        else
        {
            DDLogDebug(@"Call reported successfully using PushKit, initializing WebRTC now...");
            //initialize webrtc class (ask for external service credentials, gather ice servers etc.) for call as soon as the callkit ui is shown
            [self initWebRTCForPendingCall:uuid];
        }
    }];
    
    //call pushkit completion if given
    if(completion != nil)
        completion();
}

-(NSUUID*) initiateAudioCallToContact:(MLContact*) contact
{
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:contact.accountId];
    MLAssert(account != nil, @"account is nil in initiateAudioCallToContact!", (@{@"contact": contact}));
    
    NSUUID* uuid = [NSUUID UUID];
    
    DDLogInfo(@"Initiating audio call %@ to %@...", uuid, contact);
    
    XMPPMessage* messageNode = [[XMPPMessage alloc] init];
    messageNode.to = contact.contactJid;
    [messageNode.attributes setObject:kMessageChatType forKey:@"type"];
    [messageNode addChildNode:[[MLXMLNode alloc] initWithElement:@"propose" andNamespace:@"urn:xmpp:jingle-message:1" withAttributes:@{@"id": [uuid UUIDString]} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"description" andNamespace:@"urn:xmpp:jingle:apps:rtp:1" withAttributes:@{@"media": @"audio"} andChildren:@[] andData:nil]
    ] andData:nil]];
    [messageNode setStoreHint];
    [account send:messageNode];
    
    @synchronized(_pendingCalls) {
        _pendingCalls[uuid] = [NSMutableDictionary dictionaryWithDictionary:@{
            @"messageNode": messageNode,
            @"account": account,
            @"contact": contact,
        }];
    }
    //initialize webrtc class (ask for external service credentials, gather ice servers etc.) for call as soon as the JMI propose was sent
    [self initWebRTCForPendingCall:uuid];
    
    return uuid;
}

-(void) handleIncomingJMIStanza:(NSNotification*) notification
{
    XMPPMessage* messageNode =  notification.userInfo[@"messageNode"];
    MLAssert(messageNode != nil, @"messageNode is nil in handleIncomingJMIStanza!", notification.userInfo);
    xmpp* account = notification.object;
    MLAssert(account != nil, @"account is nil in handleIncomingJMIStanza!", notification.userInfo);
    NSString* callID = [messageNode findFirst:@"{urn:xmpp:jingle-message:1}*@id"];
    @synchronized(_pendingCalls) {
        NSUUID* uuid = [self getUUIDForCallID:callID onAccount:account];
        if(uuid == nil)
        {
            DDLogWarn(@"Ignoring incoming JMI stanza for unknown call: %@", callID);
            return;
        }
        
        DDLogInfo(@"Got new incoming JMI stanza for call %@ having call ID %@...", uuid, callID);
        
        if([messageNode check:@"{urn:xmpp:jingle-message:1}accept"])
        {
            //save state for initWebRTCForPendingCall
            _pendingCalls[uuid][@"acceptedByRemote"] = messageNode.from;
            
            //connect call immediatley if we already managed to initialize our webrtc client while the remote device was ringing
            if(_pendingCalls[uuid][@"webRTCClient"] != nil)
                [self connectOutgoingVoIPCall:uuid];
                    
        }
        else
        {
            //TODO: handle incoming JMI messages other than propose and accept (e.g. retract, reject and finish)
            DDLogWarn(@"NOT handling JMI stanza, not implemented yet: %@", messageNode);
        }
    }
}

-(void) acceptCall:(NSUUID*) uuid
{
    DDLogDebug(@"Accepting call via JMI: %@", uuid);
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[uuid] != nil, @"uuid not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        XMPPMessage* messageNode = _pendingCalls[uuid][@"messageNode"];
        MLAssert(messageNode != nil, @"messageNode not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        xmpp* account = _pendingCalls[uuid][@"account"];
        MLAssert(account != nil, @"account not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        
        XMPPMessage* jmiNode = [[XMPPMessage alloc] init];
        jmiNode.to = messageNode.fromUser;
        [jmiNode.attributes setObject:kMessageChatType forKey:@"type"];
        [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"accept" andNamespace:@"urn:xmpp:jingle-message:1" withAttributes:@{
            @"id": [messageNode findFirst:@"{urn:xmpp:jingle-message:1}*@id"]
        } andChildren:@[] andData:nil]];
        [jmiNode setStoreHint];
        [account send:jmiNode];
    }
}

-(void) retractCall:(NSUUID*) uuid
{
    DDLogDebug(@"Retracting call via JMI: %@", uuid);
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[uuid] != nil, @"uuid not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        XMPPMessage* messageNode = _pendingCalls[uuid][@"messageNode"];
        MLAssert(messageNode != nil, @"messageNode not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        xmpp* account = _pendingCalls[uuid][@"account"];
        MLAssert(account != nil, @"account not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        
        XMPPMessage* jmiNode = [[XMPPMessage alloc] init];
        jmiNode.to = messageNode.fromUser;
        [jmiNode.attributes setObject:kMessageChatType forKey:@"type"];
        [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"reject" andNamespace:@"urn:xmpp:jingle-message:1" withAttributes:@{
            @"id": [messageNode findFirst:@"{urn:xmpp:jingle-message:1}*@id"]
        } andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"cancel"]
            ] andData:nil]
        ] andData:nil]];
        [jmiNode setStoreHint];
        [account send:jmiNode];
        
        //remove this call from pending calls
        [_pendingCalls removeObjectForKey:uuid];
    }
}

-(void) rejectCall:(NSUUID*) uuid
{
    DDLogDebug(@"Rejecting call via JMI: %@", uuid);
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[uuid] != nil, @"uuid not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        XMPPMessage* messageNode = _pendingCalls[uuid][@"messageNode"];
        MLAssert(messageNode != nil, @"messageNode not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        xmpp* account = _pendingCalls[uuid][@"account"];
        MLAssert(account != nil, @"account not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        
        XMPPMessage* jmiNode = [[XMPPMessage alloc] init];
        jmiNode.to = messageNode.fromUser;
        [jmiNode.attributes setObject:kMessageChatType forKey:@"type"];
        [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"reject" andNamespace:@"urn:xmpp:jingle-message:1" withAttributes:@{
            @"id": [messageNode findFirst:@"{urn:xmpp:jingle-message:1}*@id"]
        } andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"busy"]
            ] andData:nil]
        ] andData:nil]];
        [jmiNode setStoreHint];
        [account send:jmiNode];
        
        //remove this call from pending calls
        [_pendingCalls removeObjectForKey:uuid];
    }
}

-(void) finishCall:(NSUUID*) uuid withReason:(NSString*) reason
{
    DDLogDebug(@"Finishing call via JMI: %@", uuid);
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[uuid] != nil, @"uuid not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        XMPPMessage* messageNode = _pendingCalls[uuid][@"messageNode"];
        MLAssert(messageNode != nil, @"messageNode not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        xmpp* account = _pendingCalls[uuid][@"account"];
        MLAssert(account != nil, @"account not found in pending calls when trying to send jmi stanza!", (@{@"uuid": uuid}));
        
        XMPPMessage* jmiNode = [[XMPPMessage alloc] init];
        jmiNode.to = messageNode.fromUser;
        [jmiNode.attributes setObject:kMessageChatType forKey:@"type"];
        [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"finish" andNamespace:@"urn:xmpp:jingle-message:1" withAttributes:@{
            @"id": [messageNode findFirst:@"{urn:xmpp:jingle-message:1}*@id"]
        } andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
                [[MLXMLNode alloc] initWithElement:reason]
            ] andData:nil]
        ] andData:nil]];
        [jmiNode setStoreHint];
        [account send:jmiNode];
        
        //remove this call from pending calls
        [_pendingCalls removeObjectForKey:uuid];
    }
}

@end
