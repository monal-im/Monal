//
//  xmpp.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#include <os/proc.h>

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
#import "SCRAM.h"
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

#define STATE_VERSION 18
#define CONNECT_TIMEOUT 7.0
#define IQ_TIMEOUT 60.0
NSString* const kQueueID = @"queueID";
NSString* const kStanza = @"stanza";


@interface MLPubSub ()
-(id) initWithAccount:(xmpp*) account;
-(NSDictionary*) getInternalData;
-(void) setInternalData:(NSDictionary*) data;
-(void) invalidateQueue;
-(void) handleHeadlineMessage:(XMPPMessage*) messageNode;
@end

@interface MLMucProcessor ()
-(id) initWithAccount:(xmpp*) account;
-(NSDictionary*) getInternalState;
-(void) setInternalState:(NSDictionary*) state;
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
    MLDelayableTimer* _loginTimer;
    MLDelayableTimer* _pingTimer;
    MLDelayableTimer* _reconnectTimer;
    NSMutableArray* _timersToCancelOnDisconnect;
    NSMutableArray* _smacksAckHandler;
    NSMutableDictionary* _iqHandlers;
    NSMutableArray* _reconnectionHandlers;
    NSMutableSet* _runningCapsQueries;
    NSMutableDictionary* _runningMamQueries;
    BOOL _SRVDiscoveryDone;
    BOOL _startTLSComplete;
    BOOL _catchupDone;
    double _reconnectBackoffTime;
    BOOL _reconnectInProgress;
    BOOL _disconnectInProgres;
    NSObject* _stateLockObject;     //only used for @synchronized() blocks
    BOOL _lastIdleState;
    NSMutableDictionary* _mamPageArrays;
    NSString* _internalID;
    NSString* _logtag;
    NSMutableDictionary* _inCatchup;
    NSMutableDictionary* _mdsData;
    
    //registration related stuff
    BOOL _registration;
    BOOL _registrationSubmission;
    NSString* _registrationToken;
    xmppDataCompletion _regFormCompletion;
    xmppCompletion _regFormErrorCompletion;
    xmppCompletion _regFormSubmitCompletion;
    
    //pipelining related stuff
    MLXMLNode* _cachedStreamFeaturesBeforeAuth;
    MLXMLNode* _cachedStreamFeaturesAfterAuth;
    xmppPipeliningState _pipeliningState;
    
    //scram related stuff
    SCRAM* _scramHandler;
    NSSet* _supportedSaslMechanisms;
    NSSet* _supportedChannelBindings;
    monal_void_block_t _blockToCallOnTCPOpen;
    NSString* _upgradeTask;
    
    //catchup statistics
    uint32_t _catchupStanzaCounter;
    NSDate* _catchupStartTime;
}

@property (nonatomic, assign) BOOL smacksRequestInFlight;

@property (nonatomic, assign) BOOL resuming;
@property (atomic, strong) NSString* streamID;
@property (nonatomic, assign) BOOL isDoingFullReconnect;

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

@end



@implementation xmpp

-(id) initWithServer:(nonnull MLXMPPServer*) server andIdentity:(nonnull MLXMPPIdentity*) identity andAccountID:(NSNumber*) accountID
{
    //initialize ivars depending on provided arguments
    self = [super init];
    u_int32_t i = arc4random();
    _internalID = [HelperTools hexadecimalString:[NSData dataWithBytes: &i length: sizeof(i)]];
    _logtag = [NSString stringWithFormat:@"[%@:%@]", accountID, _internalID];
    DDLogVerbose(@"Creating account %@ with id %@", accountID, _internalID);
    self.accountID = accountID;
    self.connectionProperties = [[MLXMPPConnection alloc] initWithServer:server andIdentity:identity];
    
    //setup all other ivars
    [self setupObjects];
    
    // don't init omemo on ibr account creation
    if(accountID.intValue >= 0)
        self.omemo = [[MLOMEMO alloc] initWithAccount:self];
    
    //read persisted state to make sure we never operate stateless
    //WARNING: pubsub node registrations should only be made *after* the first readState call
    [self readState];
    
    //register devicelist and notification handler (MUST be done *after* reading state)
    //[self readState] needs a valid self.omemo to load omemo state,
    //but [self.omemo activate] needs a valid pubsub node registration loaded by [self readState]
    //--> split "init" method into "init" and "activate" methods
    if(self.omemo)
        [self.omemo activate];
    
    //we want to get automatic avatar updates (XEP-0084)
    [self.pubsub registerForNode:@"urn:xmpp:avatar:metadata" withHandler:$newHandler(MLPubSubProcessor, avatarHandler)];
    
    //we want to get automatic roster name updates (XEP-0172)
    [self.pubsub registerForNode:@"http://jabber.org/protocol/nick" withHandler:$newHandler(MLPubSubProcessor, rosterNameHandler)];
    
    //we want to get automatic bookmark updates (XEP-0048)
    //this will only be used/handled, if the account disco feature urn:xmpp:bookmarks:1#compat-pep is not set by the server and ignored otherwise
    //(it will be automatically headline-pushed nevertheless --> TODO: remove this once all modern servers support XEP-0402 compat)
    [self.pubsub registerForNode:@"storage:bookmarks" withHandler:$newHandler(MLPubSubProcessor, bookmarksHandler)];
    
    //we now support the modern bookmarks protocol (XEP-0402)
    [self.pubsub registerForNode:@"urn:xmpp:bookmarks:1" withHandler:$newHandler(MLPubSubProcessor, bookmarks2Handler)];
    
    //we support mds
    [self.pubsub registerForNode:@"urn:xmpp:mds:displayed:0" withHandler:$newHandler(MLPubSubProcessor, mdsHandler)];
    
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
    [self setCapsHash:[HelperTools getEntityCapsHashForIdentities:@[client] andFeatures:_capsFeatures andForms:@[]]];
    
    //init pubsub as early as possible to allow other classes or other parts of this file to register pubsub nodes they are interested in
    self.pubsub = [[MLPubSub alloc] initWithAccount:self];
    
    //init muc processor
    self.mucProcessor = [[MLMucProcessor alloc] initWithAccount:self];
    
    _stateLockObject = [NSObject new];
    [self initSM3];
    self.isDoingFullReconnect = YES;
    
    _accountState = kStateLoggedOut;
    _registration = NO;
    _registrationSubmission = NO;
    _startTLSComplete = NO;
    _catchupDone = NO;
    _reconnectInProgress = NO;
    _disconnectInProgres = NO;
    _lastIdleState = NO;
    _outputQueue = [NSMutableArray new];
    _iqHandlers = [NSMutableDictionary new];
    _reconnectionHandlers = [NSMutableArray new];
    _mamPageArrays = [NSMutableDictionary new];
    _runningCapsQueries = [NSMutableSet new];
    _runningMamQueries = [NSMutableDictionary new];
    _inCatchup = [NSMutableDictionary new];
    _mdsData = [NSMutableDictionary new];
    _pipeliningState = kPipelinedNothing;
    _cachedStreamFeaturesBeforeAuth = nil;
    _cachedStreamFeaturesAfterAuth = nil;
    _timersToCancelOnDisconnect = [NSMutableArray new];

    _SRVDiscoveryDone = NO;
    _discoveredServersList = [NSMutableArray new];
    if(!_usableServersList)
        _usableServersList = [NSMutableArray new];
    _reconnectBackoffTime = 0;
    
    _parseQueue = [NSOperationQueue new];
    _parseQueue.name = [NSString stringWithFormat:@"parseQueue[%@:%@]", self.accountID, _internalID];
    _parseQueue.qualityOfService = NSQualityOfServiceUtility;
    _parseQueue.maxConcurrentOperationCount = 1;
    [_parseQueue addObserver:self forKeyPath:@"operationCount" options:NSKeyValueObservingOptionNew context:nil];
    
    _receiveQueue = [NSOperationQueue new];
    _receiveQueue.name = [NSString stringWithFormat:@"receiveQueue[%@:%@]", self.accountID, _internalID];
    _receiveQueue.qualityOfService = NSQualityOfServiceUserInitiated;
    _receiveQueue.maxConcurrentOperationCount = 1;
    [_receiveQueue addObserver:self forKeyPath:@"operationCount" options:NSKeyValueObservingOptionNew context:nil];

    _sendQueue = [NSOperationQueue new];
    _sendQueue.name = [NSString stringWithFormat:@"sendQueue[%@:%@]", self.accountID, _internalID];
    _sendQueue.qualityOfService = NSQualityOfServiceUserInitiated;
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
    
    self.statusMessage = @"";
}

-(void) dealloc
{
    DDLogInfo(@"Deallocating account %@ object %@", self.accountID, self);
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
    DDLogInfo(@"Done deallocating account %@ object %@", self.accountID, self);
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
    [self setCapsHash:[HelperTools getEntityCapsHashForIdentities:@[client] andFeatures:_capsFeatures andForms:@[]]];
    
    //persist this new state if the pubsub implementation tells us to
    if(persistState)
        [self persistState];
}

-(void) postError:(NSString*) message withIsSevere:(BOOL) isSevere
{
    // Do not show "Connection refused" message and other errors occuring before we are in kStateHasStream, if we still have more SRV records to try
    if([_usableServersList count] == 0 || _accountState >= kStateHasStream)
        [HelperTools postError:message withNode:nil andAccount:self andIsSevere:isSevere];
}

-(void) invalidXMLError
{
    DDLogError(@"Server returned invalid xml!");
    DDLogDebug(@"Setting _pipeliningState to kPipelinedNothing and clearing _cachedStreamFeaturesBeforeAuth and _cachedStreamFeaturesAfterAuth...");
    _pipeliningState = kPipelinedNothing;
    _cachedStreamFeaturesBeforeAuth = nil;
    _cachedStreamFeaturesAfterAuth = nil;
    [self postError:NSLocalizedString(@"Server returned invalid xml!", @"") withIsSevere:NO];
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
            kAccountID: self.accountID,
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
            //only send out idle state notifications if the receive queue is not currently suspended (e.g. account frozen)
            if(!_receiveQueue.suspended)
            {
                BOOL idle = self.idle;
                //only send out idle notifications if we changed from non-idle to idle state
                if(idle && !lastState)
                {
                    DDLogVerbose(@"Adding idle state notification to receive queue...");
                    [_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                        //don't queue this notification because it should be handled INLINE inside the receive queue
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalIdle object:self];
                    }]] waitUntilFinished:NO];
                }
                //only send out not-idle notifications if we changed from idle to non-idle state
                if(!idle && lastState)
                {
                    DDLogVerbose(@"Adding non-idle state notification to receive queue...");
                    [_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                        //don't queue this notification because it should be handled INLINE  inside the receive queue
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalNotIdle object:self];
                    }]] waitUntilFinished:NO];
                }
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
            _pingTimer == nil &&
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
            "\t_pingTimer = %@\n"
            "\t[self.unAckedStanzas count] = %lu\n"
            "\t[_parseQueue operationCount] = %lu\n"
            //"\t[_receiveQueue operationCount] = %lu\n"
            "\t[_sendQueue operationCount] = %lu\n"
            "\t[[_inCatchup count] = %lu\n\t--> %@"
        ),
        self.accountID,
        bool2str(_accountState < kStateReconnecting),
        bool2str(_reconnectInProgress),
        bool2str(_catchupDone),
        _pingTimer == nil ? @"none" : @"running timer",
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
    [self unfreezeSendQueue];      //make sure the queue is operational again before dispatching to it
    [_sendQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
        DDLogVerbose(@"Cleaning up sendQueue [internal]");
        [self->_sendQueue cancelAllOperations];
        self->_outputQueue = [NSMutableArray new];
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
    DDLogInfo(@"stream creating to server: %@ port: %@ directTLS: %@", self.connectionProperties.server.connectServer, self.connectionProperties.server.connectPort, bool2str(self.connectionProperties.server.isDirectTLS));
    
    NSInputStream* localIStream;
    NSOutputStream* localOStream;
    
    if(self.connectionProperties.server.isDirectTLS == YES)
    {
        DDLogInfo(@"creating directTLS streams");
        [MLStream connectWithSNIDomain:self.connectionProperties.identity.domain connectHost:self.connectionProperties.server.connectServer connectPort:self.connectionProperties.server.connectPort tls:YES inputStream:&localIStream outputStream:&localOStream logtag:self->_logtag];
    }
    else
    {
        DDLogInfo(@"creating plaintext streams");
        [MLStream connectWithSNIDomain:self.connectionProperties.identity.domain connectHost:self.connectionProperties.server.connectServer connectPort:self.connectionProperties.server.connectPort tls:NO inputStream:&localIStream outputStream:&localOStream logtag:self->_logtag];
    }
    
    if(localOStream)
        _oStream = localOStream;
    
    if((localIStream == nil) || (localOStream == nil))
    {
        DDLogError(@"failed to create streams");
        [self postError:NSLocalizedString(@"Unable to connect to server!", @"") withIsSevere:NO];
        [self reconnect];
        return;
    }
    else
        DDLogInfo(@"streams created ok");
    
    //open sockets, init pipe and start connecting (including TLS handshake if isDirectTLS==YES)
    DDLogInfo(@"opening TCP streams");
    _pipeliningState = kPipelinedNothing;
    [_oStream setDelegate:self];
    [_oStream scheduleInRunLoop:[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierNetwork] forMode:NSDefaultRunLoopMode];
    _iPipe = [[MLPipe alloc] initWithInputStream:localIStream andOuterDelegate:self];
    [localIStream open];
    [_oStream open];
    DDLogInfo(@"TCP streams opened");
    
    //prepare xmpp parser (this is the first time for this connection --> we don't need to clear the receive queue)
    [self prepareXMPPParser];
    
    //MLStream will automatically use tcp fast open for direct tls connections
    if(self.connectionProperties.server.isDirectTLS == YES)
    {
        [self startXMPPStreamWithXMLOpening:YES];
        
        //pipeline auth request onto our stream header if we have cached stream features available
        if(_cachedStreamFeaturesBeforeAuth != nil)
        {
            DDLogDebug(@"Pipelining auth using cached stream features: %@", _cachedStreamFeaturesBeforeAuth);
            _pipeliningState = kPipelinedAuth;
            [self handleFeaturesBeforeAuth:_cachedStreamFeaturesBeforeAuth];
        }
    }
    else
    {
        //send stream start and starttls nonza as tcp fastopen idempotent data if not in direct tls mode
        //(this will concatenate everything to one single NSString queue entry)
        //(not doing this will cause the network framework to only send the first queue entry (the xml opening) but not the stream start itself)
        [self startXMPPStreamWithXMLOpening:YES withStartTLS:YES andDirectWrite:YES];
    }
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
    
    //already tried to connect once (e.g. _SRVDiscoveryDone==YES) and either all SRV records were tried or we didn't discovered any
    if(_SRVDiscoveryDone && [_usableServersList count] == 0)
    {
        //in this condition, the registration failed
        if(_registration || _registrationSubmission)
        {
            DDLogWarn(@"Could not connect for registering, publishing error...");
            [self postError:[NSString stringWithFormat:NSLocalizedString(@"Server for domain '%@' not responding!", @""), self.connectionProperties.identity.domain] withIsSevere:NO];
            return YES;
        }
    }

    // do DNS discovery if it hasn't already been set
    if(!_SRVDiscoveryDone)
    {
        DDLogInfo(@"Querying for SRV records");
        _discoveredServersList = [[MLDNSLookup new] dnsDiscoverOnDomain:self.connectionProperties.identity.domain];
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
            //this is not severe on registration, but severe otherwise
            [self postError:[NSString stringWithFormat:NSLocalizedString(@"SRV entry prohibits XMPP connection for domain %@", @""), self.connectionProperties.identity.domain] withIsSevere:!(_registration || _registrationSubmission)];
            return YES;
        }
    }
    
    // if all servers have been tried start over with the first one again
    if([_discoveredServersList count] > 0 && [_usableServersList count] == 0)
    {
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

-(BOOL) parseQueueFrozen
{
    return [_parseQueue isSuspended] == YES;
}

-(void) freezeParseQueue
{
    @synchronized(_parseQueue) {
        //pause all timers before freezing the parse queue to not trigger timers that can not be handeld properly while frozen
        [_loginTimer pause];
        [_pingTimer pause];
        [_reconnectTimer pause];
        
        //don't do this in a block on the parse queue because the parse queue could potentially have a significant amount of blocks waiting
        //to be synchronously dispatched to the receive queue and processed and we don't want to wait for all these stanzas to be processed
        //and rather freeze the parse queue as soon as possible
        _parseQueue.suspended = YES;
        
        //apparently setting _parseQueue.suspended = YES does return before the queue is actually suspended
        //--> busy wait for _parseQueue.suspended == YES
        [HelperTools busyWaitForOperationQueue:_parseQueue];
        MLAssert([self parseQueueFrozen] == YES, @"Parse queue not frozen after setting suspended to YES!");
        
        //this has to be synchronous because we want to be sure no further stanzas are leaking from the parse queue
        //into the receive queue once we leave this method
        //--> wait for all blocks put into the receive queue by the parse queue right before it was frozen
        [self dispatchOnReceiveQueue: ^{
            [HelperTools busyWaitForOperationQueue:self->_parseQueue];
            MLAssert([self parseQueueFrozen] == YES, @"Parse queue not frozen after setting suspended to YES (in receive queue)!");
            DDLogInfo(@"Parse queue is frozen now!");
        }];
    }
}

-(void) unfreezeParseQueue
{
    @synchronized(_parseQueue) {
        //this has to be synchronous because we want to be sure the parse queue is operating again once we leave this method
        [self dispatchOnReceiveQueue: ^{
            self->_parseQueue.suspended = NO;
            DDLogInfo(@"Parse queue is UNfrozen now!");
        }];
        
        //resume all timers paused when freezing the parse queue
        [_loginTimer resume];
        [_pingTimer resume];
        [_reconnectTimer resume];
    }
}

-(void) freezeSendQueue
{
    if(_sendQueue.suspended)
    {
        DDLogWarn(@"Send queue of account %@ already frozen, doing nothing...", self);
        return;
    }
    
    //wait for all queued operations to finish (this will NOT block if the tcp stream is not writable)
    [self->_sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
        self->_sendQueue.suspended = YES;
    }]] waitUntilFinished:YES];         //block until finished because we are closing the socket directly afterwards
    [HelperTools busyWaitForOperationQueue:_sendQueue];
}

-(void) unfreezeSendQueue
{
    //no need to dispatch anything here, just start processing jobs
    self->_sendQueue.suspended = NO;
}

-(void) freeze
{
    //this can only be done if this method is the only one that freezes the receive queue,
    //because this shortcut assumes that parse and send queues are always frozen, too, if the receive queue is frozen
    if(_receiveQueue.suspended)
    {
        DDLogWarn(@"Account %@ already frozen, doing nothing...", self);
        return;
    }
    
    DDLogInfo(@"Freezing account: %@", self);
    
    //this does not have to be synchronized with the freezing of the parse queue and receive queue
    [self freezeSendQueue];
    
    //don't merge the sync dispatch to freeze the receive queue with the sync dispatch done by freezeParseQueue
    //merging those might leave some tasks in the receive queue that got added to it after the parse queue freeze
    //was signalled but before it actually completed the freeze
    //statement 1:
    //this is not okay because leaked stanzas while frozen could be processed twice if the complete app gets frozen afterwards,
    //then these stanzas get processed by the appex and afterwards the complete app and subsequently the receive queue gets unfrozen again
    //statement 2:
    //stanzas still in the parse queue when unfreezing the account will be dropped because self.accountState < kStateConnected
    //will instruct the block inside prepareXMPPParser to drop any stanzas still queued in the parse queue
    //and having even self.accountState < kStateReconnecting will make a call to [self connect] mandatory,
    //which will cancel all operations still queued on the parse queue
    //statement 3:
    //normally a complete app freeze will only occur after calling [MLXMPPManager disconnectAll] and subsequently [xmpp freeze],
    //so self.accountState < kStateReconnecting should always be true on unfreeze (which will make statement 2 above always hold true)
    //statement 4:
    //if an app freeze takes too long, for example because disconnecting does not finish in time, or if the app still holds the MLProcessLock,
    //the app will be killed by iOS, which will immediately invalidate every block in every queue
    [self freezeParseQueue];
    [self dispatchOnReceiveQueue:^{
        //this is the last block running in the receive queue (it will be frozen once this block finishes execution)
        self->_receiveQueue.suspended = YES;
    }];
    [HelperTools busyWaitForOperationQueue:_receiveQueue];
}

-(void) unfreeze
{
    DDLogInfo(@"Unfreezing account: %@", self);
    
    //make sure we don't have any race conditions by dispatching this to our receive queue
    //this operation has highest priority to make sure it will be executed first once unfrozen
    NSBlockOperation* unfreezeOperation  = [NSBlockOperation blockOperationWithBlock:^{
        //this has to be the very first thing even before unfreezing the parse or send queues
        if(self.accountState < kStateReconnecting)
        {
            DDLogInfo(@"Reloading UNfrozen account %@", self.accountID);
            //(re)read persisted state (could be changed by appex)
            [self readState];
        }
        else
            DDLogInfo(@"Not reloading UNfrozen account %@, already connected", self.accountID);
        
        //this must be inside the dispatch async, because it will dispatch *SYNC* to the receive queue and potentially block or even deadlock the system
        [self unfreezeParseQueue];
        
        [self unfreezeSendQueue];
    }];
    unfreezeOperation.queuePriority = NSOperationQueuePriorityVeryHigh;     //make sure this will become the first operation executed once unfrozen
    [self->_receiveQueue addOperations: @[unfreezeOperation] waitUntilFinished:NO];
    
    //unfreeze receive queue and execute block added above
    self->_receiveQueue.suspended = NO;
}

-(void) reinitLoginTimer
{
    //check if we are still logging in and abort here, if not (we don't want a new timer when we decided to not disconnect)
    if(self->_accountState < kStateReconnecting)
        return;
    
    //cancel old timer if existing and...
    if(self->_loginTimer != nil)
        [self->_loginTimer cancel];
    //...replace it with new timer
    self->_loginTimer = createDelayableTimer(CONNECT_TIMEOUT, (^{
        self->_loginTimer = nil;
        [self dispatchAsyncOnReceiveQueue: ^{
            DDLogInfo(@"Login took too long, cancelling and trying to reconnect (potentially using another SRV record)");
            [self reconnect];
        }];
    }));
}

-(void) connect
{
    if([self parseQueueFrozen])
    {
        DDLogWarn(@"Not trying to connect: parse queue frozen!");
        return;
    }
    
    [self dispatchAsyncOnReceiveQueue: ^{
        if([self parseQueueFrozen])
        {
            DDLogWarn(@"Not trying to connect: parse queue frozen!");
            return;
        }
        
        [self->_parseQueue cancelAllOperations];          //throw away all parsed but not processed stanzas from old connections
        [self unfreezeParseQueue];                        //make sure the parse queue is operational again
        //we don't want to loose outgoing messages by throwing away their receiveQueue operation adding them to the smacks queue etc.
        //[self->_receiveQueue cancelAllOperations];        //stop everything coming after this (we will start a clean connect here!)
        
        //sanity check
        if(self.accountState >= kStateReconnecting)
        {
            DDLogError(@"asymmetrical call to login without a teardown logout, calling reconnect...");
            [self reconnect];
            return;
        }
        
        //make sure we are still enabled ("-1" is used for the account registration process and never saved to db)
        if(self.accountID.intValue != -1 && ![[DataLayer sharedInstance] isAccountEnabled:self.accountID])
        {
            DDLogError(@"Account '%@' not enabled anymore, ignoring login", self.accountID);
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
        
        DDLogVerbose(@"Removing scramHandler...");
        self->_scramHandler = nil;
        self->_blockToCallOnTCPOpen = nil;
        
        //(re)read persisted state and start connection
        [self readState];
        if([self connectionTask])
        {
            DDLogError(@"Server disallows xmpp connections for account '%@', ignoring login", self.accountID);
            self->_accountState = kStateDisconnected;
            return;
        }
        
        [self reinitLoginTimer];
    }];
}

-(void) disconnect
{
    [self disconnectWithStreamError:nil andExplicitLogout:NO];
}

-(void) disconnect:(BOOL) explicitLogout
{
    [self disconnectWithStreamError:nil andExplicitLogout:explicitLogout];
}

-(void) disconnectWithStreamError:(MLXMLNode* _Nullable) streamError
{
    [self disconnectWithStreamError:streamError andExplicitLogout:NO];
}

-(void) disconnectWithStreamError:(MLXMLNode* _Nullable) streamError andExplicitLogout:(BOOL) explicitLogout 
{
    DDLogInfo(@"disconnect called...");
    
    //short-circuit common case without dispatching to receive queue
    //this allows calling a noop disconnect while the receive queue is frozen
    if(self->_accountState<kStateReconnecting && !explicitLogout)
        return;
    
    MLAssert(!_receiveQueue.suspended, @"receive queue suspended while trying to disconnect!");
    
    //this has to be synchronous because we want to wait for the disconnect to complete before continuingand unlocking the process in the NSE
    [self dispatchOnReceiveQueue: ^{
        DDLogInfo(@"stopping running timers");
        if(self->_loginTimer)
            [self->_loginTimer cancel];     //cancel running login timer
        self->_loginTimer = nil;
        if(self->_pingTimer)
            [self->_pingTimer cancel];      //cancel running ping timer
        self->_pingTimer = nil;
        if(self->_reconnectTimer)
            [self->_reconnectTimer cancel]; //cancel running reconnect timer
        self->_reconnectTimer = nil;
        @synchronized(self->_timersToCancelOnDisconnect) {
            for(monal_void_block_t timer in self->_timersToCancelOnDisconnect)
                timer();
            [self->_timersToCancelOnDisconnect removeAllObjects];
        }
        
        DDLogVerbose(@"Removing scramHandler...");
        self->_scramHandler = nil;
        self->_blockToCallOnTCPOpen = nil;
        
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
                                $invalidate(self->_iqHandlers[iqid][@"handler"], $ID(account, self), $ID(reason, @"disconnect"));
                            else if(self->_iqHandlers[iqid][@"errorHandler"])
                                ((monal_iq_handler_t)self->_iqHandlers[iqid][@"errorHandler"])(nil);
                        }
                        self->_iqHandlers = [NSMutableDictionary new];
                    }
                    
                    //invalidate pubsub queue (*after* iq handlers that also might invalidate a result handler of the queued operation)
                    [self.pubsub invalidateQueue];
                    
                    //clear pipeline cache
                    self->_pipeliningState = kPipelinedNothing;
                    self->_cachedStreamFeaturesBeforeAuth = nil;
                    self->_cachedStreamFeaturesAfterAuth = nil;
                    
                    //clear all reconnection handlers
                    @synchronized(self->_reconnectionHandlers) {
                        [self->_reconnectionHandlers removeAllObjects];
                    }

                    //persist these changes
                    [self persistState];
                }
                
                [[DataLayer sharedInstance] resetContactsForAccount:self.accountID];
                
                //trigger view updates to make sure enabled/disabled account state propagates to all ui elements
                [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
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
            self->_reconnectBackoffTime = 0.0;
            [self unfreezeSendQueue];      //make sure the queue is operational again
            if(self.accountState>=kStateBound)
                [self->_sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
                    //disable push for this node
                    if([self.connectionProperties.accountDiscoFeatures containsObject:@"urn:xmpp:push:0"])
                        [self disablePush];
                    [self sendLastAck];
                }]] waitUntilFinished:YES];         //block until finished because we are closing the xmpp stream directly afterwards
            [self->_sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
                //close stream (either with error or normally)
                if(streamError != nil)
                    [self writeToStream:streamError.XMLString];    // dont even bother queueing
                MLXMLNode* stream = [[MLXMLNode alloc] initWithElement:@"/stream:stream"];  //hack to close stream
                [self writeToStream:stream.XMLString];    // dont even bother queueing
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
                            $invalidate(self->_iqHandlers[iqid][@"handler"], $ID(account, self), $ID(reason, @"disconnect"));
                        else if(self->_iqHandlers[iqid][@"errorHandler"])
                            ((monal_iq_handler_t)self->_iqHandlers[iqid][@"errorHandler"])(nil);
                    }
                    self->_iqHandlers = [NSMutableDictionary new];
                }
                
                //invalidate pubsub queue (*after* iq handlers that also might invalidate a result handler of the queued operation)
                [self.pubsub invalidateQueue];
                
                //clear pipeline cache
                self->_pipeliningState = kPipelinedNothing;
                self->_cachedStreamFeaturesBeforeAuth = nil;
                self->_cachedStreamFeaturesAfterAuth = nil;
                
                //clear all reconnection handlers
                @synchronized(self->_reconnectionHandlers) {
                    [self->_reconnectionHandlers removeAllObjects];
                }

                //persist these changes
                [self persistState];
            }
            
            [[DataLayer sharedInstance] resetContactsForAccount:self.accountID];
            
            //trigger view updates to make sure enabled/disabled account state propagates to all ui elements
            [[MLNotificationQueue currentQueue] postNotificationName:kMonalRefresh object:nil userInfo:nil];
        }
        else
        {
            [self unfreezeSendQueue];      //make sure the queue is operational again
            if(streamError != nil)
            {
                [self->_sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
                    //close stream with error
                    [self writeToStream:streamError.XMLString];    // dont even bother queueing
                    MLXMLNode* stream = [[MLXMLNode alloc] initWithElement:@"/stream:stream"];  //hack to close stream
                    [self writeToStream:stream.XMLString];    // dont even bother queueing
                }]] waitUntilFinished:YES];         //block until finished because we are closing the socket directly afterwards
            }
            else
            {
                //send one last ack before closing the stream (xep version 1.5.2)
                if(self.accountState>=kStateBound)
                {
                    [self->_sendQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                        [self sendLastAck];
                    }]] waitUntilFinished:YES];         //block until finished because we are closing the socket directly afterwards
                }
            }
            
            //persist these changes
            [self persistState];
        }
        
        [self closeSocket];
        [self accountStatusChanged];
        self->_disconnectInProgres = NO;
        
        //make sure our idle state is rechecked
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalNotIdle object:self];
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
        
        //sadly closing the output stream does not unblock a hanging [_oStream write:maxLength:] call
        //blocked by an ios/max runtime race condition with starttls
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
        
        //remove from runloop *after* cleaning up sendQueue (maybe this fixes a rare crash)
        [self->_oStream removeFromRunLoop:[HelperTools getExtraRunloopWithIdentifier:MLRunLoopIdentifierNetwork] forMode:NSDefaultRunLoopMode];

        DDLogInfo(@"resetting internal stream state to disconnected");
        self->_startTLSComplete = NO;
        self->_catchupDone = NO;
        self->_accountState = kStateDisconnected;
        
        [self->_parseQueue cancelAllOperations];    //throw away all parsed but not processed stanzas (we should have closed sockets then!)
        //we don't throw away operations in the receive queue because they could be more than just stanzas
        //(for example outgoing messages that should be written to the smacks queue instead of just vanishing in a void)
        //all incoming stanzas in the receive queue will honor the _accountState being lower than kStateReconnecting and be dropped
    }];
}

-(void) reconnect
{
    [self reconnectWithStreamError:nil];
}

-(void) reconnectWithStreamError:(MLXMLNode* _Nullable) streamError
{
    if(_reconnectInProgress)
    {
        DDLogInfo(@"Ignoring reconnect while one already in progress");
        return;
    }
    if(_reconnectBackoffTime == 0.0)
        _reconnectBackoffTime = 0.5;
    [self reconnectWithStreamError:streamError andWaitingTime:_reconnectBackoffTime];
    _reconnectBackoffTime = MIN(_reconnectBackoffTime + 0.5, 2.0);
}

-(void) reconnect:(double) wait
{
    [self reconnectWithStreamError:nil andWaitingTime:wait];
}

-(void) reconnectWithStreamError:(MLXMLNode* _Nullable) streamError andWaitingTime:(double) wait
{
    DDLogInfo(@"reconnect called...");
    
    if(_reconnectInProgress)
    {
        DDLogInfo(@"Ignoring reconnect while one already in progress");
        return;
    }
    
    [self dispatchAsyncOnReceiveQueue: ^{
        DDLogInfo(@"reconnect starts");
        if(self->_reconnectInProgress)
        {
            DDLogInfo(@"Ignoring reconnect while one already in progress");
            return;
        }
        
        self->_reconnectInProgress = YES;
        [self disconnectWithStreamError:streamError andExplicitLogout:NO];

        DDLogInfo(@"Trying to connect again in %G seconds...", wait);
        self->_reconnectTimer = createDelayableTimer(wait, (^{
            self->_reconnectTimer = nil;
            [self dispatchAsyncOnReceiveQueue: ^{
                //there may be another connect/login operation in progress triggered from reachability or another timer
                if(self.accountState<kStateReconnecting)
                    [self connect];
                self->_reconnectInProgress = NO;
            }];
        }), (^{
            DDLogInfo(@"Reconnect got aborted: %@", self);
            self->_reconnectTimer = nil;
            [self dispatchAsyncOnReceiveQueue: ^{
                self->_reconnectInProgress = NO;
            }];
        }));
        DDLogInfo(@"reconnect exits");
    }];
}

#pragma mark XMPP

-(void) prepareXMPPParser
{
    BOOL appex = [HelperTools isAppExtension];
    if(_xmlParser!=nil)
    {
        DDLogInfo(@"%@: resetting old xml parser", self->_logtag);
        [_xmlParser setDelegate:nil];
        [_xmlParser abortParsing];
        [_parseQueue cancelAllOperations];      //throw away all parsed but not processed stanzas (we aborted the parser right now)
    }
    if(!_baseParserDelegate)
    {
        DDLogInfo(@"%@: creating parser delegate", self->_logtag);
        _baseParserDelegate = [[MLBasePaser alloc] initWithCompletion:^(MLXMLNode* _Nullable parsedStanza) {
            DDLogVerbose(@"%@: Parse finished for new <%@> stanza...", self->_logtag, parsedStanza.element);
            
            //don't parse any more if we reached > 50 stanzas already parsed and waiting in parse queue
            //this makes ure we don't need to much memory while parsing a flood of stanzas and, in theory,
            //should create a backpressure ino the tcp stream, too
            //the calculated sleep time gives every stanza in the queue ~10ms to be handled (based on statistics)
            BOOL wasSleeping = NO;
            while(self.accountState >= kStateConnected)
            {
                //use a much smaller limit while in appex because memory there is limited to ~32MiB
                unsigned long operationCount = [self->_parseQueue operationCount];
                double usedMemory = [HelperTools report_memory];
                if(!(operationCount > 50 || (appex && usedMemory > 16 && operationCount > MAX(2, 24 - usedMemory))))
                    break;
                
                double waittime = (double)[self->_parseQueue operationCount] / 100.0;
                DDLogInfo(@"%@: Sleeping %f seconds because parse queue has %lu entries and used/available memory: %.3fMiB / %.3fMiB...", self->_logtag, waittime, (unsigned long)[self->_parseQueue operationCount], usedMemory, (CGFloat)os_proc_available_memory() / 1048576);
                [NSThread sleepForTimeInterval:waittime];
                wasSleeping = YES;
            }
            if(wasSleeping)
                DDLogInfo(@"%@: Sleeping has ended, parse queue has %lu entries and used/available memory: %.3fMiB / %.3fMiB...", self->_logtag, (unsigned long)[self->_parseQueue operationCount], [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
            
            if(self.accountState < kStateConnected)
            {
                DDLogWarn(@"%@: Throwing away incoming stanza *before* queueing in parse queue, accountState < kStateConnected", self->_logtag);
                return;
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
                DDLogVerbose(@"Synchronously handling next stanza on receive queue (%lu stanzas queued in parse queue, %lu current operations in receive queue, %.3fMiB / %.3fMiB memory used / available)", [self->_parseQueue operationCount], [self->_receiveQueue operationCount], [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
                [self->_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                    if(self.accountState < kStateConnected)
                    {
                        DDLogWarn(@"Throwing away incoming stanza queued in parse queue, accountState < kStateConnected");
                        return;
                    }
                    [MLNotificationQueue queueNotificationsInBlock:^{
                        //add whole processing of incoming stanzas to one big transaction
                        //this will make it impossible to leave inconsistent database entries on app crashes or iphone crashes/reboots
                        DDLogVerbose(@"Starting transaction for: %@", parsedStanza);
                        [[DataLayer sharedInstance] createTransaction:^{
                            DDLogVerbose(@"Started transaction for: %@", parsedStanza);
                            //don't write data to our tcp stream while inside this db transaction (all effects to the outside world should be transactional, too)
                            [self freezeSendQueue];
                            [self processInput:parsedStanza withDelayedReplay:NO];
                            DDLogVerbose(@"Ending transaction for: %@", parsedStanza);
                        }];
                        DDLogVerbose(@"Ended transaction for: %@", parsedStanza);
                        [self unfreezeSendQueue];      //this will flush all stanzas added inside the db transaction and now waiting in the send queue
                    } onQueue:@"receiveQueue"];
                    [self persistState];        //make sure to persist all state changes triggered by the events in the notification queue
                }]] waitUntilFinished:YES];
            //we have to wait for the stanza/nonza to be handled before parsing the next one to not introduce race conditions
            //between the response to our pipelined stream restart and the parser reset in the sasl success handler
            }]] waitUntilFinished:(self->_accountState < kStateBound ? YES : NO)];
        }];
    }
    else
    {
        DDLogInfo(@"%@: resetting parser delegate", self->_logtag);
        [_baseParserDelegate reset];
    }
    
    // create (new) pipe and attach a (new) streaming parser
    _xmlParser = [[NSXMLParser alloc] initWithStream:[_iPipe getNewOutputStream]];
    [_xmlParser setShouldProcessNamespaces:YES];
    [_xmlParser setShouldReportNamespacePrefixes:NO];
    //[_xmlParser setShouldReportNamespacePrefixes:YES];        //for debugging only
    [_xmlParser setShouldResolveExternalEntities:NO];
    [_xmlParser setDelegate:_baseParserDelegate];
    
    // do the stanza parsing in the low priority (=utility) global queue
    dispatch_async(dispatch_queue_create_with_target([NSString stringWithFormat:@"im.monal.xmlparser%@", self->_logtag].UTF8String, DISPATCH_QUEUE_SERIAL, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)), ^{
        DDLogInfo(@"%@: calling parse", self->_logtag);
        [self->_xmlParser parse];     //blocking operation
        DDLogInfo(@"%@: parse ended", self->_logtag);
    });
}

-(void) startXMPPStreamWithXMLOpening:(BOOL) withXMLOpening
{
    return [self startXMPPStreamWithXMLOpening:withXMLOpening withStartTLS:NO andDirectWrite:NO];
}

-(void) startXMPPStreamWithXMLOpening:(BOOL) withXMLOpening withStartTLS:(BOOL) withStartTLS andDirectWrite:(BOOL) directWrite
{
    MLXMLNode* xmlOpening = [[MLXMLNode alloc] initWithElement:@"__xml"];
    MLXMLNode* stream = [[MLXMLNode alloc] initWithElement:@"stream:stream" andNamespace:@"jabber:client" withAttributes:@{
        @"xmlns:stream": @"http://etherx.jabber.org/streams",
        @"version": @"1.0",
        @"to": self.connectionProperties.identity.domain,
    } andChildren:@[] andData:nil];
    //only set from-attribute if TLS is already established
    if(self.connectionProperties.server.isDirectTLS || self->_startTLSComplete)
        stream.attributes[@"from"] = self.connectionProperties.identity.jid;
    //ignore starttls stream feature presence and opportunistically try starttls even before receiving the stream features
    //(this is in accordance to RFC 7590: https://tools.ietf.org/html/rfc7590#section-3.1 )
    MLXMLNode* startTLS = [[MLXMLNode alloc] initWithElement:@"starttls" andNamespace:@"urn:ietf:params:xml:ns:xmpp-tls"];
    
    if(directWrite)
    {
        //log stanzas being sent as idempotent data
        if(withXMLOpening)
            [self logStanza:xmlOpening withPrefix:@"IDEMPOTENT_SEND"];
        [self logStanza:stream withPrefix:@"IDEMPOTENT_SEND"];
        if(withStartTLS)
            [self logStanza:startTLS withPrefix:@"IDEMPOTENT_SEND"];
        
        //concatenate everything and directly write it as one single string, wait until this is finished to make sure
        //the direct write is complete when returning from here (not strictly needed, but done for good measure)
        [self->_sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
            [self->_outputQueue addObject:[NSString stringWithFormat:@"%@%@%@",
                (withXMLOpening ? xmlOpening.XMLString : @""),
                stream.XMLString,
                (withStartTLS ? startTLS.XMLString : @"")
            ]];
            [self writeFromQueue];      // try to send if there is space
        }]] waitUntilFinished:YES];
    }
    else
    {
        if(withXMLOpening)
            [self send:xmlOpening];
        [self send:stream];
        if(withStartTLS)
            [self send:startTLS];
    }
}

-(void) sendPing:(double) timeout
{
    DDLogVerbose(@"sendPing called");
    [self dispatchAsyncOnReceiveQueue: ^{
        DDLogVerbose(@"sendPing called - now inside receiveQueue");
        
        //make sure we are enabled before doing anything
        if(![[DataLayer sharedInstance] isAccountEnabled:self.accountID])
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
        else if(self->_pingTimer)
        {
            DDLogInfo(@"ping already sent, ignoring second ping request.");
            return;
        }
        else if([self->_parseQueue operationCount] > 4)
        {
            DDLogWarn(@"parseQueue overflow, delaying ping by 4 seconds.");
            @synchronized(self->_timersToCancelOnDisconnect) {
                [self->_timersToCancelOnDisconnect addObject:createTimer(4.0, (^{
                    DDLogDebug(@"ping delay expired, retrying ping.");
                    [self sendPing:timeout];
                }))];
            }
        }
        else
        {
            //start ping timer
            self->_pingTimer = createDelayableTimer(timeout, (^{
                self->_pingTimer = nil;
                [self dispatchAsyncOnReceiveQueue: ^{
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
                if(self->_pingTimer)
                {
                    [self->_pingTimer cancel];      //cancel timer (ping was successful)
                    self->_pingTimer = nil;
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
                [self sendIq:ping withResponseHandler:^(XMPPIQ* result __unused) {
                    handler();
                } andErrorHandler:^(XMPPIQ* error) {
                    handler();
                }];
            }
        }
    }];
}

#pragma mark smacks

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
        for(NSDictionary* dic in sendCopy)
            [self send:(XMPPStanza*)[dic objectForKey:kStanza]];
        DDLogInfo(@"Done resending unacked stanzas...");
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
            for(NSDictionary* dic in sendCopy)
            {
                XMPPStanza* stanza = [dic objectForKey:kStanza];
                //only resend message stanzas because of the smacks error condition
                //but don't add them to our outgoing smacks queue again, if smacks isn't supported
                if([stanza.element isEqualToString:@"message"])
                    [self send:stanza withSmacks:self.connectionProperties.supportsSM3];
            }
            //persist these changes, the queue can now be empty (because smacks enable failed)
            //or contain all the resent stanzas (e.g. only resume failed)
            [self persistState];
        }
    }
}

-(BOOL) shouldTriggerSyncErrorForImportantUnackedOutgoingStanzas
{
    @synchronized(_stateLockObject) {
        DDLogInfo(@"Checking for important unacked stanzas...");
        for(NSDictionary* dic in self.unAckedStanzas)
        {
            MLXMLNode* xmlNode = [dic objectForKey:kStanza];
            //nonzas are not important here
            if(![xmlNode isKindOfClass:[XMPPStanza class]])
                continue;
            XMPPStanza* stanza = (XMPPStanza*)xmlNode;
            //important stanzas are message stanzas containing a body element
            if([stanza.element isEqualToString:@"message"] && [stanza check:@"body"])
                return YES;
        }
    }
    //no important stanzas found
    return NO;
}

-(BOOL) removeAckedStanzasFromQueue:(NSNumber*) hvalue
{
    NSMutableArray* ackHandlerToCall = [[NSMutableArray alloc] initWithCapacity:[_smacksAckHandler count]];
    @synchronized(_stateLockObject) {
        //stanza counting bugs on the server are fatal
        if(([hvalue unsignedIntValue] - [self.lastHandledOutboundStanza unsignedIntValue]) > [self.unAckedStanzas count])
        {
            self.streamID = nil;        //we don't ever want to resume this
            NSString* message = @"Server acknowledged more stanzas than sent by client";
            DDLogError(@"Stream error: %@", message);
            [self postError:message withIsSevere:NO];
            MLXMLNode* streamError = [[MLXMLNode alloc] initWithElement:@"stream:error" withAttributes:@{@"type": @"cancel"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"undefined-condition" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[] andData:nil],
                [[MLXMLNode alloc] initWithElement:@"handled-count-too-high" andNamespace:@"urn:xmpp:sm:3" withAttributes:@{
                    @"h": [hvalue stringValue],
                    @"send-count": [self.lastOutboundStanza stringValue],
                } andChildren:@[] andData:nil],
                [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[] andData:message],
            ] andData:nil];
            [self reconnectWithStreamError:streamError];
            return YES;
        }
        //stanza counting bugs on the server are fatal
        if([hvalue unsignedIntValue] < [self.lastHandledOutboundStanza unsignedIntValue])
        {
            self.streamID = nil;        //we don't ever want to resume this
            NSString* message = @"Server acknowledged less stanzas than last time";
            DDLogError(@"Stream error: %@", message);
            [self postError:message withIsSevere:NO];
            MLXMLNode* streamError = [[MLXMLNode alloc] initWithElement:@"stream:error" withAttributes:@{@"type": @"cancel"} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"undefined-condition" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[] andData:nil],
                [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[] andData:message],
            ] andData:nil];
            [self reconnectWithStreamError:streamError];
            return YES;
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
                            [[MLNotificationQueue currentQueue] postNotificationName:kMonalSentMessageNotice object:self userInfo:@{@"message":messageNode}];
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
    
    return NO;
}

-(void) requestSMAck:(BOOL) force
{
    //caution: this could be called from sendQueue, too!
    MLXMLNode* rNode;
    @synchronized(_stateLockObject) {
        unsigned long unackedCount = (unsigned long)[self.unAckedStanzas count];
        if(self.accountState>=kStateBound && self.connectionProperties.supportsSM3 &&
            ((!self.smacksRequestInFlight && unackedCount>0) || force)
        ) {
            DDLogVerbose(@"requesting smacks ack...");
            rNode = [[MLXMLNode alloc] initWithElement:@"r" andNamespace:@"urn:xmpp:sm:3" withAttributes:@{} andChildren:@[] andData:nil];
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
    
    NSDictionary* dic;
    @synchronized(_stateLockObject) {
        dic = @{
            @"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza],
        };
    }
    MLXMLNode* aNode = [[MLXMLNode alloc] initWithElement:@"a" andNamespace:@"urn:xmpp:sm:3" withAttributes:dic andChildren:@[] andData:nil];
    if(queuedSend)
        [self send:aNode];
    else      //this should only be done from sendQueue (e.g. by sendLastAck())
        [self writeToStream:aNode.XMLString];		// dont even bother queueing
}

#pragma mark - stanza handling

-(void) processInput:(MLXMLNode*) parsedStanza withDelayedReplay:(BOOL) delayedReplay
{
    if(delayedReplay)
        DDLogInfo(@"delayedReplay of Stanza: %@", parsedStanza);
    else
        DDLogInfo(@"RECV Stanza: %@", parsedStanza);
    
    //update stanza counter statistics
    self->_catchupStanzaCounter++;
    
    //restart logintimer for every incoming stanza when not logged in (don't do anything without a running timer)
    if(!delayedReplay && _loginTimer != nil && self->_accountState < kStateLoggedIn)
        [self reinitLoginTimer];
    
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
            if([@"" isEqualToString:presenceNode.from] || [@"" isEqualToString:presenceNode.to] || [presenceNode.fromHost containsString:@"@"] || [presenceNode.toHost containsString:@"@"])
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
            
            MLContact* contact = [MLContact createContactFromJid:presenceNode.fromUser andAccountID:self.accountID];
            if([presenceNode.fromUser isEqualToString:self.connectionProperties.identity.jid])
            {
                DDLogInfo(@"got self presence");
                
                //ignore special presences for status updates (they don't have one)
                if(![presenceNode check:@"/@type"])
                {
                    NSMutableDictionary* accountDetails = [[DataLayer sharedInstance] detailsForAccount:self.accountID];
                    accountDetails[@"statusMessage"] = [presenceNode check:@"status#"] ? [presenceNode findFirst:@"status#"] : @"";
                    [[DataLayer sharedInstance] updateAccounWithDictionary:accountDetails];
                }
            }
            else
            {
                if([presenceNode check:@"/<type=subscribe>"])
                {
                    // check if we need a contact request
                    NSDictionary* contactSub = [[DataLayer sharedInstance] getSubscriptionForContact:contact.contactJid andAccount:contact.accountID];
                    DDLogVerbose(@"Got subscription request for contact %@ having subscription status: %@", presenceNode.fromUser, contactSub);
                    if(!contactSub || !([[contactSub objectForKey:@"subscription"] isEqualToString:kSubTo] || [[contactSub objectForKey:@"subscription"] isEqualToString:kSubBoth]))
                        [[DataLayer sharedInstance] addContactRequest:contact];
                    else if(contactSub && [[contactSub objectForKey:@"subscription"] isEqualToString:kSubTo])
                        [self addToRoster:contact withPreauthToken:nil];
                    
                    //wait 1 sec for nickname and profile image to be processed, then send out kMonalContactRefresh notification
                    createTimer(1.0, (^{
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self userInfo:@{
                            @"contact": [MLContact createContactFromJid:presenceNode.fromUser andAccountID:self.accountID]
                        }];
                    }));
                }
                
                if([presenceNode check:@"/<type=unsubscribe>"])
                {
                    // check if we need a contact request
                    NSDictionary* contactSub = [[DataLayer sharedInstance] getSubscriptionForContact:contact.contactJid andAccount:contact.accountID];
                    DDLogVerbose(@"Got unsubscribe request of contact %@ having subscription status: %@", presenceNode.fromUser, contactSub);
                    [[DataLayer sharedInstance] deleteContactRequest:contact];
                    
                    //wait 1 sec for nickname and profile image to be processed, then send out kMonalContactRefresh notification
                    createTimer(1.0, (^{
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self userInfo:@{
                            @"contact": [MLContact createContactFromJid:presenceNode.fromUser andAccountID:self.accountID]
                        }];
                    }));
                }

                if(contact.isMuc || [presenceNode check:@"{http://jabber.org/protocol/muc#user}x"] || [presenceNode check:@"{http://jabber.org/protocol/muc}x"])
                {
                    //only handle presences for mucs we know
                    if([[DataLayer sharedInstance] isBuddyMuc:presenceNode.fromUser forAccount:self.accountID])
                        [self.mucProcessor processPresence:presenceNode];
                    else
                        DDLogError(@"Got presence of unknown muc %@, ignoring...", presenceNode.fromUser);
                    
                    //mark this stanza as handled
                    [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                    return;
                }
                
                if(![[HelperTools defaultsDB] boolForKey: @"allowNonRosterContacts"] && !contact.isSubscribedFrom)
                {
                    //mark this stanza as handled
                    [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                    return;
                }

                if(![presenceNode check:@"/@type"])
                {
                    DDLogVerbose(@"presence notice from %@", presenceNode.fromUser);
                    if(contact.isMuc)
                        [self.mucProcessor processPresence:presenceNode];
                    else
                    {
                        contact.state = [presenceNode findFirst:@"show#"];
                        contact.statusMessage = [presenceNode findFirst:@"status#"];

                        //add contact if possible (ignore already existing contacts)
                        [[DataLayer sharedInstance] addContact:presenceNode.fromUser forAccount:self.accountID nickname:nil];

                        //clear the state field in db and reset the ver hash for this resource
                        [[DataLayer sharedInstance] setOnlineBuddy:presenceNode forAccount:self.accountID];
                        
                        //update buddy state
                        [[DataLayer sharedInstance] setBuddyState:presenceNode forAccount:self.accountID];
                        [[DataLayer sharedInstance] setBuddyStatus:presenceNode forAccount:self.accountID];
                        
                        [[MLNotificationQueue currentQueue] postNotificationName:kMonalNewPresenceNotice object:self userInfo:@{
                            @"jid": presenceNode.fromUser,
                            @"accountID": self.accountID,
                            @"resource": nilWrapper(presenceNode.fromResource),
                            @"available": @YES,
                        }];
                    }
                }
                else if([presenceNode check:@"/<type=unavailable>"])
                {
                    DDLogVerbose(@"Updating lastInteraction from unavailable presence...");
                    [[DataLayer sharedInstance] setOfflineBuddy:presenceNode forAccount:self.accountID];
                    
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalNewPresenceNotice object:self userInfo:@{
                        @"jid": presenceNode.fromUser,
                        @"accountID": self.accountID,
                        @"resource": nilWrapper(presenceNode.fromResource),
                        @"available": @NO,
                    }];
                    
                    //inform other parts of our system that the lastInteraction timestamp has potentially changed
                    //(e.g. no supporting resource online anymore)
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
                        @"jid": presenceNode.fromUser,
                        @"accountID": self.accountID,
                        @"lastInteraction": nilWrapper([[DataLayer sharedInstance] lastInteractionOfJid:presenceNode.fromUser forAccountID:self.accountID]),
                        @"isTyping": @NO,
                        @"resource": nilWrapper(presenceNode.fromResource),
                    }];
                }

                //handle entity capabilities (this has to be done *after* setOnlineBuddy which sets the ver hash for the resource to "")
                if(
                    [presenceNode check:@"{http://jabber.org/protocol/caps}c@hash"] &&
                    [presenceNode check:@"{http://jabber.org/protocol/caps}c@ver"] &&
                    presenceNode.fromUser &&
                    presenceNode.fromResource
                )
                {
                    NSString* newVer = [presenceNode findFirst:@"{http://jabber.org/protocol/caps}c@ver"];
                    BOOL shouldQueryCaps = NO;
                    if(![@"sha-1" isEqualToString:[presenceNode findFirst:@"{http://jabber.org/protocol/caps}c@hash"]])
                    {
                        DDLogWarn(@"Unknown caps hash algo '%@', requesting disco query without checking hash!", [presenceNode findFirst:@"{http://jabber.org/protocol/caps}c@hash"]);
                        shouldQueryCaps = YES;
                    }
                    else
                    {
                        NSString* ver = [[DataLayer sharedInstance] getVerForUser:presenceNode.fromUser andResource:presenceNode.fromResource onAccountID:self.accountID];
                        if(!ver || ![ver isEqualToString:newVer])     //caps hash of resource changed
                            [[DataLayer sharedInstance] setVer:newVer forUser:presenceNode.fromUser andResource:presenceNode.fromResource onAccountID:self.accountID];

                        if(![[DataLayer sharedInstance] getCapsforVer:newVer onAccountID:self.accountID])
                        {
                            DDLogInfo(@"Presence included unknown caps hash %@, requesting disco query", newVer);
                            shouldQueryCaps = YES;
                        }
                    }
                    
                    if(shouldQueryCaps)
                    {
                        if([_runningCapsQueries containsObject:newVer])
                            DDLogInfo(@"Presence included unknown caps hash %@, but disco query already running, not querying again", newVer);
                        else
                        {
                            DDLogInfo(@"Querying disco for caps hash: %@", newVer);
                            XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
                            [discoInfo setiqTo:presenceNode.from];
                            [discoInfo setDiscoInfoNode];
                            [self sendIq:discoInfo withHandler:$newHandler(MLIQProcessor, handleEntityCapsDisco)];
                            [_runningCapsQueries addObject:newVer];
                        }
                    }
                }
                
                //handle last interaction time (this must be done *after* parsing the ver attribute to get the cached capabilities)
                //but only do so if the urn:xmpp:idle:1 was supported by that resource (e.g. don't send out unneeded updates)
                if(![presenceNode check:@"/@type"] && presenceNode.fromResource && [[DataLayer sharedInstance] checkCap:@"urn:xmpp:idle:1" forUser:presenceNode.fromUser andResource:presenceNode.fromResource onAccountID:self.accountID])
                {
                    DDLogVerbose(@"Updating lastInteraction from normal presence...");
                    //findFirst: will return nil for lastInteraction = "online" --> DataLayer will handle that correctly
                    [[DataLayer sharedInstance] setLastInteraction:[presenceNode findFirst:@"{urn:xmpp:idle:1}idle@since|datetime"] forJid:presenceNode.fromUser andResource:presenceNode.fromResource onAccountID:self.accountID];
                    
                    //inform other parts of our system that the lastInteraction timestamp has changed
                    [[MLNotificationQueue currentQueue] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
                        @"jid": presenceNode.fromUser,
                        @"accountID": self.accountID,
                        @"lastInteraction": nilWrapper([[DataLayer sharedInstance] lastInteractionOfJid:presenceNode.fromUser forAccountID:self.accountID]),
                        @"isTyping": @NO,
                        @"resource": nilWrapper(presenceNode.fromResource),
                    }];
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
            if([@"" isEqualToString:outerMessageNode.from] || [@"" isEqualToString:outerMessageNode.to] || [outerMessageNode.fromHost containsString:@"@"] || [outerMessageNode.toHost containsString:@"@"])
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
                    [messageNode addChildNode:[outerMessageNode findFirst:@"{urn:xmpp:mam:2}result/{urn:xmpp:forward:0}forwarded/{urn:xmpp:delay}delay"]];
                
                DDLogDebug(@"mam extracted, messageNode is now: %@", messageNode);
            }
            else if([outerMessageNode check:@"{urn:xmpp:carbons:2}*"])     //carbon copy
            {
                if(!self.connectionProperties.usingCarbons2)
                {
                    DDLogError(@"carbon copies not enabled, ignoring this spoofed carbon copy!");
                    //even these stanzas have to be counted by smacks
                    [self incrementLastHandledStanzaWithDelayedReplay:delayedReplay];
                    return;
                }
                
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
                    [messageNode addChildNode:[outerMessageNode findFirst:@"{urn:xmpp:delay}delay"]];
                
                DDLogDebug(@"carbon extracted, messageNode is now: %@", messageNode);
            }
            
            //sanity: check if inner message from and to attributes are valid and throw it away if not
            if([@"" isEqualToString:messageNode.from] || [@"" isEqualToString:messageNode.to] || [messageNode.fromHost containsString:@"@"] || [messageNode.toHost containsString:@"@"])
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
                DDLogInfo(@"Processing message stanza (delayedReplay=%@)...", bool2str(delayedReplay));
                
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
                    [[DataLayer sharedInstance] setLastStanzaId:stanzaid forMuc:messageNode.fromUser andAccount:self.accountID];
                }
                else if(stanzaid && ![messageNode check:@"/<type=groupchat>"])
                {
                    DDLogVerbose(@"Updating lastStanzaId of user archive in database to: %@", stanzaid);
                    [[DataLayer sharedInstance] setLastStanzaId:stanzaid forAccount:self.accountID];
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
            
            //openfire compatibility: remove iq-to of bind
            if([self.connectionProperties.serverIdentity isEqualToString:@"https://www.igniterealtime.org/projects/openfire/"] && [iqNode check:@"/{jabber:client}iq<type=result>/{urn:ietf:params:xml:ns:xmpp-bind}bind"])
                iqNode.to = nil;
            
            //sanity: check if iq from and to attributes are valid and throw it away if not
            if([@"" isEqualToString:iqNode.from] || [@"" isEqualToString:iqNode.to] || [iqNode.fromHost containsString:@"@"] || [iqNode.toHost containsString:@"@"])
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
            //use parsedStanza instead of iqNode to be sure we get the raw values even if ids etc. get added automatically to iq stanzas if accessed as XMPPIQ* object
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
                [MLIQProcessor processUnboundIq:iqNode forAccount:self];
            
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
            self.isDoingFullReconnect = NO;

            //now we are bound again
            _accountState = kStateBound;
            _connectedTime = [NSDate date];
            _reconnectBackoffTime = 0;
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
            
            //enable push in case our token has changed
            [self enablePush];
            
            //ping all mucs to check if we are still connected (XEP-0410)
            [self.mucProcessor pingAllMucs];
            
            @synchronized(_stateLockObject) {
                //signal finished catchup if our current outgoing stanza counter is acked, this introduces an additional roundtrip to make sure
                //all stanzas the *server* wanted to replay have been received, too
                //request an ack to accomplish this if stanza replay did not already trigger one (smacksRequestInFlight is false if replay did not trigger one)
                if(!self.smacksRequestInFlight)
                    [self requestSMAck:YES];    //force sending of the request even if the smacks queue is empty (needed to always trigger the smacks handler below after 1 RTT)
                DDLogVerbose(@"Adding resume smacks handler to check for completed catchup on account %@: %@", self.accountID, self.lastOutboundStanza);
                weakify(self);
                [self addSmacksHandler:^{
                    strongify(self);
                    DDLogInfo(@"Inside resume smacks handler: catchup *possibly* done (%@)", self.lastOutboundStanza);
                    //having no entry at all means catchup and replay are done
                    //if replay is not done yet, the kMonalFinishedCatchup notification will be triggered by the replay handler once the replay is finished
                    if(self->_inCatchup[self.connectionProperties.identity.jid] == nil && !self->_catchupDone)
                    {
                        DDLogInfo(@"Replay really done, now posting kMonalFinishedCatchup notification");
                        [self handleFinishedCatchup];
                    }
                    
                    //handle all delayed replays not yet done and resume them (e.g. all _inCatchup entries being NO)
                    NSDictionary* catchupCopy = [self->_inCatchup copy];
                    for(NSString* archiveJid in catchupCopy)
                    {
                        if([catchupCopy[archiveJid] boolValue] == NO)  //NO means no mam catchup running, but delayed replay not yet done --> resume delayed replay
                        {
                            DDLogInfo(@"Resuming replay of delayed stanzas for %@...", archiveJid);
                            //this will put a truly async block onto the receive queue which will resume the delayed stanza replay
                            //this replay will race with new live stanzas coming in, but that does not matter:
                            //every incominglive stanza will be put into our replay queue and replayed once its time comes
                            //the kMonalFinishedCatchup notification will be triggered by the replay handler once the replay is finished (e.g. the replay queue in our db is empty)
                            [self mamFinishedFor:archiveJid];
                        }
                    }
                }];
            }
            
            //initialize stanza counter for statistics
            [self initCatchupStats];
        }
        else if([parsedStanza check:@"/{urn:xmpp:sm:3}failed"] && self.connectionProperties.supportsSM3 && self.accountState<kStateBound && self.resuming)
        {
            //we landed here because smacks resume failed
            
            __block BOOL error = NO;
            self.resuming = NO;
            @synchronized(_stateLockObject) {
                //invalidate stream id
                self.streamID = nil;
                //get h value, if server supports smacks revision 1.5
                NSNumber* h = [parsedStanza findFirst:@"/@h|int"];
                DDLogInfo(@"++++++++++++++++++++++++ failed resume: h=%@", h);
                if(h!=nil)
                    error = [self removeAckedStanzasFromQueue:h];
                //persist these changes
                [self persistState];
            }

            //don't try to bind, if removeAckedStanzasFromQueue returned an error (it will trigger a reconnect in these cases)
            if(!error)
            {
                //bind  a new resource like normal on failed resume (supportsSM3 is still YES here but switches to NO on failed enable later on, if necessary)
                [self bindResource:self.connectionProperties.identity.resource];
            }
        }
        else if([parsedStanza check:@"/{urn:xmpp:sm:3}failed"] && self.connectionProperties.supportsSM3 && self.accountState>=kStateBound && !self.resuming)
        {
            //we landed here because smacks enable failed
            
            self.connectionProperties.supportsSM3 = NO;
            //init session and query disco, roster etc.
            [self initSession];
        }
#pragma mark - SASL1
        else if([parsedStanza check:@"/{urn:ietf:params:xml:ns:xmpp-sasl}failure"])
        {
            if(self.accountState >= kStateLoggedIn)
                return [self invalidXMLError];
            
            //record TLS version
            self.connectionProperties.tlsVersion = [((MLStream*)self->_oStream) isTLS13] ? @"1.3" : @"1.2";
            
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
            message = [NSString stringWithFormat:NSLocalizedString(@"Login error, account disabled: %@", @""), message];
            
            //clear pipeline cache to make sure we have a fresh restart next time
            xmppPipeliningState oldPipeliningState = _pipeliningState;
            _pipeliningState = kPipelinedNothing;
            _cachedStreamFeaturesBeforeAuth = nil;
            _cachedStreamFeaturesAfterAuth = nil;
            
            //don't report error but reconnect if we pipelined stuff that is not correct anymore...
            if(oldPipeliningState != kPipelinedNothing)
            {
                DDLogWarn(@"Reconnecting to flush pipeline...");
                [self reconnect];
            }
            //...but don't try again if it's really the password, that's wrong
            //make sure this error is reported, even if there are other SRV records left (we disconnect here and won't try again)
            else
                [HelperTools postError:message withNode:nil andAccount:self andIsSevere:YES andDisableAccount:YES];
        }
        else if([parsedStanza check:@"/{urn:ietf:params:xml:ns:xmpp-sasl}challenge"])
        {
            //we don't support any challenge-response SASL mechanism for SASL1
            return [self invalidXMLError];
        }
        else if([parsedStanza check:@"/{urn:ietf:params:xml:ns:xmpp-sasl}success"])
        {
            if(self.accountState >= kStateLoggedIn)
                return [self invalidXMLError];
            
            //record TLS version
            self.connectionProperties.tlsVersion = [((MLStream*)self->_oStream) isTLS13] ? @"1.3" : @"1.2";
            
            //perform logic to handle sasl success
            DDLogInfo(@"Got SASL Success");
            
            self->_accountState = kStateLoggedIn;
            [[MLNotificationQueue currentQueue] postNotificationName:kMLIsLoggedInNotice object:self];
            
            _usableServersList = [NSMutableArray new];       //reset list to start again with the highest SRV priority on next connect
            if(_loginTimer)
            {
                [self->_loginTimer cancel];     //we are now logged in --> cancel running login timer
                _loginTimer = nil;
            }
            self->_loggedInOnce = YES;
            
            //after sasl success a new stream will be started --> reset parser to accommodate this
            [self prepareXMPPParser];
            
            //this could possibly be with or without XML opening (old behaviour was with opening, so keep that)
            DDLogDebug(@"Sending NOT-pipelined stream restart...");
            [self startXMPPStreamWithXMLOpening:YES];
            
            //only pipeline stream resume/bind if not already done
            if(_pipeliningState < kPipelinedResumeOrBind)
            {
                //pipeline stream resume/bind after auth onto our stream header if we have cached stream features available
                if(_cachedStreamFeaturesAfterAuth != nil)
                {
                    DDLogDebug(@"Pipelining resume or bind using cached stream features: %@", _cachedStreamFeaturesAfterAuth);
                    _pipeliningState = kPipelinedResumeOrBind;
                    [self handleFeaturesAfterAuth:_cachedStreamFeaturesAfterAuth];
                }
            }
        }
#pragma mark - SASL2
        else if([parsedStanza check:@"/{urn:xmpp:sasl:2}challenge"])
        {
            if(self.accountState >= kStateLoggedIn)
                return [self invalidXMLError];
            
            //only allow challenge handling, if we are in scram mode (e.g. we selected a SCRAM-XXX auth method)
            if(!self->_scramHandler)
                return [self invalidXMLError];
            
            NSString* message = nil;
            BOOL deactivate_account = NO;
            NSString* innerSASLData = [[NSString alloc] initWithData:[parsedStanza findFirst:@"/{urn:xmpp:sasl:2}challenge#|base64"] encoding:NSUTF8StringEncoding];
            switch([self->_scramHandler parseServerFirstMessage:innerSASLData]) {
                case MLScramStatusSSDPTriggered: deactivate_account = YES; message = NSLocalizedString(@"Detected ongoing MITM attack via SSDP, aborting authentication and disabling account to limit damage. You should try to reenable your account once you are in a clean networking environment again.", @""); break;
                case MLScramStatusNonceError: deactivate_account = NO; message = NSLocalizedString(@"Error handling SASL challenge of server (nonce error), disconnecting!", @"parenthesis should be verbatim"); break;
                case MLScramStatusUnsupportedMAttribute: deactivate_account = NO; message = NSLocalizedString(@"Error handling SASL challenge of server (m-attr error), disconnecting!", @"parenthesis should be verbatim"); break;
                case MLScramStatusIterationCountInsecure: deactivate_account = NO; message = NSLocalizedString(@"Error handling SASL challenge of server (iteration count too low), disconnecting!", @"parenthesis should be verbatim"); break;
                case MLScramStatusServerFirstOK: deactivate_account = NO; message = nil; break;        //everything is okay
                default: unreachable(@"wrong status for scram message!"); break;
            }
            
            //check for incomplete XEP-0440 support (not implementing mandatory tls-server-end-point channel-binding) not mitigated by SSDP
            //(we allow either support for tls-server-end-point or SSDP signed non-support)
            if([kServerDoesNotFollowXep0440Error isEqualToString:[self channelBindingToUse]])
            {
                MLXMLNode* streamError = [[MLXMLNode alloc] initWithElement:@"stream:error" withAttributes:@{@"type": @"cancel"} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"undefined-condition" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[] andData:nil],
                    [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-streams" withAttributes:@{} andChildren:@[] andData:kServerDoesNotFollowXep0440Error],
                ] andData:nil];
                [self disconnectWithStreamError:streamError andExplicitLogout:YES];
                
                //make sure this error is reported, even if there are other SRV records left (we disconnect here and won't try again)
                [HelperTools postError:NSLocalizedString(@"Either this is a man-in-the-middle attack OR your server neither implements XEP-0474 nor does it fully implement XEP-0440 which mandates support for tls-server-end-point channel-binding. In either case you should inform your server admin! Account disabled now.", @"") withNode:nil andAccount:self andIsSevere:YES andDisableAccount:YES];
            }
            
            if(message != nil)
            {
                DDLogError(@"SCRAM says this server-first message was wrong!");
                
                //clear pipeline cache to make sure we have a fresh restart next time
                xmppPipeliningState oldPipeliningState = _pipeliningState;
                _pipeliningState = kPipelinedNothing;
                _cachedStreamFeaturesBeforeAuth = nil;
                _cachedStreamFeaturesAfterAuth = nil;
                
                //don't report error but reconnect if we pipelined stuff that is not correct anymore...
                if(oldPipeliningState != kPipelinedNothing)
                {
                    DDLogWarn(@"Reconnecting to flush pipeline...");
                    [self reconnect];
                    return;
                }
                
                //...but don't try again if it's really the server-first message, that's wrong
                //make sure this error is reported, even if there are other SRV records left (we disconnect here and won't try again)
                //deactivate the account if requested, too
                [HelperTools postError:message withNode:nil andAccount:self andIsSevere:YES andDisableAccount:deactivate_account];
                [self disconnect];
                
                return;
            }
            
            NSData* channelBindingData = [((MLStream*)self->_oStream) channelBindingDataForType:[self channelBindingToUse]];
            MLXMLNode* responseXML = [[MLXMLNode alloc] initWithElement:@"response" andNamespace:@"urn:xmpp:sasl:2" withAttributes:@{} andChildren:@[] andData:[HelperTools encodeBase64WithString:[self->_scramHandler clientFinalMessageWithChannelBindingData:channelBindingData]]];
            [self send:responseXML];
            
            //pipeline stream restart
            /*
            * WARNING: this can not be done, because pipelining a stream restart will break the local parser:
            *          1. the <?xml ...?> "tag" confuses the parser if its coming in an already established stream (e.g. if it sees it twice)
            *          2. the parser can not be reset after receiving the sasl <success/> because the old parser could have already swallowed everything
            *             coming after the <success/> (e.g. the new stream opening and stream features and possibly even the smacks resumption data)
            *          3. making the used parser (NSXMLParser) ignore subsequent <?xml ...?> headers does not seem possible
            *          4. switching to a new parser (maybe written in rust) can solve this and would save us 1 RTT more in every sasl scheme (even challenge-response ones)
            * TODO SOLUTION: SASL2 supports the <inline/> element instead, to "pipeline" smacks-resume and/or bind2 onto the SASL2 authentication
            
            DDLogDebug(@"Pipelining stream restart after response to auth challenge...");
            _pipeliningState = kPipelinedStreamRestart;
            [self startXMPPStreamWithXMLOpening:NO];
            
            //pipeline stream resume/bind after auth onto our stream header if we have cached stream features available
            if(_cachedStreamFeaturesAfterAuth != nil)
            {
                DDLogDebug(@"Pipelining resume or bind using cached stream features: %@", _cachedStreamFeaturesAfterAuth);
                _pipeliningState = kPipelinedResumeOrBind;
                [self handleFeaturesAfterAuth:_cachedStreamFeaturesAfterAuth];
            }
            */
        }
        else if([parsedStanza check:@"/{urn:xmpp:sasl:2}failure"])
        {
            NSString* errorReason = [parsedStanza findFirst:@"{urn:ietf:params:xml:ns:xmpp-streams}!text$"];
            NSString* message = [parsedStanza findFirst:@"text#"];
            DDLogWarn(@"Got SASL2 %@: %@", errorReason, message);
            if([errorReason isEqualToString:@"not-authorized"])
            {
                if(!message)
                    message = NSLocalizedString(@"Not Authorized. Please check your credentials.", @"");
            }
            else
            {
                if(!message)
                    message = [NSString stringWithFormat:NSLocalizedString(@"Server returned SASL2 error '%@'.", @""), errorReason];
            }
            message = [NSString stringWithFormat:NSLocalizedString(@"Login error, account disabled: %@", @""), message];
            
            //clear pipeline cache to make sure we have a fresh restart next time
            xmppPipeliningState oldPipeliningState = _pipeliningState;
            _pipeliningState = kPipelinedNothing;
            _cachedStreamFeaturesBeforeAuth = nil;
            _cachedStreamFeaturesAfterAuth = nil;
            
            //don't report error but reconnect if we pipelined stuff that is not correct anymore...
            if(oldPipeliningState != kPipelinedNothing)
            {
                DDLogWarn(@"Reconnecting to flush pipeline...");
                [self reconnect];
            }
            //...but don't try again if it's really the password, that's wrong
            else
            {
                //display sasl mechanism list and list of channel-binding types even if SASL2 failed
                
                //build mechanism list displayed in ui (mark _scramHandler.method as used)
                NSMutableDictionary* mechanismList = [NSMutableDictionary new];
                for(NSString* mechanism in _supportedSaslMechanisms)
                    mechanismList[mechanism] = @([mechanism isEqualToString:self->_scramHandler.method]);
                DDLogInfo(@"Saving saslMethods list: %@", mechanismList);
                self.connectionProperties.saslMethods = mechanismList;
                
                //build channel-binding list displayed in ui (mark [self channelBindingToUse] as used)
                NSMutableDictionary* channelBindings = [NSMutableDictionary new];
                if(_supportedChannelBindings != nil)
                    for(NSString* cbType in _supportedChannelBindings)
                        channelBindings[cbType] = @([cbType isEqualToString:[self channelBindingToUse]]);
                DDLogInfo(@"Saving channel-binding types list: %@", channelBindings);
                self.connectionProperties.channelBindingTypes = channelBindings;
                
                //record SDDP support
                self.connectionProperties.supportsSSDP = self->_scramHandler.ssdpSupported;
                
                //record TLS version
                self.connectionProperties.tlsVersion = [((MLStream*)self->_oStream) isTLS13] ? @"1.3" : @"1.2";
                
                //make sure this error is reported, even if there are other SRV records left (we disconnect here and won't try again)
                [HelperTools postError:message withNode:nil andAccount:self andIsSevere:YES andDisableAccount:YES];
            }
        }
        else if([parsedStanza check:@"/{urn:xmpp:sasl:2}success"])
        {
            if(self.accountState >= kStateLoggedIn)
                return [self invalidXMLError];
            
            //check server-final message for correctness if needed
            if(!self->_scramHandler.finishedSuccessfully)
                [self handleScramInSuccessOrContinue:parsedStanza];
            
            //build mechanism list displayed in ui (mark _scramHandler.method as used)
            NSMutableDictionary* mechanismList = [NSMutableDictionary new];
            for(NSString* mechanism in _supportedSaslMechanisms)
                mechanismList[mechanism] = @([mechanism isEqualToString:self->_scramHandler.method]);
            DDLogInfo(@"Saving saslMethods list: %@", mechanismList);
            self.connectionProperties.saslMethods = mechanismList;
            
            //build channel-binding list displayed in ui (mark [self channelBindingToUse] as used)
            NSMutableDictionary* channelBindings = [NSMutableDictionary new];
            if(_supportedChannelBindings != nil)
                for(NSString* cbType in _supportedChannelBindings)
                    channelBindings[cbType] = @([cbType isEqualToString:[self channelBindingToUse]]);
            DDLogInfo(@"Saving channel-binding types list: %@", channelBindings);
            self.connectionProperties.channelBindingTypes = channelBindings;
            
            //update user identity using authorization-identifier, including support for fullJids (as specified by BIND2)
            [self.connectionProperties.identity bindJid:[parsedStanza findFirst:@"authorization-identifier#"]];
            
            //record SDDP support
            self.connectionProperties.supportsSSDP = self->_scramHandler.ssdpSupported;
            
            //record TLS version
            self.connectionProperties.tlsVersion = [((MLStream*)self->_oStream) isTLS13] ? @"1.3" : @"1.2";
            
            self->_scramHandler = nil;
            self->_blockToCallOnTCPOpen = nil;     //just to be sure but not strictly necessary
            self->_accountState = kStateLoggedIn;
            _usableServersList = [NSMutableArray new];       //reset list to start again with the highest SRV priority on next connect
            if(_loginTimer)
            {
                [self->_loginTimer cancel];     //we are now logged in --> cancel running login timer
                _loginTimer = nil;
            }
            self->_loggedInOnce = YES;
            
            //pin sasl2 support for this account (this is done only after successful auth to prevent DOS MITM attacks simulating SASL2 support)
            //downgrading to SASL1 would mean PLAIN instead of SCRAM and no protocol agility for channel-bindings,
            //if XEP-0440 is not supported by server
            [[DataLayer sharedInstance] deactivatePlainForAccount:self.accountID];
            
            //NOTE: we don't have any stream restart when using SASL2
            //NOTE: we don't need to pipeline anything here, because SASL2 sends out the new stream features immediately without a stream restart
            _cachedStreamFeaturesAfterAuth = nil;       //make sure we don't accidentally try to do pipelining
        }
        else if([parsedStanza check:@"/{urn:xmpp:sasl:2}continue"])
        {
            if(self.accountState >= kStateLoggedIn)
                return [self invalidXMLError];
            
            //check server-final message for correctness
            [self handleScramInSuccessOrContinue:parsedStanza];
            
            NSArray* tasks = [parsedStanza find:@"tasks/task#"];
            if(tasks.count == 0)
            {
                [HelperTools postError:NSLocalizedString(@"Server implementation error: SASL2 tasks empty, account disabled!", @"") withNode:nil andAccount:self andIsSevere:YES andDisableAccount:YES];
                return;
            }
            
            if(tasks.count != 1)
            {
                [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"We don't support any task requested by the server, account disabled: %@", @""), tasks] withNode:nil andAccount:self andIsSevere:YES andDisableAccount:YES];
                return;
            }
            
            if(![tasks[0] isEqualToString:_upgradeTask])
            {
                [HelperTools postError:[NSString stringWithFormat:NSLocalizedString(@"We don't support the single task requested by the server, account disabled: %@", @""), tasks] withNode:nil andAccount:self andIsSevere:YES andDisableAccount:YES];
                return;
            }
            
            [self send:[[MLXMLNode alloc] initWithElement:@"next" andNamespace:@"urn:xmpp:sasl:2" withAttributes:@{
                @"task": _upgradeTask
            } andChildren:@[] andData:nil]];
        }
        else if([parsedStanza check:@"/{urn:xmpp:sasl:2}task-data/{urn:xmpp:scram-upgrade:0}salt"])
        {
            NSData* salt = [parsedStanza findFirst:@"{urn:xmpp:scram-upgrade:0}salt#|base64"];
            uint32_t iterations = (uint32_t)[[parsedStanza findFirst:@"{urn:xmpp:scram-upgrade:0}salt@iterations|uint"] unsignedLongValue];
            
            NSString* scramMechanism = [_upgradeTask substringWithRange:NSMakeRange(5, _upgradeTask.length-5)];
            DDLogInfo(@"Upgrading password using SCRAM mechanism: %@", scramMechanism);
            SCRAM* scramUpgradeHandler = [[SCRAM alloc] initWithUsername:self.connectionProperties.identity.user password:self.connectionProperties.identity.password andMethod:scramMechanism];
            NSData* saltedPassword = [scramUpgradeHandler hashPasswordWithSalt:salt andIterationCount:iterations];
            
            [self send:[[MLXMLNode alloc] initWithElement:@"task-data" andNamespace:@"urn:xmpp:sasl:2" withAttributes:@{} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"hash" andNamespace:@"urn:xmpp:scram-upgrade:0" andData:[HelperTools encodeBase64WithData:saltedPassword]]
            ] andData:nil]];
        }
        else if([parsedStanza check:@"/{http://etherx.jabber.org/streams}features"])
        {
            //prevent reconnect attempt
            if(_accountState < kStateHasStream)
                _accountState = kStateHasStream;
            
            //perform logic to handle stream
            if(self.accountState < kStateLoggedIn)
            {
                //handle features normally if we didn't have a cached copy for pipelining (but always refresh our cached copy)
                if(_cachedStreamFeaturesBeforeAuth == nil)
                {
                    DDLogDebug(@"Handling NOT-pipelined stream features (before auth)...");
                    [self handleFeaturesBeforeAuth:parsedStanza];
                }
                else
                    DDLogDebug(@"Stream features (before auth) already read from cache, ignoring incoming stream features (but refreshing cache)...");
                _cachedStreamFeaturesBeforeAuth = parsedStanza;
            }
            else
            {
                //handle features normally if we didn't have a cached copy for pipelining (but always refresh our cached copy)
                if(_cachedStreamFeaturesAfterAuth == nil)
                {
                    DDLogDebug(@"Handling NOT-pipelined stream features (after auth)...");
                    [self handleFeaturesAfterAuth:parsedStanza];
                }
                else
                    DDLogDebug(@"Stream features (after auth) already read from cache, ignoring incoming stream features (but refreshing cache).\n Cached: %@\nIncoming: %@", _cachedStreamFeaturesAfterAuth, parsedStanza);
                _cachedStreamFeaturesAfterAuth = parsedStanza;
            }
        }
        else if([parsedStanza check:@"/{http://etherx.jabber.org/streams}error"])
        {
            NSString* errorReason = [parsedStanza findFirst:@"{urn:ietf:params:xml:ns:xmpp-streams}!text$"];
            NSString* errorText = [parsedStanza findFirst:@"{urn:ietf:params:xml:ns:xmpp-streams}text#"];
            DDLogWarn(@"Got secure XMPP stream error %@: %@", errorReason, errorText);
            DDLogDebug(@"Setting _pipeliningState to kPipelinedNothing and clearing _cachedStreamFeaturesBeforeAuth and _cachedStreamFeaturesAfterAuth...");
            _pipeliningState = kPipelinedNothing;
            _cachedStreamFeaturesBeforeAuth = nil;
            _cachedStreamFeaturesAfterAuth = nil;
            NSString* message = [NSString stringWithFormat:NSLocalizedString(@"XMPP stream error: %@", @""), errorReason];
            if(errorText && ![errorText isEqualToString:@""])
                message = [NSString stringWithFormat:NSLocalizedString(@"XMPP stream error %@: %@", @""), errorReason, errorText];
            [self postError:message withIsSevere:NO];
            [self reconnect];
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
            
            //don't ignore this error when trying to register, even though it could be a mitm etc.
            if(_registration || _registrationSubmission)
                [self postError:message withIsSevere:NO];
            else
            {
//this error could be a mitm or some other network problem caused by an active attacker, just ignore it since we are not in a tls context here
#ifdef IS_ALPHA
                [self postError:message withIsSevere:NO];
#endif
            }
            [self reconnect];
        }
        else if([parsedStanza check:@"/{http://etherx.jabber.org/streams}features"])
        {
            //normally we would ignore starttls stream feature presence and opportunistically try starttls
            //(this is in accordance to RFC 7590: https://tools.ietf.org/html/rfc7590#section-3.1 )
            //BUT: we already pipelined the starttls command when starting the stream --> do nothing here
            DDLogInfo(@"Ignoring non-encrypted stream features (we already pipelined the starttls command when opening the stream)");
            return;
        }
        else if([parsedStanza check:@"/{urn:ietf:params:xml:ns:xmpp-tls}proceed"])
        {
            //stop the old xml parser and clear the parse queue
            //if we do not do this we could be prone to mitm attacks injecting xml elements into the stream before it gets encrypted
            //such xml elements would then get processed as received *after* the TLS initialization
            if(_xmlParser!=nil)
            {
                DDLogInfo(@"stopping old xml parser");
                [_xmlParser setDelegate:nil];
                [_xmlParser abortParsing];
                _xmlParser = nil;
                //throw away all parsed but not processed stanzas (we aborted the parser right now)
                //the xml parser will fill the parse queue synchronously while < kStateBound
                //--> no stanzas/nonzas will leak into the parse queue after resetting the parser and clearing the parse queue
                [_parseQueue cancelAllOperations];
            }
            //prepare input/output streams
            [_iPipe drainInputStreamAndCloseOutputStream];      //remove all pending data before starting tls handshake
            self->_streamHasSpace = NO;     //make sure we do not try to send any data while the tls handshake is still performed
            
            //dispatch async to not block the db transaction of the proceed stanza inside the receive queue
            //while waiting for the tls handshake to complete
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                DDLogInfo(@"configuring/starting tls handshake");
                MLStream* oStream = (MLStream*)self->_oStream;
                [oStream startTLS];
                if(!oStream.hasTLS)
                {
                    //only show this error if the connection was not closed but timed out (this is the case we want to debug here)
                    //other cases (cert errors etc.) should not trigger this notification
                    if([oStream streamStatus] != NSStreamStatusClosed)
                        showErrorOnAlpha(self, @"Failed to complete TLS handshake while using STARTTLS, retrying!");
                    DDLogError(@"Failed to complete TLS handshake, reconnecting!");
                    [self reconnect];
                    return;
                }
                self->_startTLSComplete = YES;
                
                //we successfully completed the tls handshake, now proceed inside the receive queue again
                [self->_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                    if(self.accountState<kStateReconnecting)
                    {
                        DDLogWarn(@"Aborting second half of starttls handling, accountState < kStateReconnecting");
                        return;
                    }
                    //create proper context for pipelining auth stuff (notification queue, db transaction etc.)
                    [MLNotificationQueue queueNotificationsInBlock:^{
                        [[DataLayer sharedInstance] createTransaction:^{
                            //don't write data to our tcp stream while inside this db transaction (all effects to the outside world should be transactional, too)
                            [self freezeSendQueue];
                            
                            //restart xml stream and parser
                            [self prepareXMPPParser];
                            [self startXMPPStreamWithXMLOpening:YES];
                            
                            //pipeline auth request onto our stream header if we have cached stream features available
                            if(self->_cachedStreamFeaturesBeforeAuth != nil)
                            {
                                DDLogDebug(@"Pipelining auth using cached stream features: %@", self->_cachedStreamFeaturesBeforeAuth);
                                self->_pipeliningState = kPipelinedAuth;
                                [self handleFeaturesBeforeAuth:self->_cachedStreamFeaturesBeforeAuth];
                            }
                        }];
                        [self unfreezeSendQueue];      //this will flush all stanzas added inside the db transaction and now waiting in the send queue
                    } onQueue:@"receiveQueue"];
                    [self persistState];        //make sure to persist all state changes triggered by the events in the notification queue
                }]] waitUntilFinished:NO];
            });
        }
        else
        {
            DDLogError(@"Ignoring unhandled *INSECURE* top-level xml element <%@>, reconnecting: %@", parsedStanza.element, parsedStanza);
            [self reconnect];
        }
    }
}

-(void) handleFeaturesBeforeAuth:(MLXMLNode*) parsedStanza
{
    return [self handleFeaturesBeforeAuth:parsedStanza withForceSasl2:NO];
}

-(void) handleFeaturesBeforeAuth:(MLXMLNode*) parsedStanza withForceSasl2:(BOOL) forceSasl2
{
    monal_id_returning_void_block_t checkProperSasl2Support = ^{
        //check if we SASL2 is supported with something better than PLAIN and, if so, switch off plain_activated
        NSSet* supportedSasl2Mechanisms = [NSSet setWithArray:[parsedStanza find:@"{urn:xmpp:sasl:2}authentication/mechanism#"]];
        for(NSString* mechanism in [SCRAM supportedMechanismsIncludingChannelBinding:YES])
            if([supportedSasl2Mechanisms containsObject:mechanism])
            {
                return @YES;
            }
        return @NO;
    };
    monal_id_block_t clearPipelineCacheOrReportSevereError = ^(NSString* msg) {
        DDLogWarn(@"Clearing auth pipeline due to error...");
        
        //clear pipeline cache to make sure we have a fresh restart next time
        xmppPipeliningState oldPipeliningState = self->_pipeliningState;
        self->_pipeliningState = kPipelinedNothing;
        self->_cachedStreamFeaturesBeforeAuth = nil;
        self->_cachedStreamFeaturesAfterAuth = nil;
        
        if(oldPipeliningState != kPipelinedNothing)
        {
            DDLogWarn(@"Retrying auth without pipelining...");
            [self reconnect];
        }
        else
        {
            //make sure this error is reported, even if there are other SRV records left (we disconnect here and won't try again)
            [HelperTools postError:msg withNode:nil andAccount:self andIsSevere:YES andDisableAccount:YES];
        }
    };
    //called below, if neither SASL1 nor SASL2 could be used to negotiate a valid SASL mechanism
    monal_void_block_t noAuthSupported = ^{
        DDLogWarn(@"No supported auth mechanism: %@", self->_supportedSaslMechanisms);
        
        //sasl2 will be pinned if we saw sasl2 support and PLAIN was NOT allowed by creating this account using the  advanced account creation menu
        //display scary warning message if sasl2 is pinned and login was successful at least once
        //or display a message pointing to the advanced account creation menu if sasl2 is pinned and login was NOT successful at least once
        //(e.g. we are trying to create this account just now)
        if(![[DataLayer sharedInstance] isPlainActivatedForAccount:self.accountID])
        {
            DDLogDebug(@"Plain is not activated for this account...");
            if(self->_loggedInOnce)
            {
                clearPipelineCacheOrReportSevereError(NSLocalizedString(@"Server suddenly lacks support for SASL2-SCRAM, ongoing MITM attack highly likely, aborting authentication and disabling account to limit damage. You should try to reenable your account once you are in a clean networking environment again.", @""));
                return;
            }
            //_supportedSaslMechanisms==nil indicates SASL1 support only
            else if([self->_supportedSaslMechanisms containsObject:@"PLAIN"] || self->_supportedSaslMechanisms == nil)
            {
                //leave that in for translators, we might use it at a later time
                while(!NSLocalizedString(@"This server isn't additionally hardened against man-in-the-middle attacks on the TLS encryption layer by using authentication methods that are secure against such attacks! This indicates an ongoing attack if the server is supposed to support SASL2 and SCRAM and is harmless otherwise. Use the advanced account creation menu and turn on the PLAIN switch there if you still want to log in to this server.", @""));
                
                clearPipelineCacheOrReportSevereError(NSLocalizedString(@"This server lacks support for SASL2 and SCRAM, additionally hardening authentication against man-in-the-middle attacks on the TLS encryption layer. Since this server is listed as supporting both at https://github.com/monal-im/SCRAM_PreloadList (or you intentionally left the PLAIN switch off when using the advanced account creation menu), an ongoing MITM attack is very likely! Try again once you are in a clean network environment.", @""));
                return;
            }
        }
        clearPipelineCacheOrReportSevereError(NSLocalizedString(@"No supported auth mechanism found, disabling account!", @""));
    };
    
    if(![parsedStanza check:@"{urn:xmpp:ibr-token:0}register"])
        DDLogWarn(@"Server NOT supporting Pre-Authenticated IBR");
    if(_registration)
    {
        if(_registrationToken && [parsedStanza check:@"{urn:xmpp:ibr-token:0}register"])
        {
            DDLogInfo(@"Registration: Calling submitRegToken");
            [self submitRegToken:_registrationToken];
        }
        else
        {
            DDLogInfo(@"Registration: Directly calling requestRegForm");
            [self requestRegForm];
        }
    }
    else if(_registrationSubmission)
    {
        DDLogInfo(@"Registration: Calling submitRegForm");
        [self submitRegForm];
    }
    //prefer SASL2 over SASL1
    else if([parsedStanza check:@"{urn:xmpp:sasl:2}authentication/mechanism"] && (![[DataLayer sharedInstance] isPlainActivatedForAccount:self.accountID] || forceSasl2))
    {
        DDLogDebug(@"Trying SASL2...");
        
        weakify(self);
        _blockToCallOnTCPOpen = ^{
            strongify(self);
            
            if([self->_supportedSaslMechanisms containsObject:@"PLAIN"])
                DDLogWarn(@"Server supports SASL2 PLAIN, ignoring because this is insecure!");
            
            //create list of upgradable scram mechanisms and pick the first one (highest security) the server and we support
            //but only do so, if we are using channel-binding for additional security
            //(a MITM could passively intercept the new SCRAM hash which is roughly equivalent to intercepting the plaintext password)
            self->_upgradeTask = nil;
            if([self channelBindingToUse] != nil && ![kServerDoesNotFollowXep0440Error isEqualToString:[self channelBindingToUse]])
            {
                NSSet* upgradesOffered = [NSSet setWithArray:[parsedStanza find:@"{urn:xmpp:sasl:2}authentication/{urn:xmpp:sasl:upgrade:0}upgrade#"]];
                for(NSString* method in [SCRAM supportedMechanismsIncludingChannelBinding:NO])
                    if([upgradesOffered containsObject:[NSString stringWithFormat:@"UPGR-%@", method]])
                    {
                        self->_upgradeTask = [NSString stringWithFormat:@"UPGR-%@", method];
                        break;
                    }
            }
            
            //check for supported scram mechanisms (highest security first!)
            for(NSString* mechanism in [SCRAM supportedMechanismsIncludingChannelBinding:[self channelBindingToUse] != nil])
                if([self->_supportedSaslMechanisms containsObject:mechanism])
                {
                    self->_scramHandler = [[SCRAM alloc] initWithUsername:self.connectionProperties.identity.user password:self.connectionProperties.identity.password andMethod:mechanism];
                    //set ssdp data for downgrade protection
                    //_supportedChannelBindings will be nil, if XEP-0440 is not supported by our server (which should never happen because XEP-0440 is mandatory for SASL2)
                    [self->_scramHandler setSSDPMechanisms:[self->_supportedSaslMechanisms allObjects] andChannelBindingTypes:[self->_supportedChannelBindings allObjects]];
                    MLXMLNode* authenticate = [[MLXMLNode alloc]
                        initWithElement:@"authenticate"
                        andNamespace:@"urn:xmpp:sasl:2"
                        withAttributes:@{@"mechanism": mechanism}
                        andChildren:@[
                            [[MLXMLNode alloc] initWithElement:@"initial-response" andData:[HelperTools encodeBase64WithString:[self->_scramHandler clientFirstMessageWithChannelBinding:[self channelBindingToUse]]]],
                            [[MLXMLNode alloc] initWithElement:@"user-agent" withAttributes:@{
                                @"id":[[[UIDevice currentDevice] identifierForVendor] UUIDString],
                            } andChildren:@[
                                [[MLXMLNode alloc] initWithElement:@"software" andData:@"Monal IM"],
                                [[MLXMLNode alloc] initWithElement:@"device" andData:[[UIDevice currentDevice] name]],
                            ] andData:nil],
                        ]
                        andData:nil
                    ];
                    //add upgrade element if we mutually support upgrades
                    if(self->_upgradeTask != nil)
                        [authenticate addChildNode:[[MLXMLNode alloc] initWithElement:@"upgrade" andNamespace:@"urn:xmpp:sasl:upgrade:0" andData:self->_upgradeTask]];
                    [self send:authenticate];
                    return;
                }
            
            //could not find any matching SASL2 mechanism (we do NOT support PLAIN)
            noAuthSupported();
        };
        
        //extract menchanisms presented
        _supportedSaslMechanisms = [NSSet setWithArray:[parsedStanza find:@"{urn:xmpp:sasl:2}authentication/mechanism#"]];
        
        //extract supported channel-binding types
        if([parsedStanza check:@"{urn:xmpp:sasl-cb:0}sasl-channel-binding"])
            _supportedChannelBindings = [NSSet setWithArray:[parsedStanza find:@"{urn:xmpp:sasl-cb:0}sasl-channel-binding/channel-binding@type"]];
        else
            _supportedChannelBindings = nil;
        
        //check if the server supports *any* scram method and wait for TLS connection establishment if so
        BOOL supportsScram = NO;
        for(NSString* mechanism in [SCRAM supportedMechanismsIncludingChannelBinding:YES])
            if([_supportedSaslMechanisms containsObject:mechanism])
                supportsScram = YES;
        
        //directly call our continuation block if SCRAM is not supported, because _blockToCallOnTCPOpen() will throw an error then
        //(we currently only support SCRAM for SASL2)
        //pipelining can also be done immediately if we are sure the tls handshake is complete (e.g. we're NOT in direct tls mode)
        //and if we are not pipelining the auth, we can call the block immediately, too
        //(because the TLS connection was obviously already established and that made us receive the non-cached stream features used here)
        //if we don't call it here, the continuation block will be called automatically once the TLS connection got established
        if(!supportsScram || !self.connectionProperties.server.isDirectTLS || _pipeliningState < kPipelinedAuth)
        {
            _blockToCallOnTCPOpen();
            _blockToCallOnTCPOpen = nil;     //don't call this twice
        }
        else
            DDLogWarn(@"Waiting until TLS stream is connected before pipelining the auth element due to channel binding...");
    }
    //check if the server activated SASL2 after previously only upporting SASL1
    else if([[DataLayer sharedInstance] isPlainActivatedForAccount:self.accountID] && ((NSNumber*)checkProperSasl2Support()).boolValue)
    {
        DDLogInfo(@"We detected SASL2 SCRAM support, deactivating forced SASL1 PLAIN fallback and retrying using SASL2...");
        [[DataLayer sharedInstance] deactivatePlainForAccount:self.accountID];
        //try again, this time using sasl2
        return [self handleFeaturesBeforeAuth:parsedStanza withForceSasl2:YES];
    }
    //SASL1 is fallback only if SASL2 isn't supported with something better than PLAIN
    else if([parsedStanza check:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms/mechanism"] && [[DataLayer sharedInstance] isPlainActivatedForAccount:self.accountID])
    {
        DDLogDebug(@"Trying SASL1...");
        
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
            
            //even double pipelining (e.g. pipelining onto the already pipelined sasl plain auth) is possible when using auth=PLAIN
            /*
             * WARNING: this can not be done, because pipelining a stream restart will break the local parser:
             *          1. the <?xml ...?> "tag" confuses the parser if its coming in an already established stream (e.g. if it sees it twice)
             *          2. the parser can not be reset after receiving the sasl <success/> because the old parser could have already swallowed everything
             *             coming after the <success/> (e.g. the new stream opening and stream features and possibly even the smacks resumption data)
             *          3. making the used parser (NSXMLParser) ignore subsequent <?xml ...?> headers does not seem possible
             *          4. switching to a new parser (maybe written in rust) can solve this and would save us 1 RTT more in every sasl scheme (even challenge-response ones)
             * TODO SOLUTION: SASL2 supports the <inline/> element instead, to "pipeline" smacks-resume and/or bind2 onto the SASL2 authentication
            DDLogDebug(@"Pipelining stream restart after auth...");
            _pipeliningState = kPipelinedStreamRestart;
            [self startXMPPStreamWithXMLOpening:NO];
            
            //pipeline stream resume/bind after auth onto our stream header if we have cached stream features available
            if(_cachedStreamFeaturesAfterAuth != nil)
            {
                DDLogDebug(@"Pipelining resume or bind using cached stream features: %@", _cachedStreamFeaturesAfterAuth);
                _pipeliningState = kPipelinedResumeOrBind;
                [self handleFeaturesAfterAuth:_cachedStreamFeaturesAfterAuth];
            }
            */
        }
        else
            noAuthSupported();
    }
    else
    {
        DDLogDebug(@"Neither SASL2 nor SASL1 worked...");
        
        //this is not a downgrade but something weird going on, log it as such
        if(![parsedStanza check:@"{urn:xmpp:sasl:2}authentication/mechanism"] && ![parsedStanza check:@"{urn:ietf:params:xml:ns:xmpp-sasl}mechanisms/mechanism"])
            DDLogError(@"Something weird happened: neither SASL1 nor SASL2 auth supported by this server!");
        noAuthSupported();
    }
}

-(void) handleFeaturesAfterAuth:(MLXMLNode*) parsedStanza
{
    self.connectionProperties.serverFeatures = parsedStanza;
    
    //this is set to NO if we fail to enable it
    if([parsedStanza check:@"{urn:xmpp:sm:3}sm"])
    {
        DDLogInfo(@"Server supports SM3");
        self.connectionProperties.supportsSM3 = YES;
    }
    
    if([parsedStanza check:@"{http://jabber.org/protocol/caps}c@node"])
    {
        DDLogInfo(@"Server identity: %@", [parsedStanza findFirst:@"{http://jabber.org/protocol/caps}c@node"]);
        self.connectionProperties.serverIdentity = [parsedStanza findFirst:@"{http://jabber.org/protocol/caps}c@node"];
    }
    
    MLXMLNode* resumeNode = nil;
    @synchronized(_stateLockObject) {
        //test if smacks is supported and allows resume
        if(self.connectionProperties.supportsSM3 && self.streamID)
        {
            NSDictionary* dic = @{
                @"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza],
                @"previd":self.streamID,
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

-(void) handleScramInSuccessOrContinue:(MLXMLNode*) parsedStanza
{
    //perform logic to handle sasl success
    DDLogInfo(@"Got SASL2 Success/Continue");
    
    //only parse and validate scram response, if we are in scram mode (should always be the case)
    MLAssert(self->_scramHandler != nil, @"self->_scramHandler should NEVER be nil when using SASL2!");
    
    NSString* message = nil;
    BOOL deactivate_account = NO;
    NSString* innerSASLData = [[NSString alloc] initWithData:[parsedStanza findFirst:@"additional-data#|base64"] encoding:NSUTF8StringEncoding];
    switch([self->_scramHandler parseServerFinalMessage:innerSASLData]) {
        case MLScramStatusWrongServerProof: deactivate_account = YES; message = NSLocalizedString(@"SCRAM server proof wrong, ongoing MITM attack highly likely, aborting authentication and disabling account to limit damage. You should try to reenable your account once you are in a clean networking environment again.", @""); break;
        case MLScramStatusServerError: deactivate_account = NO; message = NSLocalizedString(@"Unexpected error authenticating server using SASL2 (does your server have a bug?), disconnecting!", @""); break;
        case MLScramStatusServerFinalOK: deactivate_account = NO; message = nil; break;        //everything is okay
        default: unreachable(@"wrong status for scram message!"); break;
    }
    
    if(message != nil)
    {
        DDLogError(@"SCRAM says this server-final message was wrong!");
        
        //clear pipeline cache to make sure we have a fresh restart next time
        _pipeliningState = kPipelinedNothing;
        _cachedStreamFeaturesBeforeAuth = nil;
        _cachedStreamFeaturesAfterAuth = nil;
        
        //make sure this error is reported, even if there are other SRV records left (we disconnect here and won't try again)
        //deactivate the account if requested, too
        [HelperTools postError:message withNode:nil andAccount:self andIsSevere:YES andDisableAccount:deactivate_account];
        [self disconnect];
        
        return;
    }
    else
        DDLogDebug(@"SCRAM says this server-final message was correct");
}

//bridge needed fo MLServerDetails.m
-(NSArray*) supportedChannelBindingTypes
{
    return [((MLStream*)self->_oStream) supportedChannelBindingTypes];
}

-(NSString* _Nullable) channelBindingToUse
{
    NSArray* typesList = [((MLStream*)self->_oStream) supportedChannelBindingTypes];
    if(typesList == nil || typesList.count == 0)
        return nil;     //we don't support any channel-binding for this TLS connection
    for(NSString* type in typesList)
        if(_supportedChannelBindings != nil && [_supportedChannelBindings containsObject:type])
            return type;
    
    //if our scram handshake is not finished yet and no mutually supported channel-binding can be found --> ignore that for now (see below)
    //if our scram handshake finished without negotiating a mutually supported channel-binding and this was not backed by SSDP --> report error
    if(self->_scramHandler.serverFirstMessageParsed && !self->_scramHandler.ssdpSupported)
    {
        DDLogWarn(@"Could not find any supported channel-binding type, this MUST be a mitm attack, because tls-server-end-point is mandatory via XEP-0440!");
        return kServerDoesNotFollowXep0440Error;     //this will trigger a disconnect
    }
    if(!self->_scramHandler.serverFirstMessageParsed)
        DDLogWarn(@"Could not find any supported channel-binding type, this COULD be a mitm attack (check via XEP-0474 pending)!");
    return nil;
}

#pragma mark stanza handling

// -(AnyPromise*) sendIq:(XMPPIQ*) iq
// {
//     return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
//         [self sendIq:iq withResponseHandler:^(XMPPIQ* response) {
//             resolve(response);
//         } andErrorHandler:^(XMPPIQ* error) {
//             resolve(error);
//         }];
//     }];
// }

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
    //serialize this state update with other receive queue updates
    //not doing this will make it race with a readState call in the receive queue before the write of this update can happen,
    //which will remove this entry from state and the iq answer received later on be discarded
    [self dispatchAsyncOnReceiveQueue:^{
        if(handler)
        {
            DDLogVerbose(@"Adding %@ to iqHandlers...", handler);
            @synchronized(self->_iqHandlers) {
                self->_iqHandlers[iq.id] = [@{@"iq":iq, @"timeout":@(IQ_TIMEOUT), @"handler":handler} mutableCopy];
            }
        }
        [self send:iq];     //this will also call persistState --> we don't need to do this here explicitly (to make sure our iq delegate is stored to db)
    }];
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
                [self logStanza:queued_stanza withPrefix:[NSString stringWithFormat:@"ADD UNACKED STANZA: %@", self.lastOutboundStanza]];
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
        BOOL isPreauthRegisterRequest = [stanza isKindOfClass:[XMPPIQ class]] && [stanza check:@"/<type=set>/{urn:xmpp:pars:0}preauth"];
        if(
            self.accountState>=kStateBound ||
            (self.accountState>kStateDisconnected && (![stanza isKindOfClass:[XMPPStanza class]] || isBindRequest || isRegisterRequest || isPreauthRegisterRequest))
        )
        {
            [self->_sendQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
                [self logStanza:stanza withPrefix:@"SEND"];
                [self->_outputQueue addObject:stanza];
                [self writeFromQueue];      // try to send if there is space
            }]];
        }
        else
            [self logStanza:stanza withPrefix:@"NOT ADDING STANZA TO SEND QUEUE"];
    }];
}

-(void) logStanza:(MLXMLNode*) stanza withPrefix:(NSString*) prefix
{
#if !TARGET_OS_SIMULATOR
    if([stanza check:@"/{urn:ietf:params:xml:ns:xmpp-sasl}*"])
        DDLogDebug(@"%@: redacted sasl element: %@", prefix, [stanza findFirst:@"/{urn:ietf:params:xml:ns:xmpp-sasl}*$"]);
    else if([stanza check:@"/{jabber:client}iq<type=set>/{jabber:iq:register}query"])
        DDLogDebug(@"%@: redacted register/change password iq", prefix);
    else
        DDLogDebug(@"%@: %@", prefix, stanza);
#else
    DDLogDebug(@"%@: %@", prefix, stanza);
#endif
}


#pragma mark messaging

-(void) retractMessage:(MLMessage*) msg
{
    MLAssert([msg.accountID isEqual:self.accountID], @"Can not retract message from one account on another account!", (@{@"self.accountID": self.accountID, @"msg": msg}));
    XMPPMessage* messageNode = [[XMPPMessage alloc] initWithType:msg.isMuc ? kMessageGroupChatType : kMessageChatType to:msg.buddyName];
    
    DDLogVerbose(@"Retracting message: %@", msg);
    //retraction
    [messageNode addChildNode:[[MLXMLNode alloc] initWithElement:@"retract" andNamespace:@"urn:xmpp:message-retract:1" withAttributes:@{
        @"id": msg.isMuc ? msg.stanzaId : msg.messageId,
    } andChildren:@[] andData:nil]];
    
    //add fallback indication and fallback body
    [messageNode addChildNode:[[MLXMLNode alloc] initWithElement:@"fallback" andNamespace:@"urn:xmpp:fallback:0" withAttributes:@{
        @"for": @"urn:xmpp:message-retract:1",
    } andChildren:@[] andData:nil]];
    [messageNode setBody:@"This person attempted to retract a previous message, but it's unsupported by your client."];
    
    //for MAM
    [messageNode setStoreHint];
    
    [self send:messageNode];
}

-(void) moderateMessage:(MLMessage*) msg withReason:(NSString*) reason
{
    MLAssert(msg.isMuc, @"Moderated message must be in a muc!");
    
    XMPPIQ* iqNode = [[XMPPIQ alloc] initWithType:kiqSetType to:msg.buddyName];
    [iqNode addChildNode:[[MLXMLNode alloc] initWithElement:@"moderate" andNamespace:@"urn:xmpp:message-moderate:1" withAttributes:@{
        @"id": msg.stanzaId,
    } andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"retract" andNamespace:@"urn:xmpp:message-retract:1"],
        [[MLXMLNode alloc] initWithElement:@"reason" andData:reason],
    ] andData:nil]];
    [self sendIq:iqNode withHandler:$newHandler(MLIQProcessor, handleModerationResponse, $ID(msg))];
}

-(void) addEME:(NSString*) encryptionNamesapce withName:(NSString* _Nullable) name toMessageNode:(XMPPMessage*) messageNode
{
    if(name)
        [messageNode addChildNode:[[MLXMLNode alloc] initWithElement:@"encryption" andNamespace:@"urn:xmpp:eme:0" withAttributes:@{
            @"namespace": encryptionNamesapce,
            @"name": name
        } andChildren:@[] andData:nil]];
    else
        [messageNode addChildNode:[[MLXMLNode alloc] initWithElement:@"encryption" andNamespace:@"urn:xmpp:eme:0" withAttributes:@{
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
    
    XMPPMessage* messageNode = [[XMPPMessage alloc] initToContact:contact];
    if(messageId)       //use the uuid autogenerated when our message node was created above if no id was supplied
        messageNode.id = messageId;

#ifdef IS_ALPHA
    // WARNING NOT FOR PRODUCTION
    // encrypt messages that should not be encrypted (but still use plaintext body for devices not speaking omemo)
    if(!encrypt && !isUpload && (!contact.isMuc || (contact.isMuc && [contact.mucType isEqualToString:kMucTypeGroup])))
    {
        [self.omemo encryptMessage:messageNode withMessage:message toContact:contact.contactJid];
        //[self addEME:@"eu.siacs.conversations.axolotl" withName:@"OMEMO" toMessageNode:messageNode];
    }
    // WARNING NOT FOR PRODUCTION END
#endif

#ifndef DISABLE_OMEMO
    if(encrypt && (!contact.isMuc || (contact.isMuc && [contact.mucType isEqualToString:kMucTypeGroup])))
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
    if(contact.isMuc)
        [messageNode.attributes setObject:kMessageGroupChatType forKey:@"type"];
    else
        [messageNode.attributes setObject:kMessageChatType forKey:@"type"];
    
    //request receipts and chat-markers in 1:1 or groups (no channels!)
    if(!contact.isMuc || [kMucTypeGroup isEqualToString:contact.mucType])
    {
        [messageNode addChildNode:[[MLXMLNode alloc] initWithElement:@"request" andNamespace:@"urn:xmpp:receipts"]];
        [messageNode addChildNode:[[MLXMLNode alloc] initWithElement:@"markable" andNamespace:@"urn:xmpp:chat-markers:0"]];
    }

    //for MAM
    [messageNode setStoreHint];
    
    //handle LMC
    if(LMCId)
        [messageNode setLMCFor:LMCId];

    [self send:messageNode];
}

-(void) sendChatState:(BOOL) isTyping toContact:(nonnull MLContact*) contact
{
    if(self.accountState < kStateBound)
        return;

    XMPPMessage* messageNode = [[XMPPMessage alloc] initToContact:contact];
    [messageNode setNoStoreHint];
    if(isTyping)
        [messageNode addChildNode:[[MLXMLNode alloc] initWithElement:@"composing" andNamespace:@"http://jabber.org/protocol/chatstates"]];
    else
        [messageNode addChildNode:[[MLXMLNode alloc] initWithElement:@"active" andNamespace:@"http://jabber.org/protocol/chatstates"]];
    [self send:messageNode];
}

#pragma mark set connection attributes

-(void) persistState
{
    DDLogVerbose(@"%@ --> persistState before: used/available memory: %.3fMiB / %.3fMiB)...", self.accountID, [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
    [self realPersistState];
    DDLogVerbose(@"%@ --> persistState after: used/available memory: %.3fMiB / %.3fMiB)...", self.accountID, [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
}

-(void) realPersistState
{
    //make sure to create a transaction before locking the state object to prevent the following deadlock:
    //thread 1 (for example: receiveQueue): holding write transaction and waiting for state lock object
    //thread 2 (for example: urllib session): holding state lock object and waiting for write transaction
    [[DataLayer sharedInstance] createTransaction:^{
        @synchronized(self->_stateLockObject) {
            DDLogVerbose(@"%@ --> realPersistState before: used/available memory: %.3fMiB / %.3fMiB)...", self.accountID, [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
            //state dictionary
            NSMutableDictionary* values = [NSMutableDictionary new];

            //collect smacks state
            [values setValue:self.lastHandledInboundStanza forKey:@"lastHandledInboundStanza"];
            [values setValue:self.lastHandledOutboundStanza forKey:@"lastHandledOutboundStanza"];
            [values setValue:self.lastOutboundStanza forKey:@"lastOutboundStanza"];
            [values setValue:[self.unAckedStanzas copy] forKey:@"unAckedStanzas"];
            [values setValue:self.streamID forKey:@"streamID"];
            [values setObject:[NSNumber numberWithBool:self.isDoingFullReconnect] forKey:@"isDoingFullReconnect"];

            NSMutableDictionary* persistentIqHandlers = [NSMutableDictionary new];
            NSMutableDictionary* persistentIqHandlerDescriptions = [NSMutableDictionary new];
            @synchronized(self->_iqHandlers) {
                for(NSString* iqid in self->_iqHandlers)
                    if(self->_iqHandlers[iqid][@"handler"] != nil)
                    {
                        persistentIqHandlers[iqid] = self->_iqHandlers[iqid];
                        persistentIqHandlerDescriptions[iqid] = [NSString stringWithFormat:@"%@: %@", self->_iqHandlers[iqid][@"timeout"], self->_iqHandlers[iqid][@"handler"]];
                    }
            }
            [values setObject:persistentIqHandlers forKey:@"iqHandlers"];
            
            @synchronized(self->_reconnectionHandlers) {
                [values setObject:[self->_reconnectionHandlers copy] forKey:@"reconnectionHandlers"];
            }

            [values setValue:[self.connectionProperties.serverFeatures copy] forKey:@"serverFeatures"];
            [values setValue:[self.connectionProperties.serverDiscoFeatures copy] forKey:@"serverDiscoFeatures"];
            [values setValue:[self.connectionProperties.accountDiscoFeatures copy] forKey:@"accountDiscoFeatures"];
            
            if(self.connectionProperties.uploadServer)
                [values setObject:self.connectionProperties.uploadServer forKey:@"uploadServer"];
            
            if(self.connectionProperties.conferenceServers)
                [values setObject:self.connectionProperties.conferenceServers forKey:@"conferenceServers"];
            
            [values setObject:[self.pubsub getInternalData] forKey:@"pubsubData"];
            [values setObject:[self.mucProcessor getInternalState] forKey:@"mucState"];
            [values setObject:[self->_runningCapsQueries copy] forKey:@"runningCapsQueries"];
            [values setObject:[self->_runningMamQueries copy] forKey:@"runningMamQueries"];
            [values setObject:[NSNumber numberWithBool:self->_loggedInOnce] forKey:@"loggedInOnce"];
            [values setObject:[NSNumber numberWithBool:self.connectionProperties.usingCarbons2] forKey:@"usingCarbons2"];
            [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsBookmarksCompat] forKey:@"supportsBookmarksCompat"];
            [values setObject:[NSNumber numberWithBool:self.connectionProperties.pushEnabled] forKey:@"pushEnabled"];
            [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPubSub] forKey:@"supportsPubSub"];
            [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPubSubMax] forKey:@"supportsPubSubMax"];
            [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsModernPubSub] forKey:@"supportsModernPubSub"];
            [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsHTTPUpload] forKey:@"supportsHTTPUpload"];
            [values setObject:[NSNumber numberWithBool:self.connectionProperties.accountDiscoDone] forKey:@"accountDiscoDone"];
            [values setObject:[self->_inCatchup copy] forKey:@"inCatchup"];
            [values setObject:[self->_mdsData copy] forKey:@"mdsData"];
            
            if(self->_cachedStreamFeaturesBeforeAuth != nil)
                [values setObject:self->_cachedStreamFeaturesBeforeAuth forKey:@"cachedStreamFeaturesBeforeAuth"];
            if(self->_cachedStreamFeaturesAfterAuth != nil)
                [values setObject:self->_cachedStreamFeaturesAfterAuth forKey:@"cachedStreamFeaturesAfterAuth"];
            
            if(self.connectionProperties.discoveredServices)
                [values setObject:[self.connectionProperties.discoveredServices copy] forKey:@"discoveredServices"];
            
            if(self.connectionProperties.discoveredStunTurnServers)
                [values setObject:[self.connectionProperties.discoveredStunTurnServers copy] forKey:@"discoveredStunTurnServers"];
            
            if(self.connectionProperties.discoveredAdhocCommands)
                [values setObject:[self.connectionProperties.discoveredAdhocCommands copy] forKey:@"discoveredAdhocCommands"];
            
            if(self.connectionProperties.serverVersion)
                [values setObject:self.connectionProperties.serverVersion forKey:@"serverVersion"];

            [values setObject:self->_lastInteractionDate forKey:@"lastInteractionDate"];
            [values setValue:[NSDate date] forKey:@"stateSavedAt"];
            [values setValue:@(STATE_VERSION) forKey:@"VERSION"];

            if(self.omemo != nil && self.omemo.state != nil)
                [values setObject:self.omemo.state forKey:@"omemoState"];
            
            [values setObject:[NSNumber numberWithBool:self.hasSeenOmemoDeviceListAfterOwnDeviceid] forKey:@"hasSeenOmemoDeviceListAfterOwnDeviceid"];
            
            //save state dictionary
            [[DataLayer sharedInstance] persistState:values forAccount:self.accountID];

            //debug output
            DDLogVerbose(@"%@ --> persistState(saved at %@):\n\tisDoingFullReconnect=%@,\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@\n\tlastInteractionDate=%@\n\tpersistentIqHandlers=%@\n\tsupportsHttpUpload=%d\n\tpushEnabled=%d\n\tsupportsPubSub=%d\n\tsupportsModernPubSub=%d\n\tsupportsPubSubMax=%d\n\tsupportsBookmarksCompat=%d\n\taccountDiscoDone=%d\n\t_inCatchup=%@\n\tomemo.state=%@\n\thasSeenOmemoDeviceListAfterOwnDeviceid=%@\n",
                self.accountID,
                values[@"stateSavedAt"],
                bool2str(self.isDoingFullReconnect),
                self.lastHandledInboundStanza,
                self.lastHandledOutboundStanza,
                self.lastOutboundStanza,
                self.unAckedStanzas ? [self.unAckedStanzas count] : 0, self.unAckedStanzas ? "" : " (NIL)",
                self.streamID,
                self->_lastInteractionDate,
                persistentIqHandlerDescriptions,
                self.connectionProperties.supportsHTTPUpload,
                self.connectionProperties.pushEnabled,
                self.connectionProperties.supportsPubSub,
                self.connectionProperties.supportsModernPubSub,
                self.connectionProperties.supportsPubSubMax,
                self.connectionProperties.supportsBookmarksCompat,
                self.connectionProperties.accountDiscoDone,
                self->_inCatchup,
                self.omemo.state,
                bool2str(self.hasSeenOmemoDeviceListAfterOwnDeviceid)
            );
            DDLogVerbose(@"%@ --> realPersistState after: used/available memory: %.3fMiB / %.3fMiB)...", self.accountID, [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
        }
    }];
}

-(void) readState
{
    DDLogVerbose(@"%@ --> readState before: used/available memory: %.3fMiB / %.3fMiB)...", self.accountID, [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
    [self realReadState];
    DDLogVerbose(@"%@ --> readState after: used/available memory: %.3fMiB / %.3fMiB)...", self.accountID, [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
}

-(void) realReadState
{
    @synchronized(_stateLockObject) {
        DDLogVerbose(@"%@ --> realReadState before: used/available memory: %.3fMiB / %.3fMiB)...", self.accountID, [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
        NSMutableDictionary* dic = [[DataLayer sharedInstance] readStateForAccount:self.accountID];
        if(dic)
        {
            //check state version
            int oldVersion = [dic[@"VERSION"] intValue];
            if(oldVersion != STATE_VERSION)
            {
                DDLogWarn(@"Account state upgraded from %@ to %d, invalidating state...", dic[@"VERSION"], STATE_VERSION);
                dic = [[self class] invalidateState:dic];
                
                //don't show deviceid alerts on state update (if we need to regenerate our own deviceid, MLOMEMO will reset this to NO anyways)
                if(oldVersion <= 16)
                    self.hasSeenOmemoDeviceListAfterOwnDeviceid = YES;
            }
            
            //collect smacks state
            self.lastHandledInboundStanza = [dic objectForKey:@"lastHandledInboundStanza"];
            self.lastHandledOutboundStanza = [dic objectForKey:@"lastHandledOutboundStanza"];
            self.lastOutboundStanza = [dic objectForKey:@"lastOutboundStanza"];
            NSArray* stanzas = [dic objectForKey:@"unAckedStanzas"];
            self.unAckedStanzas = [stanzas mutableCopy];
            self.streamID = [dic objectForKey:@"streamID"];
            if([dic objectForKey:@"isDoingFullReconnect"])
            {
                NSNumber* isDoingFullReconnect = [dic objectForKey:@"isDoingFullReconnect"];
                self.isDoingFullReconnect = isDoingFullReconnect.boolValue;
            }
            
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
            NSMutableDictionary* persistentIqHandlerDescriptions = [NSMutableDictionary new];
            @synchronized(_iqHandlers) {
                //remove all current persistent handlers...
                NSMutableDictionary* handlersCopy = [_iqHandlers copy];
                for(NSString* iqid in handlersCopy)
                    if(handlersCopy[iqid][@"handler"] != nil)
                        [_iqHandlers removeObjectForKey:iqid];
                //...and replace them with persistent handlers loaded from state
                for(NSString* iqid in persistentIqHandlers)
                {
                    _iqHandlers[iqid] = [persistentIqHandlers[iqid] mutableCopy];
                    persistentIqHandlerDescriptions[iqid] = [NSString stringWithFormat:@"%@: %@", persistentIqHandlers[iqid][@"timeout"], persistentIqHandlers[iqid][@"handler"]];
                }
            }
            
            @synchronized(self->_reconnectionHandlers) {
                [_reconnectionHandlers removeAllObjects];
                [_reconnectionHandlers addObjectsFromArray:[dic objectForKey:@"reconnectionHandlers"]];
            }
            
            self.connectionProperties.serverFeatures = [dic objectForKey:@"serverFeatures"];
            self.connectionProperties.serverDiscoFeatures = [dic objectForKey:@"serverDiscoFeatures"];
            self.connectionProperties.accountDiscoFeatures = [dic objectForKey:@"accountDiscoFeatures"];
            
            self.connectionProperties.discoveredServices = [[dic objectForKey:@"discoveredServices"] mutableCopy];
            self.connectionProperties.discoveredStunTurnServers = [[dic objectForKey:@"discoveredStunTurnServers"] mutableCopy];
            self.connectionProperties.discoveredAdhocCommands = [[dic objectForKey:@"discoveredAdhocCommands"] mutableCopy];
            self.connectionProperties.serverVersion = [dic objectForKey:@"serverVersion"];
            
            self.connectionProperties.uploadServer = [dic objectForKey:@"uploadServer"];
            self.connectionProperties.conferenceServers = [[dic objectForKey:@"conferenceServers"] mutableCopy];
            
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
            
            if([dic objectForKey:@"supportsBookmarksCompat"])
            {
                NSNumber* compatNumber = [dic objectForKey:@"supportsBookmarksCompat"];
                self.connectionProperties.supportsBookmarksCompat = compatNumber.boolValue;
            }
            
            if([dic objectForKey:@"pushEnabled"])
            {
                NSNumber* pushEnabled = [dic objectForKey:@"pushEnabled"];
                self.connectionProperties.pushEnabled = pushEnabled.boolValue;
            }
            
            if([dic objectForKey:@"supportsPubSub"])
            {
                NSNumber* supportsPubSub = [dic objectForKey:@"supportsPubSub"];
                self.connectionProperties.supportsPubSub = supportsPubSub.boolValue;
            }
            
            if([dic objectForKey:@"supportsPubSubMax"])
            {
                NSNumber* supportsPubSubMax = [dic objectForKey:@"supportsPubSubMax"];
                self.connectionProperties.supportsPubSubMax = supportsPubSubMax.boolValue;
            }
            
            if([dic objectForKey:@"supportsModernPubSub"])
            {
                NSNumber* supportsModernPubSub = [dic objectForKey:@"supportsModernPubSub"];
                self.connectionProperties.supportsModernPubSub = supportsModernPubSub.boolValue;
            }
            
            if([dic objectForKey:@"supportsHTTPUpload"])
            {
                NSNumber* supportsHTTPUpload = [dic objectForKey:@"supportsHTTPUpload"];
                self.connectionProperties.supportsHTTPUpload = supportsHTTPUpload.boolValue;
            }
            
            if([dic objectForKey:@"lastInteractionDate"])
                _lastInteractionDate = [dic objectForKey:@"lastInteractionDate"];
            
            if([dic objectForKey:@"accountDiscoDone"])
            {
                NSNumber* accountDiscoDone = [dic objectForKey:@"accountDiscoDone"];
                self.connectionProperties.accountDiscoDone = accountDiscoDone.boolValue;
            }
            
            if([dic objectForKey:@"pubsubData"])
                [self.pubsub setInternalData:[dic objectForKey:@"pubsubData"]];
            
            if([dic objectForKey:@"mucState"])
                [self.mucProcessor setInternalState:[dic objectForKey:@"mucState"]];
            
            if([dic objectForKey:@"runningCapsQueries"])
                _runningCapsQueries = [[dic objectForKey:@"runningCapsQueries"] mutableCopy];
            
            if([dic objectForKey:@"runningMamQueries"])
                _runningMamQueries = [[dic objectForKey:@"runningMamQueries"] mutableCopy];
            
            if([dic objectForKey:@"inCatchup"])
                _inCatchup = [[dic objectForKey:@"inCatchup"] mutableCopy];
            
            if([dic objectForKey:@"mdsData"])
                _mdsData = [[dic objectForKey:@"mdsData"] mutableCopy];
            
            if([dic objectForKey:@"cachedStreamFeaturesBeforeAuth"])
                _cachedStreamFeaturesBeforeAuth = [dic objectForKey:@"cachedStreamFeaturesBeforeAuth"];
            if([dic objectForKey:@"cachedStreamFeaturesAfterAuth"])
                _cachedStreamFeaturesAfterAuth = [dic objectForKey:@"cachedStreamFeaturesAfterAuth"];
            
            if([dic objectForKey:@"omemoState"] && self.omemo)
                self.omemo.state = [dic objectForKey:@"omemoState"];
            
            if([dic objectForKey:@"hasSeenOmemoDeviceListAfterOwnDeviceid"])
            {
                NSNumber* hasSeenOmemoDeviceListAfterOwnDeviceid = [dic objectForKey:@"hasSeenOmemoDeviceListAfterOwnDeviceid"];
                self.hasSeenOmemoDeviceListAfterOwnDeviceid = hasSeenOmemoDeviceListAfterOwnDeviceid.boolValue;
            }
            
            //debug output
            DDLogVerbose(@"%@ --> readState(saved at %@):\n\tisDoingFullReconnect=%@,\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@,\n\tlastInteractionDate=%@\n\tpersistentIqHandlers=%@\n\tsupportsHttpUpload=%d\n\tpushEnabled=%d\n\tsupportsPubSub=%d\n\tsupportsModernPubSub=%d\n\tsupportsPubSubMax=%d\n\tsupportsBookmarksCompat=%d\n\taccountDiscoDone=%d\n\t_inCatchup=%@\n\tomemo.state=%@\n\thasSeenOmemoDeviceListAfterOwnDeviceid=%@\n",
                self.accountID,
                dic[@"stateSavedAt"],
                bool2str(self.isDoingFullReconnect),
                self.lastHandledInboundStanza,
                self.lastHandledOutboundStanza,
                self.lastOutboundStanza,
                self.unAckedStanzas ? [self.unAckedStanzas count] : 0, self.unAckedStanzas ? "" : " (NIL)",
                self.streamID,
                self->_lastInteractionDate,
                persistentIqHandlerDescriptions,
                self.connectionProperties.supportsHTTPUpload,
                self.connectionProperties.pushEnabled,
                self.connectionProperties.supportsPubSub,
                self.connectionProperties.supportsModernPubSub,
                self.connectionProperties.supportsPubSubMax,
                self.connectionProperties.supportsBookmarksCompat,
                self.connectionProperties.accountDiscoDone,
                self->_inCatchup,
                self.omemo.state,
                bool2str(self.hasSeenOmemoDeviceListAfterOwnDeviceid)
            );
            if(self.unAckedStanzas)
                for(NSDictionary* dic in self.unAckedStanzas)
                    DDLogDebug(@"readState unAckedStanza %@: %@", [dic objectForKey:kQueueID], [dic objectForKey:kStanza]);
        }
        
        //always reset handler and smacksRequestInFlight when loading smacks state
        _smacksAckHandler = [NSMutableArray new];
        self.smacksRequestInFlight = NO;
        
        DDLogVerbose(@"%@ --> realReadState after: used/available memory: %.3fMiB / %.3fMiB)...", self.accountID, [HelperTools report_memory], (CGFloat)os_proc_available_memory() / 1048576);
    }
}

+(NSMutableDictionary*) invalidateState:(NSDictionary*) dic
{
    NSArray* toKeep = @[@"lastHandledInboundStanza", @"lastHandledOutboundStanza", @"lastOutboundStanza", @"unAckedStanzas", @"loggedInOnce", @"lastInteractionDate", @"inCatchup", @"hasSeenOmemoDeviceListAfterOwnDeviceid"];
    
    NSMutableDictionary* newState = [NSMutableDictionary new];
    if(dic)
    {
        for(NSString* entry in toKeep)
            if(dic[entry] != nil)
                newState[entry] = dic[entry];
    }
    
    //set smacks state to sane defaults if not present in our old state at all (this are the values used by initSM3, too)
    if(newState[@"lastHandledInboundStanza"] == nil)
        newState[@"lastHandledInboundStanza"] = [NSNumber numberWithInteger:0];
    if(newState[@"lastHandledOutboundStanza"] == nil)
        newState[@"lastHandledOutboundStanza"] = [NSNumber numberWithInteger:0];
    if(newState[@"lastOutboundStanza"] == nil)
        newState[@"lastOutboundStanza"] = [NSNumber numberWithInteger:0];
    if(newState[@"unAckedStanzas"] == nil)
        newState[@"unAckedStanzas"] = [NSMutableArray new];
    
    newState[@"stateSavedAt"] = [NSDate date];
    newState[@"VERSION"] = @(STATE_VERSION);
    
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
        self.unAckedStanzas = [NSMutableArray new];
        self.streamID = nil;
        _smacksAckHandler = [NSMutableArray new];
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
    
    self.isDoingFullReconnect = YES;
    _accountState = kStateBinding;
    
    //delete old resources because we get new presences once we're done initializing the session
    [[DataLayer sharedInstance] resetContactsForAccount:self.accountID];
    
    //inform all old iq handlers of invalidation and clear _iqHandlers dictionary afterwards
    @synchronized(_iqHandlers) {
        //make sure this works even if the invalidation handlers add a new iq to the list
        NSMutableDictionary* handlersCopy = [_iqHandlers mutableCopy];
        [_iqHandlers removeAllObjects];
        
        for(NSString* iqid in handlersCopy)
        {
            DDLogWarn(@"Invalidating iq handler for iq id '%@'", iqid);
            if(handlersCopy[iqid][@"handler"] != nil)
                $invalidate(handlersCopy[iqid][@"handler"], $ID(account, self), $ID(reason, @"bind"));
            else if(handlersCopy[iqid][@"errorHandler"])
                ((monal_iq_handler_t)handlersCopy[iqid][@"errorHandler"])(nil);
        }
        
    }
    
    //invalidate pubsub queue (a pubsub operation will be either invalidated by an iq handler above OR by the invalidation here, but never twice!)
    [self.pubsub invalidateQueue];
    
    //clean up all idle timers
    [[DataLayer sharedInstance] cleanupIdleTimerOnAccountID:self.accountID];
    
    //force new disco queries because we landed here because of a failed smacks resume
    //(or the account got forcibly disconnected/reconnected or this is the very first login of this account)
    //--> all of this reasons imply that we had to start a new xmpp stream and our old cached disco data
    //    and other state values are stale now
    //(smacks state will be reset/cleared later on if appropriate, no need to handle smacks here)
    self.connectionProperties.serverDiscoFeatures = [NSSet new];
    self.connectionProperties.accountDiscoFeatures = [NSSet new];
    self.connectionProperties.discoveredServices = [NSMutableArray new];
    self.connectionProperties.discoveredStunTurnServers = [NSMutableArray new];
    self.connectionProperties.discoveredAdhocCommands = [NSMutableDictionary new];
    self.connectionProperties.serverVersion = nil;
    self.connectionProperties.conferenceServers = [NSMutableDictionary new];
    self.connectionProperties.supportsHTTPUpload = NO;
    self.connectionProperties.uploadServer = nil;
    //self.connectionProperties.supportsSM3 = NO;                   //already set by stream feature parsing
    self.connectionProperties.pushEnabled = NO;
    self.connectionProperties.supportsBookmarksCompat = NO;
    self.connectionProperties.usingCarbons2 = NO;
    //self.connectionProperties.serverIdentity = @"";               //already set by stream feature parsing
    self.connectionProperties.supportsPubSub = NO;
    self.connectionProperties.supportsPubSubMax = NO;
    self.connectionProperties.supportsModernPubSub = NO;
    self.connectionProperties.accountDiscoDone = NO;
    
    //clear list of running mam queries
    _runningMamQueries = [NSMutableDictionary new];
    
    //clear list of running caps queries
    _runningCapsQueries = [NSMutableSet new];
    
    //clear old catchup state (technically all stanzas still in delayedMessageStanzas could have also been
    //in the parseQueue in the last run and deleted there)
    //--> no harm in deleting them when starting a new session (but DON'T DELETE them when resuming the old smacks session)
    _inCatchup = [NSMutableDictionary new];
    [[DataLayer sharedInstance] deleteDelayedMessageStanzasForAccount:self.accountID];
    
    //send bind iq
    XMPPIQ* iqNode = [[XMPPIQ alloc] initWithType:kiqSetType];
    [iqNode setBindWithResource:resource];
    [self sendIq:iqNode withHandler:$newHandler(MLIQProcessor, handleBind)];
}

-(void) queryDisco
{
    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType to:self.connectionProperties.identity.domain];
    [discoInfo setDiscoInfoNode];
    [self sendIq:discoInfo withHandler:$newHandler(MLIQProcessor, handleServerDiscoInfo)];
    
    XMPPIQ* discoItems = [[XMPPIQ alloc] initWithType:kiqGetType to:self.connectionProperties.identity.domain];
    [discoItems setDiscoItemNode];
    [self sendIq:discoItems withHandler:$newHandler(MLIQProcessor, handleServerDiscoItems)];
    
    XMPPIQ* accountInfo = [[XMPPIQ alloc] initWithType:kiqGetType to:self.connectionProperties.identity.jid];
    [accountInfo setDiscoInfoNode];
    [self sendIq:accountInfo withHandler:$newHandler(MLIQProcessor, handleAccountDiscoInfo)];
    
    XMPPIQ* adhocCommands = [[XMPPIQ alloc] initWithType:kiqGetType to:self.connectionProperties.identity.domain];
    [adhocCommands setAdhocDiscoNode];
    [self sendIq:adhocCommands withHandler:$newHandler(MLIQProcessor, handleAdhocDisco)];
}

-(void) queryServerVersion
{
    XMPPIQ* serverVersion = [[XMPPIQ alloc] initWithType:kiqGetType to:self.connectionProperties.identity.domain];
    [serverVersion getEntitySoftwareVersionInfo];
    [self sendIq:serverVersion withHandler:$newHandler(MLIQProcessor, handleVersionResponse)];
}

-(void) queryExternalServicesOn:(NSString*) jid
{
    XMPPIQ* externalDisco = [[XMPPIQ alloc] initWithType:kiqGetType];
    [externalDisco setiqTo:jid];
    [externalDisco addChildNode:[[MLXMLNode alloc] initWithElement:@"services" andNamespace:@"urn:xmpp:extdisco:2"]];
    [self sendIq:externalDisco withHandler:$newHandler(MLIQProcessor, handleExternalDisco)];
}

-(void) queryExternalServiceCredentialsFor:(NSDictionary*) service completion:(monal_id_block_t) completion
{
    XMPPIQ* credentialsQuery = [[XMPPIQ alloc] initWithType:kiqGetType];
    [credentialsQuery setiqTo:service[@"directoryJid"]];
    [credentialsQuery addChildNode:[[MLXMLNode alloc] initWithElement:@"credentials" andNamespace:@"urn:xmpp:extdisco:2" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"service"  withAttributes:@{
            @"type": service[@"type"],
            @"host": service[@"host"],
            @"port": service[@"port"],
        } andChildren:@[] andData:nil]
    ] andData:nil]];
    [self sendIq:credentialsQuery withResponseHandler:^(XMPPIQ* response) {
        completion([response findFirst:@"{urn:xmpp:extdisco:2}credentials/service@@"]);
    } andErrorHandler:^(XMPPIQ* error) {
        DDLogWarn(@"Got error while quering for credentials of external service %@: %@", service, error);
        completion(@{});
    }];
}

-(void) purgeOfflineStorage
{
    XMPPIQ* purgeIq = [[XMPPIQ alloc] initWithType:kiqSetType];
    [purgeIq setPurgeOfflineStorage];
    [self sendIq:purgeIq withResponseHandler:^(XMPPIQ* response __unused) {
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
    if(!_isCSIActive && [[HelperTools defaultsDB] boolForKey:@"SendLastUserInteraction"])
        [presence setLastInteraction:_lastInteractionDate];
    
    [self send:presence];
}

-(void) fetchRoster
{
    XMPPIQ* roster = [[XMPPIQ alloc] initWithType:kiqGetType];
    NSString* rosterVer;
    if([self.connectionProperties.serverFeatures check:@"{urn:xmpp:features:rosterver}ver"])
        rosterVer = [[DataLayer sharedInstance] getRosterVersionForAccount:self.accountID];
    [roster setRosterRequest:rosterVer];
    [self sendIq:roster withHandler:$newHandler(MLIQProcessor, handleRoster)];
}

-(void) initSession
{
    DDLogInfo(@"Now bound, initializing new xmpp session");
    self.isDoingFullReconnect = YES;
    
    //we are now bound
    _connectedTime = [NSDate date];
    _reconnectBackoffTime = 0;
    
    //indicate we are bound now, *after* initializing/resetting all the other data structures to avoid race conditions
    _accountState = kStateBound;
    
    //inform other parts of monal about our new state
    [[MLNotificationQueue currentQueue] postNotificationName:kMLResourceBoundNotice object:self];
    [self accountStatusChanged];
    
    //now fetch roster, request disco and send initial presence
    [self fetchRoster];
    
    //query disco *before* sending out our first presence because this presence will trigger pubsub "headline" updates and we want to know
    //if and what pubsub/pep features the server supports, before handling that
    //we can pipeline the disco requests and outgoing presence broadcast, though
    [self queryDisco];
    [self queryServerVersion];
    [self purgeOfflineStorage];
    [self setMAMPrefs:@"always"];   //make sure we are able to do proper catchups
    [self sendPresence];            //this will trigger a replay of offline stanzas on prosody (no XEP-0013 support anymore 😡)
    //the offline messages will come in *after* we initialized the mam query, because the disco result comes in first
    //(and this is what triggers mam catchup)
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
    
    //fetch current mds state
    [self.pubsub fetchNode:@"urn:xmpp:mds:displayed:0" from:self.connectionProperties.identity.jid withItemsList:nil andHandler:$newHandler(MLPubSubProcessor, handleMdsFetchResult)];
    
    //NOTE: mam query will be done in MLIQProcessor once the disco result for our own jid/account returns
    
    //initialize stanza counter for statistics
    [self initCatchupStats];
}

-(void) addReconnectionHandler:(MLHandler*) handler
{
    //don't check if we are bound and execute the handler directly if so
    //--> reconnect handlers are frequently used while being bound to schedule a task on *next* (re)connect
    //--> in cases where the reconnect handler is only needed if we are not bound, the caller can do this check itself
    //    (this might introduce small race conditions, though, but these should be negligible in most cases)
    @synchronized(_reconnectionHandlers) {
        [_reconnectionHandlers addObject:handler];
    }
    [self persistState];
}

-(void) setBlocked:(BOOL) blocked forJid:(NSString* _Nonnull) blockedJid
{
    if(![self.connectionProperties.serverDiscoFeatures containsObject:@"urn:xmpp:blocking"])
    {
        DDLogWarn(@"Server does not support blocking...");
        return;
    }
    
    XMPPIQ* iqBlocked = [[XMPPIQ alloc] initWithType:kiqSetType];
    
    [iqBlocked setBlocked:blocked forJid:blockedJid];
    [self sendIq:iqBlocked withHandler:$newHandler(MLIQProcessor, handleBlocked, $ID(blockedJid))];
}

-(void) fetchBlocklist
{
    if(![self.connectionProperties.serverDiscoFeatures containsObject:@"urn:xmpp:blocking"])
    {
        DDLogWarn(@"Server does not support blocking...");
        return;
    }
    
    XMPPIQ* iqBlockList = [[XMPPIQ alloc] initWithType:kiqGetType];
    
    [iqBlockList requestBlockList];
    [self sendIq:iqBlockList withHandler:$newHandler(MLIQProcessor, handleBlocklist)];;
}

-(void) updateLocalBlocklistCache:(NSSet<NSString*>*) blockedJids
{
    [[DataLayer sharedInstance] updateLocalBlocklistCache:blockedJids forAccountID:self.accountID];
}

#pragma mark vcard

-(void) getEntitySoftWareVersion:(NSString*) jid
{
    NSDictionary* split = [HelperTools splitJid:jid];
    MLAssert(split[@"resource"] != nil, @"getEntitySoftWareVersion needs a full jid!");
    if([[DataLayer sharedInstance] checkCap:@"jabber:iq:version" forUser:split[@"user"] andResource:split[@"resource"] onAccountID:self.accountID])
    {
        XMPPIQ* iqEntitySoftWareVersion = [[XMPPIQ alloc] initWithType:kiqGetType to:jid];
        [iqEntitySoftWareVersion getEntitySoftwareVersionInfo];
        [self sendIq:iqEntitySoftWareVersion withHandler:$newHandler(MLIQProcessor, handleVersionResponse)];
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
        NSMutableDictionary* headers = [NSMutableDictionary new];
        headers[@"Content-Type"] = params[@"contentType"];
        for(MLXMLNode* header in [response find:@"{urn:xmpp:http:upload:0}slot/put/header"])
            headers[[header findFirst:@"/@name"]] = [header findFirst:@"/#"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [MLHTTPRequest
                sendWithVerb:kPut path:[response findFirst:@"{urn:xmpp:http:upload:0}slot/put@url"]
                headers:headers
                withArguments:nil
                data:params[@"data"]
                andCompletionHandler:^(NSError* error, id result __unused) {
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
        if([[HelperTools defaultsDB] boolForKey:@"SendLastUserInteraction"])
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
        if([[HelperTools defaultsDB] boolForKey:@"SendLastUserInteraction"])
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
        if(self.accountState<kStateBound || ![self.connectionProperties.serverFeatures check:@"{urn:xmpp:csi:0}csi"])
        {
            DDLogVerbose(@"NOT sending csi state, because we are not bound yet (or csi is not supported)");
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
    if(![self.connectionProperties.accountDiscoFeatures containsObject:@"urn:xmpp:mam:2"])
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
    NSMutableArray* __block pageList = [NSMutableArray new];
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
        
        NSMutableArray* __block historyIdList = [NSMutableArray new];
        NSNumber* __block historyId = [NSNumber numberWithInt:[[[DataLayer sharedInstance] getSmallestHistoryId] intValue] - retrievedBodies];
        
        //ignore all notifications generated while processing the queued stanzas
        [MLNotificationQueue queueNotificationsInBlock:^{
            uint32_t pageNo = 0;
            //iterate through all pages and their messages forward in time (pages have already been sorted forward in time internally)
            DDLogDebug(@"Handling %@ mam pages...", @([pageList count]));
            for(NSArray* page in [[pageList reverseObjectEnumerator] allObjects])
            {
                //process received message stanzas and manipulate the db accordingly
                //if a new message got added to the history db, the message processor will return a MLMessage instance containing the history id of the newly created entry
                DDLogDebug(@"Handling %@ entries in mam page...", @([page count]));
                uint32_t entryNo = 0;
                for(NSDictionary* data in page)
                {
                    //don't write data to our tcp stream while inside this db transaction
                    //(all effects to the outside world should be transactional, too)
                    [self freezeSendQueue];
                    //process all queued mam stanzas in a dedicated db write transaction
                    [[DataLayer sharedInstance] createTransaction:^{
                        DDLogVerbose(@"Handling mam page entry[%u(%@).%u(%@)]): %@", pageNo, @([pageList count]), entryNo, @([page count]), data);
                        MLMessage* msg = [MLMessageProcessor processMessage:data[@"messageNode"] andOuterMessage:data[@"outerMessageNode"] forAccount:self withHistoryId:historyId];
                        DDLogVerbose(@"Got message processor result: %@", msg);
                        //add successfully added messages to our display list
                        //stanzas not transporting a body will be processed, too, but the message processor will return nil for these
                        if(msg != nil)
                        {
                            [historyIdList addObject:msg.messageDBId];      //we only need the history id to fetch a fresh copy later
                            historyId = [NSNumber numberWithInt:[historyId intValue] + 1];      //calculate next history id
                        }
                    }];
                    [self unfreezeSendQueue];      //this will flush all stanzas added inside the db transaction and now waiting in the send queue
                    entryNo++;
                }
                pageNo++;
            }
            
            //throw away all queued notifications before leaving this context
            [(MLNotificationQueue*)[MLNotificationQueue currentQueue] clear];
        } onQueue:@"MLhistoryIgnoreQueue"];
        
        DDLogDebug(@"collected mam:2 before-pages now contain %lu messages in summary not already in history", (unsigned long)[historyIdList count]);
        MLAssert([historyIdList count] <= retrievedBodies, @"did add more messages to historydb table than bodies collected!", (@{
            @"historyIdList": historyIdList,
            @"retrievedBodies": @(retrievedBodies),
        }));
        if([historyIdList count] < retrievedBodies)
            DDLogWarn(@"Got %lu mam history messages already contained in history db, possibly ougoing messages that did not have a stanzaid yet!", (unsigned long)(retrievedBodies - [historyIdList count]));
        //query db (again) for the real MLMessage to account for changes in history table by non-body metadata messages received after the body-message
        completion([[DataLayer sharedInstance] messagesForHistoryIDs:historyIdList], nil);
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
        if(contact.isMuc)
        {
            if(!before)
                before = [[DataLayer sharedInstance] lastStanzaIdForMuc:contact.contactJid andAccount:self.accountID];
            [query setiqTo:contact.contactJid];
            [query setMAMQueryLatestMessagesForJid:nil before:before];
        }
        else
        {
            if(!before)
                before = [[DataLayer sharedInstance] lastStanzaIdForAccount:self.accountID];
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
    [self.mucProcessor leave:room withBookmarksUpdate:YES keepBuddylistEntry:NO];
}

-(AnyPromise*) checkJidType:(NSString*) jid
{
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
        [discoInfo setiqTo:jid];
        [discoInfo setDiscoInfoNode];
        [self sendIq:discoInfo withResponseHandler:^(XMPPIQ* response) {
            NSSet* features = [NSSet setWithArray:[response find:@"{http://jabber.org/protocol/disco#info}query/feature@var"]];
            //check if this is a muc or account
            if([features containsObject:@"http://jabber.org/protocol/muc"])
                return resolve(@"muc");
            else
                return resolve(@"account");
        } andErrorHandler:^(XMPPIQ* error) {
            //this means the jid is an account which can not be queried if not subscribed
            if([error check:@"/<type=error>/error<type=cancel>/{urn:ietf:params:xml:ns:xmpp-stanzas}service-unavailable"])
                return resolve(@"account");
            else if([error check:@"/<type=error>/error<type=auth>/{urn:ietf:params:xml:ns:xmpp-stanzas}subscription-required"])
                return resolve(@"account");
            //any other error probably means the remote server is not reachable or (even more likely) the jid is incorrect
            NSString* errorDescription = [HelperTools extractXMPPError:error withDescription:NSLocalizedString(@"Unexpected error while checking type of jid:", @"")];
            DDLogError(@"checkJidType got an error, informing user: %@", errorDescription);
            resolve([NSError errorWithDomain:@"Monal" code:0 userInfo:@{NSLocalizedDescriptionKey: error == nil ? NSLocalizedString(@"Unexpected error while checking type of jid, please try again", @"") : errorDescription}]);
        }];
    }];
}

#pragma mark- XMPP add and remove contact

-(void) removeFromRoster:(MLContact*) contact
{
    DDLogVerbose(@"Removing jid from roster: %@", contact);
    
    //delete contact request if it exists
    [[DataLayer sharedInstance] deleteContactRequest:contact];
    
    XMPPPresence* presence = [XMPPPresence new];
    [presence unsubscribeContact:contact];
    [self send:presence];
    
    XMPPPresence* presence2 = [XMPPPresence new];
    [presence2 unsubscribedContact:contact];
    [self send:presence2];
    
    XMPPIQ* iq = [[XMPPIQ alloc] initWithType:kiqSetType];
    [iq setRemoveFromRoster:contact];
    [self send:iq];
}

-(void) addToRoster:(MLContact*) contact withPreauthToken:(NSString* _Nullable) preauthToken
{
    DDLogVerbose(@"(re)adding jid to roster: %@", contact);
    
    //delete contact request if it exists
    [[DataLayer sharedInstance] deleteContactRequest:contact];
    
    XMPPPresence* acceptPresence = [XMPPPresence new];
    [acceptPresence subscribedContact:contact];
    [self send:acceptPresence];
    
    XMPPPresence* subscribePresence = [XMPPPresence new];
    [subscribePresence subscribeContact:contact withPreauthToken:preauthToken];
    [self send:subscribePresence];
}

-(void) updateRosterItem:(MLContact*) contact withName:(NSString*) name
{
    DDLogVerbose(@"Updating roster item of jid: %@", contact.contactJid);
    XMPPIQ* roster = [[XMPPIQ alloc] initWithType:kiqSetType];
    [roster setUpdateRosterItem:contact withName:name];
    //this delegate will handle errors (result responses don't include any data that could be processed and will be ignored)
    [self sendIq:roster withHandler:$newHandler(MLIQProcessor, handleRoster)];
}

#pragma mark - account management

-(void) createInvitationWithCompletion:(monal_id_block_t) completion
{
    XMPPIQ* iq = [[XMPPIQ alloc] initWithType:kiqSetType to:self.connectionProperties.identity.domain];
    [iq addChildNode:[[MLXMLNode alloc] initWithElement:@"command" andNamespace:@"http://jabber.org/protocol/commands" withAttributes:@{
        @"node": @"urn:xmpp:invite#invite",
        @"action": @"execute",
    } andChildren:@[] andData:nil]];
    [self sendIq:iq withResponseHandler:^(XMPPIQ* response) {
        NSString* status = [response findFirst:@"{http://jabber.org/protocol/commands}command<node=urn:xmpp:invite#invite>@status"];
        NSString* uri = [response findFirst:@"{http://jabber.org/protocol/commands}command<node=urn:xmpp:invite#invite>/\\[0]@uri\\"];
        NSString* landing = [response findFirst:@"{http://jabber.org/protocol/commands}command<node=urn:xmpp:invite#invite>/\\[0]@landing-url\\"];
        NSDate* expires = [response findFirst:@"{http://jabber.org/protocol/commands}command<node=urn:xmpp:invite#invite>/\\[0]@expire\\|datetime"];
        //at least yax.im does not implement the dataform depicted in XEP-0401 example 4 (dataform with <item/> wrapper)
        if(uri == nil)
        {
            uri = [response findFirst:@"{http://jabber.org/protocol/commands}command<node=urn:xmpp:invite#invite>/\\@uri\\"];
            landing = [response findFirst:@"{http://jabber.org/protocol/commands}command<node=urn:xmpp:invite#invite>/\\@landing-url\\"];
            expires = [response findFirst:@"{http://jabber.org/protocol/commands}command<node=urn:xmpp:invite#invite>/\\@expire\\|datetime"];
        }
        if([@"completed" isEqualToString:status] && uri != nil)
        {
            if(landing == nil)
                landing = [NSString stringWithFormat:@"https://invite.monal-im.org/#%@", uri];
            completion(@{
                @"success": @YES,
                @"uri": uri,
                @"landing": landing,
                @"expires": nilWrapper(expires),
            });
        }
        else
            completion(@{
                @"success": @NO,
                @"error": [NSString stringWithFormat:NSLocalizedString(@"Failed to create invitation, unknown error: %@", @""), status],
            });
    } andErrorHandler:^(XMPPIQ* error) {
        completion(@{
            @"success": @NO,
            @"error": [HelperTools extractXMPPError:error withDescription:@"Failed to create invitation"],
        });
    }];
}

-(AnyPromise*) changePassword:(NSString*) newPass
{
    return [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        XMPPIQ* iq = [[XMPPIQ alloc] initWithType:kiqSetType];
        [iq setiqTo:self.connectionProperties.identity.domain];
        [iq changePasswordForUser:self.connectionProperties.identity.user newPassword:newPass];

        [self sendIq:iq withResponseHandler:^(XMPPIQ* response) {
            resolve(nil);
        } andErrorHandler:^(XMPPIQ* error) {
            NSString* errorMessage = error ? [HelperTools extractXMPPError:error withDescription:NSLocalizedString(@"Could not change password", @"")] : NSLocalizedString(@"Could not change password: your account is currently not connected", @"");
            resolve([NSError errorWithDomain:@"Monal" code:0 userInfo:@{NSLocalizedDescriptionKey: errorMessage}]);
        }];
    }];
}

-(void) requestRegFormWithToken:(NSString* _Nullable) token andCompletion:(xmppDataCompletion) completion andErrorCompletion:(xmppCompletion) errorCompletion
{
    //this is a registration request
    _registration = YES;
    _registrationSubmission = NO;
    _registrationToken = token;
    _regFormCompletion = completion;
    _regFormErrorCompletion = errorCompletion;
    [self connect];
}

-(void) registerUser:(NSString*) username withPassword:(NSString*) password captcha:(NSString* _Nullable) captcha andHiddenFields:(NSDictionary* _Nullable) hiddenFields withCompletion:(xmppCompletion) completion
{
    //this is a registration submission
    _registration = NO;
    _registrationSubmission = YES;
    self.regUser = username;
    self.regPass = password;
    self.regCode = captcha;
    self.regHidden = hiddenFields;
    _regFormSubmitCompletion = completion;
    if(_accountState < kStateHasStream)
        [self connect];
    else
    {
        DDLogInfo(@"Registration: Calling submitRegForm");
        [self submitRegForm];
    }
}

-(void) submitRegToken:(NSString*) token
{
    XMPPIQ* iq = [[XMPPIQ alloc] initWithType:kiqSetType];
    [iq setiqTo:self.connectionProperties.identity.domain];
    [iq submitRegToken:token];
    
    [self sendIq:iq withResponseHandler:^(XMPPIQ* result __unused) {
        DDLogInfo(@"Registration: Calling requestRegForm from submitRegToken handler");
        [self requestRegForm];
    } andErrorHandler:^(XMPPIQ* error) {
        //dispatch completion handler outside of the receiveQueue
        if(self->_regFormErrorCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                self->_regFormErrorCompletion(NO, [HelperTools extractXMPPError:error withDescription:@"Could not submit registration token"]);
            });
    }];
}

-(void) requestRegForm
{
    XMPPIQ* iq = [[XMPPIQ alloc] initWithType:kiqGetType];
    [iq setiqTo:self.connectionProperties.identity.domain];
    [iq getRegistrationFields];

    [self sendIq:iq withResponseHandler:^(XMPPIQ* result) {
        if(!(
            ([result check:@"{jabber:iq:register}query/username"] && [result check:@"{jabber:iq:register}query/password"]) ||
            [result check:@"{jabber:iq:register}query/\\{jabber:iq:register}form\\"] ||
            [result check:@"{jabber:iq:register}query/\\{urn:xmpp:captcha}form\\"]
        ))
        {
            //dispatch completion handler outside of the receiveQueue
            if(self->_regFormErrorCompletion)
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    if([result check:@"{jabber:iq:register}query/instructions"])
                        self->_regFormErrorCompletion(NO, [NSString stringWithFormat:@"Could not request registration form: %@", [result findFirst:@"{jabber:iq:register}query/instructions#"]]);
                    else
                        self->_regFormErrorCompletion(NO, @"Could not request registration form: unknown error");
                });
            return;
        }
        //dispatch completion handler outside of the receiveQueue
        if(self->_regFormCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSMutableDictionary* hiddenFormFields = nil;
                if([result check:@"{jabber:iq:register}query/{jabber:x:data}x<type=form>/field"])
                {
                    hiddenFormFields = [NSMutableDictionary new];
                    for(MLXMLNode* field in [result find:@"{jabber:iq:register}query/{jabber:x:data}x<type=form>/field<type=hidden>"])
                        hiddenFormFields[[field findFirst:@"/@var"]] = [field findFirst:@"value#"];
                }
                self->_regFormCompletion([result findFirst:@"{jabber:iq:register}query/{urn:xmpp:bob}data#|base64"], hiddenFormFields);
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
    XMPPIQ* iq = [[XMPPIQ alloc] initWithType:kiqSetType];
    [iq registerUser:self.regUser withPassword:self.regPass captcha:self.regCode andHiddenFields:self.regHidden];

    [self sendIq:iq withResponseHandler:^(XMPPIQ* result __unused) {
        //dispatch completion handler outside of the receiveQueue
        if(self->_regFormSubmitCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                self->_regFormSubmitCompletion(YES, nil);
            });
    } andErrorHandler:^(XMPPIQ* error) {
        //dispatch completion handler outside of the receiveQueue
        if(self->_regFormSubmitCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                self->_regFormSubmitCompletion(NO, [HelperTools extractXMPPError:error withDescription:@"Could not submit registration form"]);
            });
    }];
}

#pragma mark - nsstream delegate

-(void)stream:(NSStream*) stream handleEvent:(NSStreamEvent) eventCode
{
    DDLogDebug(@"Stream %@ has event %lu", stream, (unsigned long)eventCode);
    switch(eventCode)
    {
        case NSStreamEventOpenCompleted:
        {
            DDLogVerbose(@"Stream %@ open completed", stream);
            //reset _streamHasSpace to its default value until the fist NSStreamEventHasSpaceAvailable event occurs
            if(stream == _oStream)
            {
                self->_streamHasSpace = NO;
                
                //restart logintimer when our output stream becomes readable (don't do anything without a running timer)
                if(_loginTimer != nil && self->_accountState < kStateLoggedIn)
                    [self reinitLoginTimer];
                
                //we want this to be sync instead of async to make sure we are in kStateConnected before sending anything
                [self dispatchOnReceiveQueue:^{
                    self->_accountState = kStateConnected;
                    if(self->_blockToCallOnTCPOpen != nil)
                    {
                        self->_blockToCallOnTCPOpen();
                        self->_blockToCallOnTCPOpen = nil;     //don't call this twice
                    }
                }];
            }
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
            /*
            if(stream != _oStream)      //check for _oStream here, because we don't have any _iStream (the mlpipe input stream was directly handed over to the xml parser)
            {
                DDLogInfo(@"Ignoring error in iStream (will already be handled in oStream error handler");
                break;
            }
            */
            
            //check accountState to make sure we don't swallow any errors thrown while [self connect] was already called,
            //but the _reconnectInProgress flag not reset yet
            if(_reconnectInProgress && self.accountState<kStateReconnecting)
            {
                DDLogInfo(@"Ignoring error in %@: already waiting for reconnect...", stream);
                break;
            }
            
            //don't display errors while disconnecting
            if(_disconnectInProgres)
            {
                DDLogInfo(@"Ignoring stream error in %@: already disconnecting...", stream);
                break;
            }
            
            NSString* message = st_error.localizedDescription;
            switch(st_error.code)
            {
                case errSSLXCertChainInvalid: {
                    message = NSLocalizedString(@"TLS Error: Certificate chain is invalid", @"");
                    break;
                }

                case errSSLUnknownRootCert: {
                    message = NSLocalizedString(@"TLS Error: Unknown root certificate", @"");
                    break;
                }

                case errSSLCertExpired: {
                    message = NSLocalizedString(@"TLS Error: Certificate expired", @"");
                    break;
                }

                case errSSLHostNameMismatch: {
                    message = NSLocalizedString(@"TLS Error: Host name mismatch", @"");
                    break;
                }

                case errSSLBadCert: {
                    message = NSLocalizedString(@"TLS Error: Bad certificate", @"");
                    break;
                }

            }
            
            [self postError:message withIsSevere:NO];
            DDLogInfo(@"stream error, calling reconnect: %@", message);
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
            if(_disconnectInProgres)
            {
                DDLogInfo(@"Ignoring stream eof in %@: already disconnecting...", stream);
                break;
            }
            DDLogInfo(@"%@ Stream %@ encountered eof, trying to reconnect via parse queue in 1 second", [stream class], stream);
            //use a timer to make sure the incoming data was pushed *through* the MLPipe and reached the parseQueue
            //already when pushing our reconnect block onto the parseQueue
            @synchronized(self->_timersToCancelOnDisconnect) {
                [self->_timersToCancelOnDisconnect addObject:createTimer(1.0, (^{
                    //add this to parseQueue to make sure we completely handle everything that came in before the connection was closed, before handling the close event itself
                    [self->_parseQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                        DDLogInfo(@"Inside parseQueue: %@ Stream %@ encountered eof, trying to reconnect", [stream class], stream);
                        [self reconnect];
                    }]] waitUntilFinished:NO];
                }))];
            }
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
    NSMutableArray* queueCopy = [[NSMutableArray alloc] initWithArray:_outputQueue];
    DDLogVerbose(@"iterating _outputQueue");
    for(id entry in queueCopy)
    {
        BOOL success = NO;
        NSString* entryType = @"unknown";
        if([entry isKindOfClass:[MLXMLNode class]])
        {
            entryType = @"MLXMLNode";
            MLXMLNode* node = (MLXMLNode*)entry;
            success = [self writeToStream:node.XMLString];
            if(success)
            {
                //only react to stanzas, not nonzas
                if([node.element isEqualToString:@"iq"]
                    || [node.element isEqualToString:@"message"]
                    || [node.element isEqualToString:@"presence"]) {
                    requestAck=YES;
                }
            }
        }
        else
        {
            entryType = @"NSString";
            success = [self writeToStream:entry];
        }

        if(success)
        {
            DDLogVerbose(@"removing sent %@ entry from _outputQueue", entryType);
            [_outputQueue removeObject:entry];
        }
        else        //stop sending the remainder of the queue if the send failed (tcp output buffer full etc.)
        {
            DDLogInfo(@"could not send whole _outputQueue: tcp buffer full or connection has an error");
            break;
        }
    }
    
    //restart logintimer for new write to our stream while not logged in (don't do anything without a running timer)
    if(_loginTimer != nil && self->_accountState < kStateLoggedIn)
        [self reinitLoginTimer];

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
    if(_outputBufferByteCount > 0)
    {
        DDLogVerbose(@"sending remaining bytes in outputBuffer: %lu", (unsigned long)_outputBufferByteCount);
        NSInteger sentLen = [_oStream write:_outputBuffer maxLength:_outputBufferByteCount];
        if(sentLen > 0)
        {
            if((NSUInteger)sentLen != _outputBufferByteCount)		//some bytes remaining to send --> trim buffer and return NO
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
            NSError* error = [_oStream streamError];
            DDLogError(@"sending: failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
            //reconnect from third party queue to not block send queue
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
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
            if(_outputBuffer == NULL)
            {
                [NSException raise:@"NSInternalInconsistencyException" format:@"failed malloc" arguments:nil];
                return NO;      //since the stanza was partially written, neither YES nor NO as return value will result in a consistent state
            }
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
        NSError* error = [_oStream streamError];
        DDLogError(@"sending: failed with error %ld domain %@ message %@", (long)error.code, error.domain, error.userInfo);
        //reconnect from third party queue to not block send queue
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self reconnect];
        });
        return NO;
    }
}

#pragma mark misc

-(void) enablePush
{
#if TARGET_OS_SIMULATOR
    DDLogError(@"Not registering push on the simulator!");
    [self disablePush];
#else
    NSString* pushToken = [MLXMPPManager sharedInstance].pushToken;
    NSString* selectedPushServer = [[HelperTools defaultsDB] objectForKey:@"selectedPushServer"];
    if(pushToken == nil || [pushToken length] == 0 || selectedPushServer == nil || self.accountState < kStateBound)
    {
        DDLogInfo(@"NOT registering and enabling push: %@ token: %@ (accountState: %ld, supportsPush: %@)", selectedPushServer, pushToken, (long)self.accountState, bool2str([self.connectionProperties.accountDiscoFeatures containsObject:@"urn:xmpp:push:0"]));
        return;
    }
    if([MLXMPPManager sharedInstance].hasAPNSToken)
    {
        BOOL needsDeregister = false;
        // check if the currently used push server is an old server that should no longer be used
        if([[HelperTools getInvalidPushServers] objectForKey:selectedPushServer] != nil)
        {
            needsDeregister = YES;
            DDLogInfo(@"Selecting new push server because the previous is a legacy server");
            // select new pushserver
            NSString* newPushServer = [HelperTools getSelectedPushServerBasedOnLocale];
            [[HelperTools defaultsDB] setObject:newPushServer forKey:@"selectedPushServer"];
            selectedPushServer = newPushServer;
        }
        // check if the last used push server (db) matches the currently selected server
        NSString* lastUsedPushServer = [[DataLayer sharedInstance] lastUsedPushServerForAccount:self.accountID];
        if([lastUsedPushServer isEqualToString:selectedPushServer] == NO)
            [self disablePushOnOldAndAdditionalServers:lastUsedPushServer];
        else if(needsDeregister)
            [self disablePushOnOldAndAdditionalServers:nil];
        // push is now disabled on the existing server
        // enable push
        XMPPIQ* enablePushIq = [[XMPPIQ alloc] initWithType:kiqSetType];
        [enablePushIq setPushEnableWithNode:pushToken onAppserver:selectedPushServer];
        [self sendIq:enablePushIq withHandler:$newHandler(MLIQProcessor, handlePushEnabled, $ID(selectedPushServer))];
    }
    else // [MLXMPPManager sharedInstance].hasAPNSToken == NO
    {
        if([self.connectionProperties.accountDiscoFeatures containsObject:@"urn:xmpp:push:0"])
        {
            //disable push for this node
            [self disablePush];
        }
    }
#endif
}

-(void) disablePush
{
    DDLogVerbose(@"Trying to disable push on account: %@", self.accountID);
    NSString* pushToken = [[HelperTools defaultsDB] objectForKey:@"pushToken"];
    NSString* pushServer = [[DataLayer sharedInstance] lastUsedPushServerForAccount:self.accountID];
    if(pushToken == nil || pushServer == nil)
    {
        return;
    }
    DDLogInfo(@"DISABLING push token %@ on server %@ (accountState: %ld, supportsPush: %@)", pushToken, pushServer, (long)self.accountState, bool2str([self.connectionProperties.accountDiscoFeatures containsObject:@"urn:xmpp:push:0"]));
    XMPPIQ* disable = [[XMPPIQ alloc] initWithType:kiqSetType];
    [disable setPushDisable:pushToken onPushServer:pushServer];
    [self send:disable];
}

-(void) disablePushOnOldAndAdditionalServers:(NSString*) additionalServer
{
    // Disable push on old / legacy servers
    NSDictionary<NSString*, NSString*>* oldServers = [HelperTools getInvalidPushServers];
    for(NSString* server in oldServers)
    {
        DDLogInfo(@"Disabling push on old pushserver: %@", server);
        XMPPIQ* disable = [[XMPPIQ alloc] initWithType:kiqSetType];
        NSString* pushNode = nilExtractor([oldServers objectForKey:server]);
        //use push token if the push node is nil (e.g. for fpush based servers)
        if(pushNode == nil)
            pushNode = [MLXMPPManager sharedInstance].pushToken;
        [disable setPushDisable:pushNode onPushServer:server];
        [self send:disable];
    }
    // disable push on the last used server
    if(additionalServer != nil && [MLXMPPManager sharedInstance].pushToken != nil)
    {
        DDLogInfo(@"Disabling push on last used pushserver: %@", additionalServer);
        XMPPIQ* disable = [[XMPPIQ alloc] initWithType:kiqSetType];
        [disable setPushDisable:[MLXMPPManager sharedInstance].pushToken onPushServer:additionalServer];
        [self send:disable];
    }
    // disable push on all non selected available push servers
    NSString* selectedNewPushServer = [[HelperTools defaultsDB] objectForKey:@"selectedPushServer"];
    for(NSString* availServer in [HelperTools getAvailablePushServers])
    {
        if([availServer isEqualToString:selectedNewPushServer] == YES)
            continue;
        XMPPIQ* disable = [[XMPPIQ alloc] initWithType:kiqSetType];
        [disable setPushDisable:[MLXMPPManager sharedInstance].pushToken onPushServer:availServer];
        [self send:disable];
    }
}

-(void) updateIqHandlerTimeouts
{
    //only handle iq timeouts while the parseQueue is almost empty
    //(a long backlog in the parse queue could trigger spurious iq timeouts for iqs we already received an answer to, but didn't process it yet)
    if([_parseQueue operationCount] > 4 || _accountState < kStateBound || !_catchupDone)
        return;
    
    //update idle timers, too
    [[DataLayer sharedInstance] decrementIdleTimersForAccount:self];
    
    //update iq handlers
    BOOL stateUpdated = NO;
    @synchronized(_iqHandlers) {
        //we are NOT mutating on iteration here, because we use dispatchAsyncOnReceiveQueue to handle timeouts
        NSMutableArray* idsToRemove = [NSMutableArray new];
        for(NSString* iqid in _iqHandlers)
        {
            //decrement handler timeout every second and check if it landed below zero --> trigger a fake iq error to handle timeout
            //this makes sure a freeze/killed app doesn't immediately trigger timeouts once the app is restarted, as it would be with timestamp based timeouts
            //doing it this way makes sure the incoming iq result has a chance to be processed even in a freeze/kill scenario
            _iqHandlers[iqid][@"timeout"] = @([_iqHandlers[iqid][@"timeout"] doubleValue] - 1.0);
            if([_iqHandlers[iqid][@"timeout"] doubleValue] < 0.0)
            {
                DDLogWarn(@"%@: Timeout of handler triggered: %@", _logtag, _iqHandlers[iqid]);
                //only force save state after calling a handler
                //(timeout changes that don't make it to disk only extend the timeout by a few seconds but don't have any negative sideeffect)
                stateUpdated = YES;
                
                //fake xmpp stanza error to make timeout handling transparent without the need for invalidation handler
                //we need to fake the from, too (no from means own bare jid)
                XMPPIQ* errorIq = [[XMPPIQ alloc] initAsErrorTo:_iqHandlers[iqid][@"iq"]];
                errorIq.to = self.connectionProperties.identity.fullJid;
                if([_iqHandlers[iqid][@"iq"] to] != nil)
                    errorIq.from = [_iqHandlers[iqid][@"iq"] to];
                else
                    errorIq.from = self.connectionProperties.identity.jid;
                [errorIq addChildNode:[[MLXMLNode alloc] initWithElement:@"error" withAttributes:@{@"type": @"wait"} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"remote-server-timeout" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas"],
                    [[MLXMLNode alloc] initWithElement:@"text" andNamespace:@"urn:ietf:params:xml:ns:xmpp-stanzas" withAttributes:@{} andChildren:@[] andData:[NSString stringWithFormat:@"No response in %d seconds", (int)IQ_TIMEOUT]],
                ] andData:nil]];
                
                //make sure our fake error iq is handled inside the receiveQueue
                //extract this from _iqHandlers to make sure we only handle iqs that didn't get handled in the meantime
                NSMutableDictionary* iqHandler = self->_iqHandlers[iqid];
                [idsToRemove addObject:iqid];
                if(iqHandler)
                {
                    //do a real async dispatch, not an automatic sync one because we are in the same queue
                    [_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                        //make sure these handlers are called inside a db write transaction just like receiving a real error iq
                        //--> don't create a deadlock with 2 threads waiting for db write transaction and synchronized iqhandlers
                        //    in opposite order
                        [[DataLayer sharedInstance] createTransaction:^{
                            DDLogDebug(@"Calling iq handler with faked error iq: %@", errorIq);
                            if(iqHandler[@"handler"] != nil)
                                $call(iqHandler[@"handler"], $ID(account, self), $ID(iqNode, errorIq));
                            else if(iqHandler[@"errorHandler"] != nil)
                                ((monal_iq_handler_t) iqHandler[@"errorHandler"])(errorIq);
                        }];
                    }]] waitUntilFinished:NO];
                }
                else
                    DDLogError(@"%@: iq handler for '%@' vanished while switching to receive queue", _logtag, iqid);
            }
        }
        //now delete iqs marked for deletion
        for(NSString* iqid in idsToRemove)
            [_iqHandlers removeObjectForKey:iqid];
    }
    
    //make sure all state is persisted as soon as possible (we could have called handlers and we don't want to execute them twice!)
    if(stateUpdated)
        [self persistState];
}

-(void) delayIncomingMessageStanzasForArchiveJid:(NSString*) archiveJid
{
    _inCatchup[archiveJid] = @YES;      //catchup not done and replay not finished
}

-(void) delayIncomingMessageStanzaUntilCatchupDone:(XMPPMessage*) originalParsedStanza
{
    NSString* archiveJid = self.connectionProperties.identity.jid;
    if([[originalParsedStanza findFirst:@"/@type"] isEqualToString:@"groupchat"])
        archiveJid = originalParsedStanza.fromUser;
    
    [[DataLayer sharedInstance] addDelayedMessageStanza:originalParsedStanza forArchiveJid:archiveJid andAccountID:self.accountID];
}

//this method is needed to not have a retain cycle (happens when using a block instead of this method in mamFinishedFor:)
-(void) _handleInternalMamFinishedFor:(NSString*) archiveJid
{
    if(self.accountState < kStateBound)
    {
        DDLogWarn(@"Aborting delayed replay because not >= kStateBound anymore! Remaining stanzas will be kept in DB and be handled after next smacks reconnect.");
        return;
    }
    
    [MLNotificationQueue queueNotificationsInBlock:^{
        DDLogVerbose(@"Creating db transaction for delayed stanza handling of jid %@", archiveJid);
        [[DataLayer sharedInstance] createTransaction:^{
            //don't write data to our tcp stream while inside this db transaction (all effects to the outside world should be transactional, too)
            [self freezeSendQueue];
            //pick the next delayed message stanza (will return nil if there isn't any left)
            MLXMLNode* delayedStanza = [[DataLayer sharedInstance] getNextDelayedMessageStanzaForArchiveJid:archiveJid andAccountID:self.accountID];
            DDLogDebug(@"Got delayed stanza: %@", delayedStanza);
            if(delayedStanza == nil)
            {
                DDLogInfo(@"Catchup finished for jid %@", archiveJid);
                [self->_inCatchup removeObjectForKey:archiveJid];     //catchup done and replay finished
                
                //handle cached mds data for this jid
                if(self->_mdsData[archiveJid] != nil)
                    [self handleMdsData:self->_mdsData[archiveJid] forJid:archiveJid];
                
                //handle old mamFinished code as soon as all delayed messages have been processed
                //we need to wait for all delayed messages because at least omemo needs the pep headline messages coming in during mam catchup
                if([self.connectionProperties.identity.jid isEqualToString:archiveJid])
                {
                    if(!self->_catchupDone)
                    {
                        DDLogVerbose(@"Now posting kMonalFinishedCatchup notification");
                        [self handleFinishedCatchup];
                    }
                }
            }
            else
            {
                //now *really* process delayed message stanza
                [self processInput:delayedStanza withDelayedReplay:YES];
                
                DDLogDebug(@"Delayed Stanza finished processing: %@", delayedStanza);
                
                //add async processing of next delayed message stanza to receiveQueue
                //the async dispatching makes it possible to abort the replay by pushing a disconnect block etc. onto the receieve queue
                //and makes sure we process every delayed stanza in its own receive queue operation and its own db transaction
                [self->_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
                    [self _handleInternalMamFinishedFor:archiveJid];
                }]] waitUntilFinished:NO];
            }
        }];
        DDLogVerbose(@"Transaction for delayed stanza handling for jid %@ ended", archiveJid);
        [self unfreezeSendQueue];      //this will flush all stanzas added inside the db transaction and now waiting in the send queue
    } onQueue:@"delayedStanzaReplay"];
    [self persistState];        //make sure to persist all state changes triggered by the events in the notification queue
}

-(void) mamFinishedFor:(NSString*) archiveJid
{
    //we should be already in the receive queue, but just to make sure (sync dispatch will do nothing if we already are in the right queue)
    [self dispatchOnReceiveQueue:^{
        self->_inCatchup[archiveJid] = @NO;       //catchup done, but replay not finished
        //handle delayed message stanzas delivered while the mam catchup was in progress
        //the first call and all subsequent self-invocations are handled by dispatching it async to the receiveQueue
        //the async dispatching makes it possible to abort the replay by pushing a disconnect block etc. onto the receieve queue
        //and makes sure we process every delayed stanza in its own receive queue operation and its own db transaction
        [self->_receiveQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
            [self _handleInternalMamFinishedFor:archiveJid];
        }]] waitUntilFinished:NO];
    }];
}

-(void) initCatchupStats
{
    self->_catchupStanzaCounter = 0;
    self->_catchupStartTime = [NSDate date];
}

-(void) logCatchupStats
{
    if(self->_catchupStartTime != nil)
    {
        NSDate* now = [NSDate date];
        DDLogInfo(@"Handled %u stanzas in %f seconds...", self->_catchupStanzaCounter, [now timeIntervalSinceDate:self->_catchupStartTime]);
    }
}

-(void) handleFinishedCatchup
{
    self->_catchupDone = YES;
    self.isDoingFullReconnect = !self.connectionProperties.supportsSM3;
    
    //log catchup statistics
    [self logCatchupStats];
    
    //call all reconnection handlers and clear them afterwards
    @synchronized(_reconnectionHandlers) {
        NSArray* handlers = [_reconnectionHandlers copy];
        [_reconnectionHandlers removeAllObjects];
        for(MLHandler* handler in handlers)
            $call(handler, $ID(account, self));
    }
    [self persistState];
    
    //don't queue this notification because it should be handled INLINE inside the receive queue
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFinishedCatchup object:self userInfo:nil];
}

-(void) updateMdsData:(NSDictionary*) mdsData
{
    for(NSString* jid in mdsData)
    {
        //update cached data
        _mdsData[jid] = mdsData[jid];
        
        //handle mds update directly, if not in catchup for this jid
        //everything else will be handled once the catchup is finished
        NSString* catchupJid = self.connectionProperties.identity.jid;
        if([[DataLayer sharedInstance] isBuddyMuc:jid forAccount:self.accountID])
            catchupJid = jid;
        if(_inCatchup[catchupJid] == nil && _mdsData[jid] != nil)
            [self handleMdsData:_mdsData[jid] forJid:jid];
    }
}

-(void) handleMdsData:(MLXMLNode*) data forJid:(NSString*) jid
{
    NSString* stanzaId = [data findFirst:@"{urn:xmpp:mds:displayed:0}displayed/{urn:xmpp:sid:0}stanza-id@id"];
    NSString* by = [data findFirst:@"{urn:xmpp:mds:displayed:0}displayed/{urn:xmpp:sid:0}stanza-id@by"];
    DDLogInfo(@"Got mds displayed element for chat %@ by %@: %@", jid, by, stanzaId);
    
    if([[DataLayer sharedInstance] isBuddyMuc:jid forAccount:self.accountID])
    {
        if(![jid isEqualToString:by])
        {
            DDLogWarn(@"Mds stanza-id by not equal to muc jid, ignoring!");
            return;
        }
        
        //NSString* ownNick = [[DataLayer sharedInstance] ownNickNameforMuc:jid forAccount:self.accountID]
        NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:jid andAccount:self.accountID tillStanzaId:stanzaId wasOutgoing:NO];
        DDLogDebug(@"Muc marked as read: %@", unread);
        
        //remove notifications of all remotely read messages (indicated by sending a display marker)
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessagesNotice object:self userInfo:@{@"messagesArray":unread}];
        
        //update unread count in active chats list
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self userInfo:@{
            @"contact": [MLContact createContactFromJid:jid andAccountID:self.accountID]
        }];
    }
    else
    {
        if(![self.connectionProperties.identity.jid isEqualToString:by])
        {
            DDLogWarn(@"Mds stanza-id by not equal to own bare jid, ignoring!");
            return;
        }
        
        NSArray* unread = [[DataLayer sharedInstance] markMessagesAsReadForBuddy:jid andAccount:self.accountID tillStanzaId:stanzaId wasOutgoing:NO];
        DDLogDebug(@"1:1 marked as read: %@", unread);
        
        //remove notifications of all remotely read messages (indicated by sending a display marker)
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalDisplayedMessagesNotice object:self userInfo:@{@"messagesArray":unread}];
        
        //update unread count in active chats list
        [[MLNotificationQueue currentQueue] postNotificationName:kMonalContactRefresh object:self userInfo:@{
            @"contact": [MLContact createContactFromJid:jid andAccountID:self.accountID]
        }];
    }
}

-(void) addMessageToMamPageArray:(NSDictionary*) messageDictionary
{
    @synchronized(_mamPageArrays) {
        if(!_mamPageArrays[[messageDictionary[@"outerMessageNode"] findFirst:@"{urn:xmpp:mam:2}result@queryid"]])
            _mamPageArrays[[messageDictionary[@"outerMessageNode"] findFirst:@"{urn:xmpp:mam:2}result@queryid"]] = [NSMutableArray new];
        [_mamPageArrays[[messageDictionary[@"outerMessageNode"] findFirst:@"{urn:xmpp:mam:2}result@queryid"]] addObject:messageDictionary];
    }
}

-(NSMutableArray*) getOrderedMamPageFor:(NSString*) mamQueryId
{
    NSMutableArray* array;
    @synchronized(_mamPageArrays) {
        if(_mamPageArrays[mamQueryId] == nil)
            return [NSMutableArray new];       //return empty array if nothing can be found (after app crash etc.)
        array = _mamPageArrays[mamQueryId];
        [_mamPageArrays removeObjectForKey:mamQueryId];
    }
    return array;
}

-(void) publishMDSMarkerForMessage:(MLMessage*) msg
{
    NSString* max_items = @"255";       //fallback for servers not supporting "max"
    if(self.connectionProperties.supportsPubSubMax)
        max_items = @"max";
    [self.pubsub publishItem:[[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{kId: msg.buddyName} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"displayed" andNamespace:@"urn:xmpp:mds:displayed:0" withAttributes:@{} andChildren:@[
            [[MLXMLNode alloc] initWithElement:@"stanza-id" andNamespace:@"urn:xmpp:sid:0" withAttributes:@{
                @"by": msg.isMuc ? msg.buddyName : self.connectionProperties.identity.jid,
                @"id": msg.stanzaId,
            } andChildren:@[] andData:nil]
        ] andData:nil]
    ] andData:nil] onNode:@"urn:xmpp:mds:displayed:0" withConfigOptions:@{
        @"pubsub#persist_items": @"true",
        @"pubsub#access_model": @"whitelist",
        @"pubsub#max_items": max_items,
        @"pubsub#send_last_published_item": @"never",
    }];
}

-(void) sendDisplayMarkerForMessages:(NSArray<MLMessage*>*) unread
{
    //ignore empty arrays
    if(unread.count == 0)
        return;
    
    //send displayed marker for last unread message *marked as wanting chat markers* (XEP-0333)
    MLMessage* lastMarkableMessage = nil;
    for(MLMessage* msg in unread)
        if(msg.displayMarkerWanted)
            lastMarkableMessage = msg;
    
    //last unread message used for mds
    MLMessage* lastUnreadMessage = [unread lastObject];
    
    if(![[HelperTools defaultsDB] boolForKey:@"SendDisplayedMarkers"])
    {
        DDLogVerbose(@"Not sending chat marker, configured to not do so...");
        [self publishMDSMarkerForMessage:lastUnreadMessage];      //always publish mds marker
        return;
    }
    
    //don't send chatmarkers in channels (all messages have the same muc attributes, randomly pick the last one)
    if(lastUnreadMessage.isMuc && [kMucTypeChannel isEqualToString:lastUnreadMessage.mucType])
    {
        DDLogVerbose(@"Not sending XEP-0333 chat marker in channel...");
        [self publishMDSMarkerForMessage:lastUnreadMessage];      //always publish mds marker
        return;
    }
    
    //all messages have the same contact, randomly pick the last one
    MLContact* contact = [MLContact createContactFromJid:lastUnreadMessage.buddyName andAccountID:lastUnreadMessage.accountID];
    //don't send chatmarkers to 1:1 chats with users in our contact list that did not subscribe us (e.g. are not allowed to see us)
    if(!contact.isMuc && !contact.isSubscribedFrom)
    {
        DDLogVerbose(@"Not sending chat marker, we are not subscribed from this contact...");
        [self publishMDSMarkerForMessage:lastUnreadMessage];      //always publish mds marker
        return;
    }
    
    //only send chatmarkers if requested by contact
    BOOL assistedMDS = [self.connectionProperties.accountDiscoFeatures containsObject:@"urn:xmpp:mds:server-assist:0"] && lastMarkableMessage == lastUnreadMessage;
    if(lastMarkableMessage != nil)
    {
        XMPPMessage* displayedNode = [[XMPPMessage alloc] initToContact:contact];
        [displayedNode setDisplayed:lastMarkableMessage.isMuc && lastMarkableMessage.stanzaId != nil ? lastMarkableMessage.stanzaId : lastMarkableMessage.messageId];
        if(assistedMDS)
            [displayedNode setMDSDisplayed:lastMarkableMessage.stanzaId withStanzaIdBy:(lastMarkableMessage.isMuc ? lastMarkableMessage.buddyName : self.connectionProperties.identity.jid)];
        [displayedNode setStoreHint];
        DDLogVerbose(@"Sending display marker: %@", displayedNode);
        [self send:displayedNode];
    }
    
    //send mds if not already done by server using mds-assist
    if(!assistedMDS)
        [self publishMDSMarkerForMessage:lastUnreadMessage];      //always publish mds marker
}

-(void) removeFromServerWithCompletion:(void (^)(NSString* _Nullable error)) completion
{
    XMPPIQ* remove = [[XMPPIQ alloc] initWithType:kiqSetType];
    [remove addChildNode:[[MLXMLNode alloc] initWithElement:@"query" andNamespace:@"jabber:iq:register" withAttributes:@{} andChildren:@[
        [[MLXMLNode alloc] initWithElement:@"remove"]
    ] andData:nil]];
    [self sendIq:remove withResponseHandler:^(XMPPIQ* result) {
        //disconnect account and throw away everything waiting to be processed
        //(for example the stream close coming from the server after removing the account on the server)
        [self disconnect:YES];  //this disconnect is needed to not show spurious errors on delete (technically the explicitLogout is not needed, but it doesn't hurt either)
        [[MLXMPPManager sharedInstance] removeAccountForAccountID:self.accountID];
        completion(nil);        //signal success to UI
    } andErrorHandler:^(XMPPIQ* error) {
        if(error != nil)        //don't report iq invalidation on disconnect as error
        {
            NSString* errorStr = [HelperTools extractXMPPError:error withDescription:NSLocalizedString(@"Server does not support account removal", @"")];
            completion(errorStr);   //signal error to UI
        }
    }];
}

-(void) markCapsQueryCompleteFor:(NSString*) ver
{
    [_runningCapsQueries removeObject:ver];
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

-(void) publishAvatar:(UIImage*) image
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if(!image)
        {
            DDLogInfo(@"Retracting own avatar image");
            [self.pubsub deleteNode:@"urn:xmpp:avatar:metadata" andHandler:$newHandler(MLPubSubProcessor, avatarDeleted)];
            [self.pubsub deleteNode:@"urn:xmpp:avatar:data" andHandler:$newHandler(MLPubSubProcessor, avatarDeleted)];
            //publish empty metadata node, as per XEP-0084
            [self.pubsub publishItem:
                [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{} andChildren:@[
                    [[MLXMLNode alloc] initWithElement:@"metadata" andNamespace:@"urn:xmpp:avatar:metadata" withAttributes:@{} andChildren:@[] andData:nil]
                ] andData:nil]
            onNode:@"urn:xmpp:avatar:metadata" withConfigOptions:@{
                @"pubsub#persist_items": @"true",
                @"pubsub#access_model": @"presence"
            } andHandler:$newHandler(MLPubSubProcessor, avatarDeleted)];
        }
        else
        {
            //should work for ejabberd >= 19.02 and prosody >= 0.11
            NSData* imageData = [HelperTools resizeAvatarImage:image withCircularMask:NO toMaxBase64Size:60000];
            NSString* imageHash = [HelperTools hexadecimalString:[HelperTools sha1:imageData]];
            
            DDLogInfo(@"Publishing own avatar image with hash %@", imageHash);
            
            //publish data node (must be done *before* publishing the new metadata node)
            MLXMLNode* item = [[MLXMLNode alloc] initWithElement:@"item" withAttributes:@{@"id": imageHash} andChildren:@[
                [[MLXMLNode alloc] initWithElement:@"data" andNamespace:@"urn:xmpp:avatar:data" withAttributes:@{} andChildren:@[] andData:[HelperTools encodeBase64WithData:imageData]]
            ] andData:nil];
            
            [self.pubsub publishItem:item onNode:@"urn:xmpp:avatar:data" withConfigOptions:@{
                @"pubsub#persist_items": @"true",
                @"pubsub#access_model": @"presence"
            } andHandler:$newHandler(MLPubSubProcessor, avatarDataPublished, $ID(imageHash), $UINTEGER(imageBytesLen, imageData.length))];
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
    return [NSString stringWithFormat:@"%@[%@]: %@", self.accountID, _internalID, self.connectionProperties.identity.jid];
}

@end
