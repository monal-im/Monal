//
//  MLCall.m
//  monalxmpp
//
//  Created by admin on 30.12.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
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

@import PushKit;
@import CallKit;
@import WebRTC;

//this is our private interface only shared with MLVoIPProcessor
@interface MLCall() <WebRTCClientDelegate>
{
    //these are not synthesized automatically because we have getters and setters
    MLXMLNode* _jmiProceed;
    CXAnswerCallAction* _providerAnswerAction;
    WebRTCClient* _webRTCClient;
    BOOL _muted;
    BOOL _speaker;
    BOOL _isConnected;
    AVAudioSession* _audioSession;
}
@property (nonatomic, strong) NSUUID* uuid;
@property (nonatomic, strong) NSString* jmiid;
@property (nonatomic, strong) MLContact* contact;
@property (nonatomic) MLCallDirection direction;

@property (nonatomic, strong) MLXMLNode* _Nullable jmiPropose;
@property (nonatomic, strong) MLXMLNode* _Nullable jmiProceed;
@property (nonatomic, strong) NSString* _Nullable fullRemoteJid;
@property (nonatomic, strong) WebRTCClient* _Nullable webRTCClient;
@property (nonatomic, strong) CXAnswerCallAction* _Nullable providerAnswerAction;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isReconnecting;
@property (nonatomic, assign) BOOL isFinished;
@property (nonatomic, assign) BOOL tieBreak;
@property (nonatomic, strong) AVAudioSession* _Nullable audioSession;
@property (nonatomic, assign) MLCallFinishReason finishReason;
@property (nonatomic, assign) uint32_t durationTime;
@property (nonatomic, strong) NSTimer* _Nullable callDurationTimer;
@property (nonatomic, strong) monal_void_block_t _Nullable cancelDiscoveringTimeout;
@property (nonatomic, strong) monal_void_block_t _Nullable cancelRingingTimeout;
@property (nonatomic, strong) monal_void_block_t _Nullable cancelConnectingTimeout;

@property (nonatomic, readonly) xmpp* account;
@property (nonatomic, strong) MLVoIPProcessor* voipProcessor;
@end

//this is private and only shared to this class
@interface MLVoIPProcessor()
@property (nonatomic, strong) CXCallController* _Nullable callController;
@property (nonatomic, strong) CXProvider* _Nullable cxProvider;
-(void) removeCall:(MLCall*) call;
@end

@implementation MLCall

+(instancetype) makeDummyCall:(int) type
{
    NSUUID* uuid = [NSUUID UUID];
    return [[self alloc] initWithUUID:uuid jmiid:uuid.UUIDString contact:[MLContact makeDummyContact:type] andDirection:MLCallDirectionOutgoing];
}

-(instancetype) initWithUUID:(NSUUID*) uuid jmiid:(NSString*) jmiid contact:(MLContact*) contact andDirection:(MLCallDirection) direction
{
    self = [super init];
    MLAssert(uuid != nil, @"Call UUIDs must not be nil!");
    MLAssert(jmiid != nil, @"Call jmiids must not be nil!");
    self.uuid = uuid;
    self.jmiid = jmiid;
    self.contact = contact;
    self.direction = direction;
    self.isConnected = NO;
    self.isReconnecting = NO;
    self.durationTime = 0;
    self.isFinished = NO;
    self.finishReason = MLCallFinishReasonUnknown;
    self.cancelDiscoveringTimeout = nil;
    self.cancelRingingTimeout = nil;
    self.cancelConnectingTimeout = nil;
    
    [HelperTools dispatchSyncReentrant:^{
        MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
        MLAssert(appDelegate.voipProcessor != nil, @"appDelegate.voipProcessor should never be nil!");
        self.voipProcessor = appDelegate.voipProcessor;
    } onQueue:dispatch_get_main_queue()];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processIncomingSDP:) name:kMonalIncomingSDP object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processIncomingICECandidate:) name:kMonalIncomingICECandidate object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAudioRouteChangeNotification:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    return self;
}

-(void) deinit
{
    [self.callDurationTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - public interface

-(void) end
{
    DDLogVerbose(@"Requesting end call transaction for %@", [self short]);
    CXEndCallAction* endCallAction = [[CXEndCallAction alloc] initWithCallUUID:self.uuid];
    CXTransaction* transaction = [[CXTransaction alloc] initWithAction:endCallAction];
    [self.voipProcessor.callController requestTransaction:transaction completion:^(NSError* error) {
        if(error != nil)
        {
            //try to do this "manually" without looping through callkit
            DDLogError(@"Error requesting end call transaction: %@", error);
            [self handleEndCallActionWithReason:MLCallFinishReasonUnknown];
            return;
        }
        else
            DDLogInfo(@"Successfully created end call transaction for CallKit..");
    }];
}

-(void) setMuted:(BOOL) muted
{
    @synchronized(self) {
        if(!self.isConnected)
            return;
        _muted = muted;
        if(_muted)
            [self.webRTCClient muteAudio];
        else
            [self.webRTCClient unmuteAudio];
    }
}

-(BOOL) muted
{
    @synchronized(self) {
        return _muted;
    }
}

-(void) setSpeaker:(BOOL) speaker
{
    @synchronized(self) {
        if(!self.isConnected)
            return;
        if(_speaker == speaker)
            return;
        _speaker = speaker;
        if(_speaker)
            [self.webRTCClient speakerOn];
        else
            [self.webRTCClient speakerOff];
    }
}

-(BOOL) speaker
{
    @synchronized(self) {
        return _speaker;
    }
}

-(MLCallState) state
{
    @synchronized(self) {
        if(self.direction == MLCallDirectionOutgoing)
        {
            if(self.isFinished)
                return MLCallStateFinished;
            if(self.isConnected && self.webRTCClient != nil && self.audioSession != nil)
                return MLCallStateConnected;
            if(self.jmiProceed != nil && self.isReconnecting)
                return MLCallStateReconnecting;
            if(self.jmiProceed != nil)
                return MLCallStateConnecting;
            if(self.jmiProceed == nil && self.cancelRingingTimeout != nil)
                return MLCallStateRinging;
            if(self.jmiProceed == nil && self.cancelDiscoveringTimeout != nil)
                return MLCallStateDiscovering;
            return MLCallStateUnknown;
        }
        else
        {
            if(self.isFinished)
                return MLCallStateFinished;
            if(self.isConnected && self.webRTCClient != nil && self.audioSession != nil)
                return MLCallStateConnected;
            if(self.providerAnswerAction != nil && self.isReconnecting)
                return MLCallStateReconnecting;
            if(self.providerAnswerAction != nil)
                return MLCallStateConnecting;
            if(self.providerAnswerAction == nil)
                return MLCallStateRinging;
            return MLCallStateUnknown;
        }
    }
}

+(NSSet*) keyPathsForValuesAffectingState
{
    return [NSSet setWithObjects:@"direction", @"isConnected", @"jmiProceed", @"webRTCClient", @"providerAnswerAction", @"audioSession", @"isFinished", @"cancelDiscoveringTimeout", @"cancelRingingTimeout", @"cancelConnectingTimeout", nil];
}

#pragma mark - internals

-(xmpp*) account
{
    @synchronized(self) {
        xmpp* account = [[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId];
        MLAssert(account != nil, @"Account of call must be listed in MLXMPPManager connected accounts!", (@{
            @"contact": nilWrapper(self.contact),
            @"call": nilWrapper(self),
        }));
        return account;
    }
}
-(void) startCallDuartionTimer
{
    //the timer needs a thread with runloop, see https://stackoverflow.com/a/18098396/3528174
    dispatch_async(dispatch_get_main_queue(), ^{
        DDLogInfo(@"%@: Starting call duration timer...", [self short]);
        if(self.cancelConnectingTimeout != nil)
            self.cancelConnectingTimeout();
        if(self.callDurationTimer != nil)
            [self.callDurationTimer invalidate];
        self.callDurationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer* timer) {
            DDLogVerbose(@"%@:Call duration timer triggered: %d", [self short], self.durationTime);
            if(self.state == MLCallStateFinished)
            {
                DDLogInfo(@"%@: Stopping call duration timer...", [self short]);
                [timer invalidate];
                self.callDurationTimer = nil;
            }
            else
                self.durationTime++;
        }];
    });
}

-(void) setJmiProceed:(MLXMLNode*) jmiProceed
{
    @synchronized(self) {
        _jmiProceed = jmiProceed;
        if(self.direction == MLCallDirectionOutgoing && self.webRTCClient != nil)
            [self establishOutgoingConnection];
    }
}
-(MLXMLNode*) jmiProceed
{
    @synchronized(self) {
        return _jmiProceed;
    }
}

-(void) setProviderAnswerAction:(CXAnswerCallAction*) action
{
    @synchronized(self) {
        _providerAnswerAction = action;
        if(self.direction == MLCallDirectionIncoming && self.webRTCClient != nil)
            [self establishIncomingConnection];
    }
}
-(CXAnswerCallAction*) providerAnswerAction
{
    @synchronized(self) {
        return _providerAnswerAction;
    }
}

-(void) setWebRTCClient:(WebRTCClient*) webRTCClient
{
    @synchronized(self) {
        _webRTCClient = webRTCClient;
        if(self.webRTCClient != nil && self.direction == MLCallDirectionIncoming && self.providerAnswerAction != nil)
            [self establishIncomingConnection];
        if(self.webRTCClient != nil && self.direction == MLCallDirectionOutgoing && self.jmiProceed != nil)
            [self establishOutgoingConnection];
    }
}
-(WebRTCClient*) webRTCClient
{
    @synchronized(self) {
        return _webRTCClient;
    }
}

-(void) setIsConnected:(BOOL) isConnected
{
    @synchronized(self) {
        BOOL oldValue = _isConnected;
        _isConnected = isConnected;
        
        //if switching to connected state: check if we need to activate the already reported audio session now
        if(oldValue == NO && self.isConnected == YES && self.audioSession != nil)
            [self didActivateAudioSession:self.audioSession];
        
        //start timer once we are fully connected
        if(self.isConnected && self.audioSession != nil)
            [self startCallDuartionTimer];
    }
}
-(BOOL) isConnected
{
    @synchronized(self) {
        return _isConnected;
    }
}

-(void) setAudioSession:(AVAudioSession*) audioSession
{
    @synchronized(self) {
        if(audioSession != nil)
            MLAssert(_audioSession == nil, @"Audio session should never be activated without deactivating old audio session first!", (@{
                @"oldAudioSession": nilWrapper(_audioSession),
                @"newAudioSession": nilWrapper(audioSession),
                @"call": self,
            }));
        AVAudioSession* oldSession = _audioSession;
        _audioSession = audioSession;
        
        //do nothing if not yet connected
        if(self.isConnected == YES && oldSession == nil && self.audioSession != nil)
            [self didActivateAudioSession:self.audioSession];
        
        if(self.audioSession == nil && oldSession != nil)
            [self didDeactivateAudioSession:oldSession];
        
        //start timer once we are fully connected
        if(self.isConnected && self.audioSession != nil)
            [self startCallDuartionTimer];
    }
}
-(AVAudioSession*) audioSession
{
    @synchronized(self) {
        return _audioSession;
    }
}

-(void) didActivateAudioSession:(AVAudioSession*) audioSession
{
    DDLogInfo(@"Activating audio session now: %@", audioSession);
    [[RTCAudioSession sharedInstance] lockForConfiguration];
    [[RTCAudioSession sharedInstance] audioSessionDidActivate:audioSession];
    [[RTCAudioSession sharedInstance] setIsAudioEnabled:YES];
    [[RTCAudioSession sharedInstance] unlockForConfiguration];
}

-(void) didDeactivateAudioSession:(AVAudioSession*) audioSession
{
    DDLogInfo(@"Deactivating audio session now: %@", audioSession);
    [[RTCAudioSession sharedInstance] lockForConfiguration];
    [[RTCAudioSession sharedInstance] audioSessionDidDeactivate:audioSession];
    [[RTCAudioSession sharedInstance] setIsAudioEnabled:NO];
    [[RTCAudioSession sharedInstance] unlockForConfiguration];
}

-(void) reportRinging
{
    DDLogDebug(@"%@ was reported as ringing...", [self short]);
    [self createRingingTimeoutTimer];
}

-(void) migrateTo:(MLCall*) otherCall
{
    //send jmi finish with migration before chaning all ids etc.
    DDLogDebug(@"Migrating call using JMI finish: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initTo:self.contact.contactJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"finish" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"expired"]
        ] andData:nil],
        [[MLXMLNode alloc] initWithElement:@"migrated" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{
            @"to": otherCall.jmiid,
        }  andChildren:@[] andData:nil]
    ] andData:nil]];
    [jmiNode setStoreHint];
    [self.account send:jmiNode];
    
    @synchronized(self) {
        DDLogDebug(@"Preparing this call for new webrtc connection...");
        self.jmiid = otherCall.jmiid;
        self.direction = otherCall.direction;
        self.isConnected = NO;
        self.isReconnecting = YES;
        self.finishReason = MLCallFinishReasonUnknown;
        if(self.webRTCClient != nil)
        {
            DDLogDebug(@"Closing old webrtc connection...");
            WebRTCClient* client = self.webRTCClient;
            self.webRTCClient = nil;
            [client.peerConnection close];
        }
        DDLogDebug(@"Stopping all running timers...");
        if(self.cancelDiscoveringTimeout != nil)
            self.cancelDiscoveringTimeout();
        self.cancelDiscoveringTimeout = nil;
        if(self.cancelRingingTimeout != nil)
            self.cancelRingingTimeout();
        self.cancelRingingTimeout = nil;
        if(self.cancelConnectingTimeout != nil)
            self.cancelConnectingTimeout();
        self.cancelConnectingTimeout = nil;
        
        //report this migrated call as ringing
        [self sendJmiRinging];
        
        //now fake a cxprovider answer action (we do auto-answer this call, but ios does not even know we switched the underlying webrtc connection)
        DDLogVerbose(@"Faking CXAnswerCallAction...");
        self.providerAnswerAction = [[CXAnswerCallAction alloc] initWithCallUUID:self.uuid];
    }
    DDLogDebug(@"Migration done, waiting for new webrtc connection...");
}

-(void) handleEndCallActionWithReason:(MLCallFinishReason) reason
{
    //stop all running timers
    if(self.cancelDiscoveringTimeout != nil)
        self.cancelDiscoveringTimeout();
    self.cancelDiscoveringTimeout = nil;
    if(self.cancelRingingTimeout != nil)
        self.cancelRingingTimeout();
    self.cancelRingingTimeout = nil;
    if(self.cancelConnectingTimeout != nil)
        self.cancelConnectingTimeout();
    self.cancelConnectingTimeout = nil;
    
    //end webrtc call if already established or in the process of establishing
    if(self.webRTCClient != nil)
    {
        [self.webRTCClient.peerConnection close];
        self.webRTCClient = nil;
    }
    
    //update state (this will automatically stop the call duration timer)
    self.finishReason = reason;
    self.isConnected = NO;
    self.isFinished = YES;
    
    //remove this call from pending calls
    [self.voipProcessor removeCall:self];
    
    //the CXEndCallAction means either the call was rejected (if not yet answered) or it was terminated normally (if the call was accepted)
    //see https://developer.apple.com/documentation/callkit/cxcallendedreason?language=objc for end reasons
    if(self.direction == MLCallDirectionIncoming)
    {
        [self.providerAnswerAction fail];               //fail will do nothing if already fulfilled or nil
        if(self.jmiProceed == nil)
        {
            if(self.finishReason == MLCallFinishReasonAnsweredElsewhere)
                [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonAnsweredElsewhere];
            else if(self.finishReason == MLCallFinishReasonUnanswered)
                [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonRemoteEnded];
            else if(self.finishReason == MLCallFinishReasonRejected)
                [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonDeclinedElsewhere];
            else if(self.finishReason == MLCallFinishReasonDeclined)
            {
                if(self.tieBreak)
                    [self sendJmiRejectWithTieBreak];
                else
                    [self sendJmiReject];
            }
            else
                MLAssert(NO, @"Unexpected finish reason!", (@{@"reason": @(self.finishReason), @"call": self}));
        }
        else
        {
            if(self.finishReason == MLCallFinishReasonNormal)
            {
                [self sendJmiFinishWithReason:@"success"];
                //this is not needed because this case is always looped through cxprovider endCallAction
                //[self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonRemoteEnded];
            }
            else if(self.finishReason == MLCallFinishReasonConnectivityError)
            {
                [self sendJmiFinishWithReason:@"connectivity-error"];
                [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
            }
            else
                MLAssert(NO, @"Unexpected finish reason!", (@{@"reason": @(self.finishReason), @"call": self}));
        }
    }
    else
    {
        if(self.jmiPropose != nil)
        {
            if(self.jmiProceed == nil)
            {
                if(self.finishReason == MLCallFinishReasonRejected)
                    [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonRemoteEnded];
                else if(self.finishReason == MLCallFinishReasonAnsweredElsewhere)
                    [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonAnsweredElsewhere];
                else if(self.finishReason == MLCallFinishReasonRetracted)
                {
                    if(self.tieBreak)
                        [self sendJmiRetractWithTieBreak];
                    else
                        [self sendJmiRetract];
                }
                else
                    MLAssert(NO, @"Unexpected finish reason!", (@{@"reason": @(self.finishReason), @"call": self}));
            }
            else
            {
                if(self.finishReason == MLCallFinishReasonNormal)
                {
                    [self sendJmiFinishWithReason:@"success"];
                    //this is not needed because this case is always looped through cxprovider endCallAction
                    //[self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonRemoteEnded];
                }
                else if(self.finishReason == MLCallFinishReasonConnectivityError)
                {
                    [self sendJmiFinishWithReason:@"connectivity-error"];
                    [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
                }
                else
                    MLAssert(NO, @"Unexpected finish reason!", (@{@"reason": @(self.finishReason), @"call": self}));
            }
        }
        else
        {
            //this case probably does never happen
            //(the outgoing call transaction was started, but start call action not yet executed, and then the end call action arrives)
            [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonUnanswered];
            self.finishReason = MLCallFinishReasonConnectivityError;
        }
    }
}

-(void) createConnectingTimeoutTimer
{
    if(self.cancelRingingTimeout != nil)
        self.cancelRingingTimeout();
    self.cancelConnectingTimeout = createTimer(15.0, (^{
        DDLogError(@"Failed to connect call, aborting!");
        [self end];
    }));
}

-(void) createRingingTimeoutTimer
{
    if(self.cancelDiscoveringTimeout != nil)
        self.cancelDiscoveringTimeout();
    self.cancelRingingTimeout = createTimer(45.0, (^{
        DDLogError(@"Call not answered in time, aborting!");
        [self end];
    }));
}

-(void) createDiscoveringTimeoutTimer
{
    self.cancelDiscoveringTimeout = createTimer(30.0, (^{
        DDLogError(@"Discovery not answered in time, aborting!");
        [self end];
    }));
}

-(void) establishIncomingConnection
{
    DDLogInfo(@"Now connecting incoming VoIP call: %@", self);
    [self createConnectingTimeoutTimer];
    
    //TODO: in our non-jingle protocol we only have to accept the call via XEP-0353 and the initiator (e.g. remote) will then initialize the webrtc session via IQs
    [self sendJmiProceed];
}

-(void) establishOutgoingConnection
{
    DDLogInfo(@"Now connecting outgoing VoIP call: %@", self);
    [self.voipProcessor.cxProvider reportOutgoingCallWithUUID:self.uuid startedConnectingAtDate:nil];
    [self createConnectingTimeoutTimer];
    
    //TODO: in our non-jingle protocol the initiator (e.g. we) has to initialize the webrtc session by sending the proper IQs
    [self.webRTCClient offerWithCompletion:^(RTCSessionDescription* sdp) {
        DDLogDebug(@"WebRTC reported local SDP offer, sending to '%@'...", self.fullRemoteJid);
        
        //see https://webrtc.googlesource.com/src/+/refs/heads/main/sdk/objc/api/peerconnection/RTCSessionDescription.h
        XMPPIQ* sdpIQ = [[XMPPIQ alloc] initWithType:kiqSetType to:self.fullRemoteJid];
        [sdpIQ addChildNode:[[MLXMLNode alloc] initWithElement:@"sdp" andNamespace:@"urn:tmp:monal:webrtc:sdp:1" withAttributes:@{
            @"id": self.jmiid,
            @"type": [RTCSessionDescription stringForType:sdp.type]
        } andChildren:@[] andData:[HelperTools encodeBase64WithString:sdp.sdp]]];
        [self.account sendIq:sdpIQ withResponseHandler:^(XMPPIQ* result) {
            DDLogDebug(@"Received SDP response for offer: %@", result);
            NSString* rawSDP = [[NSString alloc] initWithData:[result findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp#|base64"] encoding:NSUTF8StringEncoding];
            NSString* type = [result findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp@type"];
            RTCSessionDescription* resultSDP = [[RTCSessionDescription alloc] initWithType:[RTCSessionDescription typeForString:type] sdp:rawSDP];
            DDLogDebug(@"Setting resultSDP on webRTCClient(%@): %@", self.webRTCClient, resultSDP);
            [self.webRTCClient setRemoteSdp:resultSDP completion:^(id error) {
                if(error)
                    DDLogError(@"Got error while passing remote SDP to webRTCClient: %@", error);
                else
                    DDLogDebug(@"Successfully passed SDP to webRTCClient...");
            }];
        } andErrorHandler:^(XMPPIQ* error) {
            if(error != nil)
                DDLogError(@"Got error for SDP offer: %@", error);
        }];
    }];
}

-(void) sendJmiPropose
{
    DDLogDebug(@"Proposing new call via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initTo:self.contact.contactJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"propose" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"description" andNamespace:@"urn:xmpp:jingle:apps:rtp:1" withAttributes:@{@"media": @"audio"} andChildren:@[] andData:nil]
    ] andData:nil]];
    [jmiNode setStoreHint];
    self.jmiPropose = jmiNode;
    [self.account send:jmiNode];
    
    //abort if no device responds with "ringing" in time
    [self createDiscoveringTimeoutTimer];
}

-(void) sendJmiReject
{
    DDLogDebug(@"Rejecting via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initTo:self.contact.contactJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"reject" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"busy"]
        ] andData:nil]
    ] andData:nil]];
    [jmiNode setStoreHint];
    [self.account send:jmiNode];
}

-(void) sendJmiRejectWithTieBreak
{
    DDLogDebug(@"Rejecting with tie-break via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initTo:self.contact.contactJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"reject" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"expired"]
        ] andData:nil],
        [[MLXMLNode alloc] initWithElement:@"tie-break"]
    ] andData:nil]];
    [jmiNode setStoreHint];
    [self.account send:jmiNode];
}

-(void) sendJmiRinging
{
    DDLogDebug(@"Ringing via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initTo:self.contact.contactJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"ringing" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[] andData:nil]];
    [jmiNode setStoreHint];
    [self.account send:jmiNode];
}

-(void) sendJmiProceed
{
    DDLogDebug(@"Accepting via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initTo:self.contact.contactJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"proceed" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[] andData:nil]];
    [jmiNode setStoreHint];
    self.jmiProceed = jmiNode;
    [self.account send:jmiNode];
}

-(void) sendJmiFinishWithReason:(NSString*) reason
{
    DDLogDebug(@"Finishing via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initTo:self.contact.contactJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"finish" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
            [[MLXMLNode alloc] initWithElement:reason]
        ] andData:nil]
    ] andData:nil]];
    [jmiNode setStoreHint];
    [self.account send:jmiNode];
}

-(void) sendJmiRetract
{
    DDLogDebug(@"Retracting via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initTo:self.contact.contactJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"retract" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"cancel"]
        ] andData:nil]
    ] andData:nil]];
    [jmiNode setStoreHint];
    [self.account send:jmiNode];
}

-(void) sendJmiRetractWithTieBreak
{
    DDLogDebug(@"Retracting via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initTo:self.contact.contactJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"retract" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"cancel"]
        ] andData:nil]
    ] andData:nil]];
    [jmiNode setStoreHint];
    [self.account send:jmiNode];
}

-(NSString*) description
{
    NSString* state;
    switch(self.state)
    {
        case MLCallStateRinging: state = @"ringing"; break;
        case MLCallStateConnecting: state = @"connecting"; break;
        case MLCallStateConnected: state = @"connected"; break;
        case MLCallStateFinished: state = @"finished"; break;
        case MLCallStateUnknown: state = @"unknown"; break;
        default: state = @"undefined"; break;
    }
    return [NSString stringWithFormat:@"%@Call:%@", self.direction == MLCallDirectionIncoming ? @"Incoming" : @"Outgoing", @{
        @"uuid": self.uuid,
        @"state": state,
        @"contact": nilWrapper(self.contact),
        @"fullRemoteJid": nilWrapper(self.fullRemoteJid),
        @"jmiPropose": nilWrapper(self.jmiPropose),
        @"jmiProceed": nilWrapper(self.jmiProceed),
        @"webRTCClient": nilWrapper(self.webRTCClient),
        @"providerAnswerAction": nilWrapper(self.providerAnswerAction),
        @"isConnected": self.isConnected ? @"YES" : @"NO",
    }];
}

-(NSString*) short
{
    return [NSString stringWithFormat:@"%@Call:%@", self.direction == MLCallDirectionIncoming ? @"Incoming" : @"Outgoing", self.uuid];
}

-(BOOL) isEqualToContact:(MLContact*) contact
{
    return [self.contact isEqualToContact:contact];
}

-(BOOL) isEqualToCall:(MLCall*) call
{
    return [self.uuid isEqual:call.uuid];
}

-(BOOL) isEqual:(id _Nullable) object
{
    if(object == nil || self == object)
        return YES;
    else if([object isKindOfClass:[MLContact class]])
        return [self isEqualToContact:(MLContact*)object];
    else if([object isKindOfClass:[MLCall class]])
        return [self isEqualToCall:(MLCall*)object];
    else
        return NO;
}

-(NSUInteger) hash
{
    return [self.uuid hash];
}

#pragma mark - WebRTCClientDelegate

-(void) webRTCClient:(WebRTCClient*) webRTCClient didDiscoverLocalCandidate:(RTCIceCandidate*) candidate
{
    if(webRTCClient != self.webRTCClient)
    {
        DDLogDebug(@"%@: Ignoring discovered local ICE candidate: %@ (call migrated)", [self short], candidate);
        return;
    }
    DDLogDebug(@"%@: Discovered local ICE candidate: %@", [self short], candidate);
    //see https://webrtc.googlesource.com/src/+/refs/heads/main/sdk/objc/api/peerconnection/RTCIceCandidate.h
    DDLogDebug(@"%@: sending new local ICE candidate to '%@'...", [self short], self.fullRemoteJid);
    XMPPIQ* candidateIQ = [[XMPPIQ alloc] initWithType:kiqSetType to:self.fullRemoteJid];
    [candidateIQ addChildNode:[[MLXMLNode alloc] initWithElement:@"candidate" andNamespace:@"urn:tmp:monal:webrtc:candidate:1" withAttributes:@{
        @"id": self.jmiid,
        @"sdpMLineIndex": [[NSNumber numberWithInt:candidate.sdpMLineIndex] stringValue],
        @"sdpMid": [HelperTools encodeBase64WithString:candidate.sdpMid]
    } andChildren:@[] andData:[HelperTools encodeBase64WithString:candidate.sdp]]];
    [self.account sendIq:candidateIQ withResponseHandler:^(XMPPIQ* result) {
        DDLogDebug(@"%@: Received ICE candidate result: %@", [self short], result);
    } andErrorHandler:^(XMPPIQ* error) {
        if(error != nil)
            DDLogError(@"%@: Got error for ICE candidate: %@", [self short], error);
    }];
}
    
-(void) webRTCClient:(WebRTCClient*) webRTCClient didChangeConnectionState:(RTCIceConnectionState) state
{
    @synchronized(self) {
        if(webRTCClient != self.webRTCClient)
        {
            DDLogInfo(@"Ignoring new RTCIceConnectionState %ld for peer connection: %@ (call migrated)", (long)state, self.webRTCClient.peerConnection);
            return;
        }
        DDLogDebug(@"New RTCIceConnectionState %ld for peer connection: %@", (long)state, self.webRTCClient.peerConnection);
        switch(state)
        {
            case RTCIceConnectionStateConnected:
                DDLogInfo(@"New WebRTC ICE state: connected, falling through to completed...");
            case RTCIceConnectionStateCompleted:
                DDLogInfo(@"New WebRTC ICE state: completed: %@", self);
                self.isConnected = YES;
                //at this stage this means the call is incoming (--> fulfill callkit answer action to update ui to reflect connected call)
                if(self.direction == MLCallDirectionIncoming)
                {
                    DDLogInfo(@"Informing CallKit of successful connection of incoming call...");
                    [self.providerAnswerAction fulfill];
                }
                //otherwise the call was outgoing (--> initialize callkit ui for outgoing call, we are connected now)
                else
                {
                    DDLogInfo(@"Informing CallKit of successful connection of outgoing call...");
                    [self.voipProcessor.cxProvider reportOutgoingCallWithUUID:self.uuid connectedAtDate:nil];
                }
                break;
            case RTCIceConnectionStateDisconnected:
                DDLogInfo(@"New WebRTC ICE state: disconnected: %@", self);
                [self end];     //use "end" because this was a successful call
                break;
            case RTCIceConnectionStateFailed:
                DDLogInfo(@"New WebRTC ICE state: failed: %@", self);
                [self end];
                break;
            //all following states can be ignored
            case RTCIceConnectionStateClosed:
                DDLogInfo(@"New WebRTC ICE state: closed: %@", self);
                break;
            case RTCIceConnectionStateNew:
                DDLogInfo(@"New WebRTC ICE state: new: %@", self);
                break;
            case RTCIceConnectionStateChecking:
                DDLogInfo(@"New WebRTC ICE state: checking: %@", self);
                break;
            case RTCIceConnectionStateCount:
                DDLogInfo(@"New WebRTC ICE state: count: %@", self);
                break;
            default:
                DDLogInfo(@"New WebRTC ICE state: UNKNOWN: %@", self);
                break;
        }
    }
}
    
-(void) webRTCClient:(WebRTCClient*) webRTCClient didReceiveData:(NSData*) data
{
    if(webRTCClient != self.webRTCClient)
    {
        DDLogDebug(@"Ignoring received WebRTC data: %@ (call migrated)", data);
        return;
    }
    DDLogDebug(@"Received WebRTC data: %@", data);
}

#pragma mark - ICE handling

-(void) processIncomingICECandidate:(NSNotification*) notification
{
    DDLogInfo(@"Got new incoming ICE candidate...");
    xmpp* account = notification.object;
    NSDictionary* userInfo = notification.userInfo;
    XMPPIQ* iqNode = userInfo[@"iqNode"];
    NSUUID* uuid = [iqNode findFirst:@"{urn:tmp:monal:webrtc:candidate:1}candidate@id|uuid"];
    if(![account.accountNo isEqualToNumber:self.account.accountNo] || ![self.uuid isEqual:uuid])
    {
        DDLogInfo(@"Incoming ICE candidate not matching %@, ignoring...", [self short]);
        return;
    }
    
    NSString* rawSDP = [[NSString alloc] initWithData:[iqNode findFirst:@"{urn:tmp:monal:webrtc:candidate:1}candidate#|base64"] encoding:NSUTF8StringEncoding];
    NSNumber* sdpMLineIndex = [iqNode findFirst:@"{urn:tmp:monal:webrtc:candidate:1}candidate@sdpMLineIndex|int"];
    NSString* sdpMid = [[NSString alloc] initWithData:[iqNode findFirst:@"{urn:tmp:monal:webrtc:candidate:1}candidate@sdpMid|base64"] encoding:NSUTF8StringEncoding];
    RTCIceCandidate* incomingCandidate = [[RTCIceCandidate alloc] initWithSdp:rawSDP sdpMLineIndex:[sdpMLineIndex intValue] sdpMid:sdpMid];
    DDLogInfo(@"%@: Got remote ICE candidate for call: %@", self, incomingCandidate);
    
    weakify(self);
    [self.webRTCClient setRemoteCandidate:incomingCandidate completion:^(id error) {
        strongify(self);
        DDLogDebug(@"Got setRemoteCandidate callback...");
        if(error)
        {
            DDLogError(@"Got error while passing new remote ICE candidate to webRTCClient: %@", error);
            XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
            [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"wait"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"internal-server-error" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
            ] andData:nil]];
            [self.account send:errorIq];
        }
        else
        {
            DDLogDebug(@"Successfully passed new remote ICE candidate to webRTCClient...");
            [self.account send:[[XMPPIQ alloc] initAsResponseTo:iqNode]];
        }
    }];
    
    DDLogDebug(@"Leaving method...");
}

-(void) processIncomingSDP:(NSNotification*) notification
{
    DDLogInfo(@"Got new incoming SDP...");
    xmpp* account = notification.object;
    NSDictionary* userInfo = notification.userInfo;
    XMPPIQ* iqNode = userInfo[@"iqNode"];
    NSUUID* uuid = [iqNode findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp@id|uuid"];
    if(![account.accountNo isEqualToNumber:self.account.accountNo] || ![self.uuid isEqual:uuid])
    {
        DDLogInfo(@"Incoming SDP not matching %@, ignoring...", [self short]);
        return;
    }
    
    NSString* rawSDP = [[NSString alloc] initWithData:[iqNode findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp#|base64"] encoding:NSUTF8StringEncoding];
    NSString* type = [iqNode findFirst:@"{urn:tmp:monal:webrtc:sdp:1}sdp@type"];
    RTCSessionDescription* resultSDP = [[RTCSessionDescription alloc] initWithType:[RTCSessionDescription typeForString:type] sdp:rawSDP];
    DDLogInfo(@"%@: Got remote SDP for call: %@", self, resultSDP);
    
    //this is blocking (e.g. no need for an inner @synchronized)
    weakify(self);
    [self.webRTCClient setRemoteSdp:resultSDP completion:^(id error) {
        strongify(self);
        if(error)
        {
            DDLogError(@"Got error while passing remote SDP to webRTCClient: %@", error);
            XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
            [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"wait"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"internal-server-error" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
            ] andData:nil]];
            [self.account send:errorIq];
        }
        else
        {
            DDLogDebug(@"Successfully passed SDP to webRTCClient...");
            //it seems we have to create an offer and ignore it before we can create the desired answer
            [self.webRTCClient offerWithCompletion:^(RTCSessionDescription* sdp) {
                [self.webRTCClient answerWithCompletion:^(RTCSessionDescription* localSdp) {
                    XMPPIQ* responseIq = [[XMPPIQ alloc] initAsResponseTo:iqNode];
                    [responseIq addChildNode:[[MLXMLNode alloc] initWithElement:@"sdp" andNamespace:@"urn:tmp:monal:webrtc:sdp:1" withAttributes:@{
                        @"id": self.jmiid,
                        @"type": [RTCSessionDescription stringForType:localSdp.type]
                    } andChildren:@[] andData:[HelperTools encodeBase64WithString:localSdp.sdp]]];
                    [self.account send:responseIq];
                }];
            }];
        }
    }];
    
    DDLogDebug(@"Leaving method...");
}

-(void) handleAudioRouteChangeNotification:(NSNotification*) notification
{
    DDLogVerbose(@"Audio route changed: %@", notification);
    DDLogVerbose(@"Current audio route: %@", self.audioSession.currentRoute);
    BOOL speaker = NO;
    for(AVAudioSessionPortDescription* port in self.audioSession.currentRoute.outputs)
        if(port.portType == AVAudioSessionPortBuiltInSpeaker)
            speaker = YES;
    
    if(speaker)
        self.speaker = YES;
    else
        self.speaker = NO;
}

@end
