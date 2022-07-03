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
        
        xmpp* account = _pendingCalls[self.uuid][@"account"];
        XMPPMessage* messageNode = _pendingCalls[self.uuid][@"messageNode"];
        NSString* localCallID = [messageNode findFirst:@"{urn:xmpp:jingle-message:1}propose@id"];
        [account sendCandidate:candidate forCallID:localCallID toFullJid:messageNode.from];
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
                //inform callkit of established connection
                [_pendingCalls[self.uuid][@"answerAction"] fulfill];
                break;
            case RTCIceConnectionStateDisconnected:
                DDLogInfo(@"New WebRTC ICE state: disconnected");
                [self.voipProcessor.cxprovider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonRemoteEnded];
                
                //TODO: send XEP-0353 call end
                
                [_pendingCalls removeObjectForKey:self.uuid];
                break;
            case RTCIceConnectionStateFailed:
            case RTCIceConnectionStateClosed:
                DDLogInfo(@"New WebRTC ICE state: closed");
                [self.voipProcessor.cxprovider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
                
                //TODO: send XEP-0353 call end
                
                [_pendingCalls removeObjectForKey:self.uuid];
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleIncomingVoipCall:) name:kMonalIncomingVoipCall object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processIncomingSDP:) name:kMonalIncomingSDP object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processIncomingICECandidate:) name:kMonalIncomingICECandidate object:nil];

    return self;
}

-(void) deinit
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    DDLogInfo(@"APNS voip didInvalidatePushTokenForType called and ignored...");
}

//called if jmi message was received by appex
-(void) pushRegistry:(PKPushRegistry*) registry didReceiveIncomingPushWithPayload:(PKPushPayload*) payload forType:(PKPushType) type withCompletionHandler:(void (^)(void)) completion
{
    NSDictionary* userInfo = [HelperTools unserializeData:[HelperTools dataWithBase64EncodedString:payload.dictionaryPayload[@"base64Payload"]]];
    [self processIncomingCall:userInfo withCompletion:completion];
}

//called if jmi message was received by mainapp
-(void) handleIncomingVoipCall:(NSNotification*) notification
{
    [self processIncomingCall:notification.userInfo withCompletion:nil];
}

-(void) processIncomingICECandidate:(NSNotification*) notification
{
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
        for(NSUUID* uuid in _pendingCalls)
        {
            NSString* localCallID = [_pendingCalls[uuid][@"messageNode"] findFirst:@"{urn:xmpp:jingle-message:1}propose@id"];
            if(_pendingCalls[uuid][@"account"] == account && [callID isEqualToString:localCallID])
            {
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
                return;
            }
        }
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
    xmpp* account = notification.object;
    NSDictionary* userInfo = notification.userInfo;
    XMPPIQ* iqNode = userInfo[@"iqNode"];
    
    NSString* rawSDP = [[NSString alloc] initWithData:[iqNode findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp#|base64"] encoding:NSUTF8StringEncoding];
    NSString* type = [iqNode findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp@type"];
    RTCSessionDescription* resultSDP = [[RTCSessionDescription alloc] initWithType:[RTCSessionDescription typeForString:type] sdp:rawSDP];
    NSString* callID = [iqNode findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp@id"];
    
    //search pending calls for callID
    @synchronized(_pendingCalls) {
        for(NSUUID* uuid in _pendingCalls)
        {
            NSString* localCallID = [_pendingCalls[uuid][@"messageNode"] findFirst:@"{urn:xmpp:jingle-message:1}propose@id"];
            if(_pendingCalls[uuid][@"account"] == account && [callID isEqualToString:localCallID])
            {
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
                        //it seems we have to create an offer and ignore it before we can create an answer
                        WebRTCClient* webRTCClient = _pendingCalls[uuid][@"webRTCClient"];
                        [webRTCClient offerWithCompletion:^(RTCSessionDescription* sdp) {
                            [webRTCClient answerWithCompletion:^(RTCSessionDescription* localSdp) {
                                XMPPIQ* responseIq = [[XMPPIQ alloc] initAsResponseTo:iqNode];
                                [responseIq addChildNode:[[MLXMLNode alloc] initWithElement:@"sdp" andNamespace:@"urn:tmp:monal:webrtc:sdp:1" withAttributes:@{
                                    @"id": localCallID,
                                    @"type": [RTCSessionDescription stringForType:localSdp.type]
                                } andChildren:@[] andData:[HelperTools encodeBase64WithString:localSdp.sdp]]];
                                [account send:responseIq];
                            }];
                        }];
                    }
                }];
                return;
            }
        }
    }
    
    //not found --> ignore incoming sdp and respond with error
    DDLogWarn(@"Could not find pending call for remote sdp offer, responding with error...");
    XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
    [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"wait"} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"unexpected-request" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
    ] andData:nil]];
    [account send:errorIq];
}

-(void) connectIncommingVoIPCall:(NSUUID*) uuid
{
    XMPPMessage* messageNode;
    xmpp* account;
    WebRTCClient* webRTCClient;
    @synchronized(_pendingCalls) {
        messageNode = _pendingCalls[uuid][@"messageNode"];
        account = _pendingCalls[uuid][@"account"];
        webRTCClient = _pendingCalls[uuid][@"webRTCClient"];
    }
    
    XMPPMessage* acceptNode = [[XMPPMessage alloc] init];
    acceptNode.to = messageNode.fromUser;
    [acceptNode.attributes setObject:kMessageChatType forKey:@"type"];
    [acceptNode addChildNode:[[MLXMLNode alloc] initWithElement:@"accept" andNamespace:@"urn:xmpp:jingle-message:1" withAttributes:@{
        @"id": [messageNode findFirst:@"{urn:xmpp:jingle-message:1}propose@id"]
    } andChildren:@[] andData:nil]];
    [acceptNode setStoreHint];
    [account send:acceptNode];
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
    DDLogDebug(@"CXProvider: performAnswerCallAction with provider=%@, CXStartCallAction=%@", provider, action);
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
    [self connectIncommingVoIPCall:action.callUUID];
}

-(void) provider:(CXProvider*) provider performEndCallAction:(CXEndCallAction*) action
{
    DDLogDebug(@"CXProvider: performEndCallAction with provider=%@, CXEndCallAction=%@", provider, action);
    //TODO: end webrtc call if connected
    //TODO: use jmi to inform remote of state (rejected if not webrtc initialized, finalized otherwise)
    [action fulfill];
}

-(void) provider:(CXProvider*) provider didActivateAudioSession:(AVAudioSession*) audioSession
{
    DDLogDebug(@"CXProvider: didActivateAudioSession with provider=%@, audioSession=%@", provider, audioSession);
    [[RTCAudioSession sharedInstance] audioSessionDidActivate:audioSession];
}

-(void) provider:(CXProvider*) provider didDeactivateAudioSession:(AVAudioSession*) audioSession
{
    DDLogDebug(@"CXProvider: didDeactivateAudioSession with provider=%@, audioSession=%@", provider, audioSession);
    [[RTCAudioSession sharedInstance] audioSessionDidDeactivate:audioSession];
}

-(void) initWebRTCForPendingCall:(NSUUID*) uuid
{
    xmpp* account;
    @synchronized(_pendingCalls) {
        MLAssert(_pendingCalls[uuid] != nil, @"Pending call not present anymore!", (@{
            @"uuid": uuid,
        }));
        
        account = _pendingCalls[uuid][@"account"];
    }
    
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
                [iceServers addObject:[[RTCIceServer alloc] initWithURLStrings:@[[NSString stringWithFormat:@"%@:%@:%@", serviceWithCredentials[@"type"], serviceWithCredentials[@"host"], serviceWithCredentials[@"port"]]] username:serviceWithCredentials[@"username"] credential:serviceWithCredentials[@"password"]]];
                
                //proceed only if all ice servers have been processed
                if([iceServers count] == [account.connectionProperties.discoveredStunTurnServers count])
                {
                    WebRTCClient* webRTCClient = [[WebRTCClient alloc] initWithIceServers:iceServers];
                    webRTCClient.delegate = [[WebRTCDelegate alloc] initWithUUID:uuid andVoIPProcessor:self];
                    @synchronized(_pendingCalls) {
                        if(!_pendingCalls[uuid])
                            return;
                        
                        _pendingCalls[uuid][@"webRTCClient"] = webRTCClient;
                        
                        //don't try to connect voip call if call wasn't accepted by user yet (will be done once accepted)
                        if(!_pendingCalls[uuid][@"answerAction"])
                            return;
                    }
                    
                    //call was already accepted --> connect voip call
                    [self connectIncommingVoIPCall:uuid];
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
        WebRTCClient* webRTCClient = [[WebRTCClient alloc] initWithIceServers:iceServers];
        webRTCClient.delegate = [[WebRTCDelegate alloc] initWithUUID:uuid andVoIPProcessor:self];
        @synchronized(_pendingCalls) {
            if(!_pendingCalls[uuid])
                return;
            
            _pendingCalls[uuid][@"webRTCClient"] = webRTCClient;
            
            //don't try to connect voip call if call wasn't accepted by user yet (will be done once accepted)
            if(!_pendingCalls[uuid][@"answerAction"])
                return;
        }
        
        //call was already accepted --> connect voip call
        [self connectIncommingVoIPCall:uuid];
    }
}

-(void) processIncomingCall:(NSDictionary* _Nonnull) userInfo withCompletion:(void (^ _Nullable)(void)) completion
{
    XMPPMessage* messageNode =  userInfo[@"messageNode"];
    xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:userInfo[@"accountNo"]];
    MLAssert(account != nil, @"account is nil in processIncomingCall!", userInfo);
    
    //save mapping from callkit uuid to our own call info
    NSUUID* uuid = [NSUUID UUID];
    
    CXCallUpdate* update = [[CXCallUpdate alloc] init];
    update.remoteHandle = [[CXHandle alloc] initWithType:CXHandleTypeEmailAddress value:messageNode.fromUser];
    [self.cxprovider reportNewIncomingCallWithUUID:uuid update:update completion:^(NSError *error) {
        if(error != nil)
        {
            DDLogError(@"Call disallowed by system: %@", error);
            
            XMPPMessage* rejectNode = [[XMPPMessage alloc] init];
            rejectNode.to = messageNode.fromUser;
            [rejectNode.attributes setObject:kMessageChatType forKey:@"type"];
            [rejectNode addChildNode:[[MLXMLNode alloc] initWithElement:@"reject" andNamespace:@"urn:xmpp:jingle-message:1" withAttributes:@{
                @"id": [messageNode findFirst:@"{urn:xmpp:jingle-message:1}propose@id"]
            } andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"busy"],
                    [[MLXMLNode alloc] initWithElement:@"text" andData:@"Busy here"],
                ] andData:nil]
            ] andData:nil]];
            [rejectNode setStoreHint];
            [account send:rejectNode];
        }
        else
        {
            //initialize webrtc class (ask for external service credentials, gather ice servers etc.) for call as soon as the callkit ui is shown
            @synchronized(_pendingCalls) {
                _pendingCalls[uuid] = [NSMutableDictionary dictionaryWithDictionary:@{
                    @"messageNode": messageNode,
                    @"account": account,
                    @"contact": [MLContact createContactFromJid:messageNode.fromUser andAccountNo:account.accountNo],
                }];
            }
            [self initWebRTCForPendingCall:uuid];
        }
    }];
    
    //call pushkit completion if given
    if(completion != nil)
        completion();
}

@end
