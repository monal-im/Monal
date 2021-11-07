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
#import "MLDNSLookup.h"
#import "MLSignalStore.h"
#import "MLPubSub.h"
#import "MLOMEMO.h"

#import "MLStream.h"
#import "MLPipe.h"
#import "MLProcessLock.h"
#import "DataLayer.h"
#import "HelperTools.h"
#import "MLXMPPManager.h"
#import "MLNotificationQueue.h"

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
#import "MLPubSubProcessor.h"
#import "MLMucProcessor.h"

#import "MLHTTPRequest.h"
#import "AESGcm.h"

@import AVFoundation;

#define STATE_VERSION 5
#define CONNECT_TIMEOUT 10.0
#define IQ_TIMEOUT 20.0
NSString* const kQueueID = @"queueID";
NSString* const kStanza = @"stanza";


@interface MLPubSub ()
-(id) initWithAccount:(xmpp*) account;
-(NSDictionary*) getInternalData;
-(void) setInternalData:(NSDictionary*) data;
-(void) handleHeadlineMessage:(XMPPMessage*) messageNode;
@end

@interface MLMucProcessor ()
-(id) initWithAccount:(xmpp*) account;
-(NSDictionary*) getInternalState;
-(void) setInternalState:(NSDictionary*) state;
-(void) resetForNewSession;
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
    NSMutableDictionary* _runningMamQueries;
    BOOL _SRVDiscoveryDone;
    BOOL _startTLSComplete;
    BOOL _catchupDone;
    double _exponentialBackoff;
    BOOL _reconnectInProgress;
    BOOL _disconnectInProgres;
    NSObject* _stateLockObject;     //only used for @synchronized() blocks
    BOOL _lastIdleState;
    NSMutableDictionary* _mamPageArrays;
    BOOL _firstLoginForThisInstance;
    NSString* _internalID;
    NSMutableDictionary* _inCatchup;
    
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
    _internalID = [[NSUUID UUID] UUIDString];
    DDLogVerbose(@"Created account %@ with id %@", accountNo, _internalID);
    self.accountNo = accountNo;
    self.connectionProperties = [[MLXMPPConnection alloc] initWithServer:server andIdentity:identity];
    
    //setup all other ivars
    [self setupObjects];
    
    //read persisted state to make sure we never operate stateless
    //WARNING: pubsub node registrations should only be made *after* the first readState call
    [self readState];
    
    // don't init omemo on account creation
    if(accountNo.intValue >= 0)
    {
        // init omemo
        self.omemo = [[MLOMEMO alloc] initWithAccount:self];
    }
    
    //we want to get automatic avatar updates (XEP-0084)
    [self.pubsub registerForNode:@"urn:xmpp:avatar:metadata" withHandler:$newHandler(MLPubSubProcessor, avatarHandler)];
    
    //we want to get automatic roster name updates (XEP-0172)
    [self.pubsub registerForNode:@"http://jabber.org/protocol/nick" withHandler:$newHandler(MLPubSubProcessor, rosterNameHandler)];
    
    //we want to get automatic bookmark updates (XEP-0048)
    [self.pubsub registerForNode:@"storage:bookmarks" withHandler:$newHandler(MLPubSubProcessor, bookmarksHandler)];
    
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
    
    //init muc processor
    self.mucProcessor = [[MLMucProcessor alloc] initWithAccount:self];
    
    _stateLockObject = [[NSObject alloc] init];
    [self initSM3];
    
    _accountState = kStateLoggedOut;
    _registration = NO;
    _registrationSubmission = NO;
    _startTLSComplete = NO;
    _catchupDone = NO;
    _reconnectInProgress = NO;
    _disconnectInProgres = NO;
    _lastIdleState = NO;
    _firstLoginForThisInstance = YES;
    _outputQueue = [[NSMutableArray alloc] init];
    _iqHandlers = [[NSMutableDictionary alloc] init];
    _mamPageArrays = [[NSMutableDictionary alloc] init];
    _runningMamQueries = [[NSMutableDictionary alloc] init];
    _inCatchup = [[NSMutableDictionary alloc] init];

    _SRVDiscoveryDone = NO;
    _discoveredServersList = [[NSMutableArray alloc] init];
    if(!_usableServersList)
        _usableServersList = [[NSMutableArray alloc] init];
    _exponentialBackoff = 0;
    
    _parseQueue = [[NSOperationQueue alloc] init];
    _parseQueue.name = [NSString stringWithFormat:@"parseQueue[%@:%@]", self.accountNo, _internalID];
    _parseQueue.qualityOfService = NSQualityOfServiceUtility;
    _parseQueue.maxConcurrentOperationCount = 1;
    [_parseQueue addObserver:self forKeyPath:@"operationCount" options:NSKeyValueObservingOptionNew context:nil];
    
    _receiveQueue = [[NSOperationQueue alloc] init];
    _receiveQueue.name = [NSString stringWithFormat:@"receiveQueue[%@:%@]", self.accountNo, _internalID];
    _receiveQueue.qualityOfService = NSQualityOfServiceUtility;
    _receiveQueue.maxConcurrentOperationCount = 1;
    [_receiveQueue addObserver:self forKeyPath:@"operationCount" options:NSKeyValueObservingOptionNew context:nil];

    _sendQueue = [[NSOperationQueue alloc] init];
    _sendQueue.name = [NSString stringWithFormat:@"sendQueue[%@:%@]", self.accountNo, _internalID];
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
    self.sendIdleNotifications = [[HelperTools defaultsDB] boolForKey:@"SendLastUserInteraction"];
    
    self.statusMessage = @"";
}

-(void) dealloc
{
    DDLogInfo(@"Deallocating account %@ object %@", self.accountNo, self);
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
    DDLogInfo(@"Done deallocating account %@ object %@", self.accountNo, self);
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
    [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:self userInfo:@{@"message": NSLocalizedString(@"Server returned invalid xml!", @""), @"isSevere": @NO}];
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
        DDLogVerbose(@"DISPATCHING %@ OPERATION ON RECEIVE QUEUE %@: %lu", async ? @"ASYNC" : @"*sync*", [_receiveQueue name], [_receiveQueue operationCount]);
        [_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:operation]] waitUntilFinished:!async];
    }
    else
        operation();
}

-(void) accountStatusChanged
{
    // Send notification that our account state has changed
    [[MLNotificationQueue currentQueue] postNotificationName:kMonalAccountStatusChanged object:self userInfo:@{
            kAccountID: self.accountNo,
            kAccountState: [[NSNumber alloc] initWithInt:(int)self.accountState],
    }];
}

-(void) observeValueForKeyPath:(NSString*) keyPath ofObject:(id) object change:(NSDictionary *) change context:(void*) context
{
    //check for idle state every time the number of operations in _sendQueue, _parseQueue or _receiveQueue changes
    if((object == _sendQueue || object == _receiveQueue || object == _parseQueue) && [@"operationCount" isEqual: keyPath])
    {
        //check idle state if this queue is empty and if so, publish kMonalIdle notification
        //only do the (more heavy but complete) idle check if we reache zero operations in the observed queue
        //if the idle check returnes a state change from non-idle to idle, we dispatch the idle notification on the receive queue
        //to account for races between the second idle check done in the idle notification handler and calls to disconnect
        //issued in response to this idle notification
        //NOTE: yes, doing the check for operationCount of all queues (inside [self idle]) from an arbitrary thread is not race free.
        //with such disconnects, but: we only want to track the send queue on a best effort basis (because network sends are best effort, too)
        //to some extent we want to make sure every stanza was physically sent out to the network before our app gets frozen by ios,
        //but we don't need to make this completely race free (network "races" can occur far more often than send queue races).
        //in a race the smacks unacked stanzas array will contain the not yet sent stanzas --> we won't loose stanzas when racing the send queue
        //with [self disconnect] through an idle check
        //races on the idleness of the parse queue are even less severe and can be ignored entirely (they just have the effect as if a parsed
        //stanza would not have been received by monal in the first place, because disconnect disrupted the network connection just before the
        //stanza came in).
        //NOTE: we only want to do an idle check if we are not in the middle of a disconnect call because this can race when the _bgTask is expiring
        //and cancel the new _bgFetch because we are now idle (the dispatchAsyncOnReceiveQueue: will add a new task to the receive queue when
        //the send queue gets cleaned up and this task will run as soon as the disconnect is done and interfere with the configuration of the
        //_bgFetch and the syncError push notification both created on the main thread
        if(![object operationCount] && !_disconnectInProgres)
        {
            //make sure we do a real async dispatch not using the shortcut in dispatchAsyncOnReceiveQueue: because that could cause races
            //BACKGROUND EXPLANATION: apple calls observeValueForKeyPath: after completing the operation on the NSOperationQueue from the same thread,
            //the operation was executed in. But because the operation is already finished by the time this value observer is called,
            //the next operation could already be executing in another thread, while this observer does the async dispatch to the receive queue.
            //The async dispatch implemented in dispatchAsyncOnReceiveQueue: tests, if we are already inside the receive queue and, if so,
            //executes the operation directly, without queueing it to the receive queue.
            //This check is true, even if we are in the value observer (even though this code technically does not
            //run inside an operation on the receive queue, the check for the runnin queue in our async dispatch function still detects (erroneously)
            //that we still are "inside" the receive queue and calls the block directly rather than enqueueing a new operation on the receive queue.
            //That means we now have *2* threads executing code in the receive queue despite the queue being a serial queue
            //--> deadlocks or malicious concurrent access can happen
            //example taken from the wild (steve): the idle check in the *old* receive queue mach thread calls disconnect and tries to write
            //the final account state to the database while the next stanza is being processed in the *real* receive queue mach thread holding a
            //database transaction open. Both threads race against each other and a deadlock occurs that finally results in a MLSQLite exception
            //thrown because the sqlite3_busy_timeout triggers after 8 seconds.
            
            BOOL lastState = self->_lastIdleState;
            //only send out idle notifications if we changed from non-idle to idle state
            if(self.idle && !lastState)
            {
                DDLogVerbose(@"Adding idle state notification to receive queue...");
                [_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                    if(self.idle)       //make sure we are still idle, even if in receive queue now
                        //don't queue this notification because it should be handled INLINE inside the receive queue
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalIdle object:self];
                }]] waitUntilFinished:NO];
            }
        }
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
            _cancelPingTimer == nil &&
            !unackedCount &&
            ![_parseQueue operationCount] &&        //if something blocks the parse queue it is either an incoming stanza currently processed or waiting to be processed
            //[_receiveQueue operationCount] <= ([NSOperationQueue currentQueue]==_receiveQueue ? 1 : 0) &&
            ![_sendQueue operationCount] &&
            ![_inCatchup count]
        )
    )
        retval = YES;
    _lastIdleState = retval;
    DDLogVerbose(@("%@ --> Idle check:\n"
            "\t_accountState < kStateReconnecting = %@\n"
            "\t_reconnectInProgress = %@\n"
            "\t_catchupDone = %@\n"
            "\t_cancelPingTimer = %@\n"
            "\t[self.unAckedStanzas count] = %lu\n"
            "\t[_parseQueue operationCount] = %lu\n"
            //"\t[_receiveQueue operationCount] = %lu\n"
            "\t[_sendQueue operationCount] = %lu\n"
            "\t[[_inCatchup count] = %lu\n\t--> %@"
        ),
        self.accountNo,
        _accountState < kStateReconnecting ? @"YES" : @"NO",
        _reconnectInProgress ? @"YES" : @"NO",
        _catchupDone ? @"YES" : @"NO",
        _cancelPingTimer == nil ? @"none" : @"running timer",
        unackedCount,
        (unsigned long)[_parseQueue operationCount],
        //(unsigned long)[_receiveQueue operationCount],
        (unsigned long)[_sendQueue operationCount],
        (unsigned long)[_inCatchup count],
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
        [self->_sendQueue cancelAllOperations];
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

-(void) createStreams
{
    DDLogInfo(@"stream creating to server: %@ port: %@ directTLS: %@", self.connectionProperties.server.connectServer, self.connectionProperties.server.connectPort, self.connectionProperties.server.isDirectTLS ? @"YES" : @"NO");
    
    NSInputStream* localIStream;
    NSOutputStream* localOStream;
    
    if(self.connectionProperties.server.isDirectTLS == YES)
    {
        DDLogInfo(@"starting directSSL");
        [MLStream connectWithSNIDomain:self.connectionProperties.identity.domain connectHost:self.connectionProperties.server.connectServer connectPort:self.connectionProperties.server.connectPort inputStream:&localIStream outputStream:&localOStream];
    }
    else
    {
        [NSStream getStreamsToHostWithName:self.connectionProperties.server.connectServer port:self.connectionProperties.server.connectPort.integerValue inputStream:&localIStream outputStream:&localOStream];
    }
    
    if(localOStream)
        _oStream = localOStream;
    
    if((localIStream == nil) || (localOStream == nil))
    {
        DDLogError(@"failed to create streams");
        [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:self userInfo:@{@"message": NSLocalizedString(@"Unable to connect to server!", @""), @"isSevere": @NO}];
        [self reconnect];
        return;
    }
    else
        DDLogInfo(@"streams created ok");
    
    if(localIStream)
        _iPipe = [[MLPipe alloc] initWithInputStream:localIStream andOuterDelegate:self];
    [_oStream setDelegate:self];
    [_oStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    
    //tcp fast open is only supperted when connecting through network framework which is only supported when using direct tls
    if(self.connectionProperties.server.isDirectTLS == YES)
    {
        //make sure we really try to send this initial xmpp stream header as early data for tcp fast open even though the tcp stream did not yet trigger
        //an NSStreamEventHasSpaceAvailable event because it was not even opened yet
        //self->_streamHasSpace = YES;
        [self startXMPPStream:NO];     //send xmpp stream start (this is the first one for this connection --> we don't need to clear the receive queue)
    }
    else
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
        _discoveredServersList = [[[MLDNSLookup alloc] init] dnsDiscoverOnDomain:self.connectionProperties.identity.domain];
        _SRVDiscoveryDone = YES;
        // no SRV records found, update server to directly connect to specified domain
        if([_discoveredServersList count] == 0)
        {
            [self.connectionProperties.server updateConnectServer:self.connectionProperties.identity.domain];
            [self.connectionProperties.server updateConnectPort:@5222];
            [self.connectionProperties.server updateConnectTLS:NO];
            DDLogInfo(@"NO SRV records found, using standard xmpp config: %@:%@ (using starttls)", self.connectionProperties.server.connectServer, self.connectionProperties.server.connectPort);
        }
    }

    // Show warning when xmpp-client srv entry prohibits connections
    for(NSDictionary* row in _discoveredServersList)
    {
        // Check if entry "." == srv target
        if(![[row objectForKey:@"isEnabled"] boolValue])
        {
            DDLogInfo(@"SRV entry prohibits XMPP connection for server %@", self.connectionProperties.identity.domain);
            [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:self userInfo:@{
                @"message": [NSString stringWithFormat:NSLocalizedString(@"SRV entry prohibits XMPP connection for domain %@", @""), self.connectionProperties.identity.domain],
                @"isSevere": @YES
            }];
            return YES;
        }
    }
    
    // if all servers have been tried start over with the first one again
    if([_discoveredServersList count] > 0 && [_usableServersList count] == 0)
    {
        if(!_firstLoginForThisInstance)
            DDLogWarn(@"All %lu SRV dns records tried, starting over again", (unsigned long)[_discoveredServersList count]);
        for(NSDictionary* row in _discoveredServersList)
            DDLogInfo(@"SRV entry in _discoveredServersList: server=%@, port=%@, isSecure=%s, priority=%@, ttl=%@",
                [row objectForKey:@"server"],
                [row objectForKey:@"port"],
                [[row objectForKey:@"isSecure"] boolValue] ? "YES" : "NO",
                [row objectForKey:@"priority"],
                [row objectForKey:@"ttl"]
            );
        _usableServersList = [_discoveredServersList mutableCopy];
    }

    if([_usableServersList count] > 0)
    {
        DDLogInfo(@"Using connection parameters discovered via SRV dns record: server=%@, port=%@, isSecure=%s, priority=%@, ttl=%@",
            [[_usableServersList objectAtIndex:0] objectForKey:@"server"],
            [[_usableServersList objectAtIndex:0] objectForKey:@"port"],
            [[[_usableServersList objectAtIndex:0] objectForKey:@"isSecure"] boolValue] ? "YES" : "NO",
            [[_usableServersList objectAtIndex:0] objectForKey:@"priority"],
            [[_usableServersList objectAtIndex:0] objectForKey:@"ttl"]
        );
        [self.connectionProperties.server updateConnectServer: [[_usableServersList objectAtIndex:0] objectForKey:@"server"]];
        [self.connectionProperties.server updateConnectPort: [[_usableServersList objectAtIndex:0] objectForKey:@"port"]];
        [self.connectionProperties.server updateConnectTLS: [[[_usableServersList objectAtIndex:0] objectForKey:@"isSecure"] boolValue]];
        // remove this server so that the next connection attempt will try the next server in the list
        [_usableServersList removeObjectAtIndex:0];
        DDLogInfo(@"%lu SRV entries left:", (unsigned long)[_usableServersList count]);
        for(NSDictionary* row in _usableServersList)
            DDLogInfo(@"SRV entry in _usableServersList: server=%@, port=%@, isSecure=%s, priority=%@, ttl=%@",
                [row objectForKey:@"server"],
                [row objectForKey:@"port"],
                [[row objectForKey:@"isSecure"] boolValue] ? "YES" : "NO",
                [row objectForKey:@"priority"],
                [row objectForKey:@"ttl"]
            );
    }
    
    [self createStreams];
    return NO;
}

-(void) unfreezed
{
    //make sure we don't have any race conditions by dispatching this to our receive queue
    [self dispatchAsyncOnReceiveQueue:^{
        if(self.accountState < kStateReconnecting)
        {
            DDLogInfo(@"UNFREEZING account %@", self.accountNo);
            //(re)read persisted state (could be changed by appex)
            [self readState];
        }
        else
            DDLogInfo(@"Not UNFREEZING account %@, already connected", self.accountNo);
    }];
}

-(void) connect
{
    if(![[MLXMPPManager sharedInstance] hasConnectivity])
    {
        DDLogInfo(@"no connectivity, ignoring connect call.");
        return;
    }
    
    [self dispatchAsyncOnReceiveQueue: ^{
        [self->_parseQueue cancelAllOperations];          //throw away all parsed but not processed stanzas from old connections
        [self->_receiveQueue cancelAllOperations];        //stop everything coming after this (we will start a clean connect here!)
        
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
        self->_accountState = kStateReconnecting;
        
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
            self->_accountState = kStateDisconnected;
            return;
        }
        
        DDLogInfo(@"XMPP connnect start");
        self->_startTLSComplete = NO;
        self->_catchupDone = NO;
        
        [self cleanupSendQueue];
        
        //(re)read persisted state and start connection
        [self readState];
        if([self connectionTask])
        {
            DDLogError(@"Server disallows xmpp connections for account '%@', ignoring login", self.accountNo);
            self->_accountState = kStateDisconnected;
            return;
        }
        
        //return here if we are just registering a new account
        if(self->_registration || self->_registrationSubmission)
            return;
        
        self->_cancelLoginTimer = createTimer(CONNECT_TIMEOUT, (^{
            [self dispatchAsyncOnReceiveQueue: ^{
                self->_cancelLoginTimer = nil;
                DDLogInfo(@"login took too long, cancelling and trying to reconnect (potentially using another SRV record)");
                [self reconnect];
            }];
        }));
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
        DDLogInfo(@"stopping running timers");
        if(self->_cancelLoginTimer)
            self->_cancelLoginTimer();        //cancel running login timer
        self->_cancelLoginTimer = nil;
        if(self->_cancelPingTimer)
            self->_cancelPingTimer();         //cancel running ping timer
        self->_cancelPingTimer = nil;
        if(self->_cancelReconnectTimer)
            self->_cancelReconnectTimer();
        self->_cancelReconnectTimer = nil;
        
        if(self->_accountState<kStateReconnecting)
        {
            DDLogVerbose(@"not doing logout because already logged out, but clearing state if explicitLogout was yes");
            if(explicitLogout)
            {
                @synchronized(self->_stateLockObject) {
                    DDLogVerbose(@"explicitLogout == YES --> clearing state");
                    
                    //preserve unAckedStanzas even on explicitLogout and resend them on next connect
                    //if we don't do this, messages could get lost when logging out directly after sending them
                    //and: sending messages twice is less intrusive than silently loosing them
                    NSMutableArray* stanzas = self.unAckedStanzas;

                    //reset smacks state to sane values (this can be done even if smacks is not supported)
                    [self initSM3];
                    self.unAckedStanzas = stanzas;
                    
                    //inform all old iq handlers of invalidation and clear _iqHandlers dictionary afterwards
                    @synchronized(self->_iqHandlers) {
                        for(NSString* iqid in [self->_iqHandlers allKeys])
                        {
                            DDLogWarn(@"Invalidating iq handler for iq id '%@'", iqid);
                            if(self->_iqHandlers[iqid][@"handler"] != nil)
                                $invalidate(self->_iqHandlers[iqid][@"handler"], $ID(account, self));
                            else if(self->_iqHandlers[iqid][@"errorHandler"])
                                ((monal_iq_handler_t)self->_iqHandlers[iqid][@"errorHandler"])(nil);
                        }
                        self->_iqHandlers = [[NSMutableDictionary alloc] init];
                    }

                    //persist these changes
                    [self persistState];
                }
                
                [[DataLayer sharedInstance] resetContactsForAccount:self.accountNo];
            }
            return;
        }
        DDLogInfo(@"disconnecting");
        self->_disconnectInProgres = YES;
        
        //invalidate all ephemeral iq handlers (those not surviving an app restart or switch to/from appex)
        @synchronized(self->_iqHandlers) {
            for(NSString* iqid in [self->_iqHandlers allKeys])
            {
                if(self->_iqHandlers[iqid][@"handler"] == nil)
                {
                    NSDictionary* data = (NSDictionary*)self->_iqHandlers[iqid];
                    if(data[@"errorHandler"])
                    {
                        DDLogWarn(@"Invalidating iq handler for iq id '%@'", iqid);
                        if(data[@"errorHandler"])
                            ((monal_iq_handler_t)data[@"errorHandler"])(nil);
                    }
                    [self->_iqHandlers removeObjectForKey:iqid];
                }
            }
        }
        
        if(explicitLogout && self->_accountState>=kStateHasStream)
        {
            DDLogInfo(@"doing explicit logout (xmpp stream close)");
            self->_exponentialBackoff = 0;
            if(self.accountState>=kStateBound)
                [self->_sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
                    //disable push for this node
                    if(self.connectionProperties.supportsPush)
                    {
                        XMPPIQ* disable = [[XMPPIQ alloc] initWithType:kiqSetType];
                        [disable setPushDisable];
                        [self writeToStream:disable.XMLString];		// dont even bother queueing
                    }

                    [self sendLastAck];
                }]] waitUntilFinished:YES];         //block until finished because we are closing the xmpp stream directly afterwards
            [self->_sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
                //close stream
                MLXMLNode* stream = [[MLXMLNode alloc] initWithElement:@"/stream:stream"];  //hack to close stream
                [self writeToStream:[stream XMLString]];    // dont even bother queueing
            }]] waitUntilFinished:YES];         //block until finished because we are closing the socket directly afterwards

            @synchronized(self->_stateLockObject) {
                //preserve unAckedStanzas even on explicitLogout and resend them on next connect
                //if we don't do this, messages could get lost when logging out directly after sending them
                //and: sending messages twice is less intrusive than silently loosing them
                NSMutableArray* stanzas = self.unAckedStanzas;

                //reset smacks state to sane values (this can be done even if smacks is not supported)
                [self initSM3];
                self.unAckedStanzas = stanzas;
                
                //inform all old iq handlers of invalidation and clear _iqHandlers dictionary afterwards
                @synchronized(self->_iqHandlers) {
                    for(NSString* iqid in [self->_iqHandlers allKeys])
                    {
                        DDLogWarn(@"Invalidating iq handler for iq id '%@'", iqid);
                        if(self->_iqHandlers[iqid][@"handler"] != nil)
                            $invalidate(self->_iqHandlers[iqid][@"handler"], $ID(account, self));
                        else if(self->_iqHandlers[iqid][@"errorHandler"])
                            ((monal_iq_handler_t)self->_iqHandlers[iqid][@"errorHandler"])(nil);
                    }
                    self->_iqHandlers = [[NSMutableDictionary alloc] init];
                }

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
        self->_disconnectInProgres = NO;
    }];
}

-(void) closeSocket
{
    [self dispatchOnReceiveQueue: ^{
        DDLogInfo(@"removing streams from runLoop and aborting parser");

        //prevent any new read or write
        if(self->_xmlParser != nil)
        {
            [self->_xmlParser setDelegate:nil];
            [self->_xmlParser abortParsing];
            self->_xmlParser = nil;
        }
        [self->_iPipe close];
        self->_iPipe = nil;
        [self->_oStream setDelegate:nil];
        [self->_oStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        
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
        
        //clean up send queue now that the delegate was removed (_streamHasSpace can not switch to YES now)
        [self cleanupSendQueue];

        DDLogInfo(@"resetting internal stream state to disconnected");
        self->_startTLSComplete = NO;
        self->_catchupDone = NO;
        self->_accountState = kStateDisconnected;
        
        [self->_parseQueue cancelAllOperations];      //throw away all parsed but not processed stanzas (we should have closed sockets then!)
        //we don't throw away operations in the receive queue because they could be more than just stanzas
        //(for example outgoing messages that should be written to the smacks queue instead of just vanishing in a void)
        //all incoming stanzas in the receive queue will honor the _accountState being lower than kStateReconnecting and be dropped
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
        if(self->_reconnectInProgress)
        {
            DDLogInfo(@"Ignoring reconnect while one already in progress");
            return;
        }
        
        self->_reconnectInProgress = YES;
        [self disconnect:NO];

        DDLogInfo(@"Trying to connect again in %G seconds...", wait);
        self->_cancelReconnectTimer = createTimer(wait, (^{
            self->_cancelReconnectTimer = nil;
            [self dispatchAsyncOnReceiveQueue: ^{
                //there may be another connect/login operation in progress triggered from reachability or another timer
                if(self.accountState<kStateReconnecting)
                    [self connect];
                self->_reconnectInProgress = NO;
            }];
        }));
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
            if(self.accountState<kStateReconnecting)
            {
                DDLogWarn(@"Throwing away incoming stanza *before* queueing in parse queue, accountState < kStateReconnecting");
                return;
            }
            
            //don't parse any more if we reached > 50 stanzas already parsed and waiting in parse queue
            //this makes ure we don't need to much memory while parsing a flood of stanzas and, in theory,
            //should create a backpressure ino the tcp stream, too
            while([self->_parseQueue operationCount] > 50)
            {
                DDLogInfo(@"Sleeping 0.5 seconds because parse queue has > 50 entries...");
                [NSThread sleepForTimeInterval:0.5];
            }
#ifndef QueryStatistics
            //prime query cache by doing the most used queries in this thread ahead of the receiveQueue processing
            //only preprocess MLXMLNode queries to prime the cache if enough xml nodes are already queued
            //(we don't want to slow down processing by this)
            if([self->_parseQueue operationCount] > 2)
            {
                //this list contains the upper part of the 0.75 percentile of the statistically most used queries
                [parsedStanza find:@"/@id"];
                [parsedStanza find:@"/{urn:xmpp:sm:3}r"];
                [parsedStanza find:@"/{urn:xmpp:sm:3}a"];
                [parsedStanza find:@"/<type=get>"];
                [parsedStanza find:@"/<type=set>"];
                [parsedStanza find:@"/<type=result>"];
                [parsedStanza find:@"/<type=error>"];
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
            [self->_parseQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                //always process stanzas in the receiveQueue
                //use a synchronous dispatch to make sure no (old) tcp buffers of disconnected connections leak into the receive queue on app unfreeze
                DDLogVerbose(@"Synchronously handling next stanza on receive queue (%lu stanzas queued in parse queue, %lu current operations in receive queue)", [self->_parseQueue operationCount], [self->_receiveQueue operationCount]);
                [self->_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                    if(self.accountState<kStateReconnecting)
                    {
                        DDLogWarn(@"Throwing away incoming stanza queued in parse queue, accountState < kStateReconnecting");
                        return;
                    }
                    [MLNotificationQueue queueNotificationsInBlock:^{
                        //add whole processing of incoming stanzas to one big transaction
                        //this will make it impossible to leave inconsistent database entries on app crashes or iphone crashes/reboots
                        DDLogVerbose(@"Starting transaction for: %@", parsedStanza);
                        [[DataLayer sharedInstance] createTransaction:^{
                            DDLogVerbose(@"Started transaction for: %@", parsedStanza);
                            [self processInput:parsedStanza withDelayedReplay:NO];
                            DDLogVerbose(@"Ending transaction for: %@", parsedStanza);
                        }];
                        DDLogVerbose(@"Ended transaction for: %@", parsedStanza);
                    } onQueue:@"receiveQueue"];
                    DDLogVerbose(@"Flushed all queued notifications...");
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
        [self->_xmlParser parse];     //blocking operation
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
        else if(self->_cancelPingTimer)
        {
            DDLogInfo(@"ping already sent, ignoring second ping request.");
            return;
        }
        else if([self->_parseQueue operationCount] > 4)
        {
            DDLogWarn(@"parseQueue overflow, delaying ping by 10 seconds.");
            createTimer(10.0, (^{
                DDLogDebug(@"ping delay expired, retrying ping.");
                [self sendPing:timeout];
            }));
        }
        else
        {
            //start ping timer
            self->_cancelPingTimer = createTimer(timeout, (^{
                [self dispatchAsyncOnReceiveQueue: ^{
                    self->_cancelPingTimer = nil;
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
            }));
            monal_void_block_t handler = ^{
                DDLogInfo(@"ping response received, all seems to be well");
                if(self->_cancelPingTimer)
                {
                    self->_cancelPingTimer();      //cancel timer (ping was successful)
                    self->_cancelPingTimer = nil;
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
                } andErrorHandler:^(XMPPIQ* error) {
                    if(error != nil)
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
                //only resend message stanzas because of the smacks error condition
                //but don't add them to our outgoing smacks queue again, if smacks isn't supported
                if([stanza.element isEqualToString:@"message"])
                    [self send:stanza withSmacks:self.connectionProperties.supportsSM3];
            }];
            //persist these changes, the queue can now be empty (because smacks enable failed)
            //or contain all the resent stanzas (e.g. only resume failed)
            [self persistState];
        }
    }
}

-(void) removeAckedStanzasFromQueue:(NSNumber*) hvalue
{
    NSMutableArray* ackHandlerToCall = [[NSMutableArray alloc] initWithCapacity:[_smacksAckHandler count]];
    @synchronized(_stateLockObject) {
        if(([hvalue integerValue] - [self.lastHandledOutboundStanza integerValue]) > [self.unAckedStanzas count])
        {
            //stanza counting bugs on the server are fatal
            NSString* message = @"Server acknowledged more stanzas than sent by client";
            [self send:[[MLXMLNode alloc] initWithElement:@"stream:error" withAttributes:@{@"type": @"cancel"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"undefined-condition" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[] andData:nil],
                [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[] andData:message],
            ] andData:nil]];
            [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:self userInfo:@{@"message": message, @"isSevere": @NO}];
            [self reconnect];
        }
        
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
                        if(messageNode.id)
                            [[MLNotificationQueue currentQueue] postNotificationName:kMonalSentMessageNotice object:self userInfo:@{kMessageId:messageNode.id}];
                    }
                }
            }

            [iterationArray removeObjectsInArray:discard];
            self.unAckedStanzas = iterationArray;

            //persist these changes (but only if we actually made some changes)
            if([discard count])
                [self persistState];
        }
        
        DDLogVerbose(@"_smacksAckHandler: %@", _smacksAckHandler);
        //remove registered smacksAckHandler that will be called now
        for(NSDictionary* dic in _smacksAckHandler)
            if([[dic objectForKey:@"value"] integerValue] <= [hvalue integerValue])
            {
                DDLogVerbose(@"Adding smacks ack handler to call list: %@", dic);
                [ackHandlerToCall addObject:dic];
            }
        [_smacksAckHandler removeObjectsInArray:ackHandlerToCall];
    }
    
    //call registered smacksAckHandler that got sorted out
    for(NSDictionary* dic in ackHandlerToCall)
    {
        DDLogVerbose(@"Now calling smacks ack handler: %@", dic);
        ((monal_void_block_t)dic[@"handler"])();
    }
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
    if(self.connectionProperties.supportsSM3)
    {
        DDLogInfo(@"sending last ack");
        [self sendSMAck:NO];
    }
}

-(void) sendSMAck:(BOOL) queuedSend
{
    //don't send anything before a resource is bound
    if(self.accountState<kStateBound || !self.connectionProperties.supportsSM3)
        return;
    
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

#pragma mark - stanza handling

-(void) processInput:(MLXMLNode*) parsedStanza withDelayedReplay:(BOOL) delayedReplay
{
    if(delayedReplay)
        DDLogInfo(@"delayedReplay of Stanza: %@", parsedStanza);
    else
        DDLogInfo(@"RECV Stanza: %@", parsedStanza);
    
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
            if(h==nil)
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
            
            //sanity: check if presence from and to attributes are valid and throw it away if not
            if([@"" isEqualToString:presenceNode.from] || [@"" isEqualToString:presenceNode.to])
            {
                DDLogError(@"sanity check failed for presence node, ignoring presence: %@", presenceNode);
                //mark stanza as handled even if we don't process it further (we still received it, so we have to count it)
                [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                return;
            }
            
            //sanitize: no from or to always means own bare/full jid
            if(!presenceNode.from)
                presenceNode.from = self.connectionProperties.identity.jid;
            if(!presenceNode.to)
                presenceNode.to = self.connectionProperties.identity.fullJid;
            
            //sanity: check if toUser points to us and throw it away if not
            if(![self.connectionProperties.identity.jid isEqualToString:presenceNode.toUser])
            {
                DDLogError(@"sanity check failed presence node, ignoring presence: %@", presenceNode);
                //mark stanza as handled even if we don't process it further (we still received it, so we have to count it)
                [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                return;
            }
            
            if([presenceNode.fromUser isEqualToString:self.connectionProperties.identity.jid])
            {
                DDLogInfo(@"got self presence");
                
                //ignore special presences for status updates (they don't have one)
                if(![presenceNode check:@"/@type"])
                {
                    NSMutableDictionary* accountDetails = [[DataLayer sharedInstance] detailsForAccount:self.accountNo];
                    accountDetails[@"statusMessage"] = [presenceNode check:@"status#"] ? [presenceNode findFirst:@"status#"] : @"";
                    [[DataLayer sharedInstance] updateAccounWithDictionary:accountDetails];
                }
            }
            else
            {
                if([presenceNode check:@"/<type=subscribe>"])
                {
                    MLContact* contact = [MLContact createContactFromJid:presenceNode.fromUser andAccountNo:self.accountNo];

                    // check if we need a contact request
                    NSDictionary* contactSub = [[DataLayer sharedInstance] getSubscriptionForContact:contact.contactJid andAccount:contact.accountId];
                    DDLogVerbose(@"Got subscription request for contact %@ having subscription status: %@", presenceNode.fromUser, contactSub);
                    if(!contactSub || !([[contactSub objectForKey:@"subscription"] isEqualToString:kSubTo] || [[contactSub objectForKey:@"subscription"] isEqualToString:kSubBoth])) {
                        [[DataLayer sharedInstance] addContactRequest:contact];
                    }
                    else if(contactSub && [[contactSub objectForKey:@"subscription"] isEqualToString:kSubTo])
                        [self approveToRoster:presenceNode.fromUser];
                }

                if([presenceNode check:@"{http://jabber.org/protocol/muc#user}x"] || [presenceNode check:@"{http://jabber.org/protocol/muc}x"])
                {
                    //only handle presences for mucs we know
                    if([[DataLayer sharedInstance] isBuddyMuc:presenceNode.fromUser forAccount:self.accountNo])
                        [self.mucProcessor processPresence:presenceNode];
                    else
                        DDLogError(@"Got presence of unknown muc %@, ignoring...", presenceNode.fromUser);
                    
                    //mark this stanza as handled
                    [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                    return;
                }

                if(![presenceNode check:@"/@type"])
                {
                    DDLogVerbose(@"presence notice from %@", presenceNode.fromUser);

                    if(presenceNode.from)
                    {
                        MLContact *contact = [MLContact createContactFromJid:presenceNode.fromUser andAccountNo:self.accountNo];
                        contact.state = [presenceNode findFirst:@"show#"];
                        contact.statusMessage = [presenceNode findFirst:@"status#"];

                        //add contact if possible (ignore already existing contacts)
                        [[DataLayer sharedInstance] addContact:presenceNode.fromUser forAccount:self.accountNo nickname:nil andMucNick:nil];

                        //update buddy state
                        [[DataLayer sharedInstance] setOnlineBuddy:presenceNode forAccount:self.accountNo];
                        [[DataLayer sharedInstance] setBuddyState:presenceNode forAccount:self.accountNo];
                        [[DataLayer sharedInstance] setBuddyStatus:presenceNode forAccount:self.accountNo];

                        //handle last interaction time (only updae db if the last interaction time is NEWER than the one already in our db, needed for multiclient setups)
                        if([presenceNode check:@"{urn:xmpp:idle:1}idle@since"])
                        {
                            NSDate* lastInteraction = [[DataLayer sharedInstance] lastInteractionOfJid:presenceNode.fromUser forAccountNo:self.accountNo];
                            if([[presenceNode findFirst:@"{urn:xmpp:idle:1}idle@since|datetime"] compare:lastInteraction] == NSOrderedDescending)
                            {
                                [[DataLayer sharedInstance] setLastInteraction:[presenceNode findFirst:@"{urn:xmpp:idle:1}idle@since|datetime"] forJid:presenceNode.fromUser andAccountNo:self.accountNo];

                                [[MLNotificationQueue currentQueue] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
                                    @"jid": presenceNode.fromUser,
                                    @"accountNo": self.accountNo,
                                    @"lastInteraction": [presenceNode findFirst:@"{urn:xmpp:idle:1}idle@since|datetime"],
                                    @"isTyping": @NO
                                }];
                            }
                        }
                        else
                        {
                            [[MLNotificationQueue currentQueue] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
                                @"jid": presenceNode.fromUser,
                                @"accountNo": self.accountNo,
                                @"lastInteraction": [[NSDate date] initWithTimeIntervalSince1970:0],    //nil cannot directly be saved in NSDictionary
                                @"isTyping": @NO
                            }];
                        }
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
                        [self sendIq:discoInfo withHandler:$newHandler(MLIQProcessor, handleEntityCapsDisco)];
                    }
                }

            }
            
            //only mark stanza as handled *after* processing it
            [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
        }
        else if([parsedStanza check:@"/{jabber:client}message"])
        {
            //outerMessageNode and messageNode are the same for messages not carrying a carbon copy or mam result
            XMPPMessage* originalParsedStanza = (XMPPMessage*)[parsedStanza copy];
            XMPPMessage* outerMessageNode = (XMPPMessage*)parsedStanza;
            XMPPMessage* messageNode = outerMessageNode;
            
            //sanity: check if outer message from and to attributes are valid and throw it away if not
            if([@"" isEqualToString:outerMessageNode.from] || [@"" isEqualToString:outerMessageNode.to])
            {
                DDLogError(@"sanity check failed for outer message node, ignoring message: %@", outerMessageNode);
                //mark stanza as handled even if we don't process it further (we still received it, so we have to count it)
                [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                return;
            }
            
            //sanitize outer node: no from or to always means own bare/full jid
            if(!outerMessageNode.from)
                outerMessageNode.from = self.connectionProperties.identity.jid;
            if(!outerMessageNode.to)
                outerMessageNode.to = self.connectionProperties.identity.fullJid;
            
            //sanity: check if toUser points to us and throw it away if not
            if(![self.connectionProperties.identity.jid isEqualToString:outerMessageNode.toUser])
            {
                DDLogError(@"sanity check failed for outer message node, ignoring message: %@", outerMessageNode);
                //mark stanza as handled even if we don't process it further (we still received it, so we have to count it)
                [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                return;
            }
            
            //extract inner message if mam result or carbon copy
            //the original "outer" message will be kept in outerMessageNode while the forwarded stanza will be stored in messageNode
            if([outerMessageNode check:@"{urn:xmpp:mam:2}result"])          //mam result
            {
                //wrap everything in lock instead of writing the boolean result into a temp var because incrementLastHandledStanza
                //is wrapped in this lock, too (and we don't call anything else here)
                @synchronized(_stateLockObject) {
                    if(_runningMamQueries[[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"]] == nil)
                    {
                        DDLogError(@"mam results must be asked for, ignoring this spoofed mam result having queryid: %@!", [outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"]);
                        DDLogError(@"allowed mam queryids are: %@", _runningMamQueries);
                        //even these stanzas have to be counted by smacks
                        [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                        return;
                    }
                }
                
                //create a new XMPPMessage node instead of only a MLXMLNode because messages have some convenience properties and methods
                messageNode = [[XMPPMessage alloc] initWithXMPPMessage:[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result/{urn:xmpp:forward:0}forwarded/{jabber:client}message"]];
                
                //move mam:2 delay timestamp into forwarded message stanza if the forwarded stanza does not have one already
                //that makes parsing a lot easier later on and should not do any harm, even when resending/forwarding this inner stanza
                if([outerMessageNode check:@"{urn:xmpp:mam:2}result/{urn:xmpp:forward:0}forwarded/{urn:xmpp:delay}delay"] && ![messageNode check:@"{urn:xmpp:delay}delay"])
                    [messageNode addChild:[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result/{urn:xmpp:forward:0}forwarded/{urn:xmpp:delay}delay"]];
                
                DDLogDebug(@"mam extracted, messageNode is now: %@", messageNode);
            }
            else if(self.connectionProperties.usingCarbons2 && [outerMessageNode check:@"{urn:xmpp:carbons:2}*"])     //carbon copy
            {
                if(![self.connectionProperties.identity.jid isEqualToString:outerMessageNode.from])
                {
                    DDLogError(@"carbon copies must be from our bare jid, ignoring this spoofed carbon copy!");
                    //even these stanzas have to be counted by smacks
                    [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
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
            
            //sanity: check if inner message from and to attributes are valid and throw it away if not
            if([@"" isEqualToString:messageNode.from] || [@"" isEqualToString:messageNode.to])
            {
                DDLogError(@"sanity check failed for inner message node, ignoring message: %@", messageNode);
                //mark stanza as handled even if we don't process it further (we still received it, so we have to count it)
                [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                return;
            }
            
            //sanitize inner node: no from or to always means own bare jid
            if(!messageNode.from)
                messageNode.from = self.connectionProperties.identity.jid;
            if(!messageNode.to)
                messageNode.to = self.connectionProperties.identity.fullJid;
            
            //sanity: check if toUser or fromUser points to us and throw it away if not
            if([self.connectionProperties.identity.jid isEqualToString:messageNode.toUser] == NO && [self.connectionProperties.identity.jid isEqualToString:messageNode.fromUser] == NO)
            {
                DDLogError(@"sanity check failed for inner message node, ignoring message: %@", messageNode);
                //mark stanza as handled even if we don't process it further (we still received it, so we have to count it)
                [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                return;
            }
            
            //assert on wrong from and to values
            MLAssert(![messageNode.fromUser containsString:@"/"], @"messageNode.fromUser contains resource!", messageNode);
            MLAssert(![messageNode.toUser containsString:@"/"], @"messageNode.toUser contains resource!", messageNode);
            MLAssert(![outerMessageNode.fromUser containsString:@"/"], @"outerMessageNode.fromUser contains resource!", outerMessageNode);
            MLAssert(![outerMessageNode.toUser containsString:@"/"], @"outerMessageNode.toUser contains resource!", outerMessageNode);
            
            //capture normal (non-mam-result) messages for later processing while we are doing a mam catchup (even headline messages)
            //do so only while this archiveJid is listed in _inCatchup
            //(of course we DON'T handle already delayed message stanzas here)
            if(!delayedReplay && (
                (
                    ![[messageNode findFirst:@"/@type"] isEqualToString:@"groupchat"] &&
                    _inCatchup[self.connectionProperties.identity.jid] != nil &&
                    ![outerMessageNode check:@"{urn:xmpp:mam:2}result"]
                ) || (
                    [[messageNode findFirst:@"/@type"] isEqualToString:@"groupchat"] &&
                    _inCatchup[messageNode.fromUser] != nil &&
                    ![outerMessageNode check:@"{urn:xmpp:mam:2}result"]
                )
            )) {
                DDLogInfo(@"Saving incoming message node to delayedMessageStanzas...");
                [self delayIncomingMessageStanzaUntilCatchupDone:originalParsedStanza];
            }
            //only process mam results when they are *not* for priming the database with the initial stanzaid (the id will be taken from the iq result)
            //we do this because we don't want to randomly add one single message to our history db after the user installs the app / adds a new account
            //if the user wants to see older messages he can retrieve them using the ui (endless upscrolling through mam)
            //we don't want to process messages going backwards in time, too (e.g. MLhistory:* mam queries)
            else if(![outerMessageNode check:@"{urn:xmpp:mam:2}result"] || [[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"] hasPrefix:@"MLcatchup:"])
            {
                DDLogInfo(@"Processing message stanza (delayedReplay=%@)...", delayedReplay ? @"YES" : @"NO");
                
                //process message
                [MLMessageProcessor processMessage:messageNode andOuterMessage:outerMessageNode forAccount:self];
                
                NSString* stanzaid = [outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@id"];
                //extract stanza-id from message itself and check stanza-id @by according to the rules outlined in XEP-0359
                if(!stanzaid)
                {
                    if(![messageNode check:@"/<type=groupchat>"] && [self.connectionProperties.identity.jid isEqualToString:[messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@by"]])
                        stanzaid = [messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@id"];
                    else if([messageNode check:@"/<type=groupchat>"] && [messageNode.fromUser isEqualToString:[messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@by"]])
                        stanzaid = [messageNode findFirst:@"{urn:xmpp:sid:0}stanza-id@id"];
                }
                
                //handle stanzaids of groupchats differently (because groupchat messages do not enter the user's mam archive, but only the archive of the muc server)
                if(stanzaid && [messageNode check:@"/<type=groupchat>"])
                {
                    DDLogVerbose(@"Updating lastStanzaId of muc archive %@ in database to: %@", messageNode.fromUser, stanzaid);
                    [[DataLayer sharedInstance] setLastStanzaId:stanzaid forMuc:messageNode.fromUser andAccount:self.accountNo];
                }
                else if(stanzaid && ![messageNode check:@"/<type=groupchat>"])
                {
                    DDLogVerbose(@"Updating lastStanzaId of user archive in database to: %@", stanzaid);
                    [[DataLayer sharedInstance] setLastStanzaId:stanzaid forAccount:self.accountNo];
                }
            }
            else if([[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result@queryid"] hasPrefix:@"MLhistory:"])
                [self addMessageToMamPageArray:@{@"outerMessageNode": outerMessageNode, @"messageNode": messageNode}];       //add message to mam page array to be processed later
            
            //only mark stanza as handled *after* processing it
            [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
        }
        else if([parsedStanza check:@"/{jabber:client}iq"])
        {
            XMPPIQ* iqNode = (XMPPIQ*)parsedStanza;
            
            //sanity: check if iq from and to attributes are valid and throw it away if not
            if([@"" isEqualToString:iqNode.from] || [@"" isEqualToString:iqNode.to])
            {
                DDLogError(@"sanity check failed for iq node, ignoring iq: %@", iqNode);
                //mark stanza as handled even if we don't process it further (we still received it, so we have to count it)
                [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                return;
            }
            
            //sanitize: no from or to always means own bare jid
            if(!iqNode.from)
                iqNode.from = self.connectionProperties.identity.jid;
            if(!iqNode.to)
                iqNode.to = self.connectionProperties.identity.fullJid;
            
            //sanity: check if iq id and type attributes are present and toUser points to us and throw it away if not
            //use parsedStanza instead of iqNode to be sure we get the raw values even if ids etc. get added automaticaly to iq stanzas if accessed as XMPPIQ* object
            if(![parsedStanza check:@"/@id"] || ![parsedStanza check:@"/@type"] || ![self.connectionProperties.identity.jid isEqualToString:iqNode.toUser])
            {
                DDLogError(@"sanity check failed for iq node, ignoring iq: %@", iqNode);
                //mark stanza as handled even if we don't process it further (we still received it, so we have to count it)
                [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                return;
            }
            
            //remove handled mam queries from _runningMamQueries
            if([iqNode check:@"/<type=result>/{urn:xmpp:mam:2}fin"] && _runningMamQueries[[iqNode findFirst:@"/@id"]] != nil)
                [_runningMamQueries removeObjectForKey:[iqNode findFirst:@"/@id"]];
            else if([iqNode check:@"/<type=error>"] && _runningMamQueries[[iqNode findFirst:@"/@id"]] != nil)
                [_runningMamQueries removeObjectForKey:[iqNode findFirst:@"/@id"]];
            
            //process registered iq handlers
            NSMutableDictionary* iqHandler = nil;
            @synchronized(_iqHandlers) {
                iqHandler = _iqHandlers[[iqNode findFirst:@"/@id"]];
            }
            if(iqHandler)
            {
                if(iqHandler[@"handler"] != nil)
                    $call(iqHandler[@"handler"], $ID(account, self), $ID(iqNode));
                else if([iqNode check:@"/<type=result>"] && iqHandler[@"resultHandler"])
                    ((monal_iq_handler_t) iqHandler[@"resultHandler"])(iqNode);
                else if([iqNode check:@"/<type=error>"] && iqHandler[@"errorHandler"])
                    ((monal_iq_handler_t) iqHandler[@"errorHandler"])(iqNode);
                
                //remove handler after calling it
                @synchronized(_iqHandlers) {
                    [_iqHandlers removeObjectForKey:[iqNode findFirst:@"/@id"]];
                }
            }
            else            //only process iqs that have not already been handled by a registered iq handler
            {
                [MLIQProcessor processIq:iqNode forAccount:self];
            }
            
            //only mark stanza as handled *after* processing it
            [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
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
                if([[parsedStanza findFirst:@"/@resume|bool"] boolValue])
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
            if(h==nil)
                return [self invalidXMLError];
            self.resuming = NO;

            //now we are bound again
            _accountState = kStateBound;
            _connectedTime = [NSDate date];
            _usableServersList = [[NSMutableArray alloc] init];       //reset list to start again with the highest SRV priority on next connect
            _exponentialBackoff = 0;
            [self accountStatusChanged];

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
            
            //ping all mucs to check if we are still connected (XEP-0410)
            [self.mucProcessor pingAllMucs];
            
            @synchronized(_stateLockObject) {
                //signal finished catchup if our current outgoing stanza counter is acked, this introduces an additional roundtrip to make sure
                //all stanzas the *server* wanted to replay have been received, too
                //request an ack to accomplish this if stanza replay did not already trigger one (smacksRequestInFlight is false if replay did not trigger one)
                if(!self.smacksRequestInFlight)
                    [self requestSMAck:YES];    //force sending of the request even if the smacks queue is empty (needed to always trigger the smacks handler below after 1 RTT)
                DDLogVerbose(@"Adding resume smacks handler to check for completed catchup on account %@: %@", self.accountNo, self.lastOutboundStanza);
                weakify(self);
                [self addSmacksHandler:^{
                    strongify(self);
                    DDLogVerbose(@"Inside resume smacks handler: catchup done (%@)", self.lastOutboundStanza);
                    if(!self->_catchupDone)
                    {
                        self->_catchupDone = YES;
                        DDLogVerbose(@"Now posting kMonalFinishedCatchup notification");
                        //don't queue this notification because it should be handled INLINE inside the receive queue
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFinishedCatchup object:self userInfo:nil];
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
                if(h!=nil)
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
                    message = NSLocalizedString(@"Not Authorized. Please check your credentials.", @"");
            }
            else
            {
                if(!message)
                    message = NSLocalizedString(@"There was a SASL error on the server.", @"");
            }

            [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:self userInfo:@{@"message": message, @"isSevere": @YES}];
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
            NSString* message = [NSString stringWithFormat:NSLocalizedString(@"XMPP stream error: %@", @""), errorReason];
            if(errorText && ![errorText isEqualToString:@""])
                message = [NSString stringWithFormat:NSLocalizedString(@"XMPP stream error %@: %@", @""), errorReason, errorText];
            [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:self userInfo:@{@"message": message, @"isSevere": @NO}];
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
                        [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:self userInfo:@{@"message": NSLocalizedString(@"no supported auth mechanism, disconnecting!", @""), @"isSevere": @YES}];
                        [self disconnect];
                    }
                }
            }
            else
            {
                if([parsedStanza check:@"{urn:xmpp:csi:0}csi"])
                {
                    DDLogInfo(@"Server supports CSI");
                    self.connectionProperties.supportsClientState = YES;
                }
                if([parsedStanza check:@"{urn:xmpp:sm:3}sm"])
                {
                    DDLogInfo(@"Server supports SM3");
                    self.connectionProperties.supportsSM3 = YES;
                }
                if([parsedStanza check:@"{urn:xmpp:features:rosterver}ver"])
                {
                    DDLogInfo(@"Server supports roster versioning");
                    self.connectionProperties.supportsRosterVersion = YES;
                }
                if([parsedStanza check:@"{urn:xmpp:features:pre-approval}sub"])
                {
                    DDLogInfo(@"Server supports roster pre approval");
                    self.connectionProperties.supportsRosterPreApproval = YES;
                }
                if([parsedStanza check:@"{http://jabber.org/protocol/caps}c@node"])
                {
                    DDLogInfo(@"Server identity: %@", [parsedStanza findFirst:@"{http://jabber.org/protocol/caps}c@node"]);
                    self.connectionProperties.serverIdentity = [parsedStanza findFirst:@"{http://jabber.org/protocol/caps}c@node"];
                }
                
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
            NSString* message = [NSString stringWithFormat:NSLocalizedString(@"XMPP stream error: %@", @""), errorReason];
            if(errorText && ![errorText isEqualToString:@""])
                message = [NSString stringWithFormat:NSLocalizedString(@"XMPP stream error %@: %@", @""), errorReason, errorText];
            [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:self userInfo:@{@"message": message, @"isSevere": @NO}];
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
            //remove all pending data before starting tls handshake
            [_iPipe drainInputStream];
            
            //this will create an sslContext and, if the underlying TCP socket is already connected, immediately start the ssl handshake
            DDLogInfo(@"configuring/starting tls handshake");
            NSMutableDictionary* settings = [[NSMutableDictionary alloc] init];
            [settings setObject:(NSNumber*)kCFBooleanTrue forKey:(NSString*)kCFStreamSSLValidatesCertificateChain];
            [settings setObject:self.connectionProperties.identity.domain forKey:(NSString*)kCFStreamSSLPeerName];
            [settings setObject:@"kCFStreamSocketSecurityLevelTLSv1_2" forKey:(NSString*)kCFStreamSSLLevel];
            if(CFWriteStreamSetProperty((__bridge CFWriteStreamRef)self->_oStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings))
                DDLogInfo(@"Set TLS properties on streams. Security level %@", [self->_oStream propertyForKey:NSStreamSocketSecurityLevelKey]);
            else
            {
                DDLogError(@"not sure.. Could not confirm Set TLS properties on streams.");
                DDLogInfo(@"Set TLS properties on streams.security level %@", [self->_oStream propertyForKey:NSStreamSocketSecurityLevelKey]);
            }
            usleep(500000);        //try to avoid race conditions between tls setup and stream writes by sleeping some time
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
            _iqHandlers[iq.id] = [@{@"iq":iq, @"timeout":@(IQ_TIMEOUT), @"resultHandler":resultHandler, @"errorHandler":errorHandler} mutableCopy];
        }
    [self send:iq];
}

-(void) sendIq:(XMPPIQ*) iq withHandler:(MLHandler*) handler
{
    if(handler)
    {
        DDLogVerbose(@"Adding %@ to iqHandlers...", handler);
        @synchronized(_iqHandlers) {
            _iqHandlers[iq.id] = [@{@"iq":iq, @"timeout":@(IQ_TIMEOUT), @"handler":handler} mutableCopy];
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
    MLAssert(stanza != nil, @"stanza to send should not be nil!", @{@"withSmacks": @(withSmacks)});
    
    [self dispatchAsyncOnReceiveQueue:^{
        //add outgoing mam queryids to our state (but don't persist state because this will be done by smacks code below)
        NSString* mamQueryId = [stanza findFirst:@"/{jabber:client}iq/{urn:xmpp:mam:2}query@queryid"];
        if(mamQueryId)
            @synchronized(self->_stateLockObject) {
                DDLogDebug(@"Adding mam queryid to list: %@", mamQueryId);
                self->_runningMamQueries[mamQueryId] = stanza;
            }
        
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
            @synchronized(self->_stateLockObject) {
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
        //only exceptions: an outgoing bind request or jabber:iq:register stanza (this is allowed before binding a resource)
        BOOL isBindRequest = [stanza isKindOfClass:[XMPPIQ class]] && [stanza check:@"{urn:ietf:params:xml:ns:xmpp-bind}bind/resource"];
        BOOL isRegisterRequest = [stanza isKindOfClass:[XMPPIQ class]] && [stanza check:@"{jabber:iq:register}query"];
        if(
            self.accountState>=kStateBound ||
            (self.accountState>kStateDisconnected && (![stanza isKindOfClass:[XMPPStanza class]] || isBindRequest || isRegisterRequest))
        )
        {
            [self->_sendQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
                if([stanza check:@"/{urn:ietf:params:xml:ns:xmpp-sasl}*"])
                    DDLogDebug(@"SEND: redacted sasl element: %@", [stanza findFirst:@"/{urn:ietf:params:xml:ns:xmpp-sasl}*$"]);
                else if([stanza check:@"{jabber:iq:register}query"])
                    DDLogDebug(@"SEND: redacted register/change password iq");
                else
                    DDLogDebug(@"SEND: %@", stanza);
                [self->_outputQueue addObject:stanza];
                [self writeFromQueue];      // try to send if there is space
            }]];
        }
        else
            DDLogDebug(@"NOT ADDING STANZA TO SEND QUEUE: %@", stanza);
    }];
}

#pragma mark messaging

-(void) addEME:(NSString*) encryptionNamesapce withName:(NSString* _Nullable) name toMessageNode:(XMPPMessage*) messageNode
{
    if(name)
        [messageNode addChild:[[MLXMLNode alloc] initWithElement:@"encryption" andNamespace:@"urn:xmpp:eme:0" withAttributes:@{
            @"namespace": encryptionNamesapce,
            @"name": name
        } andChildren:@[] andData:nil]];
    else
        [messageNode addChild:[[MLXMLNode alloc] initWithElement:@"encryption" andNamespace:@"urn:xmpp:eme:0" withAttributes:@{
            @"namespace": encryptionNamesapce
        } andChildren:@[] andData:nil]];
}

-(void) sendMessage:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString*) messageId
{
    [self sendMessage:message toContact:contact isEncrypted:encrypt isUpload:isUpload andMessageId:messageId withLMCId:nil];
}

-(void) sendMessage:(NSString*) message toContact:(MLContact*) contact isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString*) messageId withLMCId:(NSString* _Nullable) LMCId
{
    DDLogVerbose(@"sending new outgoing message %@ to %@", messageId, contact.contactJid);
    
    XMPPMessage* messageNode = [[XMPPMessage alloc] init];
    messageNode.attributes[@"to"] = contact.contactJid;
    if(messageId)       //use the uuid autogenerated when our message node was created above if no id was supplied
        messageNode.id = messageId;

#ifdef IS_ALPHA
    // WARNING NOT FOR PRODUCTION
    // encrypt messages that should not be encrypted (but still use plaintext body for devices not speaking omemo)
    if(!encrypt && !isUpload)
    {
        [self.omemo encryptMessage:messageNode withMessage:message toContact:contact.contactJid];
        //[self addEME:@"eu.siacs.conversations.axolotl" withName:@"OMEMO" toMessageNode:messageNode];
    }
    // WARNING NOT FOR PRODUCTION END
#endif

#ifndef DISABLE_OMEMO
    //TODO: implement omemo for MUCs and remove this MUC check
    if(encrypt && !contact.isGroup)
    {
        [self.omemo encryptMessage:messageNode withMessage:message toContact:contact.contactJid];
        [self addEME:@"eu.siacs.conversations.axolotl" withName:@"OMEMO" toMessageNode:messageNode];
    }
    else
#endif
    {
        if(isUpload)
            [messageNode setOobUrl:message];
        else
            [messageNode setBody:message];
    }
    
    //set message type
    if(contact.isGroup)
        [messageNode.attributes setObject:kMessageGroupChatType forKey:@"type"];
    else
        [messageNode.attributes setObject:kMessageChatType forKey:@"type"];
    
    //request receipts and chat-markers in 1:1 or groups (no channels!)
    if(!contact.isGroup || [@"group" isEqualToString:contact.mucType])
    {
        [messageNode addChild:[[MLXMLNode alloc] initWithElement:@"request" andNamespace:@"urn:xmpp:receipts"]];
        [messageNode addChild:[[MLXMLNode alloc] initWithElement:@"markable" andNamespace:@"urn:xmpp:chat-markers:0"]];
    }

    //for MAM
    [messageNode setStoreHint];
    
    //handle LMC
    if(LMCId)
        [messageNode setLMCFor:LMCId];

    [self send:messageNode];
}

-(void) sendChatState:(BOOL) isTyping toJid:(NSString*) jid
{
    if(self.accountState < kStateBound)
        return;

    XMPPMessage* messageNode = [[XMPPMessage alloc] init];
    messageNode.attributes[@"to"] = jid;
    [messageNode setNoStoreHint];
    if(isTyping)
        [messageNode addChild:[[MLXMLNode alloc] initWithElement:@"composing" andNamespace:@"http://jabber.org/protocol/chatstates"]];
    else
        [messageNode addChild:[[MLXMLNode alloc] initWithElement:@"active" andNamespace:@"http://jabber.org/protocol/chatstates"]];
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
        NSMutableDictionary* persistentIqHandlerDescriptions = [[NSMutableDictionary alloc] init];
        @synchronized(_iqHandlers) {
            for(NSString* iqid in _iqHandlers)
                if(_iqHandlers[iqid][@"handler"] != nil)
                {
                    persistentIqHandlers[iqid] = _iqHandlers[iqid];
                    persistentIqHandlerDescriptions[iqid] = [NSString stringWithFormat:@"%@: %@", _iqHandlers[iqid][@"timeout"], _iqHandlers[iqid][@"handler"]];
                }
        }
        [values setObject:persistentIqHandlers forKey:@"iqHandlers"];

        [values setValue:[self.connectionProperties.serverFeatures copy] forKey:@"serverFeatures"];
        if(self.connectionProperties.uploadServer)
            [values setObject:self.connectionProperties.uploadServer forKey:@"uploadServer"];
        if(self.connectionProperties.conferenceServer)
            [values setObject:self.connectionProperties.conferenceServer forKey:@"conferenceServer"];
        
        [values setObject:[self.pubsub getInternalData] forKey:@"pubsubData"];
        [values setObject:[self.mucProcessor getInternalState] forKey:@"mucState"];
        [values setObject:_runningMamQueries forKey:@"runningMamQueries"];
        [values setObject:[NSNumber numberWithBool:_loggedInOnce] forKey:@"loggedInOnce"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.usingCarbons2] forKey:@"usingCarbons2"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPush] forKey:@"supportsPush"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.pushEnabled] forKey:@"pushEnabled"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.registeredOnPushAppserver] forKey:@"registeredOnPushAppserver"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsClientState] forKey:@"supportsClientState"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsMam2] forKey:@"supportsMAM"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPubSub] forKey:@"supportsPubSub"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsHTTPUpload] forKey:@"supportsHTTPUpload"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPing] forKey:@"supportsPing"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsRosterPreApproval] forKey:@"supportsRosterPreApproval"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsBlocking] forKey:@"supportsBlocking"];
        [values setObject:[NSNumber numberWithBool:self.connectionProperties.accountDiscoDone] forKey:@"accountDiscoDone"];
        [values setObject:[_inCatchup copy] forKey:@"inCatchup"];
        
        if(self.connectionProperties.discoveredServices)
            [values setObject:[self.connectionProperties.discoveredServices copy] forKey:@"discoveredServices"];

        [values setObject:_lastInteractionDate forKey:@"lastInteractionDate"];
        [values setValue:[NSDate date] forKey:@"stateSavedAt"];
        [values setValue:@(STATE_VERSION) forKey:@"VERSION"];

        //save state dictionary
        [[DataLayer sharedInstance] persistState:values forAccount:self.accountNo];

        //debug output
        DDLogVerbose(@"%@ --> persistState(saved at %@):\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@\n\tlastInteractionDate=%@\n\tpersistentIqHandlers=%@\n\tsupportsPush=%d\n\tsupportsHttpUpload=%d\n\tpushEnabled=%d\n\tsupportsPubSub=%d\n\tsupportsBlocking=%d\n\tsupportsClientState=%d\n\t_inCatchup=%@",
            self.accountNo,
            values[@"stateSavedAt"],
            self.lastHandledInboundStanza,
            self.lastHandledOutboundStanza,
            self.lastOutboundStanza,
            self.unAckedStanzas ? [self.unAckedStanzas count] : 0, self.unAckedStanzas ? "" : " (NIL)",
            self.streamID,
            _lastInteractionDate,
            persistentIqHandlerDescriptions,
            self.connectionProperties.supportsPush,
            self.connectionProperties.supportsHTTPUpload,
            self.connectionProperties.pushEnabled,
            self.connectionProperties.supportsPubSub,
            self.connectionProperties.supportsBlocking,
            self.connectionProperties.supportsClientState,
            _inCatchup
        );
    }
}

-(void) readSmacksStateOnly
{
    @synchronized(_stateLockObject) {
        NSMutableDictionary* dic = [[DataLayer sharedInstance] readStateForAccount:self.accountNo];
        if(dic)
        {
            //check state version
            if([dic[@"VERSION"] intValue] != STATE_VERSION)
            {
                DDLogWarn(@"Account state upgraded from %@ to %d, invalidating state...", dic[@"VERSION"], STATE_VERSION);
                dic = [[self class] invalidateState:dic];
            }
            
            //collect smacks state
            self.lastHandledInboundStanza = [dic objectForKey:@"lastHandledInboundStanza"];
            self.lastHandledOutboundStanza = [dic objectForKey:@"lastHandledOutboundStanza"];
            self.lastOutboundStanza = [dic objectForKey:@"lastOutboundStanza"];
            NSArray* stanzas = [dic objectForKey:@"unAckedStanzas"];
            self.unAckedStanzas = [stanzas mutableCopy];
            self.streamID = [dic objectForKey:@"streamID"];
            
            @synchronized(_stateLockObject) {
                //invalidate corrupt smacks states (this could potentially loose messages, but hey, the state is corrupt anyways)
                if(self.lastHandledInboundStanza == nil || self.lastHandledOutboundStanza == nil || self.lastOutboundStanza == nil || !self.unAckedStanzas)
                {
#ifndef IS_ALPHA
                    [self initSM3];
#else
                    @throw [NSException exceptionWithName:@"RuntimeError" reason:@"corrupt smacks state" userInfo:dic];
#endif
                }
            }
            
            //the list of mam queryids is closely coupled with smacks state (it records mam queryids of outgoing stanzas)
            //--> load them even when loading smacks state only
            if([dic objectForKey:@"runningMamQueries"])
                _runningMamQueries = [[dic objectForKey:@"runningMamQueries"] mutableCopy];
            
            //debug output
            DDLogVerbose(@"%@ --> readSmacksStateOnly(saved at %@):\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@,\n\tlastInteractionDate=%@",
                self.accountNo,
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
            //check state version
            if([dic[@"VERSION"] intValue] != STATE_VERSION)
            {
                DDLogWarn(@"Account state upgraded from %@ to %d, invalidating state...", dic[@"VERSION"], STATE_VERSION);
                dic = [[self class] invalidateState:dic];
            }
            
            //collect smacks state
            self.lastHandledInboundStanza = [dic objectForKey:@"lastHandledInboundStanza"];
            self.lastHandledOutboundStanza = [dic objectForKey:@"lastHandledOutboundStanza"];
            self.lastOutboundStanza = [dic objectForKey:@"lastOutboundStanza"];
            NSArray* stanzas = [dic objectForKey:@"unAckedStanzas"];
            self.unAckedStanzas = [stanzas mutableCopy];
            self.streamID = [dic objectForKey:@"streamID"];
            
            @synchronized(_stateLockObject) {
                //invalidate corrupt smacks states (this could potentially loose messages, but hey, the state is corrupt anyways)
                if(self.lastHandledInboundStanza == nil || self.lastHandledOutboundStanza == nil || self.lastOutboundStanza == nil || !self.unAckedStanzas)
                {
#ifndef IS_ALPHA
                    [self initSM3];
#else
                    @throw [NSException exceptionWithName:@"RuntimeError" reason:@"corrupt smacks state" userInfo:dic];
#endif
                }
            }
            
            NSDictionary* persistentIqHandlers = [dic objectForKey:@"iqHandlers"];
            NSMutableDictionary* persistentIqHandlerDescriptions = [[NSMutableDictionary alloc] init];
            @synchronized(_iqHandlers) {
                for(NSString* iqid in persistentIqHandlers)
                {
                    _iqHandlers[iqid] = [persistentIqHandlers[iqid] mutableCopy];
                    persistentIqHandlerDescriptions[iqid] = [NSString stringWithFormat:@"%@: %@", persistentIqHandlers[iqid][@"timeout"], persistentIqHandlers[iqid][@"handler"]];
                }
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
            
            if([dic objectForKey:@"registeredOnPushAppserver"])
            {
                NSNumber* registeredOnPushAppserver = [dic objectForKey:@"registeredOnPushAppserver"];
                self.connectionProperties.registeredOnPushAppserver = registeredOnPushAppserver.boolValue;
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
            
            if([dic objectForKey:@"supportsBlocking"])
            {
                NSNumber* supportsBlocking = [dic objectForKey:@"supportsBlocking"];
                self.connectionProperties.supportsBlocking = supportsBlocking.boolValue;
            }
            
            if([dic objectForKey:@"accountDiscoDone"])
            {
                NSNumber* accountDiscoDone = [dic objectForKey:@"accountDiscoDone"];
                self.connectionProperties.accountDiscoDone = accountDiscoDone.boolValue;
            }
            
            if([dic objectForKey:@"pubsubData"])
                [self.pubsub setInternalData:[dic objectForKey:@"pubsubData"]];
            
            if([dic objectForKey:@"mucState"])
                [self.mucProcessor setInternalState:[dic objectForKey:@"mucState"]];
            
            if([dic objectForKey:@"runningMamQueries"])
                _runningMamQueries = [[dic objectForKey:@"runningMamQueries"] mutableCopy];
            
            if([dic objectForKey:@"inCatchup"])
                _inCatchup = [[dic objectForKey:@"inCatchup"] mutableCopy];
            
            //debug output
            DDLogVerbose(@"%@ --> readState(saved at %@):\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@,\n\tlastInteractionDate=%@\n\tpersistentIqHandlers=%@\n\tsupportsPush=%d\n\tsupportsHttpUpload=%d\n\tpushEnabled=%d\n\tsupportsPubSub=%d\n\tsupportsBlocking=%d\n\tsupportsClientSate=%d\n\t_inCatchup=%@",
                self.accountNo,
                dic[@"stateSavedAt"],
                self.lastHandledInboundStanza,
                self.lastHandledOutboundStanza,
                self.lastOutboundStanza,
                self.unAckedStanzas ? [self.unAckedStanzas count] : 0, self.unAckedStanzas ? "" : " (NIL)",
                self.streamID,
                _lastInteractionDate,
                persistentIqHandlerDescriptions,
                self.connectionProperties.supportsPush,
                self.connectionProperties.supportsHTTPUpload,
                self.connectionProperties.pushEnabled,
                self.connectionProperties.supportsPubSub,
                self.connectionProperties.supportsBlocking,
                self.connectionProperties.supportsClientState,
                _inCatchup
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

+(NSMutableDictionary*) invalidateState:(NSDictionary*) dic
{
    NSArray* toKeep = @[@"lastHandledInboundStanza", @"lastHandledOutboundStanza", @"lastOutboundStanza", @"unAckedStanzas", @"loggedInOnce", @"lastInteractionDate", @"inCatchup"];
    
    NSMutableDictionary* newState = [[NSMutableDictionary alloc] init];
    if(dic)
    {
        for(NSString* entry in toKeep)
            newState[entry] = dic[entry];
        
        newState[@"stateSavedAt"] = [NSDate date];
        newState[@"VERSION"] = @(STATE_VERSION);
    }
    return newState;
}

-(void) incrementLastHandledStanzaWithDelayedReplay:(BOOL) delayedReplay
{
    //don't ack messages twice
    if(delayedReplay)
        return;
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
    if(resource == nil)
        return [self bindResource:[HelperTools encodeRandomResource]];
    //check if our resource is a modern one and change it to a modern one if not
    //this should fix rare bugs when monal was first installed a long time ago when the resource didn't yet had a random part
    NSArray* parts = [resource componentsSeparatedByString:@"."];
    if([parts count] < 2 || [[HelperTools dataWithHexString:parts[1]] length] < 1)
        return [self bindResource:[HelperTools encodeRandomResource]];
    
    _accountState = kStateBinding;
    XMPPIQ* iqNode = [[XMPPIQ alloc] initWithType:kiqSetType];
    [iqNode setBindWithResource:resource];
    [self sendIq:iqNode withHandler:$newHandler(MLIQProcessor, handleBind)];
}

-(void) queryDisco
{
    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoInfo setiqTo:self.connectionProperties.identity.domain];
    [discoInfo setDiscoInfoNode];
    [self sendIq:discoInfo withHandler:$newHandler(MLIQProcessor, handleServerDiscoInfo)];
    
    XMPPIQ* discoItems = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoItems setiqTo:self.connectionProperties.identity.domain];
    [discoItems setDiscoItemNode];
    [self sendIq:discoItems withHandler:$newHandler(MLIQProcessor, handleServerDiscoItems)];
    
    XMPPIQ* accountInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
    [accountInfo setiqTo:self.connectionProperties.identity.jid];
    [accountInfo setDiscoInfoNode];
    [self sendIq:accountInfo withHandler:$newHandler(MLIQProcessor, handleAccountDiscoInfo)];
}

-(void) purgeOfflineStorage
{
    XMPPIQ* purgeIq = [[XMPPIQ alloc] initWithType:kiqSetType];
    [purgeIq setPurgeOfflineStorage];
    [self sendIq:purgeIq withResponseHandler:^(XMPPIQ* response) {
        DDLogInfo(@"Successfully purged offline storage...");
    } andErrorHandler:^(XMPPIQ* error) {
        DDLogWarn(@"Could not purge offline storage (using XEP-0013): %@", error);
    }];
}

-(void) sendPresence
{
    //don't send presences if we are not bound
    if(_accountState < kStateBound)
        return;
    
    XMPPPresence* presence = [[XMPPPresence alloc] initWithHash:_capsHash];
    if(![self.statusMessage isEqualToString:@""])
        [presence setStatus:self.statusMessage];
    
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
    [self sendIq:roster withHandler:$newHandler(MLIQProcessor, handleRoster)];
}

-(void) initSession
{
    DDLogInfo(@"Now bound, initializing new xmpp session");
    
    //delete old resources because we get new presences once we're done initializing the session
    [[DataLayer sharedInstance] resetContactsForAccount:self.accountNo];
    
    //we are now bound
    _connectedTime = [NSDate date];
    _usableServersList = [[NSMutableArray alloc] init];     //reset list to start again with the highest SRV priority on next connect
    _exponentialBackoff = 0;
    
    //inform all old iq handlers of invalidation and clear _iqHandlers dictionary afterwards
    @synchronized(_iqHandlers) {
        //make sure this works even if the invalidation handlers add a new iq to the list
        NSMutableDictionary* handlersCopy = [_iqHandlers mutableCopy];
        _iqHandlers = [[NSMutableDictionary alloc] init];
        
        for(NSString* iqid in handlersCopy)
        {
            DDLogWarn(@"Invalidating iq handler for iq id '%@'", iqid);
            if(handlersCopy[iqid][@"handler"] != nil)
                $invalidate(handlersCopy[iqid][@"handler"], $ID(account, self));
            else if(handlersCopy[iqid][@"errorHandler"])
                ((monal_iq_handler_t)handlersCopy[iqid][@"errorHandler"])(nil);
        }
    }
    
    //clear muc state
    [self.mucProcessor resetForNewSession];
    
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
    self.connectionProperties.registeredOnPushAppserver = NO;
    self.connectionProperties.supportsMam2 = NO;
    self.connectionProperties.supportsPubSub = NO;
    self.connectionProperties.supportsHTTPUpload = NO;
    self.connectionProperties.supportsPing = NO;
    self.connectionProperties.supportsRosterPreApproval = NO;
    
    //clear list of running mam queries
    _runningMamQueries = [[NSMutableDictionary alloc] init];
    
    //clear old catchup state (technically all stanzas still in delayedMessageStanzas could have also been in the parseQueue in the last run and deleted there
    //--> no harm in deleting them when starting a new session (but DON'T DELETE them when resuming the old smacks session)
    _inCatchup = [[NSMutableDictionary alloc] init];
    [[DataLayer sharedInstance] deleteDelayedMessageStanzasForAccount:self.accountNo];
    
    //indicate we are bound now, *after* initializing/resetting all the other data structures to avoid race conditions
    _accountState = kStateBound;
    
    //don't queue this notification because it should be handled INLINE inside the receive queue
    [[NSNotificationCenter defaultCenter] postNotificationName:kMLHasConnectedNotice object:self];
    [self accountStatusChanged];
    
    //now fetch roster, request disco and send initial presence
    [self fetchRoster];
    
    //query disco *before* sending out our first presence because this presence will trigger pubsub "headline" updates and we want to know
    //if and what pubsub/pep features the server supports, before handling that
    //we can pipeline the disco requests and outgoing presence broadcast, though
    [self queryDisco];
    [self purgeOfflineStorage];
    [self sendPresence];            //this will trigger a replay of offline stanzas on prosody (no XEP-0013 support anymore 😡)
    //the offline messages will come in *after* we started to query mam, because the disco result comes in first (and this is what triggers mam catchup)
    //--> no holes in our history can be caused by these offline messages in conjunction with mam catchup,
    //    however all offline messages will be received twice (as offline message AND via mam catchup)
    
    //send own csi state (this must be done *after* presences to not delay/filter incoming presence flood needed to prime our database
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
    
    //NOTE: mam query will be done in MLIQProcessor once the disco result for our own jid/account returns
    
    //join MUCs from muc_favorites db
    for(NSDictionary* entry in [[DataLayer sharedInstance] listMucsForAccount:self.accountNo])
        [self.mucProcessor join:entry[@"room"]];
}

-(void) setBlocked:(BOOL) blocked forJid:(NSString* _Nonnull) blockedJid
{
    if(!self.connectionProperties.supportsBlocking)
        return;
    
    XMPPIQ* iqBlocked = [[XMPPIQ alloc] initWithType:kiqSetType];
    
    [iqBlocked setBlocked:blocked forJid:blockedJid];
    [self send:iqBlocked];
}

-(void) fetchBlocklist
{
    if(!self.connectionProperties.supportsBlocking) 
        return;
    
    XMPPIQ* iqBlockList = [[XMPPIQ alloc] initWithType:kiqGetType];
    
    [iqBlockList requestBlockList];
    [self sendIq:iqBlockList withHandler:$newHandler(MLIQProcessor, handleBlocklist)];;
}

-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids
{
    [[DataLayer sharedInstance] updateLocalBlocklistCache:blockedJids forAccountNo:self.accountNo];
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
        httpUploadforFile:params[@"fileName"]
        ofSize:[NSNumber numberWithInteger:((NSData*)params[@"data"]).length]
        andContentType:params[@"contentType"]
    ];
    [self sendIq:httpSlotRequest withResponseHandler:^(XMPPIQ* response) {
        DDLogInfo(@"Got slot for upload: %@", [response findFirst:@"{urn:xmpp:http:upload:0}slot/put@url"]);
        //upload to server using HTTP PUT
        NSMutableDictionary* headers = [[NSMutableDictionary alloc] init];
        headers[@"Content-Type"] = params[@"contentType"];
        for(MLXMLNode* header in [response find:@"{urn:xmpp:http:upload:0}slot/put/header"])
            headers[[header findFirst:@"/@name"]] = [header findFirst:@"/#"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [MLHTTPRequest
                sendWithVerb:kPut path:[response findFirst:@"{urn:xmpp:http:upload:0}slot/put@url"]
                headers:headers
                withArguments:nil
                data:params[@"data"]
                andCompletionHandler:^(NSError* error, id result) {
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
            completion(nil, error == nil ? [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Upload Error: your account got disconnected while requesting upload slot", @"")}] : [NSError errorWithDomain:@"MonalError" code:0 userInfo:@{NSLocalizedDescriptionKey: [HelperTools extractXMPPError:error withDescription:NSLocalizedString(@"Upload Error", @"")]}]);
    }];
}

#pragma mark client state
-(void) setClientActive
{
    [self dispatchAsyncOnReceiveQueue: ^{
        //ignore active --> active transition
        if(self->_isCSIActive)
        {
            DDLogVerbose(@"Ignoring CSI transition from active to active");
            return;
        }
        
        //record new csi state and send csi nonza
        self->_isCSIActive = YES;
        [self sendCurrentCSIState];
        
        //to make sure this date is newer than the old saved one (even if we now falsely "tag" the beginning of our interaction, not the end)
        //if everything works out as it should and the app does not get killed, we will "tag" the end of our interaction as soon as the app is backgrounded
        self->_lastInteractionDate = [NSDate date];
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
        if(!self->_isCSIActive)
        {
            DDLogVerbose(@"Ignoring CSI transition from INactive to INactive");
            return;
        }
        
        //save date as last interaction date (XEP-0319) (e.g. "tag" the end of our interaction)
        self->_lastInteractionDate = [NSDate date];
        [self persistState];
        
        //record new state
        self->_isCSIActive = NO;
        
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
        {
            DDLogVerbose(@"NOT sending csi state, because we are not bound yet");
            return;
        }
        
        //really send csi nonza
        MLXMLNode* csiNode;
        if(self->_isCSIActive)
            csiNode = [[MLXMLNode alloc] initWithElement:@"active" andNamespace:@"urn:xmpp:csi:0"];
        else
            csiNode = [[MLXMLNode alloc] initWithElement:@"inactive" andNamespace:@"urn:xmpp:csi:0"];
        [self send:csiNode];
    }];
}

#pragma mark - Message archive


-(void) setMAMPrefs:(NSString*) preference
{
    if(!self.connectionProperties.supportsMam2)
        return;
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
    [query updateMamArchivePrefDefault:preference];
    [self sendIq:query withHandler:$newHandler(MLIQProcessor, handleSetMamPrefs)];
}

-(void) getMAMPrefs
{
    XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqGetType];
    [query mamArchivePref];
    [self sendIq:query withHandler:$newHandler(MLIQProcessor, handleMamPrefs)];
}

-(void) setMAMQueryMostRecentForContact:(MLContact*) contact before:(NSString*) uid withCompletion:(void (^)(NSArray* _Nullable, NSString* _Nullable error)) completion
{
    //the completion handler will get nil, if an error prevented us toget any messaes, an empty array, if the upper end of our archive was reached or an array
    //of newly loaded mlmessages in all other cases
    unsigned int __block retrievedBodies = 0;
    NSMutableArray* __block pageList = [[NSMutableArray alloc] init];
    void __block (^query)(NSString* before);
    monal_iq_handler_t __block responseHandler;
    monal_void_block_t callUI = ^{
        //if we did not retrieve any body messages we don't need to process metadata sanzas (if any), but signal we reached the end of our archive
        //callUI() will only be called with retrievedBodies == 0 if we reached the upper end of our mam archive, because iq errors have already been
        //handled in the iq error handler below
        if(retrievedBodies == 0)
        {
            completion(@[], nil);
            return;
        }
        
        NSMutableArray* __block historyIdList = [[NSMutableArray alloc] init];
        NSNumber* __block historyId = [NSNumber numberWithInt:[[[DataLayer sharedInstance] getSmallestHistoryId] intValue] - retrievedBodies];
        
        //process all queued mam stanzas in a dedicated db write transaction
        [[DataLayer sharedInstance] createTransaction:^{
            //ignore all notifications generated while processing the queued stanzas
            [MLNotificationQueue queueNotificationsInBlock:^{
                //iterate through all pages and their messages forward in time (pages have already been sorted forward in time internally)
                for(NSArray* page in [[pageList reverseObjectEnumerator] allObjects])
                {
                    //process received message stanzas and manipulate the db accordingly
                    //if a new message got added to the history db, the message processor will return a MLMessage instance containing the history id of the newly created entry
                    for(NSDictionary* data in page)
                    {
                        DDLogVerbose(@"Handling mam page entry: %@", data);
                        MLMessage* msg = [MLMessageProcessor processMessage:data[@"messageNode"] andOuterMessage:data[@"outerMessageNode"] forAccount:self withHistoryId:historyId];
                        //add successfully added messages to our display list
                        //stanzas not transporting a body will be processed, too, but the message processor will return nil for these
                        if(msg != nil)
                        {
                            [historyIdList addObject:msg.messageDBId];      //we only need the history id to fetch a fresh copy later
                            historyId = [NSNumber numberWithInt:[historyId intValue] + 1];      //calculate next history id
                        }
                    }
                }
                
                //throw away all queued notifications before leaving this context
                [(MLNotificationQueue*)[MLNotificationQueue currentQueue] clear];
            } onQueue:@"MLhistoryIgnoreQueue"];
        }];
        
        DDLogDebug(@"collected mam:2 before-pages now contain %lu messages in summary not already in history", (unsigned long)[historyIdList count]);
        MLAssert([historyIdList count] <= retrievedBodies, @"did add more messages to historydb table than bodies collected!", (@{
            @"historyIdList": historyIdList,
            @"retrievedBodies": @(retrievedBodies),
        }));
        if([historyIdList count] < retrievedBodies)
            DDLogWarn(@"Got %lu mam history messages already contained in history db, possibly ougoing messages that did not have a stanzaid yet!", (unsigned long)(retrievedBodies - [historyIdList count]));
        if(![historyIdList count])
        {
            //call completion with nil to signal an error, if we could not get any messages not yet in history db
            completion(nil, nil);
        }
        else
        {
            //query db (again) for the real MLMessage to account for changes in history table by non-body metadata messages received after the body-message
            completion([[DataLayer sharedInstance] messagesForHistoryIDs:historyIdList], nil);
        }
    };
    responseHandler = ^(XMPPIQ* response) {
        NSMutableArray* mamPage = [self getOrderedMamPageFor:[response findFirst:@"/@id"]];
        
        //count new bodies
        for(NSDictionary* data in mamPage)
            if([data[@"messageNode"] check:@"body#"])
                retrievedBodies++;
        
        //add new mam page to page list
        [pageList addObject:mamPage];
        
        //check if we need to load more messages
        if(retrievedBodies > 25)
        {
            //call completion to display all messages saved in db
            callUI();
        }
        //query fo more messages or call completion to display all messages saved in db if we reached the end of our mam archive
        else
        {
            //page through to get more messages (a page possibly contains fewer than 25 messages having a body)
            //but because we query for 50 stanzas we could easily get more than 25 messages having a body, too
            if(
                ![[response findFirst:@"{urn:xmpp:mam:2}fin@complete|bool"] boolValue] &&
                [response check:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/first#"]
            )
            {
                query([response findFirst:@"{urn:xmpp:mam:2}fin/{http://jabber.org/protocol/rsm}set/first#"]);
            }
            else
            {
                DDLogDebug(@"Reached upper end of mam:2 archive, returning %lu messages to ui", (unsigned long)retrievedBodies);
                //can be fewer than 25 messages because we reached the upper end of the mam archive
                //even zero body-messages could be true
                callUI();
            }
        }
    };
    query = ^(NSString* _Nullable before) {
        XMPPIQ* query = [[XMPPIQ alloc] initWithType:kiqSetType];
        if(contact.isGroup)
        {
            if(!before)
                before = [[DataLayer sharedInstance] lastStanzaIdForMuc:contact.contactJid andAccount:self.accountNo];
            [query setiqTo:contact.contactJid];
            [query setMAMQueryLatestMessagesForJid:nil before:before];
        }
        else
        {
            if(!before)
                before = [[DataLayer sharedInstance] lastStanzaIdForAccount:self.accountNo];
            [query setMAMQueryLatestMessagesForJid:contact.contactJid before:before];
        }
        DDLogDebug(@"Loading (next) mam:2 page before: %@", before);
        //we always want to use blocks here because we want to make sure we get not interrupted by an app crash/restart
        //which would make us use incomplete mam pages that would produce holes in history (those are very hard to remove/fill afterwards)
        [self sendIq:query withResponseHandler:responseHandler andErrorHandler:^(XMPPIQ* error) {
            DDLogWarn(@"Got mam:2 before-query error, returning %lu messages to ui", (unsigned long)retrievedBodies);
            if(retrievedBodies == 0)
            {
                //call completion with nil, if there was an error or xmpp reconnect that prevented us to get any body-messages
                //but only for non-item-not-found errors (and internal-server-error errors sent by one of ejabberd or prosody instead [don't know which one it was])
                if(error == nil || ([error check:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}internal-server-error"] && [@"item-not-found" isEqualToString:[error findFirst:@"error/{urn:ietf:params:xml:ns:xmpp-stanzas}text#"]]))
                    completion(nil, nil);
                else
                    completion(nil, [HelperTools extractXMPPError:error withDescription:nil]);
            }
            else
            {
                //we had an error but we did already load some body-messages --> update ui anyways
                callUI();
            }
        }];
    };
    query(uid);
}

#pragma mark - MUC

-(void) joinMuc:(NSString* _Nonnull) room
{
    [self.mucProcessor join:room];
}

-(void) leaveMuc:(NSString* _Nonnull) room
{
    [self.mucProcessor leave:room withBookmarksUpdate:YES];
}

-(void) checkJidType:(NSString*) jid withCompletion:(void (^)(NSString* type, NSString* _Nullable errorMessage)) completion
{
    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoInfo setiqTo:jid];
    [discoInfo setDiscoInfoNode];
    [self sendIq:discoInfo withResponseHandler:^(XMPPIQ* response) {
        NSSet* features = [NSSet setWithArray:[response find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
        //check if this is a muc or account
        if([features containsObject:@"http://jabber.org/protocol/muc"])
            return completion(@"muc", nil);
        else
            return completion(@"account", nil);
    } andErrorHandler:^(XMPPIQ* error) {
        //this means the jid is an account which can not be queried if not subscribed
        if([error check:@"/<type=error>/error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}service-unavailable"])
            return completion(@"account", nil);
        else if([error check:@"/<type=error>/error<type=auth>/{urn:ietf:params:xml:ns:xmpp-stanzas}subscription-required"])
            return completion(@"account", nil);
        //any other error probably means the remote server is not reachable or (even more likely) the jid is incorrect
        NSString* errorDescription = [HelperTools extractXMPPError:error withDescription:NSLocalizedString(@"Unexpected error while checking type of jid:", @"")];
        DDLogError(@"checkJidType got an error, informing user: %@", errorDescription);
        return completion(@"error", error == nil ? NSLocalizedString(@"Unexpected error while checking type of jid, please try again", @"") : errorDescription);
    }];
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
    [self send:presence];   //add them
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
    [self sendIq:roster withHandler:$newHandler(MLIQProcessor, handleRoster)];
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
                completion(NO, error ? [HelperTools extractXMPPError:error withDescription:NSLocalizedString(@"Could not change password", @"")] : NSLocalizedString(@"Could not change password: your account is currently not connected", @""));
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
        if(self->_regFormCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSMutableDictionary* hiddenFormFields = [[NSMutableDictionary alloc] init];
                for(MLXMLNode* field in [result find:@"{jabber:iq:register}query/{jabber:x:data}x<type=form>/field<type=hidden>"])
                    hiddenFormFields[[field findFirst:@"/@var"]] = [field findFirst:@"value#"];
                self->_regFormCompletion([result findFirst:@"{jabber:iq:register}query/{jabber:x:data}x<type=form>/{*}data"], hiddenFormFields);
            });
    } andErrorHandler:^(XMPPIQ* error) {
        //dispatch completion handler outside of the receiveQueue
        if(self->_regFormErrorCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                self->_regFormErrorCompletion(NO, [HelperTools extractXMPPError:error withDescription:@"Could not request registration form"]);
            });
    }];
}

-(void) submitRegForm
{
    XMPPIQ* iq =[[XMPPIQ alloc] initWithType:kiqSetType];
    [iq registerUser:self.regUser withPassword:self.regPass captcha:self.regCode andHiddenFields:self.regHidden];

    [self sendIq:iq withResponseHandler:^(XMPPIQ* result) {
        //dispatch completion handler outside of the receiveQueue
        if(self->_regFormSubmitCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                self->_regFormSubmitCompletion(YES, nil);
            });
    } andErrorHandler:^(XMPPIQ* error) {
        //dispatch completion handler outside of the receiveQueue
        if(self->_regFormSubmitCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                self->_regFormSubmitCompletion(NO, [HelperTools extractXMPPError:error withDescription:@"Could not submit registration"]);
            });
    }];
}

#pragma mark - nsstream delegate

- (void)stream:(NSStream*) stream handleEvent:(NSStreamEvent) eventCode
{
    DDLogDebug(@"Stream %@ has event %lu", stream, (unsigned long)eventCode);
    switch(eventCode)
    {
        case NSStreamEventOpenCompleted:
        {
            DDLogVerbose(@"Stream %@ open completed", stream);
            //reset _streamHasSpace to its default value until the fist NSStreamEventHasSpaceAvailable event occurs
            if(stream == _oStream)
                self->_streamHasSpace = NO;
            break;
        }
        
        //for writing
        case NSStreamEventHasSpaceAvailable:
        {
            if(stream != _oStream)
            {
                DDLogDebug(@"Ignoring NSStreamEventHasSpaceAvailable event on wrong stream %@", stream);
                break;
            }
            [_sendQueue addOperationWithBlock: ^{
                DDLogVerbose(@"Stream %@ has space to write", stream);
                self->_streamHasSpace=YES;
                [self writeFromQueue];
            }];
            break;
        }
        
        //for reading
        case NSStreamEventHasBytesAvailable:
        {
            DDLogError(@"Stream %@ has bytes to read (should not be called!)", stream);
            break;
        }
        
        case NSStreamEventErrorOccurred:
        {
            NSError* st_error = [stream streamError];
            DDLogError(@"Stream %@ error code=%ld domain=%@ local desc:%@", stream, (long)st_error.code,st_error.domain, st_error.localizedDescription);
            if(stream != _oStream)      //check for _oStream here, because we don't have any _iStream (the mlpipe input stream was directly handed over to the xml parser)
            {
                DDLogInfo(@"Ignoring error in iStream (will already be handled in oStream error handler");
                break;
            }
            
            NSString* message = st_error.localizedDescription;
            switch(st_error.code)
            {
                case errSSLXCertChainInvalid: {
                    message = NSLocalizedString(@"SSL Error: Certificate chain is invalid", @"");
                    break;
                }

                case errSSLUnknownRootCert: {
                    message = NSLocalizedString(@"SSL Error: Unknown root certificate", @"");
                    break;
                }

                case errSSLCertExpired: {
                    message = NSLocalizedString(@"SSL Error: Certificate expired", @"");
                    break;
                }

                case errSSLHostNameMismatch: {
                    message = NSLocalizedString(@"SSL Error: Host name mismatch", @"");
                    break;
                }

            }
            if(!_registration)
            {
                // Do not show "Connection refused" message if there are more SRV records to try
                if(!_SRVDiscoveryDone || (_SRVDiscoveryDone && [_usableServersList count] == 0) || st_error.code != 61)
                    [[MLNotificationQueue currentQueue] postNotificationName:kXMPPError object:self userInfo:@{@"message": message, @"isSevere": @NO}];
            }

            DDLogInfo(@"stream error, calling reconnect");
            [self reconnect];
            
            break;
        }
        
        case NSStreamEventNone:
        {
            DDLogVerbose(@"Stream %@ event none", stream);
            break;
        }
        
        case NSStreamEventEndEncountered:
        {
            DDLogInfo(@"%@ Stream %@ encountered eof, trying to reconnect via parse queue in 1 second", [stream class], stream);
            //use a timer to make sure the incoming data was pushed *through* the MLPipe and reached the parseQueue already when pushng our reconnct block onto the parseQueue
            createTimer(1.0, (^{
                //add this to parseQueue to make sure we completely handle everything that came in before the connection was closed, before handling the close event itself
                [_parseQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                    DDLogInfo(@"Inside parseQueue: %@ Stream %@ encountered eof, trying to reconnect", [stream class], stream);
                    [self reconnect];
                }]] waitUntilFinished:NO];
            }));
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
        DDLogVerbose(@"no entries in _outputQueue. trying to send half-sent data.");
        [self writeToStream:nil];
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
        DDLogVerbose(@"sending remaining bytes in outputBuffer: %lu", (unsigned long)_outputBufferByteCount);
        NSInteger sentLen=[_oStream write:_outputBuffer maxLength:_outputBufferByteCount];
        if(sentLen!=-1)
        {
            if(sentLen!=_outputBufferByteCount)		//some bytes remaining to send --> trim buffer and return NO
            {
                DDLogVerbose(@"could not send all bytes in outputBuffer: %lu of %lu sent, %lu remaining", (unsigned long)sentLen, (unsigned long)_outputBufferByteCount, (unsigned long)(_outputBufferByteCount-sentLen));
                memmove(_outputBuffer, _outputBuffer+(size_t)sentLen, _outputBufferByteCount-(size_t)sentLen);
                _outputBufferByteCount-=sentLen;
                _streamHasSpace=NO;
                return NO;		//stanza has to remain in _outputQueue
            }
            else
            {
                DDLogVerbose(@"managed to send whole outputBuffer: %lu bytes", (unsigned long)sentLen);
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
            //reconnect from third party queue to not block send queue
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self reconnect];
            });
            return NO;
        }
    }

    //then try to send the stanza in question and buffer half sent data
    if(!messageOut)
    {
        DDLogInfo(@"tried to send empty message. returning without doing anything.");
        return YES;     //pretend we sent the empty "data"
    }
    const uint8_t* rawstring = (const uint8_t *)[messageOut UTF8String];
    NSInteger rawstringLen = strlen((char*)rawstring);
    if(rawstringLen <= 0)
        return YES;     //pretend we sent the empty "data"
    NSInteger sentLen = [_oStream write:rawstring maxLength:rawstringLen];
    if(sentLen!=-1)
    {
        if(sentLen!=rawstringLen)
        {
            DDLogVerbose(@"could not send all bytes of outgoing stanza: %lu of %lu sent, %lu remaining", (unsigned long)sentLen, (unsigned long)rawstringLen, (unsigned long)(rawstringLen-sentLen));
            //allocate new _outputBuffer
            _outputBuffer=malloc(sizeof(uint8_t) * (rawstringLen-sentLen));
            //copy the remaining data into the buffer and set the buffer pointer accordingly
            memcpy(_outputBuffer, rawstring+(size_t)sentLen, (size_t)(rawstringLen-sentLen));
            _outputBufferByteCount=(size_t)(rawstringLen-sentLen);
            _streamHasSpace=NO;
        }
        else
        {
            DDLogVerbose(@"managed to send whole outgoing stanza: %lu bytes", (unsigned long)sentLen);
            _outputBufferByteCount=0;
        }
        return YES;
    }
    else
    {
        NSError* error=[_oStream streamError];
        DDLogError(@"sending: failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
        //reconnect from third party queue to not block send queue
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self reconnect];
        });
        return NO;
    }
}

#pragma mark misc

-(void) enablePush
{
    NSString* pushToken = [MLXMPPManager sharedInstance].pushToken;
    if(
        [MLXMPPManager sharedInstance].hasAPNSToken &&
        self.accountState >= kStateBound &&
        pushToken != nil && [pushToken length] > 0
    )
    {
        DDLogInfo(@"registering (and enabling) push: %@ < %@ (accountState: %ld, supportsPush: %@)", [[[UIDevice currentDevice] identifierForVendor] UUIDString], pushToken, (long)self.accountState, self.connectionProperties.supportsPush ? @"YES" : @"NO");
        XMPPIQ* registerNode = [[XMPPIQ alloc] initWithType:kiqSetType];
        [registerNode setRegisterOnAppserverWithToken:pushToken];
        [registerNode setiqTo:[HelperTools pushServer][@"jid"]];
        [self sendIq:registerNode withHandler:$newHandler(MLIQProcessor, handleAppserverNodeRegistered)];
    }
    else if(![MLXMPPManager sharedInstance].hasAPNSToken && self.accountState >= kStateBound)
    {
        //disable push for this node
        DDLogInfo(@"DISABLING push: %@ < %@ (accountState: %ld, supportsPush: %@)", [[[UIDevice currentDevice] identifierForVendor] UUIDString], pushToken, (long)self.accountState, self.connectionProperties.supportsPush ? @"YES" : @"NO");
        if(self.connectionProperties.supportsPush)
        {
            XMPPIQ* disable = [[XMPPIQ alloc] initWithType:kiqSetType];
            [disable setPushDisable];
            [self send:disable];
        }
    }
    else
    {
        DDLogInfo(@"NOT registering and enabling push: %@ < %@ (accountState: %ld, supportsPush: %@)", [[[UIDevice currentDevice] identifierForVendor] UUIDString], pushToken, (long)self.accountState, self.connectionProperties.supportsPush ? @"YES" : @"NO");
    }
}

-(void) updateIqHandlerTimeouts
{
    //only handle iq timeouts while the parseQueue is almost empty
    //(a long backlog in the parse queue could trigger spurious iq timeouts for iqs we already received an answer to, but didn't process it yet)
    if([_parseQueue operationCount] > 4 || _accountState < kStateBound)
        return;
    
    @synchronized(_iqHandlers) {
        //we are NOT mutating on iteration here, because we use dispatchAsyncOnReceiveQueue to handle timeouts
        for(NSString* iqid in _iqHandlers)
        {
            //decrement handler timeout every second and check if it landed below zero --> trigger a fake iq error to handle timeout
            //this makes sure a freeze/killed app doesn't immediately trigger timeouts once the app is restarted, as it would be with timestamp based timeouts
            //doing it this way makes sure the incoming iq result has a chance to be processed even in a freeze/kill scenario
            _iqHandlers[iqid][@"timeout"] = @([_iqHandlers[iqid][@"timeout"] doubleValue] - 1.0);
            if([_iqHandlers[iqid][@"timeout"] doubleValue] < 0)
            {
                DDLogWarn(@"Timeout of handler triggered: %@", _iqHandlers[iqid]);
                
                //fake xmpp stanza error to make timeout handling transparent without the need for invalidation handler
                //we need to fake the from, too (no from means own bare jid)
                XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:_iqHandlers[iqid][@"iq"]];
                errorIq.to = self.connectionProperties.identity.fullJid;
                if([_iqHandlers[iqid][@"iq"] to] != nil)
                    errorIq.from = [_iqHandlers[iqid][@"iq"] to];
                else
                    errorIq.from = self.connectionProperties.identity.jid;
                [errorIq addChild:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"wait"} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"remote-server-timeout" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
                    [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas" withAttributes:@{} andChildren:@[] andData:[NSString stringWithFormat:@"No response in %d seconds", (int)IQ_TIMEOUT]],
                ] andData:nil]];
                
                //make sure our fake error iq is handled inside the receiveQueue
                [self dispatchAsyncOnReceiveQueue:^{
                    //extract this from _iqHandlers to make sure we only handle iqs didn't get handled in the meantime
                    NSMutableDictionary* iqHandler = nil;
                    @synchronized(self->_iqHandlers) {
                        iqHandler = self->_iqHandlers[iqid];
                    }
                    if(iqHandler)
                    {
                        DDLogDebug(@"Calling iq handler with faked error iq: %@", errorIq);
                        if(iqHandler[@"handler"] != nil)
                            $call(iqHandler[@"handler"], $ID(account, self), $ID(iqNode, errorIq));
                        else if(iqHandler[@"errorHandler"] != nil)
                            ((monal_iq_handler_t) iqHandler[@"errorHandler"])(errorIq);
                        
                        //remove handler after calling it
                        @synchronized(self->_iqHandlers) {
                            [self->_iqHandlers removeObjectForKey:iqid];
                        }
                    }
                    else
                        DDLogWarn(@"iq handler for '%@' vanished while switching to receive queue", iqid);
                }];
            }
        }
    }
}

-(void) delayIncomingMessageStanzasForArchiveJid:(NSString*) archiveJid
{
    _inCatchup[archiveJid] = @YES;
}

-(void) delayIncomingMessageStanzaUntilCatchupDone:(XMPPMessage*) originalParsedStanza
{
    NSString* archiveJid = self.connectionProperties.identity.jid;
    if([[originalParsedStanza findFirst:@"/@type"] isEqualToString:@"groupchat"])
        archiveJid = originalParsedStanza.fromUser;
    
    [[DataLayer sharedInstance] addDelayedMessageStanza:originalParsedStanza forArchiveJid:archiveJid andAccountNo:self.accountNo];
}

//this method is needed to not have a retain cycle (happens when using a block instead of this method in mamFinishedFor:)
-(void) _handleInternalMamFinishedFor:(NSString*) archiveJid
{
    if(self.accountState < kStateBound)
    {
        DDLogWarn(@"Aborting delayed replac because not >= kStateBound anymore! Stanzas will remain in DB ang will be handled after next smacks reconnect.");
        return;
    }
    
    //pick the next delayed message stanza (will return nil if there isn't any left)
    MLXMLNode* delayedStanza = [[DataLayer sharedInstance] getNextDelayedMessageStanzaForArchiveJid:archiveJid andAccountNo:self.accountNo];
    DDLogDebug(@"Got delayed stanza: %@", delayedStanza);
    if(delayedStanza == nil)
    {
        DDLogInfo(@"Catchup finished for jid %@", archiveJid);
        [_inCatchup removeObjectForKey:archiveJid];
        
        //handle old mamFinished code as soon as all delayed messages have been processed
        //we need to wait for all delayed messages because at least omemo needs the pep headline messages coming in during mam catchup
        if([self.connectionProperties.identity.jid isEqualToString:archiveJid])
        {
            if(!_catchupDone)
            {
                _catchupDone = YES;
                DDLogVerbose(@"Now posting kMonalFinishedCatchup notification");
                //don't queue this notification because it should be handled INLINE inside the receive queue
                [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFinishedCatchup object:self userInfo:nil];
            }
        }
    }
    else
    {
        //now *really* process delayed message stanza
        [self processInput:delayedStanza withDelayedReplay:YES];
        
        //add processing of next delayed message stanza to receiveQueue
        [self dispatchAsyncOnReceiveQueue:^{
            [self _handleInternalMamFinishedFor:archiveJid];
        }];
    }
}
-(void) mamFinishedFor:(NSString*) archiveJid
{
    //we should be already in the receive queue, but just to make sure (sync dispatch will do nothing if we already are in the right queue)
    [self dispatchOnReceiveQueue:^{
        //handle delayed message stanzas delivered while the mam catchup was in progress
        //the first call is handled directly, while all subsequent self-invocations are handled by dispatching it async to the receiveQueue
        //the async dispatcing makes it possible to abort the replay by pushing a disconnect block etc. onto the receieve queue
        [self _handleInternalMamFinishedFor:archiveJid];
    }];
}

-(void) addMessageToMamPageArray:(NSDictionary*) messageDictionary
{
    @synchronized(_mamPageArrays) {
        if(!_mamPageArrays[[messageDictionary[@"outerMessageNode"] findFirst:@"{urn:xmpp:mam:2}result@queryid"]])
            _mamPageArrays[[messageDictionary[@"outerMessageNode"] findFirst:@"{urn:xmpp:mam:2}result@queryid"]] = [[NSMutableArray alloc] init];
        [_mamPageArrays[[messageDictionary[@"outerMessageNode"] findFirst:@"{urn:xmpp:mam:2}result@queryid"]] addObject:messageDictionary];
    }
}

-(NSMutableArray*) getOrderedMamPageFor:(NSString*) mamQueryId
{
    NSMutableArray* array;
    @synchronized(_mamPageArrays) {
        if(_mamPageArrays[mamQueryId] == nil)
            return [[NSMutableArray alloc] init];       //return empty array if nothing can be found (after app crash etc.)
        array = _mamPageArrays[mamQueryId];
        [_mamPageArrays removeObjectForKey:mamQueryId];
    }
    return array;
}

-(void) sendDisplayMarkerForMessage:(MLMessage*) msg
{
    if(![[HelperTools defaultsDB] boolForKey:@"SendDisplayedMarkers"])
        return;
    
    //don't send chatmarkers in channels
    if(msg.isMuc && [@"channel" isEqualToString:msg.mucType])
        return;
    
    XMPPMessage* displayedNode = [[XMPPMessage alloc] init];
    //the message type is needed so that the store hint is accepted by the server
    displayedNode.attributes[@"type"] = msg.isMuc ? @"groupchat" : @"chat";
    displayedNode.attributes[@"to"] = msg.inbound ? msg.buddyName : self.connectionProperties.identity.jid;
    [displayedNode setDisplayed:msg.messageId];
    [displayedNode setStoreHint];
    [self send:displayedNode];
}

-(void) publishRosterName:(NSString* _Nullable) rosterName
{
    DDLogInfo(@"Publishing own nickname: '%@'", rosterName);
    if(!rosterName || !rosterName.length)
        [self.pubsub deleteNode:@"http://jabber.org/protocol/nick" andHandler:$newHandler(MLPubSubProcessor, rosterNameDeleted)];
    else
        [self.pubsub publishItem:
            [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": @"current"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"nick" andNamespace:@"http://jabber.org/protocol/nick" withAttributes:@{} andChildren:@[] andData:rosterName]
            ] andData:nil]
        onNode:@"http://jabber.org/protocol/nick" withConfigOptions:@{
            @"pubsub#persist_items": @"true",
            @"pubsub#access_model": @"presence"
        } andHandler:$newHandler(MLPubSubProcessor, rosterNamePublished)];
}

-(NSData*) resizeAvatarImage:(UIImage*) image
{
    // resize image to a maximum of 600x600 pixel
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
            [self.pubsub deleteNode:@"urn:xmpp:avatar:metadata" andHandler:$newHandler(MLPubSubProcessor, avatarDeleted)];
            [self.pubsub deleteNode:@"urn:xmpp:avatar:data" andHandler:$newHandler(MLPubSubProcessor, avatarDeleted)];
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
            } andHandler:$newHandler(MLPubSubProcessor, avatarDataPublished, $ID(imageHash), $ID(imageData))];
        }
    });
}

-(void) publishStatusMessage:(NSString*) message
{
    self.statusMessage = message;
    [self sendPresence];
}

-(NSString*) description
{
    return [NSString stringWithFormat:@"%@[%@]: %@", self.accountNo, _internalID, self.connectionProperties.identity.jid];
}

@end
