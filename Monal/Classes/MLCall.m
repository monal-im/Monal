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
#import "MLOMEMO.h"

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
@property (nonatomic) MLCallType callType;
@property (nonatomic) MLCallDirection direction;
@property (nonatomic) MLCallEncryptionState encryptionState;

@property (nonatomic, strong) MLXMLNode* _Nullable jmiPropose;
@property (nonatomic, strong) MLXMLNode* _Nullable jmiProceed;
@property (nonatomic, strong) NSString* _Nullable fullRemoteJid;
@property (nonatomic, strong) WebRTCClient* _Nullable webRTCClient;
@property (nonatomic, strong) CXAnswerCallAction* _Nullable providerAnswerAction;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL wasConnectedOnce;
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
@property (nonatomic, strong) monal_void_block_t _Nullable cancelWaitUntilIceRestart;
@property (nonatomic, strong) MLXMLNode* localSDP;
@property (nonatomic, strong) MLXMLNode* remoteSDP;
@property (nonatomic, strong) NSNumber* remoteOmemoDeviceId;
@property (nonatomic, strong) NSObject* candidateQueueLock;
@property (nonatomic, strong) NSMutableArray<XMPPIQ*>* incomingCandidateQueue;
@property (nonatomic, strong) NSMutableArray<XMPPIQ*>* outgoingCandidateQueue;

@property (nonatomic, readonly) xmpp* account;
@property (nonatomic, strong) MLVoIPProcessor* voipProcessor;
@end

//this is private and only shared to this class
@interface MLVoIPProcessor()
@property (nonatomic, strong) CXCallController* _Nullable callController;
@property (nonatomic, strong) CXProvider* _Nullable cxProvider;
-(void) removeCall:(MLCall*) call;
-(void) initWebRTCForPendingCall:(MLCall*) call;
-(void) handleIncomingJMIStanza:(MLXMLNode*) messageNode onAccount:(xmpp*) account;
@end

@implementation MLCall

+(instancetype) makeDummyCall:(int) type
{
    NSUUID* uuid = [NSUUID UUID];
    return [[self alloc] initWithUUID:uuid jmiid:uuid.UUIDString contact:[MLContact makeDummyContact:type] callType:MLCallTypeAudio andDirection:MLCallDirectionOutgoing];
}

-(instancetype) initWithUUID:(NSUUID*) uuid jmiid:(NSString*) jmiid contact:(MLContact*) contact callType:(MLCallType) callType andDirection:(MLCallDirection) direction
{
    self = [super init];
    MLAssert(uuid != nil, @"Call UUIDs must not be nil!");
    MLAssert(jmiid != nil, @"Call jmiids must not be nil!");
    self.uuid = uuid;
    self.jmiid = jmiid;
    self.contact = contact;
    self.callType = callType;
    self.direction = direction;
    self.encryptionState = MLCallEncryptionStateUnknown;
    self.isConnected = NO;
    self.wasConnectedOnce = NO;
    self.isReconnecting = NO;
    self.durationTime = 0;
    self.isFinished = NO;
    self.finishReason = MLCallFinishReasonUnknown;
    self.cancelDiscoveringTimeout = nil;
    self.cancelRingingTimeout = nil;
    self.cancelConnectingTimeout = nil;
    self.localSDP = nil;
    self.remoteSDP = nil;
    self.remoteOmemoDeviceId = nil;
    self.candidateQueueLock = [NSObject new];
    self.incomingCandidateQueue = [NSMutableArray new];
    self.outgoingCandidateQueue = [NSMutableArray new];
    
    [HelperTools dispatchAsync:NO reentrantOnQueue:dispatch_get_main_queue() withBlock:^{
        MonalAppDelegate* appDelegate = (MonalAppDelegate*)[[UIApplication sharedApplication] delegate];
        MLAssert(appDelegate.voipProcessor != nil, @"appDelegate.voipProcessor should never be nil!");
        self.voipProcessor = appDelegate.voipProcessor;
    }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processIncomingSDP:) name:kMonalIncomingSDP object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(processIncomingICECandidate:) name:kMonalIncomingICECandidate object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAudioRouteChangeNotification:) name:AVAudioSessionRouteChangeNotification object:nil];
    //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleConnectivityChange:) name:kMonalConnectivityChange object:nil];
    
    return self;
}

-(void) dealloc
{
    DDLogInfo(@"Called dealloc: %@", self);
    [self.callDurationTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - public interface

-(void) startCaptureLocalVideoWithRenderer:(id<RTCVideoRenderer>) renderer andCameraPosition:(AVCaptureDevicePosition) position
{
    MLAssert(self.callType == MLCallTypeVideo, @"startCaptureLocalVideoWithRenderer:andCameraPosition: can only be called for video calls!");
    [self.webRTCClient startCaptureLocalVideoWithRenderer:renderer andCameraPosition:position];
}

-(void) stopCaptureLocalVideo
{
    MLAssert(self.callType == MLCallTypeVideo, @"stopCaptureLocalVideo: can only be called for video calls!");
    [self.webRTCClient stopCaptureLocalVideo];
}

-(void) renderRemoteVideoWithRenderer:(id<RTCVideoRenderer>) renderer
{
    MLAssert(self.callType == MLCallTypeVideo, @"renderRemoteVideoWithRenderer: can only be called for video calls!");
    [self.webRTCClient renderRemoteVideoTo:renderer];
}

-(void) hideVideo
{
    MLAssert(self.callType == MLCallTypeVideo, @"hideVideo: can only be called for video calls!");
    [self.webRTCClient hideVideo];
}

-(void) showVideo
{
    MLAssert(self.callType == MLCallTypeVideo, @"showVideo: can only be called for video calls!");
    [self.webRTCClient showVideo];
}

-(void) end
{
    if(self.isFinished)
    {
        DDLogInfo(@"Not requesting end call action: call already in finished state...");
        return;
    }
    DDLogVerbose(@"Requesting end call transaction for %@", [self short]);
    CXEndCallAction* endCallAction = [[CXEndCallAction alloc] initWithCallUUID:self.uuid];
    CXTransaction* transaction = [[CXTransaction alloc] initWithAction:endCallAction];
    [self.voipProcessor.callController requestTransaction:transaction completion:^(NSError* error) {
        if(error != nil)
        {
            //try to do this "manually" without looping through callkit
            DDLogError(@"Error requesting end call transaction: %@", error);
            [self internalHandleEndCallActionWithReason:MLCallFinishReasonUnknown];
            return;
        }
        else
            DDLogInfo(@"Successfully created end call transaction for CallKit..");
    }];
}

-(void) delayedEnd:(double) delay withDisconnectedState:(BOOL) disconnected
{
    createTimer(delay, (^{
        //isConnected = NO will result in MLCallFinishReasonConnectivityError if wasConnectedOnce == YES
        if(disconnected)
            self.isConnected = NO;
        [self end];
    }));
}

-(void) setMuted:(BOOL) muted
{
    @synchronized(self) {
        if(self.webRTCClient == nil || self.audioSession == nil)
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
        if(self.webRTCClient == nil || self.audioSession == nil)
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
    return [NSSet setWithObjects:@"direction", @"isConnected", @"jmiProceed", @"webRTCClient", @"providerAnswerAction", @"audioSession", @"isFinished", @"cancelDiscoveringTimeout", @"cancelRingingTimeout", @"cancelConnectingTimeout", @"isReconnecting", nil];
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
        if(self.cancelDiscoveringTimeout != nil)
            self.cancelDiscoveringTimeout();
        self.cancelDiscoveringTimeout = nil;
        if(self.cancelRingingTimeout != nil)
            self.cancelRingingTimeout();
        self.cancelRingingTimeout = nil;
        if(self.cancelConnectingTimeout != nil)
            self.cancelConnectingTimeout();
        self.cancelConnectingTimeout = nil;
        
        //don't restart our timer if we just reconnected
        if(self.isReconnecting)
            return;
        if(self.callDurationTimer != nil)
            [self.callDurationTimer invalidate];
        DDLogInfo(@"%@: Starting call duration timer...", [self short]);
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
        if(self.direction == MLCallDirectionOutgoing)
        {
            //see https://gist.github.com/iNPUTmice/aa4fc0aeea6ce5fb0e0fe04baca842cd
            self.remoteOmemoDeviceId = [jmiProceed findFirst:@"{urn:xmpp:jingle-message:0}proceed/{http://gultsch.de/xmpp/drafts/omemo/dlts-srtp-verification}device@id|uint"];
            DDLogInfo(@"Proceed set remote omemo deviceid to: %@", self.remoteOmemoDeviceId);
        }
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
        if(isConnected)
            self.wasConnectedOnce = YES;
        
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
    NSError* error = nil;
    DDLogInfo(@"Activating audio session now: %@", audioSession);
    [[RTCAudioSession sharedInstance] lockForConfiguration];
    NSUInteger options = 0;
    options |= AVAudioSessionCategoryOptionAllowBluetooth;
    options |= AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    options |= AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers;
    options |= AVAudioSessionCategoryOptionAllowAirPlay;
    [[RTCAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:options error:&error];
    if(error != nil)
        DDLogError(@"Failed to configure AVAudioSession category: %@", error);
    [[RTCAudioSession sharedInstance] setMode:AVAudioSessionModeVoiceChat error:&error];
    if(error != nil)
        DDLogError(@"Failed to configure AVAudioSession mode: %@", error);
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
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initWithType:kMessageChatType to:self.fullRemoteJid];
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
        DDLogDebug(@"%@: Preparing this call for new webrtc connection...", [self short]);
        self.jmiid = otherCall.jmiid;
        self.fullRemoteJid = otherCall.fullRemoteJid;
        self.callType = otherCall.callType;
        self.isConnected = NO;
        self.isReconnecting = YES;
        self.finishReason = MLCallFinishReasonUnknown;
        self.direction = otherCall.direction;
        self.jmiPropose = otherCall.jmiPropose;
        self.jmiProceed = nil;
        [self.callDurationTimer invalidate];
        self.callDurationTimer = nil;
        self.localSDP = otherCall.localSDP;     //should be nil
        self.remoteSDP = otherCall.remoteSDP;   //should be nil
        self.incomingCandidateQueue = otherCall.incomingCandidateQueue;             //should be empty
        self.outgoingCandidateQueue = otherCall.outgoingCandidateQueue;             //should be empty
        self.remoteOmemoDeviceId = otherCall.remoteOmemoDeviceId;   //depends on jmiProceed and should be empty
        self.encryptionState = MLCallEncryptionStateUnknown;        //depends on callstate >= connecting
        otherCall = nil;
        
        DDLogDebug(@"%@: Stopping all running timers...", [self short]);
        if(self.cancelDiscoveringTimeout != nil)
            self.cancelDiscoveringTimeout();
        self.cancelDiscoveringTimeout = nil;
        if(self.cancelRingingTimeout != nil)
            self.cancelRingingTimeout();
        self.cancelRingingTimeout = nil;
        if(self.cancelConnectingTimeout != nil)
            self.cancelConnectingTimeout();
        self.cancelConnectingTimeout = nil;
        
        if(self.webRTCClient != nil)
        {
            DDLogDebug(@"%@: Closing old webrtc connection...", [self short]);
            __block WebRTCClient* client = self.webRTCClient;
            self.webRTCClient = nil;
            //do this async to not run into a deadlock with the signalling thread
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [client.peerConnection close];
                client = nil;
                
                //report this migrated call as ringing
                [self sendJmiRinging];
                
                //now fake a cxprovider answer action (we do auto-answer this call, but ios does not even know we switched the underlying webrtc connection)
                DDLogVerbose(@"%@: Faking CXAnswerCallAction...", [self short]);
                self.providerAnswerAction = [[CXAnswerCallAction alloc] initWithCallUUID:self.uuid];
    
                DDLogVerbose(@"%@: Initializing webrtc for our migrated call...", [self short]);
                [self.voipProcessor initWebRTCForPendingCall:self];
                
                DDLogDebug(@"%@: Migration done, waiting for new webrtc connection...", [self short]);
            });
        }
        else
            DDLogDebug(@"%@: No old webrtc connection to close...", [self short]);
    }
}

-(void) handleEndCallActionWithReason:(MLCallFinishReason) reason
{
    @synchronized(self) {
        [self internalHandleEndCallActionWithReason:reason];
        [self internalUpdateCallKitState];
    }
}

-(void) internalHandleEndCallActionWithReason:(MLCallFinishReason) reason
{
    @synchronized(self) {
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
            WebRTCClient* client = self.webRTCClient;
            self.webRTCClient = nil;                    //this will prevent the new webrtc state from being handled
            //do this async to not run into a deadlock with the signalling thread
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [client.peerConnection close];
            });
        }
        
        //update state (this will automatically stop the call duration timer)
        self.finishReason = reason;
        self.isConnected = NO;
        self.isFinished = YES;
        
        //remove this call from pending calls
        [self.voipProcessor removeCall:self];
    }
}

-(void) internalUpdateCallKitState
{
    @synchronized(self) {
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
                else if(self.finishReason == MLCallFinishReasonError)
                {
                    [self sendJmiFinishWithReason:@"application-error"];
                    [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
                }
                else
                    unreachable(@"Unexpected finish reason!", (@{@"call": self}));
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
                else if(self.finishReason == MLCallFinishReasonSecurityError)
                {
                    [self sendJmiFinishWithReason:@"security-error"];
                    [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
                }
                else if(self.finishReason == MLCallFinishReasonError)
                {
                    [self sendJmiFinishWithReason:@"application-error"];
                    [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
                }
                else
                    unreachable(@"Unexpected finish reason!", (@{@"call": self}));
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
                    else if(self.finishReason == MLCallFinishReasonError)
                    {
                        [self sendJmiFinishWithReason:@"application-error"];
                        [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
                    }
                    else
                        unreachable(@"Unexpected finish reason!", (@{@"call": self}));
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
                    else if(self.finishReason == MLCallFinishReasonSecurityError)
                    {
                        [self sendJmiFinishWithReason:@"security-error"];
                        [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
                    }
                    else if(self.finishReason == MLCallFinishReasonError)
                    {
                        [self sendJmiFinishWithReason:@"application-error"];
                        [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonFailed];
                    }
                    else
                        unreachable(@"Unexpected finish reason!", (@{@"call": self}));
                }
            }
            else
            {
                //this case probably does never happen
                //(the outgoing call transaction was started, but start call action not yet executed, and then the end call action arrives)
                [self sendJmiFinishWithReason:@"connectivity-error"];
                [self.voipProcessor.cxProvider reportCallWithUUID:self.uuid endedAtDate:nil reason:CXCallEndedReasonUnanswered];
                self.finishReason = MLCallFinishReasonConnectivityError;
            }
        }
    }
}

-(void) createConnectingTimeoutTimer
{
    if(self.cancelDiscoveringTimeout != nil)
        self.cancelDiscoveringTimeout();
    self.cancelDiscoveringTimeout = nil;
    if(self.cancelRingingTimeout != nil)
        self.cancelRingingTimeout();
    self.cancelRingingTimeout = nil;
    if(self.cancelConnectingTimeout != nil)
        self.cancelConnectingTimeout();
    self.cancelConnectingTimeout = nil;
    self.cancelConnectingTimeout = createTimer(15.0, (^{
        DDLogError(@"Failed to connect call, aborting!");
        [self end];
    }));
}

-(void) createReconnectingTimeoutTimer
{
    if(self.cancelDiscoveringTimeout != nil)
        self.cancelDiscoveringTimeout();
    self.cancelDiscoveringTimeout = nil;
    if(self.cancelRingingTimeout != nil)
        self.cancelRingingTimeout();
    self.cancelRingingTimeout = nil;
    if(self.cancelConnectingTimeout != nil)
        self.cancelConnectingTimeout();
    self.cancelConnectingTimeout = nil;
    self.cancelConnectingTimeout = createTimer(45.0, (^{
        DDLogError(@"Failed to connect call, aborting!");
        [self end];
    }));
}

-(void) createRingingTimeoutTimer
{
    if(self.cancelDiscoveringTimeout != nil)
        self.cancelDiscoveringTimeout();
    self.cancelDiscoveringTimeout = nil;
    if(self.cancelRingingTimeout != nil)
        self.cancelRingingTimeout();
    self.cancelRingingTimeout = nil;
    self.cancelRingingTimeout = createTimer(45.0, (^{
        DDLogError(@"Call not answered in time, aborting!");
        [self end];
    }));
}

-(void) createDiscoveringTimeoutTimer
{
    if(self.cancelDiscoveringTimeout != nil)
        self.cancelDiscoveringTimeout();
    self.cancelDiscoveringTimeout = nil;
    self.cancelDiscoveringTimeout = createTimer(30.0, (^{
        DDLogError(@"Discovery not answered in time, aborting!");
        [self end];
    }));
}

-(void) establishIncomingConnection
{
    DDLogInfo(@"Now connecting incoming VoIP call: %@", self);
    [self.webRTCClient configureAudioSession];
    [self createConnectingTimeoutTimer];
    //the remote (e.g. "initiator") will send a jingle "session-initiate" as soon as it receives our jmi proceed
    [self sendJmiProceed];
}

-(void) establishOutgoingConnection
{
    DDLogInfo(@"Now connecting outgoing VoIP call: %@", self);
    [self.webRTCClient configureAudioSession];
    [self.voipProcessor.cxProvider reportOutgoingCallWithUUID:self.uuid startedConnectingAtDate:nil];
    [self createConnectingTimeoutTimer];
    [self offerSDP];
}

/*
-(void) restartIce
{
    if(self.isReconnecting)
    {
        DDLogWarn(@"Not restarting ICE, already reconnecting!");
        return;
    }
    DDLogInfo(@"Restarting ICE...");
    @synchronized(self) {
        self.isConnected = NO;
        self.isReconnecting = YES;
        [self.webRTCClient.peerConnection restartIce];
        
        //we have to decide for a prefered direction because otherwise we'd get a webrtc error on incoming sdp:
        //Failed to set remote offer sdp: Called in wrong state: have-local-offer
        if(self.direction == MLCallDirectionOutgoing)
            [self offerSDP];
        
        //start connecting timeout if not already running (but leave it running if so, because we don't want to create endless reconnect loops
        if(self.cancelConnectingTimeout == nil)
            [self createReconnectingTimeoutTimer];
    }
}

-(void) handleConnectivityChange:(NSNotification*) notification
{
    //only handle connectivity change if we switched to unreachable
    if(self.wasConnectedOnce && self.isConnected && !self.isReconnecting && [notification.userInfo[@"reachable"] boolValue] == NO)
    {
        DDLogDebug(@"Connectivity changed, restarting ICE...");
        //this will reconnect and use the (possibly still working) old connection until
        //the new connection is usable, then transparently switch over to the new one
        [self restartIce];
    }
    else
        DDLogDebug(@"Not restarting ICE because of connectivity change: was never connected");
}
*/

-(void) offerSDP
{
    //see https://webrtc.googlesource.com/src/+/refs/heads/main/sdk/objc/api/peerconnection/RTCSessionDescription.h
    [self.webRTCClient offerWithCompletion:^(RTCSessionDescription* sdp) {
        DDLogDebug(@"WebRTC reported local SDP '%@', sending to '%@': %@", [RTCSessionDescription stringForType:sdp.type], self.fullRemoteJid, sdp.sdp);
        
        NSArray<MLXMLNode*>* children = [HelperTools sdp2xml:sdp.sdp withInitiator:YES];
        if(children.count == 0)
        {
            DDLogError(@"Could not serialize local SDP to XML!");
            [self handleEndCallActionWithReason:MLCallFinishReasonError];
            return;
        }
        
        //we don't encrypt anything if encryption is not enabled for this contact or if the remote did not send us their deviceid
        if(self.contact.isEncrypted && self.remoteOmemoDeviceId != nil && [self encryptFingerprintsInChildren:children])
        {
            //we are encrypted now (if the remote can't decrypt this or answers with a cleartext fingerprint, we throw a security error later on)
            self.encryptionState = [self encryptionTypeForDeviceid:self.remoteOmemoDeviceId];
        }
        else
            self.encryptionState = MLCallEncryptionStateClear;
        
        XMPPIQ* sdpIQ = [[XMPPIQ alloc] initWithType:kiqSetType to:self.fullRemoteJid];
        [sdpIQ addChildNode:[[MLXMLNode alloc] initWithElement:@"jingle" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{
            @"action": @"session-initiate",
            @"sid": self.jmiid,
        } andChildren:children andData:nil]];
        @synchronized(self.candidateQueueLock) {
            self.localSDP = sdpIQ;
        }
        [self.account sendIq:sdpIQ withResponseHandler:^(XMPPIQ* result) {
            DDLogDebug(@"Received SDP response for offer: %@", result);
        } andErrorHandler:^(XMPPIQ* error) {
            DDLogError(@"Got error for SDP offer: %@", error);
        }];
    }];
}

-(void) sendJmiPropose
{
    DDLogDebug(@"Proposing new call via JMI: %@", self);
    NSMutableArray* descriptions = [NSMutableArray new];
    [descriptions addObject:[[MLXMLNode alloc] initWithElement:@"description" andNamespace:@"urn:xmpp:jingle:apps:rtp:1" withAttributes:@{@"media": @"audio"} andChildren:@[] andData:nil]];
    if(self.callType == MLCallTypeVideo)
        [descriptions addObject:[[MLXMLNode alloc] initWithElement:@"description" andNamespace:@"urn:xmpp:jingle:apps:rtp:1" withAttributes:@{@"media": @"video"} andChildren:@[] andData:nil]];
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initToContact:self.contact];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"propose" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:descriptions andData:nil]];
    [jmiNode setStoreHint];
    self.jmiPropose = jmiNode;
    [self.account send:jmiNode];
    
    //abort if no device responds with "ringing" in time
    [self createDiscoveringTimeoutTimer];
}

-(void) sendJmiReject
{
    DDLogDebug(@"Rejecting via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initWithType:kMessageChatType to:self.fullRemoteJid];
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
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initWithType:kMessageChatType to:self.fullRemoteJid];
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
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initWithType:kMessageChatType to:self.fullRemoteJid];
    [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"ringing" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[] andData:nil]];
    [jmiNode setStoreHint];
    [self.account send:jmiNode];
}

-(void) sendJmiProceed
{
    DDLogDebug(@"Accepting via JMI: %@", self);
    //xep 0353 mandates bare jid, but daniel will update it to mandate full jid
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initWithType:kMessageChatType to:self.fullRemoteJid];
    MLXMLNode* proceedElement = [[MLXMLNode alloc] initWithElement:@"proceed" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
        @"id": self.jmiid,
    } andChildren:@[] andData:nil];
    //only offer omemo deviceid for encryption if encryption is enabled for this contact
    if(self.contact.isEncrypted)
    {
        //see https://gist.github.com/iNPUTmice/aa4fc0aeea6ce5fb0e0fe04baca842cd
        [proceedElement addChildNode:[[MLXMLNode alloc] initWithElement:@"device" andNamespace:@"http://gultsch.de/xmpp/drafts/omemo/dlts-srtp-verification" withAttributes:@{
            @"id": [self.account.omemo getDeviceId],
        } andChildren:@[] andData:nil]];
    }
    [jmiNode addChildNode:proceedElement];
    [jmiNode setStoreHint];
    self.jmiProceed = jmiNode;
    [self.account send:jmiNode];
}

-(void) sendJmiFinishWithReason:(NSString*) reason
{
    DDLogVerbose(@"Finishing via jingle: %@", self);
    XMPPIQ* jingleIQ = [[XMPPIQ alloc] initWithType:kiqSetType to:self.fullRemoteJid];
    [jingleIQ addChildNode:[[MLXMLNode alloc] initWithElement:@"jingle" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{
        @"action": @"session-terminate",
        @"sid": self.jmiid,
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"reason" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{}  andChildren:@[
            [[MLXMLNode alloc] initWithElement:reason]
        ] andData:nil]
    ] andData:nil]];
    [self.account send:jingleIQ];
    
    DDLogDebug(@"Finishing via JMI: %@", self);
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initWithType:kMessageChatType to:self.fullRemoteJid];
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
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initToContact:self.contact];
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
    XMPPMessage* jmiNode = [[XMPPMessage alloc] initToContact:self.contact];
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
        case MLCallStateDiscovering: state = @"discovering"; break;
        case MLCallStateRinging: state = @"ringing"; break;
        case MLCallStateConnecting: state = @"connecting"; break;
        case MLCallStateReconnecting: state = @"reconnecting"; break;
        case MLCallStateConnected: state = @"connected"; break;
        case MLCallStateFinished: state = @"finished"; break;
        case MLCallStateUnknown: state = @"unknown"; break;
        default: state = @"undefined"; break;
    }
    return [NSString stringWithFormat:@"%@Call:%@",
        self.direction == MLCallDirectionIncoming ? @"Incoming" : @"Outgoing",
        @{
            @"uuid": self.uuid,
            @"jmiid": self.jmiid,
            @"state": state,
            @"finishReason": @(self.finishReason),
            @"durationTime": @(self.durationTime),
            @"contact": nilWrapper(self.contact),
            @"fullRemoteJid": nilWrapper(self.fullRemoteJid),
            @"jmiPropose": nilWrapper(self.jmiPropose),
            @"jmiProceed": nilWrapper(self.jmiProceed),
            @"webRTCClient": nilWrapper(self.webRTCClient),
            @"providerAnswerAction": nilWrapper(self.providerAnswerAction),
            @"wasConnectedOnce": bool2str(self.wasConnectedOnce),
            @"isConnected": bool2str(self.isConnected),
            @"isReconnecting": bool2str(self.isReconnecting),
            @"hasLocalSDP": bool2str(self.localSDP != nil),
            @"hasRemoteSDP": bool2str(self.remoteSDP != nil),
            @"remoteOmemoDeviceId": nilWrapper(self.remoteOmemoDeviceId),
            @"encryptionState": @(self.encryptionState),
        }
    ];
}

-(NSString*) short
{
    return [NSString stringWithFormat:@"%@Call:%@{%@}", self.direction == MLCallDirectionIncoming ? @"Incoming" : @"Outgoing", self.uuid, self.jmiid];
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
    @synchronized(self) {
        if(webRTCClient != self.webRTCClient)
        {
            DDLogDebug(@"%@: Ignoring discovered local ICE candidate: %@ (call migrated)", [self short], candidate);
            return;
        }
        DDLogDebug(@"%@: Discovered local ICE candidate destined for '%@': %@", [self short], self.fullRemoteJid, candidate);
        
        //set ufrag to nil, it will be automatically filled via candidate.sdp
        //extract the pwd from our outgoing offer using the sdpMid to identify the correct <content/> element
        NSString* localPwd = [self.localSDP findFirst:@"{urn:xmpp:jingle:1}jingle/content<name=%@>/{urn:xmpp:jingle:transports:ice-udp:1}transport@pwd", candidate.sdpMid];
        MLXMLNode* contentNode = [HelperTools candidate2xml:candidate.sdp withMid:candidate.sdpMid pwd:localPwd ufrag:nil andInitiator:self.direction==MLCallDirectionOutgoing];
        if(contentNode == nil)
        {
            DDLogError(@"Failed to convert raw sdp candidate to jingle, ignoring this candidate: %@", candidate);
            return;
        }
        //see https://webrtc.googlesource.com/src/+/refs/heads/main/sdk/objc/api/peerconnection/RTCIceCandidate.h
        XMPPIQ* candidateIq = [[XMPPIQ alloc] initWithType:kiqSetType to:self.fullRemoteJid];
        [candidateIq addChildNode:[[MLXMLNode alloc] initWithElement:@"jingle" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{
            @"action": @"transport-info",
            @"sid": self.jmiid,
        } andChildren:@[contentNode] andData:nil]];
        @synchronized(self.candidateQueueLock) {
            //queue candidate if sdp offer or answer have not been processed yet
            if(self.remoteSDP == nil || self.localSDP == nil)
            {
                DDLogDebug(@"Adding outgoing ICE candidate iq to candidate queue: %@", candidateIq);
                [self.outgoingCandidateQueue addObject:candidateIq];
                return;
            }
        }
        [self.account sendIq:candidateIq withResponseHandler:^(XMPPIQ* result) {
            DDLogDebug(@"%@: Received outgoing ICE candidate result: %@", [self short], result);
        } andErrorHandler:^(XMPPIQ* error) {
            DDLogError(@"%@: Got error for outgoing ICE candidate: %@", [self short], error);
        }];
    }
}
    
-(void) webRTCClient:(WebRTCClient*) webRTCClient didChangeConnectionState:(RTCIceConnectionState) state
{
    @synchronized(self) {
        if(webRTCClient != self.webRTCClient)
        {
            DDLogInfo(@"Ignoring new RTCIceConnectionState %ld for webRTCClient: %@ (call migrated)", (long)state, webRTCClient);
            return;
        }
        if(self.isFinished)
        {
            DDLogInfo(@"Ignoring new RTCIceConnectionState %ld for webRTCClient: %@ (call already finished)", (long)state, webRTCClient);
            return;
        }
        //state enums can be found over here: https://chromium.googlesource.com/external/webrtc/+/9eeb6240c93efe2219d4d6f4cf706030e00f64d7/webrtc/sdk/objc/Framework/Headers/WebRTC/RTCPeerConnection.h
        DDLogDebug(@"New RTCIceConnectionState %ld for webRTCClient: %@", (long)state, webRTCClient);
        //we *always* want to cancel the running iceRestart timer once the state changes
        if(self.cancelWaitUntilIceRestart != nil)
        {
            self.cancelWaitUntilIceRestart();
            self.cancelWaitUntilIceRestart = nil;
        }
        switch(state)
        {
            case RTCIceConnectionStateConnected:
                DDLogInfo(@"New WebRTC ICE state: connected, falling through to completed...");
            case RTCIceConnectionStateCompleted:
                DDLogInfo(@"New WebRTC ICE state: completed: %@", self);
                self.isConnected = YES;
                self.isReconnecting = NO;
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
                /*if(self.wasConnectedOnce)
                {
                    //wait some time before restarting ice (maybe the connection can be reestablished without a new candidate exchange)
                    //see: https://groups.google.com/g/discuss-webrtc/c/I4K8NwN4Huw
                    //see: https://webrtccourse.com/course/webrtc-codelab/module/fiddle-of-the-month/lesson/ice-restarts/
                    //see: https://medium.com/@fippo/ice-restarts-5d759caceda6
                    self.cancelWaitUntilIceRestart = createTimer(2.0, (^{
                        [self restartIce];
                    }));
                }
                else
                    [self end];*/
                //wait some time for other jmi and jingle stanzas to arrive (these may contain call end reasons we want to process)
                [self delayedEnd:2.0 withDisconnectedState:YES];
                break;
            case RTCIceConnectionStateFailed:
                DDLogInfo(@"New WebRTC ICE state: failed: %@", self);
                /*if(self.wasConnectedOnce)
                    [self restartIce];
                else
                    [self end];*/
                self.isConnected = NO;      //will result in MLCallFinishReasonConnectivityError if wasConnectedOnce == YES
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
    //ignore sdp for disabled accounts
    if(account != [[MLXMPPManager sharedInstance] getConnectedAccountForID:account.accountNo])
        return;
    //don't use self.account because that asserts on nil
    if([[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId] == nil)
        return;
    
    XMPPIQ* iqNode = userInfo[@"iqNode"];
    NSString* jmiid = [iqNode findFirst:@"{urn:xmpp:jingle:1}jingle@sid"];
    if(![account.accountNo isEqualToNumber:self.account.accountNo] || ![self.jmiid isEqual:jmiid])
    {
        DDLogInfo(@"Incoming ICE candidate not matching %@, ignoring...", [self short]);
        return;
    }
    
    @synchronized(self.candidateQueueLock) {
        //queue candidate if sdp offer or answer have not been processed yet
        if(self.remoteSDP == nil || self.localSDP == nil)
        {
            DDLogDebug(@"Adding incoming ICE candidate iq to candidate queue: %@", iqNode);
            [self.incomingCandidateQueue addObject:iqNode];
            return;
        }
    }
    [self processRemoteICECandidate:iqNode];
}

-(void) processRemoteICECandidate:(XMPPIQ*) iqNode
{
    RTCIceCandidate* incomingCandidate = nil;
    NSString* rawSdp = [HelperTools xml2candidate:[iqNode findFirst:@"{urn:xmpp:jingle:1}jingle"] withInitiator:self.direction==MLCallDirectionIncoming];
    if(rawSdp == nil)
    {
        DDLogError(@"Failed to convert jingle candidate to raw sdp!");
        XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
        [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"bad-request" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
        ] andData:nil]];
        [self.account send:errorIq];
        
        //don't be too harsh and not end the call here
        //[self handleEndCallActionWithReason:MLCallFinishReasonError];
        return;
    }
    
    //calculate correct mLineIndex by searching for the corresponding mid (e.g. content@name) in the list of contents advertised in our offer
    NSString* sdpMid = [iqNode findFirst:@"{urn:xmpp:jingle:1}jingle/content@name"];
    NSArray<MLXMLNode*>* offeredMedia = [self.remoteSDP find:@"{urn:xmpp:jingle:1}jingle/content"];
    NSUInteger mLineIndex = 0;
    for(; mLineIndex < [offeredMedia count]; mLineIndex++)
        if([sdpMid isEqualToString:offeredMedia[mLineIndex].attributes[@"name"]])
        {
            incomingCandidate = [[RTCIceCandidate alloc] initWithSdp:rawSdp sdpMLineIndex:(int)mLineIndex sdpMid:sdpMid];
            break;
        }
    if(mLineIndex == [offeredMedia count])
        DDLogError(@"Could not find content element with mid='%@' in remoteSDP!", sdpMid);
    
    if(incomingCandidate == nil)
    {
        DDLogError(@"incomingCandidate is unexpectedly nil, ignoring!");
        [self.account send:[[XMPPIQ alloc] initAsResponseTo:iqNode]];
        return;
        
//         XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
//         [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
//             [[MLXMLNode alloc] initWithElement:@"bad-request" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
//         ] andData:nil]];
//         [self.account send:errorIq];
//         
//         //don't be too harsh and not end the call here
//         //[self handleEndCallActionWithReason:MLCallFinishReasonError];
//         return;
    }
    DDLogInfo(@"%@: Got remote ICE candidate for call: %@", self, incomingCandidate);
    NSString* remoteUfrag = [self.remoteSDP findFirst:@"{urn:xmpp:jingle:1}jingle/content<name=%@>/{urn:xmpp:jingle:transports:ice-udp:1}transport@ufrag", incomingCandidate.sdpMid];
    NSString* remotePwd = [self.remoteSDP findFirst:@"{urn:xmpp:jingle:1}jingle/content<name=%@>/{urn:xmpp:jingle:transports:ice-udp:1}transport@pwd", incomingCandidate.sdpMid];
    NSString* candidateUfrag = [iqNode findFirst:@"{urn:xmpp:jingle:1}jingle/content<name=%@>/{urn:xmpp:jingle:transports:ice-udp:1}transport@ufrag", incomingCandidate.sdpMid];
    NSString* candidatePwd = [iqNode findFirst:@"{urn:xmpp:jingle:1}jingle/content<name=%@>/{urn:xmpp:jingle:transports:ice-udp:1}transport@pwd", incomingCandidate.sdpMid];
    if(remotePwd == nil || remoteUfrag == nil || ![remoteUfrag isEqualToString:candidateUfrag] || ![remotePwd isEqualToString:candidatePwd])
    {
        DDLogError(@"Jingle incoming candidate has wrong pwd or ufrag: incomingCandidate.ufrag='%@', incomingCandidate.pwd='%@', remoteSDP.ufrag='%@', remoteSDP.pwd='%@'", candidateUfrag, candidatePwd, remoteUfrag, remotePwd);
        XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
        [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"auth"} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"not-authorized" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
        ] andData:nil]];
        [self.account send:errorIq];
        
        //don't be too harsh and not end the call here
        //[self handleEndCallActionWithReason:MLCallFinishReasonError];
        return;
    }
    
    weakify(self);
    [self.webRTCClient setRemoteCandidate:incomingCandidate completion:^(id error) {
        strongify(self);
        DDLogDebug(@"Got setRemoteCandidate callback...");
        if(error)
        {
            DDLogError(@"Got error while passing new remote ICE candidate to webRTCClient: %@", error);
            XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
            [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"not-acceptable" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
            ] andData:nil]];
            [self.account send:errorIq];
            
            //don't be too harsh and not end the call here
            //[self handleEndCallActionWithReason:MLCallFinishReasonError];
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
    //ignore sdp for disabled accounts
    if(account != [[MLXMPPManager sharedInstance] getConnectedAccountForID:account.accountNo])
        return;
    //don't use self.account because that asserts on nil
    if([[MLXMPPManager sharedInstance] getConnectedAccountForID:self.contact.accountId] == nil)
        return;
    XMPPIQ* iqNode = userInfo[@"iqNode"];
    
    NSString* jmiid = [iqNode findFirst:@"{urn:xmpp:jingle:1}jingle@sid"];
    if(![account.accountNo isEqualToNumber:self.account.accountNo] || ![self.jmiid isEqual:jmiid])
    {
        DDLogInfo(@"Ignoring incoming SDP not matching: %@", self);
        return;
    }
    
    //make sure we don't handle incoming sdp twice
    if(self.remoteSDP != nil && [iqNode findFirst:@"{urn:xmpp:jingle:1}jingle<action~^session-(initiate|accept)$>"])
    {
        DDLogWarn(@"Got new remote sdp but we already got one, ignoring! MITM/DDOS??");
        XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
        [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"cancel"} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"conflict" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
        ] andData:nil]];
        [self.account send:errorIq];
        return;
    }
    
    NSString* rawSDP;
    NSString* type;
    if([iqNode check:@"{urn:xmpp:jingle:1}jingle<action~^session-(initiate|accept)$>"])
    {
        if(
            ([iqNode findFirst:@"{urn:xmpp:jingle:1}jingle<action=session-accept>"] && self.direction != MLCallDirectionOutgoing) ||
            ([iqNode findFirst:@"{urn:xmpp:jingle:1}jingle<action=session-initiate>"] && self.direction != MLCallDirectionIncoming)
        ) {
            DDLogWarn(@"Unexpected incoming jingle data direction, ignoring: %@", iqNode);
            return;
        }
        
        //don't change iqNode directly to not influence code outside of this method
        iqNode = [iqNode copy];
        //handle candidates in initial sdp (our webrtc lib does not like them --> fake transport-info iqs for these)
        //(candidates in initial jingle are allowed by xep!)
        @synchronized(self.candidateQueueLock) {
            for(MLXMLNode* content in [iqNode find:@"{urn:xmpp:jingle:1}jingle/content"])
            {
                MLXMLNode* transport = [content findFirst:@"{urn:xmpp:jingle:transports:ice-udp:1}transport"];
                for(MLXMLNode* candidate in [transport find:@"{urn:xmpp:jingle:transports:ice-udp:1}candidate"])
                {
                    XMPPIQ* fakeCandidateIQ = [[XMPPIQ alloc] initWithType:kiqSetType];
                    fakeCandidateIQ.from = self.fullRemoteJid;
                    fakeCandidateIQ.to = self.account.connectionProperties.identity.fullJid;
                    MLXMLNode* shallowTransport = [transport shallowCopyWithData:YES];
                    [shallowTransport addChildNode:[transport removeChildNode:candidate]];
                    MLXMLNode* shallowContent = [content shallowCopyWithData:YES];
                    [shallowContent addChildNode:shallowTransport];
                    [fakeCandidateIQ addChildNode:[[MLXMLNode alloc] initWithElement:@"jingle" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{
                        @"action": @"transport-info",
                        @"sid": self.jmiid,
                    } andChildren:@[shallowContent] andData:nil]];
                    DDLogDebug(@"Adding fake candidate iq to candidate queue: %@", fakeCandidateIQ);
                    [self.incomingCandidateQueue addObject:fakeCandidateIQ];
                }
            }
        }
        //decrypt fingerprint, if needed (use iqNode copy created above to not influence code outside of this method)
        //only decrypt if encryption is enabled for this contact
        if(self.contact.isEncrypted)
        {
            //if this is a session-initiate and we can decrypt the fingerprint using the given deviceid, this call is encrypted now
            //if we can NOT decrypt anything, but have a remote deviceid (e.g. the iq contains an omemo envelope), this is a security error
            if([iqNode check:@"{urn:xmpp:jingle:1}jingle<action=session-initiate>"])
            {
                //save omemo deviceid if we got a session-initiate for this (incoming) call
                self.remoteOmemoDeviceId = [iqNode findFirst:@"{urn:xmpp:jingle:1}jingle<action=session-initiate>/{urn:xmpp:jingle:1}content/{urn:xmpp:jingle:transports:ice-udp:1}transport/{http://gultsch.de/xmpp/drafts/omemo/dlts-srtp-verification}fingerprint/{eu.siacs.conversations.axolotl}encrypted/header@sid|uint"];
                if(self.remoteOmemoDeviceId != nil)
                {
                    if([self decryptFingerprintsInIqNode:iqNode])
                        self.encryptionState = [self encryptionTypeForDeviceid:self.remoteOmemoDeviceId];
                    else
                    {
                        DDLogError(@"Could not decrypt remote SDP session-initiate fingerprint with OMEMO!");
                        XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
                        [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
                            [[MLXMLNode alloc] initWithElement:@"not-acceptable" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
                            [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas" andData:@"Could not decrypt call with OMEMO!"],
                        ] andData:nil]];
                        [self.account send:errorIq];
                        
                        [self handleEndCallActionWithReason:MLCallFinishReasonSecurityError];
                        return;
                    }
                }
                else
                    self.encryptionState = MLCallEncryptionStateClear;
            }
            
            //if this is a session-accept after sending an encrypted session-initiate and we can NOT decrypt the fingerprint,
            //this call is a security error (if we can decrypt it, everything is fine and the call is secured)
            if([iqNode check:@"{urn:xmpp:jingle:1}jingle<action=session-accept>"])
            {
                //we don't need to check self.remoteOmemoDeviceId, because self.encryptionState will only be different to
                //MLCallEncryptionStateClear if the deviceid is not nil
                if(self.encryptionState != MLCallEncryptionStateClear && ![self decryptFingerprintsInIqNode:iqNode])
                {
                    DDLogError(@"Could not decrypt remote SDP session-accept fingerprint with OMEMO!");
                    XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
                    [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
                        [[MLXMLNode alloc] initWithElement:@"not-acceptable" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
                        [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas" andData:@"Could not decrypt call with OMEMO!"],
                    ] andData:nil]];
                    [self.account send:errorIq];
                    
                    [self handleEndCallActionWithReason:MLCallFinishReasonSecurityError];
                    return;
                }
            }
        }
        else
            self.encryptionState = MLCallEncryptionStateClear;
        
        //check if the jingle offer/response contains only the media that got advertised in jmi and throw a security error otherwise
        if(self.callType == MLCallTypeAudio && [iqNode check:@"{urn:xmpp:jingle:1}jingle/content/{urn:xmpp:jingle:apps:rtp:1}description<media=video>"])
        {
            DDLogError(@"Security: jingle advertises video while jmi only contained audio, aborting call!");
            XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
            [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"not-acceptable" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
                [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas" andData:@"Sent video in jingle, but only advertised audio in jmi!"],
            ] andData:nil]];
            [self.account send:errorIq];
            
            [self handleEndCallActionWithReason:MLCallFinishReasonSecurityError];
            return;
        }
        
        //now handle the jingle offer/response nodes and convert jingle xml to sdp
        if([iqNode findFirst:@"{urn:xmpp:jingle:1}jingle<action=session-accept>"])
        {
            type = @"answer";
            rawSDP = [HelperTools xml2sdp:[iqNode findFirst:@"{urn:xmpp:jingle:1}jingle"] withInitiator:NO];
        }
        else if([iqNode findFirst:@"{urn:xmpp:jingle:1}jingle<action=session-initiate>"])
        {
            type = @"offer";
            rawSDP = [HelperTools xml2sdp:[iqNode findFirst:@"{urn:xmpp:jingle:1}jingle"] withInitiator:YES];
        }
    }
    //handle session-terminate: fake jmi finish message and handle it
    else if([iqNode findFirst:@"{urn:xmpp:jingle:1}jingle<action=session-terminate>"])
    {
        DDLogDebug(@"Got jingle session-terminate, faking incoming jmi:finish for Conversations compatibility...");
        XMPPMessage* jmiNode = [[XMPPMessage alloc] initWithType:kMessageChatType to:self.account.connectionProperties.identity.jid];
        [jmiNode addChildNode:[[MLXMLNode alloc] initWithElement:@"finish" andNamespace:@"urn:xmpp:jingle-message:0" withAttributes:@{
            @"id": self.jmiid,
        } andChildren:[iqNode find:@"{urn:xmpp:jingle:1}jingle<action=session-terminate>/reason"] andData:nil]];
        [jmiNode setStoreHint];
        [self.voipProcessor handleIncomingJMIStanza:jmiNode onAccount:self.account];
        return;
    }
    else
    {
        DDLogWarn(@"Unexpected incoming jingle type, ignoring: %@", iqNode);
        return;
    }
    
    DDLogVerbose(@"rawSDP(%@)=%@", type, rawSDP);
    if(rawSDP == nil)
    {
        DDLogError(@"Failed to convert jingle to raw sdp!");
        XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
        [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"bad-request" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
        ] andData:nil]];
        [self.account send:errorIq];
        
        [self handleEndCallActionWithReason:MLCallFinishReasonError];
        return;
    }
    
    //convert raw sdp string to RTCSessionDescription object
    RTCSessionDescription* resultSDP = [[RTCSessionDescription alloc] initWithType:[RTCSessionDescription typeForString:type] sdp:rawSDP];
    if(resultSDP == nil)
    {
        DDLogError(@"resultSDP is unexpectedly nil!");
        XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
        [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"bad-request" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
        ] andData:nil]];
        [self.account send:errorIq];
        
        [self handleEndCallActionWithReason:MLCallFinishReasonError];
        return;
    }
    DDLogInfo(@"%@: Got remote SDP for call: %@", self, resultSDP);
    @synchronized(self.candidateQueueLock) {
        self.remoteSDP = iqNode;
    }
    
    //this is blocking (e.g. no need for an inner @synchronized)
    weakify(self);
    [self.webRTCClient setRemoteSdp:resultSDP completion:^(id error) {
        strongify(self);
        if(error)
        {
            DDLogError(@"Got error while passing remote SDP to webRTCClient: %@", error);
            XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
            [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"not-acceptable" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
            ] andData:nil]];
            [self.account send:errorIq];
            
            [self handleEndCallActionWithReason:MLCallFinishReasonError];
            return;
        }
        else
        {
            DDLogDebug(@"Successfully passed SDP to webRTCClient...");
            //only send a "session-accept" if the remote is the initiator (e.g. this is an incoming call)
            if(self.direction == MLCallDirectionIncoming)
            {
                [self.webRTCClient answerWithCompletion:^(RTCSessionDescription* localSdp) {
                    DDLogDebug(@"Sending SDP answer back...");
                    NSArray<MLXMLNode*>* children = [HelperTools sdp2xml:localSdp.sdp withInitiator:NO];
                    //we got a session-initiate jingle iq
                    //--> self.encryptionState will NOT be MLCallEncryptionStateClear, if that iq contained an encrypted fingerprint,
                    //--> self.encryptionState WILL be MLCallEncryptionStateClear, if it did not contain such an encrypted fingerprint
                    //(in this case we just don't try to decrypt anything, the call will simply be unencrypted but continue)
                    //we don't need to check self.remoteOmemoDeviceId, because self.encryptionState will only be different to
                    //MLCallEncryptionStateClear if the deviceid is not nil
                    if(self.encryptionState != MLCallEncryptionStateClear && ![self encryptFingerprintsInChildren:children])
                    {
                        DDLogError(@"Could not encrypt local SDP response fingerprint with OMEMO!");
                        XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:iqNode];
                        [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"modify"} andChildren:@[
                            [[MLXMLNode alloc] initWithElement:@"not-acceptable" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
                            [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas" andData:@"Could not encrypt call with OMEMO!"],
                        ] andData:nil]];
                        [self.account send:errorIq];
                        
                        [self handleEndCallActionWithReason:MLCallFinishReasonSecurityError];
                        return;
                    }
                    [self.account send:[[XMPPIQ alloc] initAsResponseTo:iqNode]];
                    
                    XMPPIQ* sdpIQ = [[XMPPIQ alloc] initWithType:kiqSetType to:self.fullRemoteJid];
                    [sdpIQ addChildNode:[[MLXMLNode alloc] initWithElement:@"jingle" andNamespace:@"urn:xmpp:jingle:1" withAttributes:@{
                        @"action": @"session-accept",
                        @"sid": self.jmiid,
                    } andChildren:children andData:nil]];
                    [self.account send:sdpIQ];
                    
                    @synchronized(self.candidateQueueLock) {
                        self.localSDP = sdpIQ;
                        
                        DDLogDebug(@"Now handling queued incoming candidate iqs: %lu", (unsigned long)self.incomingCandidateQueue.count);
                        for(XMPPIQ* candidateIq in self.incomingCandidateQueue)
                            [self processRemoteICECandidate:candidateIq];
                    }
                }];
            }
            else
            {
                [self.account send:[[XMPPIQ alloc] initAsResponseTo:iqNode]];
                @synchronized(self.candidateQueueLock) {
                    DDLogDebug(@"Now handling queued incoming candidate iqs: %lu", (unsigned long)self.incomingCandidateQueue.count);
                    for(XMPPIQ* candidateIq in self.incomingCandidateQueue)
                        [self processRemoteICECandidate:candidateIq];
                }
            }
            @synchronized(self.candidateQueueLock) {
                DDLogDebug(@"Now sending queued outgoing candidate iqs: %lu", (unsigned long)self.outgoingCandidateQueue.count);
                for(XMPPIQ* candidateIq in self.outgoingCandidateQueue)
                    [self.account sendIq:candidateIq withResponseHandler:^(XMPPIQ* result) {
                        DDLogDebug(@"%@: Received outgoing ICE candidate result: %@", [self short], result);
                    } andErrorHandler:^(XMPPIQ* error) {
                        DDLogError(@"%@: Got error for outgoing ICE candidate: %@", [self short], error);
                    }];
            }
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

-(MLCallEncryptionState) encryptionTypeForDeviceid:(NSNumber* _Nonnull) deviceid
{
    NSNumber* trustLevel = [self.account.omemo getTrustLevelForJid:self.contact.contactJid andDeviceId:deviceid];
    if(trustLevel == nil)
        return MLCallEncryptionStateClear;
    switch(trustLevel.intValue)
    {
        case MLOmemoTrusted: return MLCallEncryptionStateTrusted;
        case MLOmemoToFU: return MLCallEncryptionStateToFU;
        default: return MLCallEncryptionStateClear;
    }
}

-(BOOL) encryptFingerprintsInChildren:(NSArray<MLXMLNode*>*) children
{
    //don't try to encrypt if the remote deviceid is not trusted
    if([self encryptionTypeForDeviceid:self.remoteOmemoDeviceId] == MLCallEncryptionStateClear)
        return NO;
    
    //see https://gist.github.com/iNPUTmice/aa4fc0aeea6ce5fb0e0fe04baca842cd
    BOOL retval = NO;
    for(MLXMLNode* child in children)
        for(MLXMLNode* fingerprint in [child find:@"/{urn:xmpp:jingle:1}content/{urn:xmpp:jingle:transports:ice-udp:1}transport/{urn:xmpp:jingle:apps:dtls:0}fingerprint"])
        {
            MLXMLNode* envelope = [self.account.omemo encryptString:fingerprint.data toDeviceids:@{
                self.contact.contactJid: [NSSet setWithArray:@[self.remoteOmemoDeviceId]],
            }];
            if(envelope == nil)
            {
                DDLogWarn(@"Could not encrypt fingerprint with OMEMO!");
                return NO;
            }
            [fingerprint addChildNode:envelope];
            [fingerprint setXMLNS:@"http://gultsch.de/xmpp/drafts/omemo/dlts-srtp-verification"];
            fingerprint.data = nil;
            retval = YES;
        }
    //this is only true if at least one fingerprint could be found and encrypted (this is normally true)
    return retval;
}

-(BOOL) decryptFingerprintsInIqNode:(XMPPIQ*) iqNode
{
    //don't try to decrypt if the remote deviceid is not trusted
    if([self encryptionTypeForDeviceid:self.remoteOmemoDeviceId] == MLCallEncryptionStateClear)
        return NO;
    
    //see https://gist.github.com/iNPUTmice/aa4fc0aeea6ce5fb0e0fe04baca842cd
    BOOL retval = NO;
    for(MLXMLNode* fingerprintNode in [iqNode find:@"{urn:xmpp:jingle:1}jingle/content/{urn:xmpp:jingle:transports:ice-udp:1}transport/{http://gultsch.de/xmpp/drafts/omemo/dlts-srtp-verification}fingerprint"])
    {
        //more than one omemo envelope means we are under attack
        if([[fingerprintNode find:@"{eu.siacs.conversations.axolotl}encrypted"] count] > 1)
        {
            DDLogWarn(@"More than one OMEMO envelope found!");
            return NO;
        }
        NSString* decryptedFingerprint = [self.account.omemo decryptOmemoEnvelope:[fingerprintNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted"] forSenderJid:self.contact.contactJid andReturnErrorString:NO];
        if(decryptedFingerprint == nil)
        {
            DDLogWarn(@"Could not decrypt OMEMO encrypted fingerprint!");
            return NO;
        }
        //remove omemo envelope, correct xmlns and add our decrypted fingerprint back in as text content
        [fingerprintNode removeChildNode:[fingerprintNode findFirst:@"{eu.siacs.conversations.axolotl}encrypted"]];
        [fingerprintNode setXMLNS:@"urn:xmpp:jingle:apps:dtls:0"];
        fingerprintNode.data = decryptedFingerprint;
        retval = YES;
    }
    //this is only true if at least one fingerprint could be found and decrypted
    //(that could be false, if the remote did something weird or a MITM changed something)
    return retval;
}

@end
