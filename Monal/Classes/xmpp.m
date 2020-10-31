//
//  xmpp.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <CommonCrypto/CommonCrypto.h>
#import <CFNetwork/CFSocketStream.h>
#import <Security/SecureTransport.h>

#import "xmpp.h"
#import "jingleCall.h"
#import "MLDNSLookup.h"
#import "MLSignalStore.h"
#import "MLPubSub.h"
#import "MLOMEMO.h"

#import "MLPipe.h"
#import "MLProcessLock.h"
#import "DataLayer.h"
#import "HelperTools.h"
#import "MLXMPPManager.h"

#import "MLImageManager.h"

//XMPP objects
#import "MLBasePaser.h"
#import "MLXMLNode.h"
#import "XMPPStanza.h"
#import "XMPPDataForm.h"
#import "XMPPIQ.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"

//processors
#import "MLMessageProcessor.h"
#import "MLIQProcessor.h"

#import "MLHTTPRequest.h"
#import "AESGcm.h"
#ifndef DISABLE_OMEMO
#import "SignalProtocolObjC.h"
#endif


#define kConnectTimeout 20ull //seconds
#define kPingTimeout 120ull //seconds


NSString *const kMessageId=@"MessageID";
NSString *const kSendTimer=@"SendTimer";

NSString *const kQueueID=@"queueID";
NSString *const kStanza=@"stanza";


NSString *const kFileName=@"fileName";
NSString *const kContentType=@"contentType";
NSString *const kData=@"data";
NSString *const kContact=@"contact";

NSString *const kCompletion=@"completion";


NSString *const kXMPPError =@"error";
NSString *const kXMPPSuccess =@"success";
NSString *const kXMPPPresence = @"presence";

@interface MLPubSub ()
-(id) initWithAccount:(xmpp*) account;
-(NSDictionary*) getInternalData;
-(void) setInternalData:(NSDictionary*) data;
-(void) handleHeadlineMessage:(XMPPMessage*) messageNode;
@end

@interface xmpp()
{
    //network (stream) related stuff
    MLPipe* _iPipe;
    NSOutputStream* _oStream;
    NSMutableArray* _outputQueue;
    // buffer for stanzas we can not (completely) write to the tcp socket
    uint8_t* _outputBuffer;
    size_t _outputBufferByteCount;
    BOOL _streamHasSpace;

    //parser and queue related stuff
    NSXMLParser* _xmlParser;
    MLBasePaser* _baseParserDelegate;
    NSOperationQueue* _parseQueue;
    NSOperationQueue* _receiveQueue;
    NSOperationQueue* _sendQueue;

    //does not reset at disconnect
    BOOL _loggedInOnce;
    BOOL _isCSIActive;
    NSDate* _lastInteractionDate;
    
    //internal handlers and flags
    monal_void_block_t _cancelLoginTimer;
    monal_void_block_t _cancelPingTimer;
    monal_void_block_t _cancelReconnectTimer;
    NSMutableArray* _smacksAckHandler;
    NSMutableDictionary* _iqHandlers;
    BOOL _startTLSComplete;
    BOOL _catchupDone;
    double _exponentialBackoff;
    BOOL _reconnectInProgress;
    NSObject* _stateLockObject;     //only used for @synchronized() blocks
    BOOL _lastIdleState;
    NSMutableDictionary* _mamPageArrays;
    
    //registration related stuff
    BOOL _registration;
    BOOL _registrationSubmission;
    xmppDataCompletion _regFormCompletion;
    xmppCompletion _regFormErrorCompletion;
    xmppCompletion _regFormSubmitCompletion;
}

@property (nonatomic, assign) BOOL smacksRequestInFlight;

@property (nonatomic, assign) BOOL resuming;
@property (atomic, strong) NSString* streamID;

/**
 h to go out in r stanza
 */
@property (nonatomic, strong) NSNumber* lastHandledInboundStanza;

/**
 h from a stanza
 */
@property (nonatomic, strong) NSNumber* lastHandledOutboundStanza;

/**
 internal counter that should match lastHandledOutboundStanza
 */
@property (nonatomic, strong) NSNumber* lastOutboundStanza;

/**
 Array of NSDictionary with stanzas that have not been acked.
 NSDictionary {queueID, stanza}
 */
@property (nonatomic, strong) NSMutableArray* unAckedStanzas;

/**
 ID of the signal device query
 */

/**
    Privacy Settings: Only send idle notifications out when the user allows it
 */
@property (nonatomic, assign) BOOL sendIdleNotifications;


@end



@implementation xmpp

-(id) initWithServer:(nonnull MLXMPPServer *) server andIdentity:(nonnull MLXMPPIdentity *)identity andAccountNo:(NSString*) accountNo
{
    //initialize ivars depending on provided arguments
    self = [super init];
    self.accountNo = accountNo;
    self.connectionProperties = [[MLXMPPConnection alloc] initWithServer:server andIdentity:identity];
    
    //setup all other ivars
    [self setupObjects];
    
    //read persisted state to make sure we never operate stateless
    //WARNING: pubsub node registrations should only be made *after* the first readState call
    [self readState];
    
    // Init omemo
    self.omemo = [[MLOMEMO alloc] initWithAccount:self];
    
    //we want to get automatic avatar updates (XEP-0084)
    [self.pubsub registerForNode:@"urn:xmpp:avatar:metadata" withHandler:[HelperTools createStaticHandlerWithDelegate:[self class] andMethod:@selector(avatarHandlerFor:withNode:jid:type:andData:) andAdditionalArguments:nil]];
    
    //we want to get automatic roster name updates (XEP-0172)
    [self.pubsub registerForNode:@"http://jabber.org/protocol/nick" withHandler:[HelperTools createStaticHandlerWithDelegate:[self class] andMethod:@selector(rosterNameHandlerFor:withNode:jid:type:andData:) andAdditionalArguments:nil]];
    
    return self;
}

-(void) setupObjects
{
    //initialize _capsIdentity, _capsFeatures and _capsHash
    _capsIdentity = [[MLXMLNode alloc] initWithElement:@"identity" withAttributes:@{
        @"category": @"client",
        @"type": @"phone",
        @"name": [NSString stringWithFormat:@"Monal %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]]
    } andChildren:@[] andData:nil];
    _capsFeatures = [HelperTools getOwnFeatureSet];
    NSString* client = [NSString stringWithFormat:@"%@/%@//%@", [_capsIdentity findFirst:@"/@category"], [_capsIdentity findFirst:@"/@type"], [_capsIdentity findFirst:@"/@name"]];
    [self setCapsHash:[HelperTools getEntityCapsHashForIdentities:@[client] andFeatures:_capsFeatures]];
    
    //init pubsub as early as possible to allow other classes or other parts of this file to register pubsub nodes they are interested in
    self.pubsub = [[MLPubSub alloc] initWithAccount:self];
    
    _stateLockObject = [[NSObject alloc] init];
    [self initSM3];
    
    _accountState = kStateLoggedOut;
    _registration = NO;
    _registrationSubmission = NO;
    _startTLSComplete = NO;
    _catchupDone = NO;
    _reconnectInProgress = NO;
    _lastIdleState = NO;
    _outputQueue = [[NSMutableArray alloc] init];
    _iqHandlers = [[NSMutableDictionary alloc] init];
    _mamPageArrays = [[NSMutableDictionary alloc] init];

    _SRVDiscoveryDone = NO;
    _discoveredServersList = [[NSMutableArray alloc] init];
    if(!_usableServersList)
        _usableServersList = [[NSMutableArray alloc] init];
    _exponentialBackoff = 0;
    
    _parseQueue = [[NSOperationQueue alloc] init];
    _parseQueue.name = @"receiveQueue";
    _parseQueue.qualityOfService = NSQualityOfServiceUtility;
    _parseQueue.maxConcurrentOperationCount = 1;
    [_parseQueue addObserver:self forKeyPath:@"operationCount" options:NSKeyValueObservingOptionNew context:nil];
    
    _receiveQueue = [[NSOperationQueue alloc] init];
    _receiveQueue.name = @"receiveQueue";
    _receiveQueue.qualityOfService = NSQualityOfServiceUtility;
    _receiveQueue.maxConcurrentOperationCount = 1;
    [_receiveQueue addObserver:self forKeyPath:@"operationCount" options:NSKeyValueObservingOptionNew context:nil];

    _sendQueue = [[NSOperationQueue alloc] init];
    _sendQueue.name = @"sendQueue";
    _sendQueue.qualityOfService = NSQualityOfServiceUtility;
    _sendQueue.maxConcurrentOperationCount = 1;
    [_sendQueue addObserver:self forKeyPath:@"operationCount" options:NSKeyValueObservingOptionNew context:nil];
    if(_outputBuffer)
        free(_outputBuffer);
    _outputBuffer = nil;
    _outputBufferByteCount = 0;
    
    _isCSIActive = YES;         //default value is yes if no csi state was set yet
    if([HelperTools isAppExtension])
    {
        DDLogVerbose(@"Called from extension: CSI inactive");
        _isCSIActive = NO;        //we are always inactive when called from an extension
    }
    else if([HelperTools isInBackground])
    {
        DDLogVerbose(@"Called in background: CSI inactive");
        _isCSIActive = NO;
    }
    _lastInteractionDate = [NSDate date];     //better default than 1970

    self.statusMessage = [[HelperTools defaultsDB] stringForKey:@"StatusMessage"];
    self.awayState = [[HelperTools defaultsDB] boolForKey:@"Away"];

    self.sendIdleNotifications = [[HelperTools defaultsDB] boolForKey: @"SendLastUserInteraction"];
}

-(void) dealloc
{
    if(_outputBuffer)
        free(_outputBuffer);
    _outputBuffer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_parseQueue removeObserver:self forKeyPath:@"operationCount"];
    [_receiveQueue removeObserver:self forKeyPath:@"operationCount"];
    [_sendQueue removeObserver:self forKeyPath:@"operationCount"];
    [_parseQueue cancelAllOperations];
    [_receiveQueue cancelAllOperations];
    [_sendQueue cancelAllOperations];
}

-(void) setCapsHash:(NSString* _Nonnull) hash
{
    //check if the hash has changed and broadcast a new presence after updating the property
    if(![hash isEqualToString:_capsHash])
    {
        DDLogInfo(@"New caps hash: %@", hash);
        _capsHash = hash;
        //broadcast new version hash (will be ignored if we are not bound)
        if(_accountState >= kStateBound)
            [self sendPresence];
    }
}

-(void) setPubSubNotificationsForNodes:(NSArray* _Nonnull) nodes persistState:(BOOL) persistState
{
    NSString* client = [NSString stringWithFormat:@"%@/%@//%@", [_capsIdentity findFirst:@"/@category"], [_capsIdentity findFirst:@"/@type"], [_capsIdentity findFirst:@"/@name"]];
    NSMutableSet* featuresSet = [[NSMutableSet alloc] initWithSet:[HelperTools getOwnFeatureSet]];
    for(NSString* pubsubNode in nodes)
    {
        DDLogInfo(@"Added additional caps feature for pubsub node: %@", pubsubNode);
        [featuresSet addObject:[NSString stringWithFormat:@"%@+notify", pubsubNode]];
    }
    _capsFeatures = featuresSet;
    [self setCapsHash:[HelperTools getEntityCapsHashForIdentities:@[client] andFeatures:_capsFeatures]];
    
    //persist this new state if the pubsub implementation tells us to
    if(persistState)
        [self persistState];
}

-(void) invalidXMLError
{
    DDLogError(@"Server returned invalid xml!");
    [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, @"Server returned invalid xml!"]];
    [self reconnect];
    return;
}

-(void) dispatchOnReceiveQueue: (void (^)(void)) operation
{
    [self dispatchOnReceiveQueue:operation async:NO];
}

-(void) dispatchAsyncOnReceiveQueue: (void (^)(void)) operation
{
    [self dispatchOnReceiveQueue:operation async:YES];
}

-(void) dispatchOnReceiveQueue: (void (^)(void)) operation async:(BOOL) async
{
    if([NSOperationQueue currentQueue]!=_receiveQueue)
    {
        DDLogVerbose(@"DISPATCHING %@ OPERATION ON RECEIVE QUEUE: %lu", async ? @"ASYNC" : @"*sync*", [_receiveQueue operationCount]);
        [_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:operation]] waitUntilFinished:!async];
    }
    else
        operation();
}

-(void) accountStatusChanged
{
    // Send notification that our account state has changed
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalAccountStatusChanged object:self userInfo:@{
            kAccountID: self.accountNo,
            kAccountState: [[NSNumber alloc] initWithInt:(int)self.accountState],
    }];
}

-(void) observeValueForKeyPath:(NSString*) keyPath ofObject:(id) object change:(NSDictionary *) change context:(void*) context
{
    //check for idle state every time the number of operations in _sendQueue or _receiveQueue changes
    if((object == _sendQueue || object == _receiveQueue || object == _parseQueue) && [@"operationCount" isEqual: keyPath])
    {
        //check idle state if this queue is empty and if so, publish kMonalIdle notification
        //only do the (more heavy but complete) idle check if we reache zero operations in the observed queue
        //we dispatch the idle check and subsequent notification on the receive queue to account for races
        //between the idle check and calls to disconnect issued in response to this idle notification
        //NOTE: yes, doing the check for [_sendQueue operationCount] (inside [self idle]) from the receive queue is not race free
        //with such disconnects, but: we only want to track the send queue on a best effort basis (because network sends are best effort, too)
        //to some extent we want to make sure every stanza was physically sent out to the network before our app gets frozen by ios
        //but we don't need to make this completely race free (network "races" can occur far more often than send queue races).
        //in a race the smacks unacked stanzas array will contain the not yet sent stanzas --> we won't loose stanzas when racing the send queue
        //with [self disconnect] through an idle check
        if(![object operationCount])
            [self dispatchAsyncOnReceiveQueue:^{
                BOOL lastState = _lastIdleState;
                //only send out idle notifications if we changed from non-idle to idle state
                if(self.idle && !lastState)
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalIdle object:self];
            }];
    }
}

-(BOOL) idle
{
    BOOL retval = NO;
    //we are idle when we are not connected (and not trying to)
    //or: the catchup is done, no unacked stanzas are left in the smacks queue and receive and send queues are empty (no pending operations)
    unsigned long unackedCount = 0;
    @synchronized(_stateLockObject) {
        unackedCount = (unsigned long)[self.unAckedStanzas count];
    }
    if(
        (
            //test if this account was permanently logged out but still has stanzas pending (this can happen if we have no connectivity for example)
            //--> we are not idle in this case because we still have pending outgoing stanzas
            _accountState<kStateReconnecting &&
            !_reconnectInProgress &&
            !unackedCount
        ) || (
            //test if we are connected and idle (e.g. we're done with catchup and neither process any incoming stanzas nor trying to send anything)
            _catchupDone &&
            !unackedCount &&
            ![_parseQueue operationCount] &&
            [_receiveQueue operationCount] <= ([NSOperationQueue currentQueue]==_receiveQueue ? 1 : 0) &&
            ![_sendQueue operationCount]
        )
    )
        retval = YES;
    _lastIdleState = retval;
    DDLogVerbose(@"Idle check:\n\t_accountState < kStateReconnecting = %@\n\t_reconnectInProgress = %@\n\t_catchupDone = %@\n\t[self.unAckedStanzas count] = %lu\n\t[_parseQueue operationCount] = %lu\n\t[_receiveQueue operationCount] = %lu\n\t[_sendQueue operationCount] = %lu\n\t--> %@",
        _accountState < kStateReconnecting ? @"YES" : @"NO",
        _reconnectInProgress ? @"YES" : @"NO",
        _catchupDone ? @"YES" : @"NO",
        unackedCount,
        (unsigned long)[_parseQueue operationCount],
        (unsigned long)[_receiveQueue operationCount],
        (unsigned long)[_sendQueue operationCount],
        retval ? @"idle" : @"NOT IDLE"
    );
    return retval;
}

-(void) cleanupSendQueue
{
    DDLogVerbose(@"Cleaning up sendQueue");
    [_sendQueue cancelAllOperations];
    [_sendQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
        DDLogVerbose(@"Cleaning up sendQueue [internal]");
        [_sendQueue cancelAllOperations];
        self->_outputQueue = [[NSMutableArray alloc] init];
        if(self->_outputBuffer)
            free(self->_outputBuffer);
        self->_outputBuffer = nil;
        self->_outputBufferByteCount = 0;
        self->_streamHasSpace = NO;
        DDLogVerbose(@"Cleanup of sendQueue finished [internal]");
    }]] waitUntilFinished:YES];
    DDLogVerbose(@"Cleanup of sendQueue finished");
}

-(void) initTLS
{
    DDLogInfo(@"configuring/starting tls handshake");
	NSMutableDictionary *settings = [[NSMutableDictionary alloc] init];
	[settings setObject:self.connectionProperties.identity.domain forKey:(NSString*)kCFStreamSSLPeerName];
	if(self.connectionProperties.server.selfSignedCert)
	{
		DDLogInfo(@"configured self signed SSL");
		[settings setObject:@NO forKey:(NSString*)kCFStreamSSLValidatesCertificateChain];
	}

	//this will create an sslContext and, if the underlying TCP socket is already connected, immediately start the ssl handshake
	DDLogInfo(@"configuring SSL handshake");
	if(CFWriteStreamSetProperty((__bridge CFWriteStreamRef)self->_oStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings))
		DDLogInfo(@"Set TLS properties on streams. Security level %@", [self->_oStream propertyForKey:NSStreamSocketSecurityLevelKey]);
	else
	{
		DDLogError(@"not sure.. Could not confirm Set TLS properties on streams.");
		DDLogInfo(@"Set TLS properties on streams.security level %@", [self->_oStream propertyForKey:NSStreamSocketSecurityLevelKey]);
	}

	//see this for extracting the sslcontext of the cfstream: https://stackoverflow.com/a/26726525/3528174
	//see this for creating the proper protocols array: https://github.com/LLNL/FRS/blob/master/Pods/AWSIoT/AWSIoT/Internal/AWSIoTMQTTClient.m
	//WARNING: this will only have an effect if the TLS handshake was not already started (e.g. the TCP socket is not connected) abd ignored otherwise
	SSLContextRef sslContext = (__bridge SSLContextRef) [_oStream propertyForKey: (__bridge NSString *) kCFStreamPropertySSLContext ];
	CFStringRef strs[1];
	strs[0] = CFSTR("xmpp-client");
	CFArrayRef protocols = CFArrayCreate(NULL, (void *)strs, 1, &kCFTypeArrayCallBacks);
	SSLSetALPNProtocols(sslContext, protocols);
	CFRelease(protocols);
}

-(void) createStreams
{
    DDLogInfo(@"stream creating to server: %@ port: %@ directTLS: %@", self.connectionProperties.server.connectServer, self.connectionProperties.server.connectPort, self.connectionProperties.server.isDirectTLS ? @"YES" : @"NO");

    NSInputStream* localIStream;
    NSOutputStream* localOStream;

    [NSStream getStreamsToHostWithName:self.connectionProperties.server.connectServer port:self.connectionProperties.server.connectPort.integerValue inputStream:&localIStream outputStream:&localOStream];

    if(localOStream)
        _oStream = localOStream;
    
    if((localIStream==nil) || (localOStream==nil))
    {
        DDLogError(@"Connection failed");
        NSString *message=NSLocalizedString(@"Unable to connect to server",@ "");
        [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, message]];
        return;
    }
    else
        DDLogInfo(@"streams created ok");
    
    if(localIStream)
        _iPipe = [[MLPipe alloc] initWithInputStream:localIStream andOuterDelegate:self];
    [_oStream setDelegate:self];
    [_oStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    
    if(self.connectionProperties.server.isDirectTLS==YES)
    {
        DDLogInfo(@"starting directSSL");
        [self initTLS];
    }
    [self startXMPPStream:NO];     //send xmpp stream start (this is the first one for this connection --> we don't need to clear the receive queue)
    
    //open sockets and start connecting (including TLS handshake if isDirectTLS==YES)
    DDLogInfo(@"opening TCP streams");
    [localIStream open];
    [_oStream open];
    DDLogInfo(@"TCP streams opened");
}

-(BOOL) connectionTask
{
    // allow override for server and port if one is specified for the account
    if(![self.connectionProperties.server.host isEqual:@""])
    {
        DDLogInfo(@"Ignoring SRV records for this connection, server manually configured: %@:%@", self.connectionProperties.server.connectServer, self.connectionProperties.server.connectPort);
        [self createStreams];
        return NO;
    }

    // do DNS discovery if it hasn't already been set
    if(!_SRVDiscoveryDone)
    {
        DDLogInfo(@"Querying for SRV records");
        _discoveredServersList=[[[MLDNSLookup alloc] init] dnsDiscoverOnDomain:self.connectionProperties.identity.domain];
        _SRVDiscoveryDone = YES;
        // no SRV records found, update server to directly connect to specified domain
        if([_discoveredServersList count]==0)
        {
            [self.connectionProperties.server updateConnectServer: self.connectionProperties.identity.domain];
            [self.connectionProperties.server updateConnectPort: @5222];
            [self.connectionProperties.server updateConnectTLS: NO];
            DDLogInfo(@"NO SRV records found, using standard xmpp config: %@:%@ (using starttls)", self.connectionProperties.server.connectServer, self.connectionProperties.server.connectPort);
        }
    }

    // Show warning when xmpp-client srv entry prohibits connections
    for(NSDictionary *row in _discoveredServersList)
    {
        // Check if entry "." == srv target
        if(![[row objectForKey:@"isEnabled"] boolValue])
        {
            NSString *message = NSLocalizedString(@"SRV entry prohibits XMPP connection",@ "");
            DDLogInfo(@"%@ for domain %@", message, self.connectionProperties.identity.domain);
            [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, message]];
            return YES;
        }
    }
    
    // if all servers have been tried start over with the first one again
    if([_discoveredServersList count]>0 && [_usableServersList count]==0)
    {
        DDLogWarn(@"All %lu SRV dns records tried, starting over again", (unsigned long)[_discoveredServersList count]);
        _usableServersList = [_discoveredServersList mutableCopy];
        for(NSDictionary *row in _usableServersList)
        {
            DDLogInfo(@"SRV entry: server=%@, port=%@, isSecure=%s (prio: %@)",
                [row objectForKey:@"server"],
                [row objectForKey:@"port"],
                [[row objectForKey:@"isSecure"] boolValue] ? "YES" : "NO",
                [row objectForKey:@"priority"]
            );
        }
    }

    if([_usableServersList count]>0)
    {
        DDLogInfo(@"Using connection parameters discovered via SRV dns record: server=%@, port=%@, isSecure=%s, priority=%@",
            [[_usableServersList objectAtIndex:0] objectForKey:@"server"],
            [[_usableServersList objectAtIndex:0] objectForKey:@"port"],
            [[[_usableServersList objectAtIndex:0] objectForKey:@"isSecure"] boolValue] ? "YES" : "NO",
            [[_usableServersList objectAtIndex:0] objectForKey:@"priority"]
        );
        [self.connectionProperties.server updateConnectServer: [[_usableServersList objectAtIndex:0] objectForKey:@"server"]];
        [self.connectionProperties.server updateConnectPort: [[_usableServersList objectAtIndex:0] objectForKey:@"port"]];
        [self.connectionProperties.server updateConnectTLS: [[[_usableServersList objectAtIndex:0] objectForKey:@"isSecure"] boolValue]];
        // remove this server so that the next connection attempt will try the next server in the list
        [_usableServersList removeObjectAtIndex:0];
        DDLogInfo(@"%lu SRV entries left:", (unsigned long)[_usableServersList count]);
        for(NSDictionary *row in _usableServersList)
        {
            DDLogInfo(@"SRV entry: server=%@, port=%@, isSecure=%s (prio: %@)",
                [row objectForKey:@"server"],
                [row objectForKey:@"port"],
                [[row objectForKey:@"isSecure"] boolValue] ? "YES" : "NO",
                [row objectForKey:@"priority"]
            );
        }
    }
    
    [self createStreams];
    return NO;
}

-(void) unfreezed
{
    if(self.accountState < kStateReconnecting)
    {
        //(re)read persisted state (could be changed by appex)
        [self readState];
    }
}

-(void) connect
{
    if(![[MLXMPPManager sharedInstance] hasConnectivity])
    {
        DDLogInfo(@"no connectivity, ignoring connect call.");
        return;
    }
    
    [self dispatchAsyncOnReceiveQueue: ^{
        [_parseQueue cancelAllOperations];          //throw away all parsed but not processed stanzas from old connections
        [_receiveQueue cancelAllOperations];        //stop everything coming after this (we will start a clean connect here!)
        
        //sanity check
        if(self.accountState >= kStateReconnecting)
        {
            DDLogError(@"asymmetrical call to login without a teardown logout, calling reconnect...");
            [self reconnect];
            return;
        }
        
        //make sure we are still enabled ("-1" is used for the account registration process and never saved to db)
        if(![@"-1" isEqualToString:self.accountNo] && ![[DataLayer sharedInstance] isAccountEnabled:self.accountNo])
        {
            DDLogError(@"Account '%@' not enabled anymore, ignoring login", self.accountNo);
            return;
        }
        
        //mark this account as currently connecting
        _accountState = kStateReconnecting;
        
        //only proceed with connection if not concurrent with other processes
        DDLogVerbose(@"Checking remote process lock...");
        if(![HelperTools isAppExtension] && [MLProcessLock checkRemoteRunning:@"NotificationServiceExtension"])
        {
            DDLogInfo(@"NotificationServiceExtension is running, waiting for its termination before connecting");
            [MLProcessLock waitForRemoteTermination:@"NotificationServiceExtension"];
        }
        if([HelperTools isAppExtension] && [MLProcessLock checkRemoteRunning:@"MainApp"])
        {
            DDLogInfo(@"MainApp is running, not connecting (this should transition us into idle state again which will terminate this extension)");
            _accountState = kStateDisconnected;
            return;
        }
        
        DDLogInfo(@"XMPP connnect start");
        _startTLSComplete = NO;
        _catchupDone = NO;
        
        [self cleanupSendQueue];
        
        //(re)read persisted state and start connection
        [self readState];
        if([self connectionTask])
        {
            DDLogError(@"Server disallows xmpp connections for account '%@', ignoring login", self.accountNo);
            _accountState = kStateDisconnected;
            return;
        }
        
        //return here if we are just registering a new account
        if(_registration || _registrationSubmission)
            return;
        
        double connectTimeout = 8.0;
        _cancelLoginTimer = [HelperTools startTimer:connectTimeout withHandler:^{
            [self dispatchAsyncOnReceiveQueue: ^{
                _cancelLoginTimer = nil;
                DDLogInfo(@"login took too long, cancelling and trying to reconnect (potentially using another SRV record)");
                [self reconnect];
            }];
        }];
    }];
}

-(void) disconnect
{
    [self disconnect:NO];
}

-(void) disconnect:(BOOL) explicitLogout
{
    //this has to be synchronous because we want to wait for the disconnect to complete before continuingand unlocking the process in the NSE
    [self dispatchOnReceiveQueue: ^{
        if(_accountState<kStateReconnecting)
        {
            DDLogVerbose(@"not doing logout because already logged out");
            return;
        }
        DDLogInfo(@"disconnecting");
        [_parseQueue cancelAllOperations];          //throw away all parsed but not processed stanzas (we should be logged out then!)
        [_receiveQueue cancelAllOperations];        //stop everything coming after this (we should be logged out then!)
        
        DDLogInfo(@"stopping running timers");
        if(_cancelLoginTimer)
            _cancelLoginTimer();        //cancel running login timer
        _cancelLoginTimer = nil;
        if(_cancelPingTimer)
            _cancelPingTimer();         //cancel running ping timer
        _cancelPingTimer = nil;
        if(!_reconnectInProgress && _cancelReconnectTimer)
            _cancelReconnectTimer();
        _cancelReconnectTimer = nil;
        
        [_iqHandlers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            NSString* id = (NSString*)key;
            NSDictionary* data = (NSDictionary*)obj;
            if(data[@"errorHandler"])
            {
                DDLogWarn(@"invalidating iq handler for iq id '%@'", id);
                if(data[@"errorHandler"])
                    ((monal_iq_handler_t)data[@"errorHandler"])(nil);
            }
        }];
        
        if(explicitLogout && _accountState>=kStateHasStream)
        {
            DDLogInfo(@"doing explicit logout (xmpp stream close)");
            _exponentialBackoff = 0;
            if(self.accountState>=kStateBound)
                [_sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
                    //disable push for this node
                    if(self.pushNode && [self.pushNode length]>0 && self.connectionProperties.supportsPush)
                    {
                        XMPPIQ* disable=[[XMPPIQ alloc] initWithType:kiqSetType];
                        [disable setPushDisableWithNode:self.pushNode];
                        [self writeToStream:disable.XMLString];		// dont even bother queueing
                    }

                    [self sendLastAck];
                }]] waitUntilFinished:YES];         //block until finished because we are closing the xmpp stream directly afterwards
            [_sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
                //close stream
                MLXMLNode* stream = [[MLXMLNode alloc] init];
                stream.element = @"/stream:stream"; //hack to close stream
                [self writeToStream:[stream XMLString]]; // dont even bother queueing
            }]] waitUntilFinished:YES];         //block until finished because we are closing the socket directly afterwards

            @synchronized(_stateLockObject) {
                //preserve unAckedStanzas even on explicitLogout and resend them on next connect
                //if we don't do this, messages could get lost when logging out directly after sending them
                //and: sending messages twice is less intrusive than silently loosing them
                NSMutableArray* stanzas = self.unAckedStanzas;

                //reset smacks state to sane values (this can be done even if smacks is not supported)
                [self initSM3];
                self.unAckedStanzas = stanzas;
                _iqHandlers = [[NSMutableDictionary alloc] init];

                //persist these changes
                [self persistState];
            }
            
            [[DataLayer sharedInstance] resetContactsForAccount:self.accountNo];
        }
        else
        {
            //send one last ack before closing the stream (xep version 1.5.2)
            if(self.accountState>=kStateBound)
                [self sendLastAck];
            [self persistState];
        }
        
        [self closeSocket];
        [self accountStatusChanged];
    }];
}

-(void) closeSocket
{
    [self dispatchOnReceiveQueue: ^{
        DDLogInfo(@"removing streams from runLoop and aborting parser");
        [_receiveQueue cancelAllOperations];        //stop everything coming after this (we should have closed sockets then!)

        //prevent any new read or write
        if(_xmlParser!=nil)
        {
            [_xmlParser setDelegate:nil];
            [_xmlParser abortParsing];
        }
        [self->_iPipe close];
        self->_iPipe = nil;
        [self->_oStream setDelegate:nil];
        [self->_oStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        
        //clean up send queue now that the delegate was removed (_streamHasSpace can not switch to YES now)
        [self cleanupSendQueue];

        DDLogInfo(@"closing output stream");
        @try
        {
            [self->_oStream close];
        }
        @catch(id theException)
        {
            DDLogError(@"Exception in ostream close");
        }
        self->_oStream=nil;
        
        DDLogInfo(@"resetting internal stream state to disconnected");
        _startTLSComplete = NO;
        _catchupDone = NO;
        _accountState = kStateDisconnected;
        
        [_parseQueue cancelAllOperations];      //throw away all parsed but not processed stanzas (we should have closed sockets then!)
    }];
}

-(void) reconnect
{
    if(_reconnectInProgress)
    {
        DDLogInfo(@"Ignoring reconnect while one already in progress");
        return;
    }
    if(!_exponentialBackoff)
        _exponentialBackoff = 1.0;
    [self reconnect:_exponentialBackoff];
    _exponentialBackoff = MIN(_exponentialBackoff * 2, 10.0);
}

-(void) reconnect:(double) wait
{
    //we never want to
    if(_registration || _registrationSubmission)
        return;

    if(_reconnectInProgress)
    {
        DDLogInfo(@"Ignoring reconnect while one already in progress");
        return;
    }
    
    [self dispatchAsyncOnReceiveQueue: ^{
        if(_reconnectInProgress)
        {
            DDLogInfo(@"Ignoring reconnect while one already in progress");
            return;
        }
        
        _reconnectInProgress = YES;
        [self disconnect:NO];

        DDLogInfo(@"Trying to connect again in %G seconds...", wait);
        _cancelReconnectTimer = [HelperTools startTimer:wait withHandler:^{
            _cancelReconnectTimer = nil;
            [self dispatchAsyncOnReceiveQueue: ^{
                //there may be another connect/login operation in progress triggered from reachability or another timer
                if(self.accountState<kStateReconnecting)
                    [self connect];
                _reconnectInProgress = NO;
            }];
        }];
        DDLogInfo(@"reconnect exits");
    }];
}

#pragma mark XMPP

-(void) startXMPPStream:(BOOL) clearReceiveQueue
{
    if(_xmlParser!=nil)
    {
        DDLogInfo(@"resetting old xml parser");
        [_xmlParser setDelegate:nil];
        [_xmlParser abortParsing];
        [_parseQueue cancelAllOperations];      //throw away all parsed but not processed stanzas (we aborted the parser right now)
    }
    if(!_baseParserDelegate)
    {
        DDLogInfo(@"creating parser delegate");
        _baseParserDelegate = [[MLBasePaser alloc] initWithCompletion:^(MLXMLNode* _Nullable parsedStanza) {
#ifndef QueryStatistics
            //prime query cache by doing the most used queries in this thread ahead of the receiveQueue processing
            //only preprocess MLXMLNode queries to prime the cache if enough xml nodes are already queued
            //(we don't want to slow down processing by this)
            if([_parseQueue operationCount] > 1)
            {
                //this list contains the upper part of the 0.75 percentile of the statistically most used queries
                [parsedStanza find:@"/@id"];
                [parsedStanza find:@"/{urn:xmpp:sm:3}r"];
                [parsedStanza find:@"/{urn:xmpp:sm:3}a"];
                [parsedStanza find:@"/@<type=get>"];
                [parsedStanza find:@"/@<type=set>"];
                [parsedStanza find:@"/@<type=result>"];
                [parsedStanza find:@"/@<type=error>"];
                [parsedStanza find:@"{urn:xmpp:sid:0}origin-id"];
                [parsedStanza find:@"/{jabber:client}presence"];
                [parsedStanza find:@"/{jabber:client}message"];
                [parsedStanza find:@"/@h|int"];
                [parsedStanza find:@"{urn:xmpp:delay}delay"];
                [parsedStanza find:@"{http://jabber.org/protocol/muc#user}x/invite"];
                [parsedStanza find:@"/<type=headline>/{http://jabber.org/protocol/pubsub#event}event"];
                [parsedStanza find:@"{urn:xmpp:receipts}received@id"];
                [parsedStanza find:@"{http://jabber.org/protocol/chatstates}*"];
                [parsedStanza find:@"{eu.siacs.conversations.axolotl}encrypted/payload"];
                [parsedStanza find:@"{urn:xmpp:sid:0}stanza-id@by"];
                [parsedStanza find:@"{urn:xmpp:mam:2}result"];
                [parsedStanza find:@"{urn:xmpp:chat-markers:0}displayed@id"];
                [parsedStanza find:@"body"];
                [parsedStanza find:@"{urn:xmpp:mam:2}result@id"];
                [parsedStanza find:@"{urn:xmpp:carbons:2}*"];
            }
#endif
            //queue up new stanzas onto the parseQueue which will dispatch them synchronously to the receiveQueue
            //this makes it possible to discard all not already processed but parsed stanzas on disconnect or stream restart etc.
            [_parseQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                //always process stanzas in the receiveQueue
                //use a synchronous dispatch to make sure no (old) tcp buffers of disconnected connections leak into the receive queue on app unfreeze
                DDLogVerbose(@"Synchronously handling next stanza on receive queue (%lu stanzas queued in parse queue, %lu current operations in receive queue)", [_parseQueue operationCount], [_receiveQueue operationCount]);
                [_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                    [self processInput:parsedStanza];
                }]] waitUntilFinished:YES];
            }]] waitUntilFinished:NO];
        }];

    }
    else
    {
        DDLogInfo(@"resetting parser delegate");
        [_baseParserDelegate reset];
    }
    
    // create (new) pipe and attach a (new) streaming parser
    _xmlParser = [[NSXMLParser alloc] initWithStream:[_iPipe getNewEnd]];
    [_xmlParser setShouldProcessNamespaces:YES];
    [_xmlParser setShouldReportNamespacePrefixes:NO];
    [_xmlParser setShouldResolveExternalEntities:NO];
    [_xmlParser setDelegate:_baseParserDelegate];
    
    if(clearReceiveQueue)
    {
        //stop everything coming after this (we don't want to process stanzas that came in *before* this xmpp stream got started!)
        //if we do not do this we could be prone to attacks injecting xml elements into the new stream before it gets started
        [_iPipe drainInputStream];
        [_parseQueue cancelAllOperations];
        [_receiveQueue cancelAllOperations];
    }
    
    // do the stanza parsing in the default global queue
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DDLogInfo(@"calling parse");
        [_xmlParser parse];     //blocking operation
        DDLogInfo(@"parse ended");
    });

    MLXMLNode* xmlOpening = [[MLXMLNode alloc] initWithElement:@"__xml"];
    [self send:xmlOpening];
    MLXMLNode* stream = [[MLXMLNode alloc] initWithElement:@"stream:stream" andNamespace:@"jabber:client"];
    [stream.attributes setObject:@"http://etherx.jabber.org/streams" forKey:@"xmlns:stream"];
    [stream.attributes setObject:@"1.0" forKey:@"version"];
    if(self.connectionProperties.identity.domain)
        [stream.attributes setObject:self.connectionProperties.identity.domain forKey:@"to"];
    [self send:stream];
}

-(void) sendPing:(double) timeout
{
    DDLogVerbose(@"sendPing called");
    [self dispatchAsyncOnReceiveQueue: ^{
        DDLogVerbose(@"sendPing called - now inside receiveQueue");
        
        //make sure we are enabled before doing anything
        if(![[DataLayer sharedInstance] isAccountEnabled:self.accountNo])
        {
            DDLogInfo(@"account is disabled, ignoring ping.");
            return;
        }
        
        if(self.accountState<kStateReconnecting)
        {
            DDLogInfo(@"ping calling reconnect");
            [self reconnect:0];
            return;
        }
        
        if(self.accountState<kStateBound)
        {
            DDLogInfo(@"ping attempted before logged in and bound, ignoring ping.");
            return;
        }
        else if(_cancelPingTimer)
        {
            DDLogInfo(@"ping already sent, ignoring second ping request.");
            return;
        }
        else
        {
            //start ping timer
            _cancelPingTimer = [HelperTools startTimer:timeout withHandler:^{
                [self dispatchAsyncOnReceiveQueue: ^{
                    _cancelPingTimer = nil;
                    //check if someone already called reconnect or disconnect while we were waiting for the ping
                    //(which was called while we still were >= kStateBound)
                    if(self.accountState<kStateBound)
                        DDLogInfo(@"ping took too long, but reconnect or disconnect already in progress, ignoring");
                    else
                    {
                        DDLogInfo(@"ping took too long, reconnecting");
                        [self reconnect];
                    }
                }];
            }];
            monal_void_block_t handler = ^{
                DDLogInfo(@"ping response received, all seems to be well");
                if(_cancelPingTimer)
                {
                    _cancelPingTimer();      //cancel timer (ping was successful)
                    _cancelPingTimer = nil;
                }
            };
            
            //always use smacks pings if supported (they are shorter and better than iq pings)
            if(self.connectionProperties.supportsSM3)
            {
                DDLogVerbose(@"calling pinging requestSMAck...");
                [self requestSMAck:YES];
                [self addSmacksHandler:handler];
            }
            else
            {
                DDLogVerbose(@"sending out XEP-0199 ping...");
                //send xmpp ping even if server does not support it
                //(the ping iq will get an error response then, which is as good as a normal iq response here)
                XMPPIQ* ping = [[XMPPIQ alloc] initWithType:kiqGetType];
                [ping setiqTo:self.connectionProperties.identity.domain];
                [ping setPing];
                [self sendIq:ping withResponseHandler:^(XMPPIQ* result) {
                    handler();
                } andErrorHandler:^(XMPPIQ* error){
                    handler();
                }];
            }
        }
    }];
}

#pragma mark message ACK
-(void) addSmacksHandler:(monal_void_block_t) handler
{
    @synchronized(_stateLockObject) {
        [self addSmacksHandler:handler forValue:self.lastOutboundStanza];
    }
}

-(void) addSmacksHandler:(monal_void_block_t) handler forValue:(NSNumber*) value
{
    @synchronized(_stateLockObject) {
        if([value integerValue] < [self.lastOutboundStanza integerValue])
        {
            @throw [NSException exceptionWithName:@"RuntimeException" reason:@"Trying to add smacks handler for value *SMALLER* than current self.lastOutboundStanza, this handler would *never* be triggered!" userInfo:@{
                @"lastOutboundStanza": self.lastOutboundStanza,
                @"value": value,
            }];
        }
        NSDictionary* dic = @{@"value":value, @"handler":handler};
        [_smacksAckHandler addObject:dic];
    }
}

-(void) resendUnackedStanzas
{
    @synchronized(_stateLockObject) {
        DDLogInfo(@"Resending unacked stanzas...");
        NSMutableArray* sendCopy = [[NSMutableArray alloc] initWithArray:self.unAckedStanzas];
        //remove all stanzas from queue and correct the lastOutboundStanza counter accordingly
        self.lastOutboundStanza = [NSNumber numberWithInteger:[self.lastOutboundStanza integerValue] - [self.unAckedStanzas count]];
        //Send appends to the unacked stanzas. Not removing it now will create an infinite loop.
        //It may also result in mutation on iteration
        [self.unAckedStanzas removeAllObjects];
        [sendCopy enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic= (NSDictionary *) obj;
            [self send:(XMPPStanza*)[dic objectForKey:kStanza]];
        }];
        [self persistState];
    }
}

-(void) resendUnackedMessageStanzasOnly:(NSMutableArray*) stanzas
{
    if(stanzas)
    {
        @synchronized(_stateLockObject) {
            DDLogWarn(@"Resending unacked message stanzas only...");
            NSMutableArray* sendCopy = [[NSMutableArray alloc] initWithArray:stanzas];
            //clear queue because we don't want to repeat resending these stanzas later if the var stanzas points to self.unAckedStanzas here
            [stanzas removeAllObjects];
            [sendCopy enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSDictionary* dic = (NSDictionary *) obj;
                XMPPStanza* stanza = [dic objectForKey:kStanza];
                if([stanza.element isEqualToString:@"message"])		//only resend message stanzas because of the smacks error condition
                    [self send:stanza withSmacks:self.connectionProperties.supportsSM3];
            }];
            //persist these changes (the queue can now be empty because smacks enable failed
            //or contain all the resent stanzas (e.g. only resume failed))
            [self persistState];
        }
    }
}

-(void) removeAckedStanzasFromQueue:(NSNumber*) hvalue
{
    NSMutableArray* ackHandlerToCall;
    @synchronized(_stateLockObject) {
        self.lastHandledOutboundStanza = hvalue;
        if([self.unAckedStanzas count]>0)
        {
            NSMutableArray* iterationArray = [[NSMutableArray alloc] initWithArray:self.unAckedStanzas];
            DDLogDebug(@"removeAckedStanzasFromQueue: hvalue %@, lastOutboundStanza %@", hvalue, self.lastOutboundStanza);
            NSMutableArray* discard = [[NSMutableArray alloc] initWithCapacity:[self.unAckedStanzas count]];
            for(NSDictionary* dic in iterationArray)
            {
                NSNumber* stanzaNumber = [dic objectForKey:kQueueID];
                MLXMLNode* node = [dic objectForKey:kStanza];
                //having a h value of 1 means the first stanza was acked and the first stanza has a kQueueID of 0
                if([stanzaNumber integerValue]<[hvalue integerValue])
                {
                    [discard addObject:dic];
                    
                    //signal successful delivery to the server to all notification listeners
                    //(NOT the successful delivery to the receiving client, see the implementation of XEP-0184 for that)
                    if([node isKindOfClass:[XMPPMessage class]])
                    {
                        XMPPMessage* messageNode = (XMPPMessage*)node;
                        if(messageNode.xmppId)
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalSentMessageNotice object:self userInfo:@{kMessageId:messageNode.xmppId}];
                    }
                }
            }

            [iterationArray removeObjectsInArray:discard];
            self.unAckedStanzas = iterationArray;

            //persist these changes (but only if we actually made some changes)
            if([discard count])
                [self persistState];
        }
        
        //remove registered smacksAckHandler that will be called now
        ackHandlerToCall = [[NSMutableArray alloc] initWithCapacity:[_smacksAckHandler count]];
        for(NSDictionary* dic in _smacksAckHandler)
            if([[dic objectForKey:@"value"] integerValue] <= [hvalue integerValue])
                [ackHandlerToCall addObject:dic];
        [_smacksAckHandler removeObjectsInArray:ackHandlerToCall];
    }
    
    //call registered smacksAckHandler that got sorted out
    for(NSDictionary* dic in ackHandlerToCall)
        ((monal_void_block_t)dic[@"handler"])();
}

-(void) requestSMAck:(BOOL) force
{
    //caution: this could be called from sendQueue, too!
    MLXMLNode* rNode;
    @synchronized(_stateLockObject) {
        unsigned long unackedCount = (unsigned long)[self.unAckedStanzas count];
        NSDictionary* dic = @{
            @"lastHandledInboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledInboundStanza],
            @"lastHandledOutboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledOutboundStanza],
            @"lastOutboundStanza":[NSString stringWithFormat:@"%@", self.lastOutboundStanza],
            @"unAckedStanzasCount":[NSString stringWithFormat:@"%lu", unackedCount],
        };
        if(self.accountState>=kStateBound && self.connectionProperties.supportsSM3 &&
            ((!self.smacksRequestInFlight && unackedCount>0) || force)
        ) {
            DDLogVerbose(@"requesting smacks ack...");
            rNode = [[MLXMLNode alloc] initWithElement:@"r" andNamespace:@"urn:xmpp:sm:3" withAttributes:dic andChildren:@[] andData:nil];
            self.smacksRequestInFlight = YES;
        }
        else
            DDLogDebug(@"no smacks request, there is nothing pending or a request already in flight...");
    }
    if(rNode)
        [self send:rNode];
}

-(void) sendLastAck
{
    //send last smacks ack as required by smacks revision 1.5.2
    if(self.connectionProperties.supportsSM3) {
        DDLogInfo(@"sending last ack");
        [self sendSMAck:NO];
    }
}

-(void) sendSMAck:(BOOL) queuedSend
{
    if(self.connectionProperties.supportsSM3)
    {
        unsigned long unackedCount = 0;
        NSDictionary* dic;
        @synchronized(_stateLockObject) {
            unackedCount = (unsigned long)[self.unAckedStanzas count];
            dic = @{
                @"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza],
                @"lastHandledInboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledInboundStanza],
                @"lastHandledOutboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledOutboundStanza],
                @"lastOutboundStanza":[NSString stringWithFormat:@"%@", self.lastOutboundStanza],
                @"unAckedStanzasCount":[NSString stringWithFormat:@"%lu", unackedCount],
            };
        }
        MLXMLNode* aNode = [[MLXMLNode alloc] initWithElement:@"a" andNamespace:@"urn:xmpp:sm:3" withAttributes:dic andChildren:@[] andData:nil];
        if(queuedSend)
            [self send:aNode];
        else      //this should only be done from sendQueue (e.g. by sendLastAck())
            [self writeToStream:[aNode XMLString]];		// dont even bother queueing
    }
}

#pragma mark - stanza handling

-(void) processInput:(MLXMLNode*) parsedStanza
{
    DDLogDebug(@"RECV Stanza: %@", parsedStanza);
    
    //only process most stanzas/nonzas after having a secure context
    if(self.connectionProperties.server.isDirectTLS || self->_startTLSComplete)
    {
        if([parsedStanza check:@"/{urn:xmpp:sm:3}r"] && self.connectionProperties.supportsSM3 && self.accountState>=kStateBound)
        {
            [self sendSMAck:YES];
        }
        else if([parsedStanza check:@"/{urn:xmpp:sm:3}a"] && self.connectionProperties.supportsSM3 && self.accountState>=kStateBound)
        {
            NSNumber* h = [parsedStanza findFirst:@"/@h|int"];
            if(!h)
                return [self invalidXMLError];
            
            @synchronized(_stateLockObject) {
                //remove acked messages
                [self removeAckedStanzasFromQueue:h];

                self.smacksRequestInFlight = NO;        //ack returned
                [self requestSMAck:NO];                 //request ack again (will only happen if queue is not empty)
            }
        }
        else if([parsedStanza check:@"/{jabber:client}presence"])
        {
            XMPPPresence* presenceNode = (XMPPPresence*)parsedStanza;
            
            //sanitize: no from or to always means own bare jid
            if(!presenceNode.from)
                presenceNode.from = self.connectionProperties.identity.jid;
            if(!presenceNode.to)
                presenceNode.to = self.connectionProperties.identity.fullJid;

            if([presenceNode.fromUser isEqualToString:self.connectionProperties.identity.jid])
            {
                //ignore self presences for now
                DDLogInfo(@"ignoring presence from self");
            }
            else
            {
                if([presenceNode check:@"/<type=subscribe>"])
                {
                    MLContact* contact = [[MLContact alloc] init];
                    contact.accountId = self.accountNo;
                    contact.contactJid = presenceNode.fromUser;

                    // check if we need a contact request
                    NSDictionary* contactSub = [[DataLayer sharedInstance] getSubscriptionForContact:contact.contactJid andAccount:contact.accountId];
                    if(!contactSub || ![[contactSub objectForKey:@"subscription"] isEqualToString:kSubBoth]) {
                        [[DataLayer sharedInstance] addContactRequest:contact];
                    }
                }

                if([presenceNode check:@"{http://jabber.org/protocol/muc#user}x"])
                {
                    for(NSString* code in [presenceNode find:@"{http://jabber.org/protocol/muc#user}x/status@code"])
                    {
                        if([code isEqualToString:@"201"])
                        {
                            //201- created and needs configuration
                            //make instant room
                            XMPPIQ *configNode = [[XMPPIQ alloc] initWithType:kiqSetType];
                            [configNode setiqTo:presenceNode.from];
                            [configNode setInstantRoom];
                            [self send:configNode];
                        }
                    }

                    if([presenceNode check:@"/<type=unavailable>"])
                    {
                        [self incrementLastHandledStanza];
                        //handle this differently later
                        return;
                    }
                }

                if(![presenceNode check:@"/@type"])
                {
                    DDLogVerbose(@"presence notice from %@", presenceNode.fromUser);

                    if(presenceNode.from)
                    {
                        MLContact *contact = [[MLContact alloc] init];
                        contact.accountId = self.accountNo;
                        contact.contactJid = presenceNode.fromUser;
                        contact.state = [presenceNode findFirst:@"show#"];
                        contact.statusMessage = [presenceNode findFirst:@"status#"];

                        //add contact if possible (ignore already existing contacts)
                        [[DataLayer sharedInstance] addContact:presenceNode.fromUser forAccount:self.accountNo nickname:nil andMucNick:nil];

                        //update buddy state
                        [[DataLayer sharedInstance] setOnlineBuddy:presenceNode forAccount:self.accountNo];
                        [[DataLayer sharedInstance] setBuddyState:presenceNode forAccount:self.accountNo];
                        [[DataLayer sharedInstance] setBuddyStatus:presenceNode forAccount:self.accountNo];

                        //handle last interaction time (dispatch database update in own background thread)
                        if([presenceNode check:@"{urn:xmpp:idle:1}idle@since"])
                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                [[DataLayer sharedInstance] setLastInteraction:[presenceNode findFirst:@"{urn:xmpp:idle:1}idle@since|datetime"] forJid:presenceNode.fromUser andAccountNo:self.accountNo];
                            });
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
                                @"jid": presenceNode.fromUser,
                                @"accountNo": self.accountNo,
                                @"lastInteraction": [presenceNode check:@"{urn:xmpp:idle:1}idle@since"] ? [presenceNode findFirst:@"{urn:xmpp:idle:1}idle@since|datetime"] : [[NSDate date] initWithTimeIntervalSince1970:0],    //nil cannot directly be saved in NSDictionary
                                @"isTyping": @NO
                            }];
                        });
                    }
                    else
                    {
                        DDLogError(@"ERROR: presence notice but no user name.");
                    }
                }
                else if([presenceNode check:@"/<type=unavailable>"])
                {
                    [[DataLayer sharedInstance] setOfflineBuddy:presenceNode forAccount:self.accountNo];
                }

                //handle entity capabilities (this has to be done *after* setOnlineBuddy which sets the ver hash for the resource to "")
                if(
                    [presenceNode check:@"{http://jabber.org/protocol/caps}c@hash"] &&
                    [presenceNode check:@"{http://jabber.org/protocol/caps}c@ver"] &&
                    presenceNode.fromUser &&
                    presenceNode.fromResource
                )
                {
                    BOOL shouldQueryCaps = NO;
                    if(![@"sha-1" isEqualToString:[presenceNode findFirst:@"{http://jabber.org/protocol/caps}c@hash"]])
                    {
                        DDLogWarn(@"Unknown caps hash algo '%@', querying disco without checking hash!", [presenceNode findFirst:@"{http://jabber.org/protocol/caps}c@hash"]);
                        shouldQueryCaps = YES;
                    }
                    else
                    {
                        NSString* newVer = [presenceNode findFirst:@"{http://jabber.org/protocol/caps}c@ver"];
                        NSString* ver = [[DataLayer sharedInstance] getVerForUser:presenceNode.fromUser andResource:presenceNode.fromResource];
                        if(!ver || ![ver isEqualToString:newVer])     //caps hash of resource changed
                            [[DataLayer sharedInstance] setVer:newVer forUser:presenceNode.fromUser andResource:presenceNode.fromResource];

                        if(![[DataLayer sharedInstance] getCapsforVer:newVer])
                        {
                            DDLogInfo(@"Presence included unknown caps hash %@, querying disco", newVer);
                            shouldQueryCaps = YES;
                        }
                    }
                    
                    if(shouldQueryCaps)
                    {
                        XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
                        [discoInfo setiqTo:presenceNode.from];
                        [discoInfo setDiscoInfoNode];
                        [self sendIq:discoInfo withDelegate:[MLIQProcessor class] andMethod:@selector(handleEntityCapsDisco:withIqNode:) andAdditionalArguments:nil];
                    }
                }

            }
            
            //only mark stanza as handled *after* processing it
            [self incrementLastHandledStanza];
        }
        else if([parsedStanza check:@"/{jabber:client}message"])
        {
            //outerMessageNode and messageNode are the same for messages not carrying a carbon copy or mam result
            XMPPMessage* outerMessageNode = (XMPPMessage*)parsedStanza;
            XMPPMessage* messageNode = outerMessageNode;
            
            //sanitize outer node: no from or to always means own bare jid
            if(!outerMessageNode.from)
                outerMessageNode.from = self.connectionProperties.identity.jid;
            if(!outerMessageNode.to)
                outerMessageNode.to = self.connectionProperties.identity.fullJid;
            
            //extract inner message if mam result or carbon copy
            //the original "outer" message will be kept in outerMessageNode while the forwarded stanza will be stored in messageNode
            if([outerMessageNode check:@"{urn:xmpp:mam:2}result"])          //mam result
            {
                if(![self.connectionProperties.identity.jid isEqualToString:outerMessageNode.from])
                {
                    DDLogError(@"mam results must be from our bare jid, ignoring this spoofed mam result!");
                    //even these stanzas have do be counted by smacks
                    [self incrementLastHandledStanza];
                    return;
                }
                //create a new XMPPMessage node instead of only a MLXMLNode because messages have some convenience properties and methods
                messageNode = [[XMPPMessage alloc] initWithXMPPMessage:[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result/{urn:xmpp:forward:0}forwarded/{jabber:client}message"]];
                
                //move mam:2 delay timestamp into forwarded message stanza if the forwarded stanza does not have one already
                //that makes parsing a lot easier later on and should not do any harm, even when resending/forwarding this inner stanza
                if([outerMessageNode check:@"{urn:xmpp:mam:2}result/{urn:xmpp:forward:0}forwarded/{urn:xmpp:delay}delay"] && ![messageNode check:@"{urn:xmpp:delay}delay"])
                    [messageNode addChild:[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result/{urn:xmpp:forward:0}forwarded/{urn:xmpp:delay}delay"]];
                
                DDLogDebug(@"mam extracted, messageNode is now: %@", messageNode);
            }
            else if([outerMessageNode check:@"{urn:xmpp:carbons:2}*"])     //carbon copy
            {
                if(![self.connectionProperties.identity.jid isEqualToString:outerMessageNode.from])
                {
                    DDLogError(@"carbon copies must be from our bare jid, ignoring this spoofed carbon copy!");
                    //even these stanzas have do be counted by smacks
                    [self incrementLastHandledStanza];
                    return;
                }
                //create a new XMPPMessage node instead of only a MLXMLNode because messages have some convenience properties and methods
                messageNode = [[XMPPMessage alloc] initWithXMPPMessage:[outerMessageNode findFirst:@"{urn:xmpp:carbons:2}*/{urn:xmpp:forward:0}forwarded/{jabber:client}message"]];
                
                //move carbon copy delay timestamp into forwarded message stanza if the forwarded stanza does not have one already
                //that makes parsing a lot easier later on and should not do any harm, even when resending/forwarding this inner stanza
                if([outerMessageNode check:@"{urn:xmpp:delay}delay"] && ![messageNode check:@"{urn:xmpp:delay}delay"])
                    [messageNode addChild:[outerMessageNode findFirst:@"{urn:xmpp:delay}delay"]];
                
                DDLogDebug(@"carbon extracted, messageNode is now: %@", messageNode);
            }
            
            //sanitize inner node: no from or to always means own bare jid
            if(!messageNode.from)
                messageNode.from = self.connectionProperties.identity.jid;
            if(!messageNode.to)
                messageNode.to = self.connectionProperties.identity.fullJid;
            
            DDLogVerbose(@"Incoming outer message from='%@' to='%@' -- inner message from='%@' to='%@'", outerMessageNode.from, outerMessageNode.to, messageNode.from, messageNode.to);
            DDLogVerbose(@"Incoming outer message fromUser='%@' toUser='%@' -- inner message fromUser='%@' toUser='%@'", outerMessageNode.fromUser, outerMessageNode.toUser, messageNode.fromUser, messageNode.toUser);
            DDLogVerbose(@"Raw outer from value: '%@', raw inner from value: '%@'", outerMessageNode.attributes[@"from"], messageNode.attributes[@"from"]);
            DDLogVerbose(@"Raw outer to value: '%@', raw inner to value: '%@'", outerMessageNode.attributes[@"to"], messageNode.attributes[@"to"]);
            
            NSAssert(![messageNode.fromUser containsString:@"/"], @"messageNode.fromUser contains resource!");
            NSAssert(![messageNode.toUser containsString:@"/"], @"messageNode.toUser contains resource!");
            NSAssert(![outerMessageNode.fromUser containsString:@"/"], @"outerMessageNode.fromUser contains resource!");
            NSAssert(![outerMessageNode.toUser containsString:@"/"], @"outerMessageNode.toUser contains resource!");
            
            //only process mam results when they are *not* for priming the database with the initial stanzaid (the id will be taken from the iq result)
            //we do this because we don't want to randomly add one single message to our history db after the user installs the app / adds a new account
            //if the user wants to see older messages he can retrieve them using the ui (endless upscrolling through mam)
            if(!([outerMessageNode check:@"{urn:xmpp:mam:2}result"] && [[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"] hasPrefix:@"MLignore:"]))
                [MLMessageProcessor processMessage:messageNode andOuterMessage:outerMessageNode forAccount:self];
            
            //add newest stanzaid to database *after* processing the message, but only for non-mam messages or mam catchup
            //(e.g. those messages going forward in time not backwards)
            NSString* stanzaid = [outerMessageNode check:@"{urn:xmpp:mam:2}result"] && [[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"] hasPrefix:@"MLcatchup:"] ? [outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@id"] : nil;
            //if not from mam response: use stanzaid from message and check stnaza-id @by according to the rules outlined in XEP-0359
            if(!stanzaid && [self.connectionProperties.identity.jid isEqualToString:[messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@by"]])
                stanzaid = [messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@id"];
            if(stanzaid)
            {
                DDLogVerbose(@"Updating lastStanzaId in database to: %@", stanzaid);
                [[DataLayer sharedInstance] setLastStanzaId:stanzaid forAccount:self.accountNo];
            }
            
            //only mark stanza as handled *after* processing it
            [self incrementLastHandledStanza];
        }
        else if([parsedStanza check:@"/{jabber:client}iq"])
        {
            XMPPIQ* iqNode = (XMPPIQ*)parsedStanza;
            
            //sanity: check if iq id and type attributes are present and throw it away if not
            if(![parsedStanza check:@"/@id"] || ![parsedStanza check:@"/@type"])
            {
                //mark stanza as handled even if we don't process it further (we still received it, so we have to count it)
                [self incrementLastHandledStanza];
                return;
            }
            
            //sanitize: no from or to always means own bare jid
            if(!iqNode.from)
                iqNode.from = self.connectionProperties.identity.jid;
            if(!iqNode.to)
                iqNode.to = self.connectionProperties.identity.fullJid;
            
            //process registered iq handlers
            if(_iqHandlers[[iqNode findFirst:@"/@id"]])
            {
                if([iqNode check:@"/<type=result>"] && _iqHandlers[[iqNode findFirst:@"/@id"]][@"resultHandler"])
                    ((monal_iq_handler_t) _iqHandlers[[iqNode findFirst:@"/@id"]][@"resultHandler"])(iqNode);
                else if([iqNode check:@"/<type=error>"] && _iqHandlers[[iqNode findFirst:@"/@id"]][@"errorHandler"])
                    ((monal_iq_handler_t) _iqHandlers[[iqNode findFirst:@"/@id"]][@"errorHandler"])(iqNode);
                else if(_iqHandlers[[iqNode findFirst:@"/@id"]][@"delegate"] && _iqHandlers[[iqNode findFirst:@"/@id"]][@"method"])
                    [HelperTools callStaticHandler:_iqHandlers[[iqNode findFirst:@"/@id"]] withDefaultArguments:@[self, iqNode]];
                
                //remove handler after calling it
                [_iqHandlers removeObjectForKey:[iqNode findFirst:@"/@id"]];
            }
            else            //only process iqs that have not already been handled by a registered iq handler
            {
                [MLIQProcessor processIq:iqNode forAccount:self];

#ifndef DISABLE_OMEMO
                if([[iqNode findFirst:@"/@id"] isEqualToString:self.omemo.deviceQueryId])
                {
                    if([iqNode check:@"/<type=error>"]) {
                        //there are no devices published yet
                        [self.omemo sendOMEMODeviceWithForce:NO];
                    }
                }
#endif
                if([[iqNode findFirst:@"/@id"] isEqualToString:self.jingle.idval])
                    [self jingleResult:iqNode];
            }
            
            //only mark stanza as handled *after* processing it
            [self incrementLastHandledStanza];
        }
        else if([parsedStanza check:@"/{urn:xmpp:sm:3}enabled"])
        {
            NSMutableArray* stanzas;
            @synchronized(_stateLockObject) {
                //save old unAckedStanzas queue before it is cleared
                stanzas = self.unAckedStanzas;

                //init smacks state (this clears the unAckedStanzas queue)
                [self initSM3];

                //save streamID if resume is supported
                if([parsedStanza findFirst:@"/@resume|bool"])
                    self.streamID = [parsedStanza findFirst:@"/@id"];
                else
                    self.streamID = nil;

                //persist these changes (streamID and initSM3)
                [self persistState];
            }

            //init session and query disco, roster etc.
            [self initSession];

            //resend unacked stanzas saved above (this happens only if the server provides smacks support without resumption support)
            //or if the resumption failed for other reasons the server is responsible for
            //clean up those stanzas to only include message stanzas because iqs don't survive a session change
            //message duplicates are possible in this scenario, but that's better than dropping messages
            [self resendUnackedMessageStanzasOnly:stanzas];
        }
        else if([parsedStanza check:@"/{urn:xmpp:sm:3}resumed"] && self.connectionProperties.supportsSM3 && self.accountState<kStateBound)
        {
            NSNumber* h = [parsedStanza findFirst:@"/@h|int"];
            if(!h)
                return [self invalidXMLError];
            
            self.resuming = NO;

            //now we are bound again
            _accountState = kStateBound;
            _connectedTime = [NSDate date];
            _usableServersList = [[NSMutableArray alloc] init];       //reset list to start again with the highest SRV priority on next connect
            _exponentialBackoff = 0;

            @synchronized(_stateLockObject) {
                //remove already delivered stanzas and resend the (still) unacked ones
                [self removeAckedStanzasFromQueue:h];
                [self resendUnackedStanzas];
            }

            //publish new csi and last active state (but only do so when not in an extension
            //because the last active state does not change when inside an extension)
            [self sendCurrentCSIState];
            if(![HelperTools isAppExtension])
            {
                DDLogVerbose(@"Not in extension --> sending out presence after resume");
                [self sendPresence];
            }

            @synchronized(_stateLockObject) {
                //signal finished catchup if our current outgoing stanza counter is acked, this introduces an additional roundtrip to make sure
                //all stanzas the *server* wanted to replay have been received, too
                //request an ack to accomplish this if stanza replay did not already trigger one (smacksRequestInFlight is false if replay did not trigger one)
                if(!self.smacksRequestInFlight)
                    [self requestSMAck:YES];    //force sending of the request even if the smacks queue is empty (needed to always trigger the smacks handler below after 1 RTT)
                weakify(self);
                [self addSmacksHandler:^{
                    DDLogVerbose(@"Inside resume smacks handler: catchup done");
                    strongify(self);
                    if(!self->_catchupDone)
                    {
                        self->_catchupDone = YES;
                        DDLogVerbose(@"Now posting kMonalFinishedCatchup notification");
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFinishedCatchup object:self];
                    }
                }];
            }
        }
        else if([parsedStanza check:@"/{urn:xmpp:sm:3}failed"] && self.connectionProperties.supportsSM3 && self.accountState<kStateBound && self.resuming)
        {
            //we landed here because smacks resume failed
            
            self.resuming = NO;
            @synchronized(_stateLockObject) {
                //invalidate stream id
                self.streamID = nil;
                //get h value, if server supports smacks revision 1.5
                NSNumber* h = [parsedStanza findFirst:@"/@h|int"];
                DDLogInfo(@"++++++++++++++++++++++++ failed resume: h=%@", h);
                if(h)
                    [self removeAckedStanzasFromQueue:h];
                //persist these changes
                [self persistState];
            }

            //bind  a new resource like normal on failed resume (supportsSM3 is still YES here but switches to NO on failed enable later on, if necessary)
            [self bindResource:self.connectionProperties.identity.resource];
        }
        else if([parsedStanza check:@"/{urn:xmpp:sm:3}failed"] && self.connectionProperties.supportsSM3 && self.accountState>=kStateBound && !self.resuming)
        {
            //we landed here because smacks enable failed
            
            self.connectionProperties.supportsSM3 = NO;
            //init session and query disco, roster etc.
            [self initSession];
        }
        else if([parsedStanza check:@"/{urn:ietf:params:xml:ns:xmpp-sasl}failure"])
        {
            NSString* message = [parsedStanza findFirst:@"text#"];;
            if([parsedStanza check:@"not-authorized"])
            {
                if(!message)
                    message = @"Not Authorized. Please check your credentials.";
            }
            else
            {
                if(!message)
                    message = @"There was a SASL error on the server.";
            }

            [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, message]];
            [self disconnect];
        }
        else if([parsedStanza check:@"/{urn:ietf:params:xml:ns:xmpp-sasl}challenge"])
        {
            if(self.accountState >= kStateLoggedIn)
                return [self invalidXMLError];
            if(self.connectionProperties.server.isDirectTLS || self->_startTLSComplete)
            {
                MLXMLNode* responseXML = [[MLXMLNode alloc] initWithElement:@"response" andNamespace:@"urn:ietf:params:xml:ns:xmpp-sasl"];

                //TODO: implement SCRAM SHA1 and SHA256 based auth

                [self send:responseXML];
                return;
            }
        }
        else if([parsedStanza check:@"/{urn:ietf:params:xml:ns:xmpp-sasl}success"])
        {
            if(self.accountState >= kStateLoggedIn)
                return [self invalidXMLError];
            //perform logic to handle sasl success
            DDLogInfo(@"Got SASL Success");
            self->_accountState = kStateLoggedIn;
            if(_cancelLoginTimer)
            {
                _cancelLoginTimer();        //we are now logged in --> cancel running login timer
                _cancelLoginTimer = nil;
            }
            self->_loggedInOnce = YES;
            [self startXMPPStream:YES];
        }
        else if([parsedStanza check:@"/{http://etherx.jabber.org/streams}error"])
        {
            NSString* errorReason = [parsedStanza findFirst:@"{urn:ietf:params:xml:ns:xmpp-streams}!text$"];
            NSString* errorText = [parsedStanza findFirst:@"{urn:ietf:params:xml:ns:xmpp-streams}text#"];
            DDLogWarn(@"Got secure XMPP stream error %@: %@", errorReason, errorText);
            NSString* message = [NSString stringWithFormat:@"XMPP stream error: %@", errorReason];
            if(errorText && ![errorText isEqualToString:@""])
                message = [NSString stringWithFormat:@"XMPP stream error %@: %@", errorReason, errorText];
            [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, message]];
            [self reconnect];
        }
        else if([parsedStanza check:@"/{http://etherx.jabber.org/streams}features"])
        {
            //prevent reconnect attempt
            if(_accountState < kStateHasStream)
                _accountState = kStateHasStream;
            
            //perform logic to handle stream
            if(self.accountState < kStateLoggedIn)
            {
                if(_registration)
                {
                    DDLogInfo(@"Registration: Calling requestRegForm");
                    [self requestRegForm];
                }
                else if(_registrationSubmission)
                {
                    DDLogInfo(@"Registration: Calling submitRegForm");
                    [self submitRegForm];
                }
                else
                {
                    //extract menchanisms presented
                    NSSet* supportedSaslMechanisms = [NSSet setWithArray:[parsedStanza find:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms/mechanism#"]];
                    
                    if([supportedSaslMechanisms containsObject:@"PLAIN"])
                    {
                        [self send:[[MLXMLNode alloc]
                            initWithElement:@"auth"
                            andNamespace:@"urn:ietf:params:xml:ns:xmpp-sasl"
                            withAttributes:@{@"mechanism": @"PLAIN"}
                            andChildren:@[]
                            andData:[HelperTools encodeBase64WithString: [NSString stringWithFormat:@"\0%@\0%@", self.connectionProperties.identity.user, self.connectionProperties.identity.password]]
                        ]];
                    }
                    else
                    {
                        //no supported auth mechanism
                        //TODO: implement SCRAM SHA1 and SHA256 based auth
                        DDLogInfo(@"no supported auth mechanism, disconnecting!");
                        [self disconnect];
                    }
                }
            }
            else
            {
                if([parsedStanza check:@"{urn:xmpp:csi:0}csi"])
                    self.connectionProperties.supportsClientState = YES;
                if([parsedStanza check:@"{urn:xmpp:sm:3}sm"])
                    self.connectionProperties.supportsSM3 = YES;
                if([parsedStanza check:@"{urn:xmpp:features:rosterver}ver"])
                    self.connectionProperties.supportsRosterVersion = YES;
                if([parsedStanza check:@"{urn:xmpp:features:pre-approval}sub"])
                    self.connectionProperties.supportsRosterPreApproval = YES;
                
                MLXMLNode* resumeNode = nil;
                @synchronized(_stateLockObject) {
                    //under rare circumstances/bugs the appex could have changed the smacks state *after* our connect method was called
                    //--> load newest saved smacks state to be up to date even in this case
                    [self readSmacksStateOnly];
                    //test if smacks is supported and allows resume
                    if(self.connectionProperties.supportsSM3 && self.streamID)
                    {
                        NSDictionary* dic = @{
                            @"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza],
                            @"previd":self.streamID,
                            
                            @"lastHandledInboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledInboundStanza],
                            @"lastHandledOutboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledOutboundStanza],
                            @"lastOutboundStanza":[NSString stringWithFormat:@"%@", self.lastOutboundStanza],
                            @"unAckedStanzasCount":[NSString stringWithFormat:@"%lu", (unsigned long)[self.unAckedStanzas count]]
                        };
                        resumeNode = [[MLXMLNode alloc] initWithElement:@"resume" andNamespace:@"urn:xmpp:sm:3" withAttributes:dic andChildren:@[] andData:nil];
                        self.resuming = YES;      //this is needed to distinguish a failed smacks resume and a failed smacks enable later on
                    }
                }
                if(resumeNode)
                    [self send:resumeNode];
                else
                    [self bindResource:self.connectionProperties.identity.resource];
                
            }
        }
        else
        {
            DDLogWarn(@"Ignoring unhandled top-level xml element <%@>: %@", parsedStanza.element, parsedStanza);
        }
    }
    //handle only a subset of stanzas/nonzas when in insecure (non-tls) context
    else
    {
        if([parsedStanza check:@"/{http://etherx.jabber.org/streams}error"])
        {
            NSString* errorReason = [parsedStanza findFirst:@"{urn:ietf:params:xml:ns:xmpp-streams}!text$"];
            NSString* errorText = [parsedStanza findFirst:@"{urn:ietf:params:xml:ns:xmpp-streams}text#"];
            DDLogWarn(@"Got *INSECURE* XMPP stream error %@: %@", errorReason, errorText);
            NSString* message = [NSString stringWithFormat:@"XMPP stream error: %@", errorReason];
            if(errorText && ![errorText isEqualToString:@""])
                message = [NSString stringWithFormat:@"XMPP stream error %@: %@", errorReason, errorText];
            [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, message]];
            [self reconnect];
        }
        else if([parsedStanza check:@"/{http://etherx.jabber.org/streams}features"])
        {
            //ignore starttls stream feature presence and opportunistically try starttls
            //(this is in accordance to RFC 7590: https://tools.ietf.org/html/rfc7590#section-3.1 )
            MLXMLNode* startTLS = [[MLXMLNode alloc] initWithElement:@"starttls" andNamespace:@"urn:ietf:params:xml:ns:xmpp-tls"];
            [self send:startTLS];
            return;
        }
        else if([parsedStanza check:@"/{urn:ietf:params:xml:ns:xmpp-tls}proceed"])
        {
            [_iPipe drainInputStream];      //remove all pending data before starting tls handshake
            [self initTLS];
            self->_startTLSComplete=YES;
            //stop everything coming after this (we don't want to process stanzas that came in *before* a secure TLS context was established!)
            //if we do not do this we could be prone to mitm attacks injecting xml elements into the stream before it gets encrypted
            //such xml elements would then get processed as received *after* the TLS initialization
            [self startXMPPStream:YES];
        }
        else
        {
            DDLogError(@"Ignoring unhandled *INSECURE* top-level xml element <%@>, reconnecting: %@", parsedStanza.element, parsedStanza);
            [self reconnect];
        }
    }
}

#pragma mark stanza handling

-(void) sendIq:(XMPPIQ*) iq withResponseHandler:(monal_iq_handler_t) resultHandler andErrorHandler:(monal_iq_handler_t) errorHandler
{
    if(resultHandler || errorHandler)
        @synchronized(_iqHandlers) {
            _iqHandlers[[iq getId]] = @{@"id": [iq getId], @"resultHandler":resultHandler, @"errorHandler":errorHandler};
        }
    [self send:iq];
}

-(void) sendIq:(XMPPIQ*) iq withDelegate:(id) delegate andMethod:(SEL) method andAdditionalArguments:(NSArray*) args
{
    if(delegate && method)
    {
        DDLogVerbose(@"Adding delegate [%@ %@] to iqHandlers...", NSStringFromClass(delegate), NSStringFromSelector(method));
        @synchronized(_iqHandlers) {
            _iqHandlers[[iq getId]] = @{@"id":[iq getId], @"delegate":NSStringFromClass(delegate), @"method":NSStringFromSelector(method), @"arguments":(args ? args : @[])};
        }
    }
    [self send:iq];     //this will also call persistState --> we don't need to do this here explicitly (to make sure our iq delegate is stored to db)
}

-(void) sendIq:(XMPPIQ*) iq withDelegate:(id) delegate andMethod:(SEL) method andInvalidationMethod:(SEL) invalidationMethod andAdditionalArguments:(NSArray*) args
{
    if(delegate && method && invalidationMethod)
    {
        DDLogVerbose(@"Adding delegate [%@ %@] to iqHandlers...", NSStringFromClass(delegate), NSStringFromSelector(method));
        @synchronized(_iqHandlers) {
            _iqHandlers[[iq getId]] = @{@"id":[iq getId], @"delegate":NSStringFromClass(delegate), @"method":NSStringFromSelector(method), @"invalidationMethod":NSStringFromSelector(invalidationMethod), @"arguments":(args ? args : @[])};
        }
    }
    [self send:iq];     //this will also call persistState --> we don't need to do this here explicitly (to make sure our iq delegate is stored to db)
}

-(void) send:(MLXMLNode*) stanza
{
    //proxy to real send
    [self send:stanza withSmacks:YES];
}

-(void) send:(MLXMLNode*) stanza withSmacks:(BOOL) withSmacks
{
    NSAssert(stanza, @"stanza to send should not be nil");
    
    //always add stanzas (not nonzas!) to smacks queue to be resent later (if withSmacks=YES)
    if(withSmacks && [stanza isKindOfClass:[XMPPStanza class]])
    {
        XMPPStanza* queued_stanza = [stanza copy];
        if(![queued_stanza.element isEqualToString:@"iq"])      //add delay tag to message or presence stanzas but not to iq stanzas
        {
            //only add a delay tag if not already present
            if(![queued_stanza check:@"{urn:xmpp:delay}delay"])
                [queued_stanza addDelayTagFrom:self.connectionProperties.identity.jid];
        }
        @synchronized(_stateLockObject) {
            DDLogVerbose(@"ADD UNACKED STANZA: %@: %@", self.lastOutboundStanza, queued_stanza);
            NSDictionary* dic = @{kQueueID:self.lastOutboundStanza, kStanza:queued_stanza};
            [self.unAckedStanzas addObject:dic];
            //increment for next call
            self.lastOutboundStanza = [NSNumber numberWithInteger:[self.lastOutboundStanza integerValue] + 1];
            //persist these changes (this has to be synchronous because we want so persist stanzas to db before actually sending them)
            [self persistState];
        }
    }
    
    //only send nonzas if we are >kStateDisconnected and stanzas if we are >=kStateBound
    //only exception: an outgoing bind request stanza that is allowed before we are bound
    BOOL isBindRequest = [stanza isKindOfClass:[XMPPIQ class]] && [stanza check:@"{urn:ietf:params:xml:ns:xmpp-bind}bind/resource"];
    if(self.accountState>=kStateBound || (self.accountState>kStateDisconnected && (![stanza isKindOfClass:[XMPPStanza class]] || isBindRequest)))
    {
        [_sendQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
            DDLogDebug(@"SEND: %@", stanza);
            [_outputQueue addObject:stanza];
            [self writeFromQueue];      // try to send if there is space
        }]];
    }
    else
        DDLogDebug(@"NOT ADDING STANZA TO SEND QUEUE: %@", stanza);
}

#pragma mark messaging

-(void) sendMessage:(NSString*) message toContact:(NSString*) contact isMUC:(BOOL) isMUC isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString *) messageId
{
    XMPPMessage* messageNode = [[XMPPMessage alloc] init];
    [messageNode.attributes setObject:contact forKey:@"to"];
    [messageNode setXmppId:messageId];

#ifndef DISABLE_OMEMO
    if(encrypt && !isMUC) {
        [self.omemo encryptMessage:messageNode withMessage:message toContact:contact];
    } else {
#endif
        if(isUpload){
            [messageNode setOobUrl:message];
        } else  {
            [messageNode setBody:message];
        }
#ifndef DISABLE_OMEMO
    }
#endif
        
    if(isMUC)
    {
        [messageNode.attributes setObject:kMessageGroupChatType forKey:@"type"];
    } else  {
        [messageNode.attributes setObject:kMessageChatType forKey:@"type"];
        [messageNode addChild:[[MLXMLNode alloc] initWithElement:@"request" andNamespace:@"urn:xmpp:receipts"]];
        [messageNode addChild:[[MLXMLNode alloc] initWithElement:@"markable" andNamespace:@"urn:xmpp:chat-markers:0"]];
    }

    //for MAM
    [messageNode setStoreHint];

    [self send:messageNode];
}

-(void) sendChatState:(BOOL) isTyping toJid:(NSString*) jid
{
    if(self.accountState < kStateBound)
        return;

    XMPPMessage* messageNode = [[XMPPMessage alloc] init];
    [messageNode.attributes setObject:jid forKey:@"to"];
    [messageNode setNoStoreHint];
    if(isTyping)
    {
        MLXMLNode* chatstate = [[MLXMLNode alloc] initWithElement:@"composing" andNamespace:@"http://jabber.org/protocol/chatstates"];
        [messageNode addChild:chatstate];
    }
    else
    {
        MLXMLNode* chatstate = [[MLXMLNode alloc] initWithElement:@"active" andNamespace:@"http://jabber.org/protocol/chatstates"];
        [messageNode addChild:chatstate];
    }
    [self send:messageNode];
}

#pragma mark set connection attributes

-(void) persistState
{
    @synchronized(_stateLockObject) {
        //state dictionary
        NSMutableDictionary* values = [[NSMutableDictionary alloc] init];

        //collect smacks state
        [values setValue:self.lastHandledInboundStanza forKey:@"lastHandledInboundStanza"];
        [values setValue:self.lastHandledOutboundStanza forKey:@"lastHandledOutboundStanza"];
        [values setValue:self.lastOutboundStanza forKey:@"lastOutboundStanza"];
        [values setValue:[self.unAckedStanzas copy] forKey:@"unAckedStanzas"];
        [values setValue:self.streamID forKey:@"streamID"];

        NSMutableDictionary* persistentIqHandlers = [[NSMutableDictionary alloc] init];
        @synchronized(_iqHandlers) {
            [_iqHandlers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                NSString* id = (NSString*)key;
                NSDictionary* data = (NSDictionary*)obj;
                //only serialize persistent handlers with delegate and method
                if(data[@"delegate"] && data[@"method"])
                {
                    DDLogVerbose(@"saving serialized iq handler for iq '%@'", id);
                    [persistentIqHandlers setObject:data forKey:id];
                }
            }];
        }
        [values setObject:persistentIqHandlers forKey:@"iqHandlers"];

        [values setValue:[self.connectionProperties.serverFeatures copy] forKey:@"serverFeatures"];
        if(self.connectionProperties.uploadServer)
            [values setObject:self.connectionProperties.uploadServer forKey:@"uploadServer"];
        if(self.connectionProperties.conferenceServer)
            [values setObject:self.connectionProperties.conferenceServer forKey:@"conferenceServer"];
        
        [values setObject:[self.pubsub getInternalData] forKey:@"pubsubData"];
        [values setObject:[NSNumber numberWithBool:_loggedInOnce] forKey:@"loggedInOnce"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.usingCarbons2] forKey:@"usingCarbons2"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPush] forKey:@"supportsPush"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.pushEnabled] forKey:@"pushEnabled"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsClientState] forKey:@"supportsClientState"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsMam2] forKey:@"supportsMAM"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPubSub] forKey:@"supportsPubSub"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsHTTPUpload] forKey:@"supportsHTTPUpload"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPing] forKey:@"supportsPing"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsRosterPreApproval] forKey:@"supportsRosterPreApproval"];
        
        if(self.connectionProperties.discoveredServices)
            [values setObject:[self.connectionProperties.discoveredServices copy] forKey:@"discoveredServices"];

        [values setObject:_lastInteractionDate forKey:@"lastInteractionDate"];
        [values setValue:[NSDate date] forKey:@"stateSavedAt"];

        //save state dictionary
        [[DataLayer sharedInstance] persistState:values forAccount:self.accountNo];

        //debug output
        DDLogVerbose(@"persistState(saved at %@):\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@\n\tlastInteractionDate=%@\n\tpersistentIqHandlers=%@\n\tsupportsPush=%d\n\tsupportsHttpUpload=%d\n\tpushEnabled=%d\n\tsupportsPubSub=%d",
            values[@"stateSavedAt"],
            self.lastHandledInboundStanza,
            self.lastHandledOutboundStanza,
            self.lastOutboundStanza,
            self.unAckedStanzas ? [self.unAckedStanzas count] : 0, self.unAckedStanzas ? "" : " (NIL)",
            self.streamID,
            _lastInteractionDate,
            persistentIqHandlers,
            self.connectionProperties.supportsPush,
            self.connectionProperties.supportsHTTPUpload,
            self.connectionProperties.pushEnabled,
            self.connectionProperties.supportsPubSub
        );
    }
}

-(void) readSmacksStateOnly
{
    @synchronized(_stateLockObject) {
        NSMutableDictionary* dic = [[DataLayer sharedInstance] readStateForAccount:self.accountNo];
        if(dic)
        {
            //collect smacks state
            self.lastHandledInboundStanza = [dic objectForKey:@"lastHandledInboundStanza"];
            self.lastHandledOutboundStanza = [dic objectForKey:@"lastHandledOutboundStanza"];
            self.lastOutboundStanza = [dic objectForKey:@"lastOutboundStanza"];
            NSArray* stanzas = [dic objectForKey:@"unAckedStanzas"];
            self.unAckedStanzas = [stanzas mutableCopy];
            self.streamID = [dic objectForKey:@"streamID"];
            
            //debug output
            DDLogVerbose(@"readSmacksStateOnly(saved at %@):\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@,\n\tlastInteractionDate=%@",
                dic[@"stateSavedAt"],
                self.lastHandledInboundStanza,
                self.lastHandledOutboundStanza,
                self.lastOutboundStanza,
                self.unAckedStanzas ? [self.unAckedStanzas count] : 0, self.unAckedStanzas ? "" : " (NIL)",
                self.streamID,
                _lastInteractionDate
            );
            if(self.unAckedStanzas)
                for(NSDictionary* dic in self.unAckedStanzas)
                    DDLogDebug(@"readSmacksStateOnly unAckedStanza %@: %@", [dic objectForKey:kQueueID], [dic objectForKey:kStanza]);
            
        }
        //always reset handler and smacksRequestInFlight when loading smacks state
        _smacksAckHandler = [[NSMutableArray alloc] init];
        self.smacksRequestInFlight = NO;
    }
}

-(void) readState
{
    @synchronized(_stateLockObject) {
        NSMutableDictionary* dic = [[DataLayer sharedInstance] readStateForAccount:self.accountNo];
        if(dic)
        {
            //collect smacks state
            self.lastHandledInboundStanza = [dic objectForKey:@"lastHandledInboundStanza"];
            self.lastHandledOutboundStanza = [dic objectForKey:@"lastHandledOutboundStanza"];
            self.lastOutboundStanza = [dic objectForKey:@"lastOutboundStanza"];
            NSArray* stanzas = [dic objectForKey:@"unAckedStanzas"];
            self.unAckedStanzas = [stanzas mutableCopy];
            self.streamID = [dic objectForKey:@"streamID"];
            
            NSDictionary* persistentIqHandlers = [dic objectForKey:@"iqHandlers"];
            @synchronized(_iqHandlers) {
                [persistentIqHandlers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                    NSString* id = (NSString*)key;
                    NSDictionary* data = (NSDictionary*)obj;
                    DDLogWarn(@"Reading serialized iq handler for iq id '%@': [%@ %@]", id, data[@"delegate"], data[@"method"]);
                    [_iqHandlers setObject:data forKey:id];
                }];
            }
            
            self.connectionProperties.serverFeatures = [dic objectForKey:@"serverFeatures"];
            self.connectionProperties.discoveredServices = [dic objectForKey:@"discoveredServices"];
            
            self.connectionProperties.uploadServer = [dic objectForKey:@"uploadServer"];
            self.connectionProperties.conferenceServer = [dic objectForKey:@"conferenceServer"];
            
            if([dic objectForKey:@"loggedInOnce"])
            {
                NSNumber* loggedInOnce = [dic objectForKey:@"loggedInOnce"];
                _loggedInOnce = loggedInOnce.boolValue;
            }
            
            if([dic objectForKey:@"usingCarbons2"])
            {
                NSNumber* carbonsNumber = [dic objectForKey:@"usingCarbons2"];
                self.connectionProperties.usingCarbons2 = carbonsNumber.boolValue;
            }
            
            if([dic objectForKey:@"supportsPush"])
            {
                NSNumber* pushNumber = [dic objectForKey:@"supportsPush"];
                self.connectionProperties.supportsPush = pushNumber.boolValue;
            }
            
            if([dic objectForKey:@"pushEnabled"])
            {
                NSNumber* pushEnabled = [dic objectForKey:@"pushEnabled"];
                self.connectionProperties.pushEnabled = pushEnabled.boolValue;
            }
            
            if([dic objectForKey:@"supportsClientState"])
            {
                NSNumber* csiNumber = [dic objectForKey:@"supportsClientState"];
                self.connectionProperties.supportsClientState = csiNumber.boolValue;
            }
            
            if([dic objectForKey:@"supportsMAM"])
            {
                NSNumber* mamNumber = [dic objectForKey:@"supportsMAM"];
                self.connectionProperties.supportsMam2 = mamNumber.boolValue;
            }
            
            if([dic objectForKey:@"supportsPubSub"])
            {
                NSNumber* supportsPubSub = [dic objectForKey:@"supportsPubSub"];
                self.connectionProperties.supportsPubSub = supportsPubSub.boolValue;
            }
            
            if([dic objectForKey:@"supportsHTTPUpload"])
            {
                NSNumber* supportsHTTPUpload = [dic objectForKey:@"supportsHTTPUpload"];
                self.connectionProperties.supportsHTTPUpload = supportsHTTPUpload.boolValue;
            }
            
            if([dic objectForKey:@"supportsPing"])
            {
                NSNumber* supportsPing = [dic objectForKey:@"supportsPing"];
                self.connectionProperties.supportsPing = supportsPing.boolValue;
            }
            
            if([dic objectForKey:@"lastInteractionDate"])
                _lastInteractionDate = [dic objectForKey:@"lastInteractionDate"];
            
            if([dic objectForKey:@"supportsRosterPreApproval"])
            {
                NSNumber* supportsRosterPreApproval = [dic objectForKey:@"supportsRosterPreApproval"];
                self.connectionProperties.supportsRosterPreApproval = supportsRosterPreApproval.boolValue;
            }
            
            if([dic objectForKey:@"pubsubData"])
                [self.pubsub setInternalData:[dic objectForKey:@"pubsubData"]];
            
            //debug output
            DDLogVerbose(@"readState(saved at %@):\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@,\n\tlastInteractionDate=%@\n\tpersistentIqHandlers=%@\n\tsupportsPush=%d\n\tsupportsHttpUpload=%d\n\tpushEnabled=%d\n\tsupportsPubSub=%d",
                dic[@"stateSavedAt"],
                self.lastHandledInboundStanza,
                self.lastHandledOutboundStanza,
                self.lastOutboundStanza,
                self.unAckedStanzas ? [self.unAckedStanzas count] : 0, self.unAckedStanzas ? "" : " (NIL)",
                self.streamID,
                _lastInteractionDate,
                persistentIqHandlers,
                self.connectionProperties.supportsPush,
                self.connectionProperties.supportsHTTPUpload,
                self.connectionProperties.pushEnabled,
                self.connectionProperties.supportsPubSub
            );
            if(self.unAckedStanzas)
                for(NSDictionary* dic in self.unAckedStanzas)
                    DDLogDebug(@"readState unAckedStanza %@: %@", [dic objectForKey:kQueueID], [dic objectForKey:kStanza]);
        }
        
        //always reset handler and smacksRequestInFlight when loading smacks state
        _smacksAckHandler = [[NSMutableArray alloc] init];
        self.smacksRequestInFlight = NO;
    }
}

-(void) incrementLastHandledStanza
{
    @synchronized(_stateLockObject) {
        if(self.connectionProperties.supportsSM3)
        {
            //this will count any stanza between our bind result and smacks enable result but gets reset to sane values
            //once the smacks enable result surfaces (e.g. the wrong counting will be ignored later)
            if(self.accountState>=kStateBound)
                self.lastHandledInboundStanza = [NSNumber numberWithInteger:[self.lastHandledInboundStanza integerValue] + 1];
        }
        [self persistState];        //make sure we persist our state, even if smacks is not supported
    }
}

-(void) initSM3
{
    //initialize smacks state
    @synchronized(_stateLockObject) {
        self.lastHandledInboundStanza = [NSNumber numberWithInteger:0];
        self.lastHandledOutboundStanza = [NSNumber numberWithInteger:0];
        self.lastOutboundStanza = [NSNumber numberWithInteger:0];
        self.unAckedStanzas = [[NSMutableArray alloc] init];
        self.streamID = nil;
        _smacksAckHandler = [[NSMutableArray alloc] init];
        DDLogDebug(@"initSM3 done");
    }
}

-(void) bindResource:(NSString*) resource
{
    _accountState = kStateBinding;
    XMPPIQ* iqNode =[[XMPPIQ alloc] initWithType:kiqSetType];
    [iqNode setBindWithResource:resource];
    [self sendIq:iqNode withDelegate:[MLIQProcessor class] andMethod:@selector(handleBindFor:withIqNode:) andAdditionalArguments:nil];
}

-(void) queryDisco
{
    XMPPIQ* accountInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
    [accountInfo setiqTo:self.connectionProperties.identity.jid];
    [accountInfo setDiscoInfoNode];
    [self sendIq:accountInfo withDelegate:[MLIQProcessor class] andMethod:@selector(handleAccountDiscoInfo:withIqNode:) andAdditionalArguments:nil];
    
    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoInfo setiqTo:self.connectionProperties.identity.domain];
    [discoInfo setDiscoInfoNode];
    [self sendIq:discoInfo withDelegate:[MLIQProcessor class] andMethod:@selector(handleServerDiscoInfo:withIqNode:) andAdditionalArguments:nil];
    
    XMPPIQ* discoItems = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoItems setiqTo:self.connectionProperties.identity.domain];
    [discoItems setDiscoItemNode];
    [self sendIq:discoItems withDelegate:[MLIQProcessor class] andMethod:@selector(handleServerDiscoItems:withIqNode:) andAdditionalArguments:nil];
}

-(void) sendPresence
{
    //don't send presences if we are not bound
    if(_accountState < kStateBound)
        return;
    
    XMPPPresence* presence = [[XMPPPresence alloc] initWithHash:_capsHash];
    if(self.statusMessage)
        [presence setStatus:self.statusMessage];
    if(self.awayState)
        [presence setAway];
    
    //send last interaction date if not currently active
    //and the user prefers to send out lastInteraction date
    if(!_isCSIActive && self.sendIdleNotifications)
        [presence setLastInteraction:_lastInteractionDate];
    
    [self send:presence];
}

-(void) fetchRoster
{
    XMPPIQ* roster = [[XMPPIQ alloc] initWithType:kiqGetType];
    NSString* rosterVer;
    if(self.connectionProperties.supportsRosterVersion)
        rosterVer = [[DataLayer sharedInstance] getRosterVersionForAccount:self.accountNo];
    [roster setRosterRequest:rosterVer];
    [self sendIq:roster withDelegate:[MLIQProcessor class] andMethod:@selector(handleRosterFor:withIqNode:) andAdditionalArguments:nil];
}

-(void) initSession
{
    //delete old resources because we get new presences once we're done initializing the session
    [[DataLayer sharedInstance] resetContactsForAccount:self.accountNo];
    
    //we are now bound
    _accountState = kStateBound;
    _connectedTime = [NSDate date];
    NSDictionary* dic = @{@"AccountNo":self.accountNo, @"AccountName": self.connectionProperties.identity.jid};
    [[NSNotificationCenter defaultCenter] postNotificationName:kMLHasConnectedNotice object:dic];
    [self accountStatusChanged];
    _usableServersList = [[NSMutableArray alloc] init]; //reset list to start again with the highest SRV priority on next connect
    _exponentialBackoff = 0;
    
    //inform all old iq handlers of invalidation and clear _iqHandlers dictionary afterwards
    [_iqHandlers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        NSString* iqid = (NSString*)key;
        NSDictionary* data = (NSDictionary*)obj;
        DDLogWarn(@"Invalidating iq handler for iq id '%@'", iqid);
        if(data[@"errorHandler"])
            ((monal_iq_handler_t)data[@"errorHandler"])(nil);
        else if(data[@"delegate"] && data[@"invalidationMethod"])
        {
            DDLogVerbose(@"Calling IQHandler invalidation method [%@ %@]...", data[@"delegate"], data[@"invalidationMethod"]);
            [HelperTools callStaticHandler:@{
                @"delegate": data[@"delegate"],
                @"method": data[@"invalidationMethod"],
                @"arguments": data[@"arguments"] ? data[@"arguments"] : @[]
            } withDefaultArguments:@[self]];
        }
    }];
    _iqHandlers = [[NSMutableDictionary alloc] init];

    //force new disco queries because we landed here because of a failed smacks resume
    //(or the account got forcibly disconnected/reconnected or this is the very first login of this account)
    //--> all of this reasons imply that we had to start a new xmpp stream and our old cached disco data
    //    and other state values are stale now
    //(smacks state will be reset/cleared later on if appropriate, no need to handle smacks here)
    self.connectionProperties.serverFeatures = nil;
    self.connectionProperties.discoveredServices = nil;
    self.connectionProperties.uploadServer = nil;
    self.connectionProperties.conferenceServer = nil;
    self.connectionProperties.usingCarbons2 = NO;
    self.connectionProperties.supportsPush = NO;
    self.connectionProperties.pushEnabled = NO;
    self.connectionProperties.supportsClientState = NO;
    self.connectionProperties.supportsMam2 = NO;
    self.connectionProperties.supportsPubSub = NO;
    self.connectionProperties.supportsHTTPUpload = NO;
    self.connectionProperties.supportsPing = NO;
    self.connectionProperties.supportsRosterPreApproval = NO;

    //now fetch roster, request disco and send initial presence
    [self fetchRoster];
    //query disco *before* sending out our first presence because this presence will trigger pubsub "headline" updates and we want to know
    //if and what pubsub features the server supports, before handling that
    [self queryDisco];
    [self sendPresence];
    [self sendCurrentCSIState];
    
    //only do this if smacks is not supported because handling of the old queue will be already done on smacks enable/failed enable
    if(!self.connectionProperties.supportsSM3)
    {
        //resend stanzas still in the outgoing queue and clear it afterwards
        //this happens if the server has internal problems and advertises smacks support
        //but fails to resume the stream as well as to enable smacks on the new stream
        //clean up those stanzas to only include message stanzas because iqs don't survive a session change
        //message duplicates are possible in this scenario, but that's better than dropping messages
        //initSession() above does not add message stanzas to the self.unAckedStanzas queue --> this is safe to do
        [self resendUnackedMessageStanzasOnly:self.unAckedStanzas];
    }
    
    //mam query will be done in MLIQProcessor once the disco result returns
    
#ifndef DISABLE_OMEMO
    [self.omemo sendOMEMOBundle];
#endif
}

-(void) setStatusMessageText:(NSString*) message
{
    if(message && [message length] > 0)
        self.statusMessage = message;
    else
        message = nil;
    [self sendPresence];
}

-(void) setAway:(BOOL) away
{
    self.awayState = away;
    [self sendPresence];
}

-(void) setBlocked:(BOOL) blocked forJid:(NSString* _Nonnull) blockedJid
{
    XMPPIQ* iqBlocked= [[XMPPIQ alloc] initWithType:kiqSetType];
  
    [iqBlocked setBlocked:blocked forJid:blockedJid];
   
    [self send:iqBlocked];
}

#pragma mark vcard

-(void)getEntitySoftWareVersion:(NSString *) user
{
    NSArray *userDataArr = [user componentsSeparatedByString:@"/"];
    NSString *userWithoutResources = userDataArr[0];
    
    if ([[DataLayer sharedInstance] checkCap:@"jabber:iq:version" forUser:userWithoutResources andAccountNo:self.accountNo]) {
        XMPPIQ* iqEntitySoftWareVersion= [[XMPPIQ alloc] initWithType:kiqGetType];
        [iqEntitySoftWareVersion getEntitySoftWareVersionTo:user];
        [self send:iqEntitySoftWareVersion];
    }
}

#pragma mark HTTP upload

-(void) requestHTTPSlotWithParams:(NSDictionary*) params andCompletion:(void(^)(NSString* url, NSError* error)) completion
{
    XMPPIQ* httpSlotRequest = [[XMPPIQ alloc] initWithType:kiqGetType];
    [httpSlotRequest setiqTo:self.connectionProperties.uploadServer];
    [httpSlotRequest
        httpUploadforFile:[params objectForKey:kFileName]
        ofSize:[NSNumber numberWithInteger:((NSData*)[params objectForKey:kData]).length]
        andContentType:[params objectForKey:kContentType]
    ];
    [self sendIq:httpSlotRequest withResponseHandler:^(XMPPIQ* response) {
        DDLogInfo(@"Got slot for upload: %@", [response findFirst:@"{urn:xmpp:http:upload:0}slot/put@url"]);
        //upload to server using HTTP PUT
        NSMutableDictionary* headers = [[NSMutableDictionary alloc] init];
        headers[@"Content-Type"] = [params objectForKey:kContentType];
        for(MLXMLNode* header in [response find:@"{urn:xmpp:http:upload:0}slot/put/header"])
            headers[[header findFirst:@"/@name"]] = [header findFirst:@"/#"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [MLHTTPRequest
                sendWithVerb:kPut path:[response findFirst:@"{urn:xmpp:http:upload:0}slot/put@url"]
                headers:headers
                withArguments:nil
                data:[params objectForKey:kData]
                andCompletionHandler:^(NSError *error, id result) {
                    if(!error)
                    {
                        DDLogInfo(@"Upload succeded, get url: %@", [response findFirst:@"{urn:xmpp:http:upload:0}slot/get@url"]);
                        //send get url to contact
                        if(completion)
                            completion([response findFirst:@"{urn:xmpp:http:upload:0}slot/get@url"], nil);
                    }
                    else
                    {
                        DDLogInfo(@"Upload failed, error: %@", error);
                        if(completion)
                            completion(nil, error);
                    }
                }
            ];
        });
    } andErrorHandler:^(XMPPIQ* error) {
        if(completion)
            completion(nil, [error findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}text#"]);
    }];
}

#pragma mark client state
-(void) setClientActive
{
    [self dispatchAsyncOnReceiveQueue: ^{
        //ignore active --> active transition
        if(_isCSIActive)
        {
            DDLogVerbose(@"Ignoring CSI transition from active to active");
            return;
        }
        
        //record new csi state and send csi nonza
        _isCSIActive = YES;
        [self sendCurrentCSIState];
        
        //to make sure this date is newer than the old saved one (even if we now falsely "tag" the beginning of our interaction, not the end)
        //if everything works out as it should and the app does not get killed, we will "tag" the end of our interaction as soon as the app is backgrounded
        [self readState];       //make sure we operate on the newest state (appex could have changed it!)
        _lastInteractionDate = [NSDate date];
        [self persistState];
        
        //this will broadcast our presence without idle element, because of _isCSIActive=YES
        //(presence without idle indicates the client is now active, see XEP-0319)
        if(self.sendIdleNotifications)
            [self sendPresence];
    }];
}

-(void) setClientInactive
{
    [self dispatchAsyncOnReceiveQueue: ^{
        //ignore inactive --> inactive transition
        if(!_isCSIActive)
        {
            DDLogVerbose(@"Ignoring CSI transition from INactive to INactive");
            return;
        }
        
        //save date as last interaction date (XEP-0319) (e.g. "tag" the end of our interaction)
        [self readState];       //make sure we operate on the newest state (appex could have changed it!)
        _lastInteractionDate = [NSDate date];
        [self persistState];
        
        //record new state
        _isCSIActive = NO;
        
        //this will broadcast our presence with idle element set, because of _isCSIActive=NO (see XEP-0319)
        if(self.sendIdleNotifications)
            [self sendPresence];
        
        //send csi inactive nonza *after* broadcasting our presence
        [self sendCurrentCSIState];
        
        //proactively send smacks ACK to make sure the server knows what stanzas have been received and processed by us
        //even if the time after going into the background shortly after receiving a stanza may be too short for the server
        //to request an ack and for us to process and answer this request before apple freezes us
        [self sendSMAck:YES];
    }];
}

-(void) sendCurrentCSIState
{
    [self dispatchOnReceiveQueue: ^{
        //don't send anything before a resource is bound
        if(self.accountState<kStateBound || !self.connectionProperties.supportsClientState)
            return;
        
        //really send csi nonza
        MLXMLNode* csiNode;
        if(_isCSIActive)
            csiNode = [[MLXMLNode alloc] initWithElement:@"active" andNamespace:@"urn:xmpp:csi:0"];
        else
            csiNode = [[MLXMLNode alloc] initWithElement:@"inactive" andNamespace:@"urn:xmpp:csi:0"];
        [self send:csiNode];
    }];
}

#pragma mark - Message archive


-(void) setMAMPrefs:(NSString *) preference
{
    if(!self.connectionProperties.supportsMam2)
        return;
    XMPPIQ* query = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
    [query updateMamArchivePrefDefault:preference];
    [self send:query];
}

-(void) getMAMPrefs
{
    XMPPIQ* query = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqGetType];
    [query mamArchivePref];
    //this can be a non persistent iq handler because getMAMPrefs is only called from the ui
    //THIS HAS TO BE CHANGED IF THIS METHOD IS CALLED FROM OTHER MORE PERSISTENT PLACES
    [self sendIq:query withResponseHandler:^(XMPPIQ* response) {
        if([response check:@"{urn:xmpp:mam:2}prefs@default"])
            [[NSNotificationCenter defaultCenter] postNotificationName:kMLMAMPref object:@{@"mamPref": [response findFirst:@"{urn:xmpp:mam:2}prefs@default"]}];
        else
            DDLogError(@"MAM prefs query returned unexpected result: %@", response);
    } andErrorHandler:^(XMPPIQ* error) {
        DDLogError(@"MAM prefs query returned an error: %@", error);
    }];
}

-(void) setMAMQueryMostRecentForJid:(NSString*) jid before:(NSString*) uid withCompletion:(void (^)(NSArray* _Nullable)) completion
{
    NSMutableArray* __block messageList = [[NSMutableArray alloc] init];
    monal_iq_handler_t __block responseHandler;
    __block void (^query)(NSString* before);
    responseHandler = ^(XMPPIQ* response) {
        //insert messages having a body into the db and check if they are alread in there
        for(MLMessage* msg in [self getOrderedMamPageFor:[response findFirst:@"{urn:xmpp:mam:2}fin@queryid"]])
            if(msg.messageText)
                [[DataLayer sharedInstance] addMessageFrom:msg.from
                                                        to:msg.to
                                                forAccount:self.accountNo
                                                  withBody:msg.messageText
                                              actuallyfrom:msg.actualFrom
                                                      sent:YES              //old history messages have always been sent (they are coming from the server)
                                                    unread:NO               //old history messages have always been read (we don't want to show them as new)
                                                 messageId:msg.messageId
                                           serverMessageId:msg.stanzaId
                                               messageType:msg.messageType
                                           andOverrideDate:msg.delayTimeStamp
                                                 encrypted:msg.encrypted
                                                 backwards:YES
                                       displayMarkerWanted:NO
                                            withCompletion:^(BOOL success, NSString* newMessageType, NSNumber* historyId) {
                    //add successfully added messages to our display list
                    if(success)
                        [messageList addObject:msg];
                }];
        DDLogVerbose(@"collected mam:2 before-pages now contain %lu messages in summary not already in history", (unsigned long)[messageList count]);
        //call completion to display all messages saved in db if we have enough messages or reached end of mam archive
        if([messageList count] >= 25)
            completion(messageList);
        else
        {
            //page through to get more messages (a page possibly contians fewer than 25 messages having a body)
            //but because we query for 50 stanzas we easily could get more than 25 messages having a body, too
            if(
                ![response findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] &&
                [response check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/first#"]
            )
            {
                query([response findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/first#"]);
            }
            else
            {
                DDLogVerbose(@"Reached upper end of mam:2 archive, returning %lu messages to ui", (unsigned long)[messageList count]);
                completion(messageList);    //can be fewer than 25 messages because we reached the upper end of the mam archive
            }
        }
    };
    query = ^(NSString* before) {
        DDLogVerbose(@"Loading (next) mam:2 page before: %@", before);
        XMPPIQ* query = [[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
        [query setMAMQueryLatestMessagesForJid:jid before:before];
        //we always want to use blocks here because we want to make sure we get not interrupted by an app crash/restart
        //which would make us use incomplete mam pages that would produce holes in history (those are very hard to remove/fill afterwards)
        [self sendIq:query withResponseHandler:responseHandler andErrorHandler:^(XMPPIQ* error) {
            DDLogWarn(@"Got mam:2 before-query error, returning %lu messages to ui", (unsigned long)[messageList count]);
            if(![messageList count])
                completion(nil);            //call completion with nil, if there was an error or xmpp reconnect that prevented us to get any messages
            else
                completion(messageList);    //we had an error but did already load some messages --> update ui anyways
        }];
    };
    query(uid);
}

#pragma mark - MUC

-(void) joinRoom:(NSString*)room withNick:(NSString*)nick andPassword:(NSString *)password
{
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    NSArray* parts =[room componentsSeparatedByString:@"@"];
    if([parts count]>1)
    {
        [presence joinRoom:[parts objectAtIndex:0] withPassword:password onServer:[parts objectAtIndex:1] withName:nick];
    }
    else{
        [presence joinRoom:room withPassword:password onServer:self.connectionProperties.conferenceServer withName:nick];
    }
    [self send:presence];
}

-(void) leaveRoom:(NSString*) room withNick:(NSString *) nick
{
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    [presence leaveRoom:room onServer:nil withName:nick];
    [self send:presence];
}


#pragma mark- XMPP add and remove contact
-(void) removeFromRoster:(NSString*) contact
{
    XMPPIQ* iq = [[XMPPIQ alloc] initWithType:kiqSetType];
    [iq setRemoveFromRoster:contact];
    [self send:iq];

    XMPPPresence* presence =[[XMPPPresence alloc] init];
    [presence unsubscribeContact:contact];
    [self send:presence];

}

-(void) rejectFromRoster:(NSString*) contact
{
    XMPPPresence* presence2 =[[XMPPPresence alloc] init];
    [presence2 unsubscribedContact:contact];
    [self send:presence2];
}


-(void) addToRoster:(NSString*) contact
{
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    [presence subscribeContact:contact];
    [self send:presence]; //add them

}

-(void) approveToRoster:(NSString*) contact
{
    XMPPPresence* presence2 =[[XMPPPresence alloc] init];
    [presence2 subscribedContact:contact];
    [self send:presence2];
}

-(void) updateRosterItem:(NSString*) jid withName:(NSString*) name
{
    XMPPIQ* roster = [[XMPPIQ alloc] initWithType:kiqSetType];
    [roster setUpdateRosterItem:jid withName:name];
    //this delegate will handle errors (result responses don't include any data that could be processed and will be ignored)
    [self sendIq:roster withDelegate:[MLIQProcessor class] andMethod:@selector(handleRosterFor:withIqNode:) andAdditionalArguments:nil];
}

#pragma mark - Jingle calls
-(void)call:(MLContact*) contact
{
    if(self.jingle) return;
    self.jingle=[[jingleCall alloc] init];
    self.jingle.me=[NSString stringWithFormat:@"%@/%@", self.connectionProperties.identity.jid, self.connectionProperties.identity.resource];

    NSArray* resources= [[DataLayer sharedInstance] resourcesForContact:contact.contactJid];
    if([resources count]>0)
    {
        //TODO selct resource action sheet?
        XMPPIQ* jingleiq =[self.jingle initiateJingleTo:contact.contactJid withId:[[NSUUID UUID] UUIDString] andResource:[[resources objectAtIndex:0] objectForKey:@"resource"]];
        [self send:jingleiq];
    }
}

-(void)hangup:(MLContact*) contact
{
    XMPPIQ* jingleiq =[self.jingle terminateJinglewithId:[[NSUUID UUID] UUIDString]];
    [self send:jingleiq];
    [self.jingle rtpDisconnect];
    self.jingle=nil;
}

-(void)acceptCall:(NSDictionary*) userInfo
{
    XMPPIQ* node =[self.jingle acceptJingleTo:[userInfo objectForKey:@"user"] withId:[[NSUUID UUID] UUIDString]  andResource:[userInfo objectForKey:@"resource"]];
    [self send:node];
}


-(void)declineCall:(NSDictionary*) userInfo
{
    XMPPIQ* jingleiq =[self.jingle rejectJingleTo:[userInfo objectForKey:@"user"] withId:[[NSUUID UUID] UUIDString] andResource:[userInfo objectForKey:@"resource"]];
    [self send:jingleiq];
    [self.jingle rtpDisconnect];
    self.jingle=nil;
}

-(void) jingleResult:(XMPPIQ*) iqNode
{
    //confirmation of set call after we accepted
    if([[iqNode findFirst:@"/@id"] isEqualToString:self.jingle.idval])
    {
        NSString* from = iqNode.fromUser;
        NSString* fullName = from;
        if(!fullName) fullName = from;
        NSDictionary* userDic=@{@"buddy_name":from,
                                @"full_name":fullName,
                                kAccountID:self.accountNo
        };
        [[NSNotificationCenter defaultCenter]
         postNotificationName: kMonalCallStartedNotice object: userDic];

        [self.jingle rtpConnect];
        return;
    }

}


-(void) processJingleSetIq:(XMPPIQ*) iqNode
{
/*
 * TODO fix for new parser
    if ([iqNode.type isEqualToString:kiqSetType]) {
        if(iqNode.jingleSession) {

            //accpetance of our call
            if([[iqNode.jingleSession objectForKey:@"action"] isEqualToString:@"session-accept"] &&
               [[iqNode.jingleSession objectForKey:@"sid"] isEqualToString:self.jingle.thesid])
            {

                NSDictionary* transport1;
                NSDictionary* transport2;
                for(NSDictionary* candidate in iqNode.jingleTransportCandidates) {
                    if([[candidate objectForKey:@"component"] isEqualToString:@"1"]) {
                        transport1=candidate;
                    }
                    if([[candidate objectForKey:@"component"] isEqualToString:@"2"]) {
                        transport2=candidate;
                    }
                }

                NSDictionary* pcmaPayload;
                for(NSDictionary* payload in iqNode.jinglePayloadTypes) {
                    if([[payload objectForKey:@"name"] isEqualToString:@"PCMA"]) {
                        pcmaPayload=payload;
                        break;
                    }
                }

                if (pcmaPayload && transport1) {
                    self.jingle.recipientIP=[transport1 objectForKey:@"ip"];
                    self.jingle.destinationPort= [transport1 objectForKey:@"port"];

                    XMPPIQ* node = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                    [node setiqTo:[NSString stringWithFormat:@"%@/%@", iqNode.user,iqNode.resource]];
                    [self send:node];

                    [self.jingle rtpConnect];
                }
                return;
            }

            if([[iqNode.jingleSession objectForKey:@"action"] isEqualToString:@"session-terminate"] &&  [[iqNode.jingleSession objectForKey:@"sid"] isEqualToString:self.jingle.thesid]) {
                XMPPIQ* node = [[XMPPIQ alloc] initWithId:iqNode.idval andType:kiqResultType];
                [node setiqTo:[NSString stringWithFormat:@"%@/%@", iqNode.user,iqNode.resource]];
                [self send:node];
                [self.jingle rtpDisconnect];
            }

            if([[iqNode.jingleSession objectForKey:@"action"] isEqualToString:@"session-initiate"]) {
                NSDictionary* pcmaPayload;
                for(NSDictionary* payload in iqNode.jinglePayloadTypes) {
                    if([[payload objectForKey:@"name"] isEqualToString:@"PCMA"]) {
                        pcmaPayload=payload;
                        break;
                    }
                }

                NSDictionary* transport1;
                NSDictionary* transport2;
                for(NSDictionary* candidate in iqNode.jingleTransportCandidates) {
                    if([[candidate objectForKey:@"component"] isEqualToString:@"1"]) {
                        transport1=candidate;
                    }
                    if([[candidate objectForKey:@"component"] isEqualToString:@"2"]) {
                        transport2=candidate;
                    }
                }

                if (pcmaPayload && transport1) {
                    self.jingle = [[jingleCall alloc] init];
                    self.jingle.initiator= [iqNode.jingleSession objectForKey:@"initiator"];
                    self.jingle.responder= [iqNode.jingleSession objectForKey:@"responder"];
                    if(!self.jingle.responder)
                    {
                        self.jingle.responder = [NSString stringWithFormat:@"%@/%@", iqNode.to, self.connectionProperties.boundJid];
                    }

                    self.jingle.thesid= [iqNode.jingleSession objectForKey:@"sid"];
                    self.jingle.destinationPort= [transport1 objectForKey:@"port"];
                    self.jingle.idval=iqNode.idval;
                    if(transport2) {
                        self.jingle.destinationPort2= [transport2 objectForKey:@"port"];
                    }
                    else {
                        self.jingle.destinationPort2=[transport1 objectForKey:@"port"]; // if nothing is provided just reuse..
                    }
                    self.jingle.recipientIP=[transport1 objectForKey:@"ip"];


                    if(iqNode.user && iqNode.resource && self.connectionProperties.identity.jid) {

                        NSDictionary *dic= @{@"from":iqNode.from,
                                             @"user":iqNode.user,
                                             @"resource":iqNode.resource,
                                             @"id": iqNode.idval,
                                             kAccountID:self.accountNo,
                                             @"account_name": self.connectionProperties.identity.jid
                        };

                        [[NSNotificationCenter defaultCenter]
                         postNotificationName: kMonalCallRequestNotice object: dic];

                    }
                }
                else {
                    //does not support the same formats
                }

            }
        }
    }
*/
}


#pragma mark - account management

-(void) changePassword:(NSString *) newPass withCompletion:(xmppCompletion) completion
{
    XMPPIQ* iq =[[XMPPIQ alloc] initWithType:kiqSetType];
    [iq setiqTo:self.connectionProperties.identity.domain];
    [iq changePasswordForUser:self.connectionProperties.identity.user newPassword:newPass];
    [self sendIq:iq withResponseHandler:^(XMPPIQ* response) {
        //dispatch completion handler outside of the receiveQueue
        if(completion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(YES, @"");
            });
    } andErrorHandler:^(XMPPIQ* error) {
        //dispatch completion handler outside of the receiveQueue
        if(completion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(NO, error && [error check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}text#"] ? [error findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}text#"]: @"");
            });
    }];
}

-(void) requestRegFormWithCompletion:(xmppDataCompletion) completion andErrorCompletion:(xmppCompletion) errorCompletion
{
    //this is a registration request
    _registration = YES;
    _regFormCompletion = completion;
    _regFormErrorCompletion = errorCompletion;
    [self connect];
}

-(void) registerUser:(NSString *) username withPassword:(NSString *) password captcha:(NSString *) captcha andHiddenFields:(NSDictionary *)hiddenFields withCompletion:(xmppCompletion) completion
{
    //this is a registration submission
    _registration = NO;
    _registrationSubmission = YES;
    self.regUser = username;
    self.regPass = password;
    self.regCode = captcha;
    self.regHidden = hiddenFields;
    _regFormSubmitCompletion = completion;
    [self connect];
}

-(void) requestRegForm
{
    XMPPIQ* iq = [[XMPPIQ alloc] initWithType:kiqGetType];
    [iq setiqTo:self.connectionProperties.identity.domain];
    [iq getRegistrationFields];

    [self sendIq:iq withResponseHandler:^(XMPPIQ* result) {
        //dispatch completion handler outside of the receiveQueue
        if(_regFormCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSMutableDictionary* hiddenFormFields = [[NSMutableDictionary alloc] init];
                for(MLXMLNode* field in [result find:@"{jabber:iq:register}query/{jabber:x:data}x<type=form>/field<type=hidden>"])
                    hiddenFormFields[[field findFirst:@"/@var"]] = [field findFirst:@"value#"];
                _regFormCompletion([result findFirst:@"{jabber:iq:register}query/{jabber:x:data}x<type=form>/{*}data"], hiddenFormFields);
            });
    } andErrorHandler:^(XMPPIQ* error) {
        //dispatch completion handler outside of the receiveQueue
        if(_regFormErrorCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                _regFormErrorCompletion(nil, nil);
            });
    }];
}

-(void) submitRegForm
{
    XMPPIQ* iq =[[XMPPIQ alloc] initWithType:kiqSetType];
    [iq registerUser:self.regUser withPassword:self.regPass captcha:self.regCode andHiddenFields:self.regHidden];

    [self sendIq:iq withResponseHandler:^(XMPPIQ* result) {
        //dispatch completion handler outside of the receiveQueue
        if(_regFormSubmitCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                _regFormSubmitCompletion(YES, nil);
            });
    } andErrorHandler:^(XMPPIQ* error) {
        //dispatch completion handler outside of the receiveQueue
        if(_regFormSubmitCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                _regFormSubmitCompletion(NO, [error findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}text#"]);
            });
    }];
}

#pragma mark - nsstream delegate

- (void)stream:(NSStream*) stream handleEvent:(NSStreamEvent) eventCode
{
    DDLogVerbose(@"Stream has event");
    switch(eventCode)
    {
        case NSStreamEventOpenCompleted:
        {
            DDLogVerbose(@"Stream open completed");
            break;
        }
        
        //for writing
        case NSStreamEventHasSpaceAvailable:
        {
            [_sendQueue addOperationWithBlock: ^{
                DDLogVerbose(@"Stream has space to write");
                self->_streamHasSpace=YES;
                [self writeFromQueue];
            }];
            break;
        }
        
        //for reading
        case  NSStreamEventHasBytesAvailable:
        {
            DDLogError(@"Stream has bytes to read (should not be called!)");
            break;
        }
        
        case NSStreamEventErrorOccurred:
        {
            NSError* st_error = [stream streamError];
            DDLogError(@"Stream error code=%ld domain=%@ local desc:%@",(long)st_error.code,st_error.domain,  st_error.localizedDescription);

            NSString *message = st_error.localizedDescription;

            switch(st_error.code)
            {
                case errSSLXCertChainInvalid: {
                    message = NSLocalizedString(@"SSL Error: Certificate chain is invalid",@ "");
                    break;
                }

                case errSSLUnknownRootCert: {
                    message = NSLocalizedString(@"SSL Error: Unknown root certificate",@ "");
                    break;
                }

                case errSSLCertExpired: {
                    message = NSLocalizedString(@"SSL Error: Certificate expired",@ "");
                    break;
                }

                case errSSLHostNameMismatch: {
                    message = NSLocalizedString(@"SSL Error: Host name mismatch",@ "");
                    break;
                }

            }
            if(!_registration)
            {
                // Do not show "Connection refused" message if there are more SRV records to try
                if(!_SRVDiscoveryDone || (_SRVDiscoveryDone && [_usableServersList count] == 0) || st_error.code != 61)
                    [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, message, st_error]];
            }

            DDLogInfo(@"stream error, calling reconnect");
            [self reconnect];
            
            break;
        }
        
        case NSStreamEventNone:
        {
            DDLogVerbose(@"Stream event none");
            break;
        }
        
        case NSStreamEventEndEncountered:
        {
            DDLogInfo(@"%@ Stream end encountered, trying to reconnect", [stream class]);
            [self reconnect];
            break;
        }
    }
}

#pragma mark network I/O

-(void) writeFromQueue
{
    if(!_streamHasSpace)
    {
        DDLogVerbose(@"no space to write. early return from writeFromQueue().");
        return;
    }
    if(![_outputQueue count])
    {
        DDLogVerbose(@"no entries in _outputQueue. early return from writeFromQueue().");
        return;
    }
    BOOL requestAck=NO;
    NSMutableArray *queueCopy = [[NSMutableArray alloc] initWithArray:_outputQueue];
    DDLogVerbose(@"iterating _outputQueue");
    for(MLXMLNode* node in queueCopy)
    {
        BOOL success = [self writeToStream:node.XMLString];
        if(success)
        {
            //only react to stanzas, not nonzas
            if([node.element isEqualToString:@"iq"]
                || [node.element isEqualToString:@"message"]
                || [node.element isEqualToString:@"presence"]) {
                requestAck=YES;
            }

            DDLogVerbose(@"removing sent MLXMLNode from _outputQueue");
            [_outputQueue removeObject:node];
        }
        else        //stop sending the remainder of the queue if the send failed (tcp output buffer full etc.)
        {
            DDLogInfo(@"could not send whole _outputQueue: tcp buffer full or connection has an error");
            break;
        }
    }

    if(requestAck)
    {
        //adding the smacks request to the parseQueue will make sure that we send the request
        //*after* processing an incoming burst of stanzas (which is potentially causing an outgoing burst of stanzas)
        //this reduces the requests to an absolute minimum while still maintaining the rule to request an ack
        //for every stanza (e.g. until the smacks queue is empty) and not sending an ack if one is already in flight
        if(_accountState>=kStateBound)
            [_parseQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                [self requestSMAck:NO];
            }]] waitUntilFinished:NO];
        else
            DDLogWarn(@"no xmpp resource bound, not calling requestSMAck");
    }
    else
        DDLogVerbose(@"NOT calling requestSMAck...");
}

-(BOOL) writeToStream:(NSString*) messageOut
{
    if(!messageOut) {
        DDLogInfo(@"tried to send empty message. returning without doing anything.");
        return YES;     //pretend we sent the empty "data"
    }
    if(!_streamHasSpace)
    {
        DDLogVerbose(@"no space to write. returning.");
        return NO;      //no space to write --> stanza has to remain in _outputQueue
    }
    if(!_oStream)
    {
        DDLogVerbose(@"no stream to write. returning.");
        return NO;		//no stream to write --> stanza has to remain in _outputQueue and get dropped later on
    }

    //try to send remaining buffered data first
    if(_outputBufferByteCount>0)
    {
        NSInteger sentLen=[_oStream write:_outputBuffer maxLength:_outputBufferByteCount];
        if(sentLen!=-1)
        {
            if(sentLen!=_outputBufferByteCount)		//some bytes remaining to send --> trim buffer and return NO
            {
                memmove(_outputBuffer, _outputBuffer+(size_t)sentLen, _outputBufferByteCount-(size_t)sentLen);
                _outputBufferByteCount-=sentLen;
                _streamHasSpace=NO;
                return NO;		//stanza has to remain in _outputQueue
            }
            else
            {
                //dealloc empty buffer
                free(_outputBuffer);
                _outputBuffer=nil;
                _outputBufferByteCount=0;		//everything sent
            }
        }
        else
        {
            NSError* error=[_oStream streamError];
            DDLogError(@"sending: failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self reconnect];
            });
            return NO;
        }
    }

    //then try to send the stanza in question and buffer half sent data
    const uint8_t *rawstring = (const uint8_t *)[messageOut UTF8String];
    NSInteger rawstringLen=strlen((char*)rawstring);
    NSInteger sentLen = [_oStream write:rawstring maxLength:rawstringLen];
    if(sentLen!=-1)
    {
        if(sentLen!=rawstringLen)
        {
            //allocate new _outputBuffer
            _outputBuffer=malloc(sizeof(uint8_t) * (rawstringLen-sentLen));
            //copy the remaining data into the buffer and set the buffer pointer accordingly
            memcpy(_outputBuffer, rawstring+(size_t)sentLen, (size_t)(rawstringLen-sentLen));
            _outputBufferByteCount=(size_t)(rawstringLen-sentLen);
            _streamHasSpace=NO;
        }
        else
            _outputBufferByteCount=0;
        return YES;
    }
    else
    {
        NSError* error=[_oStream streamError];
        DDLogError(@"sending: failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self reconnect];
        });
        return NO;
    }
}

#pragma mark misc

-(void) enablePush
{
    if(
        self.accountState >= kStateBound &&
        self.connectionProperties.supportsPush &&
        self.pushNode != nil && [self.pushNode length] > 0 &&
        self.pushSecret != nil && [self.pushSecret length] > 0
    )
    {
        DDLogInfo(@"ENABLING PUSH: %@ < %@", self.pushNode, self.pushSecret);
        XMPPIQ* enable =[[XMPPIQ alloc] initWithType:kiqSetType];
        [enable setPushEnableWithNode:self.pushNode andSecret:self.pushSecret];
        [self send:enable];
        self.connectionProperties.pushEnabled = YES;
    }
    else
    {
        DDLogInfo(@"NOT enabling push: %@ < %@ (accountState: %ld, supportsPush: %@)", self.pushNode, self.pushSecret, (long)self.accountState, self.connectionProperties.supportsPush ? @"YES" : @"NO");
    }
}

-(void) mamFinished
{
    if(!_catchupDone)
    {
        _catchupDone = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFinishedCatchup object:self];

    }
}

-(MLMessage*) parseMessageToMLMessage:(XMPPMessage*) messageNode withBody:(NSString*) body andEncrypted:(BOOL) encrypted andShowAlert:(BOOL) showAlert andMessageType:(NSString*) messageType andActualFrom:(NSString*) actualFrom
{
    MLMessage* message = [[MLMessage alloc] init];
    message.from = messageNode.fromUser;
    message.actualFrom = actualFrom ? actualFrom : messageNode.fromUser;
    message.messageText = [body copy];     //this need to be the processed value since it may be decrypted
    message.to = messageNode.to ? messageNode.to : self.connectionProperties.identity.jid;
    message.messageId = [messageNode check:@"/@id"] ? [messageNode findFirst:@"/@id"] : @"";
    message.accountId = self.accountNo;
    message.encrypted = encrypted;
    message.delayTimeStamp = [messageNode findFirst:@"{urn:xmpp:delay}delay@stamp|datetime"];
    message.timestamp = [NSDate date];
    message.shouldShowAlert = showAlert;
    message.messageType = messageType;
    message.hasBeenSent = YES;      //if it came in it has been sent to the server
    message.stanzaId = [messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@id"];
    message.displayMarkerWanted = [messageNode check:@"{urn:xmpp:chat-markers:0}markable"];
    return message;
}

-(void) addMessageToMamPageArray:(XMPPMessage* _Nonnull) messageNode forOuterMessageNode:(XMPPMessage* _Nonnull) outerMessageNode withBody:(NSString* _Nonnull) body andEncrypted:(BOOL) encrypted andShowAlert:(BOOL) showAlert andMessageType:(NSString* _Nonnull) messageType
{
    MLMessage* message = [self parseMessageToMLMessage:messageNode withBody:body andEncrypted:encrypted andShowAlert:showAlert andMessageType:messageType andActualFrom:nil];
    @synchronized(_mamPageArrays) {
        if(!_mamPageArrays[[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"]])
            _mamPageArrays[[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"]] = [[NSMutableArray alloc] init];
        [_mamPageArrays[[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"]] addObject:message];
    }
}

-(NSArray* _Nullable) getOrderedMamPageFor:(NSString* _Nonnull) mamQueryId
{
    NSArray* array;
    @synchronized(_mamPageArrays) {
        if(!_mamPageArrays[mamQueryId])
            return @[];     //return empty array if nothing can be found (after app crash etc.)
        array = [_mamPageArrays[mamQueryId] copy];          //this creates an unmutable array from the mutable one
        [_mamPageArrays removeObjectForKey:mamQueryId];
    }
    if([mamQueryId hasPrefix:@"MLhistory:"])
        array = [[array reverseObjectEnumerator] allObjects];
    return array;
}

+(void) avatarHandlerFor:(xmpp*) account withNode:(NSString*) node jid:(NSString*) jid type:(NSString*) type andData:(NSDictionary*) data
{
    DDLogDebug(@"Got new avatar metadata from '%@'", jid);
    for(NSString* entry in data)
    {
        NSString* avatarHash = [data[entry] findFirst:@"{urn:xmpp:avatar:metadata}metadata/info@id"];
        if(!avatarHash)     //the user disabled his avatar
        {
            DDLogInfo(@"User %@ disabled his avatar", jid);
            [[MLImageManager sharedInstance] setIconForContact:jid andAccount:account.accountNo WithData:nil];
            [[DataLayer sharedInstance] setAvatarHash:@"" forContact:jid andAccount:account.accountNo];
        }
        else
        {
            NSString* currentHash = [[DataLayer sharedInstance] getAvatarHashForContact:jid andAccount:account.accountNo];
            if(currentHash && [avatarHash isEqualToString:currentHash])
            {
                DDLogInfo(@"Avatar hash is the same, we don't need to update our avatar image data");
                break;
            }
            [account.pubsub fetchNode:@"urn:xmpp:avatar:data" from:jid withItemsList:@[avatarHash] andHandler:[HelperTools createStaticHandlerWithDelegate:self andMethod:@selector(handleAvatarFetchResultForAccount:andJid:withErrorIq:andData:) andAdditionalArguments:nil]];
        }
        break;      //we only want to process the first item (this should also be the only item)
    }
    if([data count] > 1)
        DDLogWarn(@"Got more than one avatar metadata item!");
}

+(void) handleAvatarFetchResultForAccount:(xmpp*) account andJid:(NSString*) jid withErrorIq:(XMPPIQ*) errorIq andData:(NSDictionary*) data
{
    //ignore errors here (e.g. simply don't update the avatar image)
    //(this should never happen if other clients and servers behave properly)
    if(errorIq)
    {
        DDLogError(@"Got avatar image fetch error from jid %@: %@", jid, errorIq);
        return;
    }
    
    for(NSString* avatarHash in data)
    {
        [[MLImageManager sharedInstance] setIconForContact:jid andAccount:account.accountNo WithData:[data[avatarHash] findFirst:@"{urn:xmpp:avatar:data}data#|base64"]];
        [[DataLayer sharedInstance] setAvatarHash:avatarHash forContact:jid andAccount:account.accountNo];
        [account accountStatusChanged];     //inform ui of this change (accountStatusChanged will force a ui reload which will also reload the avatars)
        DDLogInfo(@"Avatar of '%@' fetched and updated successfully", jid);
    }
}

-(void) sendDisplayMarkerForId:(NSString*) messageid to:(NSString*) to
{
    if(![[HelperTools defaultsDB] boolForKey:@"SendDisplayedMarkers"])
        return;
    
    XMPPMessage* displayedNode = [[XMPPMessage alloc] init];
    //the message type is needed so that the store hint is accepted by the server
    displayedNode.attributes[@"type"] = kMessageChatType;
    displayedNode.attributes[@"to"] = to;
    [displayedNode setDisplayed:messageid];
    [displayedNode setStoreHint];
    [self send:displayedNode];
}

+(void) rosterNameHandlerFor:(xmpp*) account withNode:(NSString*) node jid:(NSString*) jid type:(NSString*) type andData:(NSDictionary*) data
{
    //new/updated nickname
    if([type isEqualToString:@"publish"])
    {
        for(NSString* itemId in data)
        {
            if([jid isEqualToString:account.connectionProperties.identity.jid])        //own roster name
            {
                DDLogInfo(@"Got own nickname: %@", [data[itemId] findFirst:@"{http://jabber.org/protocol/nick}nick#"]);
                NSMutableDictionary* accountDic = [[NSMutableDictionary alloc] initWithDictionary:[[DataLayer sharedInstance] detailsForAccount:account.accountNo] copyItems:YES];
                accountDic[kRosterName] = [data[itemId] findFirst:@"{http://jabber.org/protocol/nick}nick#"];
                [[DataLayer sharedInstance] updateAccounWithDictionary:accountDic];
            }
            else                                                                    //roster name of contact
            {
                DDLogInfo(@"Got nickname of %@: %@", jid, [data[itemId] findFirst:@"{http://jabber.org/protocol/nick}nick#"]);
                [[DataLayer sharedInstance] setFullName:[data[itemId] findFirst:@"{http://jabber.org/protocol/nick}nick#"] forContact:jid andAccount:account.accountNo];
                MLContact* contact = [[DataLayer sharedInstance] contactForUsername:jid forAccount:account.accountNo];
                if(contact)     //ignore updates for jids not in our roster
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                        @"contact": contact
                    }];
            }
            break;      //we only need the first item (there should be only one item in the first place)
        }
    }
    //deleted/purged node or retracted item
    else
    {
        if([jid isEqualToString:account.connectionProperties.identity.jid])        //own roster name
        {
            DDLogInfo(@"Own nickname got retracted");
            NSMutableDictionary* accountDic = [[NSMutableDictionary alloc] initWithDictionary:[[DataLayer sharedInstance] detailsForAccount:account.accountNo] copyItems:NO];
            accountDic[kRosterName] = @"";
            [[DataLayer sharedInstance] updateAccounWithDictionary:accountDic];
        }
        else
        {
            DDLogInfo(@"Nickname of %@ got retracted", jid);
            [[DataLayer sharedInstance] setFullName:@"" forContact:jid andAccount:account.accountNo];
            MLContact* contact = [[DataLayer sharedInstance] contactForUsername:jid forAccount:account.accountNo];
            if(contact)     //ignore updates for jids not in our roster
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactRefresh object:account userInfo:@{
                    @"contact": contact
                }];
        }
    }
}

-(void) publishRosterName:(NSString* _Nullable) rosterName
{
    DDLogInfo(@"Publishing own nickname: %@", rosterName);
    if(!rosterName || !rosterName.length)
        [self.pubsub deleteNode:@"http://jabber.org/protocol/nick"];
    else
        [self.pubsub publishItem:
            [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": @"current"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"nick" andNamespace:@"http://jabber.org/protocol/nick" withAttributes:@{} andChildren:@[] andData:rosterName]
            ] andData:nil]
        onNode:@"http://jabber.org/protocol/nick" withConfigOptions:@{
            @"pubsub#persist_items": @"true",
            @"pubsub#access_model": @"presence"
        }];
}

-(NSData*) resizeAvatarImage:(UIImage*) image
{
    //resize image to a maximum of 600x600 pixel
    CGRect dimensions = AVMakeRectWithAspectRatioInsideRect(image.size, CGRectMake(0, 0, 600, 600));
    DDLogInfo(@"Downsizing avatar image to %lux%lu pixel", (unsigned long)dimensions.size.width, (unsigned long)dimensions.size.height);
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:dimensions.size];
    UIImage* resizedImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [image drawInRect:dimensions];
    }];
    
    //now reduce quality until image data is smaller than ~240kb
    NSData* data;
    unsigned long limit = 240000;        //should work for ejabberd >= 19.02 and prosody >= 0.11
    CGFloat quality = 0.8;               //start here
    do
    {
        DDLogDebug(@"Resizing new avatar to quality %f", (double)quality);
        data = UIImageJPEGRepresentation(resizedImage, quality);
        DDLogDebug(@"New avatar size after changing quality: %lu", (unsigned long)data.length);
        quality /= 1.3;
    } while((data.length*1.5) > limit && quality > 0.0001);     //base64 encoded data is 1.5 times bigger than the raw binary data (take that into account)
    
    DDLogInfo(@"Returning new avatar jpeg data with size %lu and quality %f", (unsigned long)data.length, (double)quality*1.5);
    return data;
}

-(void) publishAvatar:(UIImage*) image
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if(!image)
        {
            DDLogInfo(@"Retracting own avatar image");
            [self.pubsub deleteNode:@"urn:xmpp:avatar:metadata"];
            [self.pubsub deleteNode:@"urn:xmpp:avatar:data"];
        }
        else
        {
            NSData* imageData = [self resizeAvatarImage:image];
            NSString* imageHash = [HelperTools hexadecimalString:[HelperTools sha1:imageData]];
            
            DDLogInfo(@"Publishing own avatar image with hash %@", imageHash);
            
            //publish data node (must be done *before* publishing the new metadata node)
            MLXMLNode* item = [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": imageHash} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"data" andNamespace:@"urn:xmpp:avatar:data" withAttributes:@{} andChildren:@[] andData:[HelperTools encodeBase64WithData:imageData]]
            ] andData:nil];
            
            [self.pubsub publishItem:item onNode:@"urn:xmpp:avatar:data" withConfigOptions:@{
                @"pubsub#persist_items": @"true",
                @"pubsub#access_model": @"presence"
            }];
            
            //publish metadata node (must be done *after* publishing the new data node)
            [self.pubsub publishItem:
                [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": imageHash} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"metadata" andNamespace:@"urn:xmpp:avatar:metadata" withAttributes:@{} andChildren:@[
                        [[MLXMLNode alloc] initWithElement:@"info" withAttributes:@{
                            @"id": imageHash,
                            @"type": @"image/jpeg",
                            @"bytes": [NSString stringWithFormat:@"%lu", (unsigned long)imageData.length]
                        } andChildren:@[] andData:nil]
                    ] andData:nil]
                ] andData:nil]
            onNode:@"urn:xmpp:avatar:metadata" withConfigOptions:@{
                @"pubsub#persist_items": @"true",
                @"pubsub#access_model": @"presence"
            }];
        }
    });
}

@end
