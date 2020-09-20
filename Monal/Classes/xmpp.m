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
#import "MLPipe.h"
#import "MLProcessLock.h"
#import "DataLayer.h"
#import "HelperTools.h"
#import "MLXMPPManager.h"

#import "MLImageManager.h"

//XMPP objects
#import "XMPPIQ.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"

#import "MLXMLNode.h"

#import "MLBasePaser.h"

//processors
#import "MLMessageProcessor.h"
#import "MLIQProcessor.h"
#import "MLPresenceProcessor.h"

#import "MLHTTPRequest.h"
#import "AESGcm.h"

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
    BOOL _hasRequestedServerInfo;
    BOOL _isCSIActive;
    NSDate* _lastInteractionDate;
    
    //internal handlers and flags
    monal_void_block_t _cancelLoginTimer;
    monal_void_block_t _cancelPingTimer;
    NSMutableArray* _smacksAckHandler;
    NSMutableDictionary* _iqHandlers;
    BOOL _startTLSComplete;
    BOOL _catchupDone;
    double _exponentialBackoff;
    BOOL _reconnectInProgress;
    NSObject* _smacksSyncPoint;     //only used for @synchronized() blocks
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
    self = [super init];
    self.accountNo = accountNo;
    self.connectionProperties = [[MLXMPPConnection alloc] initWithServer:server andIdentity:identity];
    [self setupObjects];
    //read persisted state to make sure we never operate stateless
    [self readState];

    return self;
}

-(void) setupObjects
{
    _smacksSyncPoint = [[NSObject alloc] init];
    _accountState = kStateLoggedOut;
    _registration = NO;
    _registrationSubmission = NO;

    _startTLSComplete = NO;
    _catchupDone = NO;
    _reconnectInProgress = NO;
    _lastIdleState=NO;

    _SRVDiscoveryDone = NO;
    _discoveredServersList = [[NSMutableArray alloc] init];
    if(!_usableServersList)
        _usableServersList = [[NSMutableArray alloc] init];
    _exponentialBackoff = 0;
    _outputQueue = [[NSMutableArray alloc] init];
    _iqHandlers = [[NSMutableDictionary alloc] init];
    _mamPageArrays = [[NSMutableDictionary alloc] init];

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

    // Init omemo
    self.omemo = [[MLOMEMO alloc] initWithAccount:self.accountNo jid:self.connectionProperties.identity.jid ressource:self.connectionProperties.identity.resource connectionProps:self.connectionProperties xmppConnection:self];

    if(_outputBuffer)
        free(_outputBuffer);
    _outputBuffer = nil;
    _outputBufferByteCount = 0;

    _versionHash = [HelperTools getOwnCapsHash];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalAccountStatusChanged object:nil userInfo:@{
            kAccountID:self.accountNo,
            kAccountState:[[NSNumber alloc] initWithInt:(int)self.accountState],
            kAccountHibernate:[NSNumber numberWithBool:[self isHibernated]]
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
    @synchronized(_smacksSyncPoint) {
        unackedCount = (unsigned long)[self.unAckedStanzas count];
    };
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
    [_sendQueue cancelAllOperations];
    [_sendQueue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
        self->_outputQueue=[[NSMutableArray alloc] init];
        if(self->_outputBuffer)
            free(self->_outputBuffer);
        self->_outputBuffer = nil;
        self->_outputBufferByteCount = 0;
        self->_streamHasSpace = NO;
    }]] waitUntilFinished:YES];
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
	if(CFReadStreamSetProperty((__bridge CFReadStreamRef)self->_oStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings))
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
        
        if(self.accountState>=kStateReconnecting)
        {
            DDLogError(@"assymetrical call to login without a teardown logout, calling reconnect...");
            [self reconnect];
            return;
        }
        
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
            return;
        }
        
        //make sure we are still enabled ("-1" is used for the account registration process and never saved to db
        if(![@"-1" isEqualToString:self.accountNo] && ![[DataLayer sharedInstance] isAccountEnabled:self.accountNo])
        {
            DDLogError(@"Account '%@' not enabled anymore, ignoring login", self.accountNo);
            return;
        }
        
        DDLogInfo(@"XMPP connnect start");
        _accountState=kStateReconnecting;
        _startTLSComplete = NO;
        _catchupDone = NO;
        
        [self cleanupSendQueue];
        
        //(re)read persisted state and start connection
        [self readState];
        if([self connectionTask])
        {
            DDLogError(@"Server disallows xmpp connections for account '%@', ignoring login", self.accountNo);
            _accountState=kStateDisconnected;
            return;
        }
        
        //return here if we are just registering a new account
        if(_registration || _registrationSubmission)
            return;
        
        double connectTimeout = 8.0;
        if([HelperTools isInBackground])
            connectTimeout = 24.0;     //long timeout if in background
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
        
        [_iqHandlers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            NSString* id = (NSString*) key;
            NSDictionary* data = (NSDictionary*) obj;
            if(data[@"invalidateOnDisconnect"]==@YES && data[@"errorHandler"])
            {
                DDLogWarn(@"invalidating iq handler for iq id '%@'", id);
                if(data[@"errorHandler"])
                    ((monal_iq_handler_t) data[@"errorHandler"])(nil);
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
                [self writeToStream:stream.XMLString]; // dont even bother queueing
            }]] waitUntilFinished:YES];         //block until finished because we are closing the socket directly afterwards

            @synchronized(_smacksSyncPoint) {
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
            [self persistState];
        
        [self closeSocket];
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalAccountStatusChanged object:nil];
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
        [HelperTools startTimer:wait withHandler:^{
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
        _baseParserDelegate = [[MLBasePaser alloc] initWithCompeltion:^(XMPPParser * _Nullable parsedStanza) {
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
                [self sendIq:ping withResponseHandler:^(ParseIq* result){
                    handler();
                } andErrorHandler:^(ParseIq* error){
                    handler();
                }];
            }
        }
    }];
}

#pragma mark message ACK
-(void) addSmacksHandler:(monal_void_block_t) handler
{
    @synchronized(_smacksSyncPoint) {
        [self addSmacksHandler:handler forValue:self.lastOutboundStanza];
    }
}

-(void) addSmacksHandler:(monal_void_block_t) handler forValue:(NSNumber*) value
{
    @synchronized(_smacksSyncPoint) {
        if([value integerValue]<[self.lastOutboundStanza integerValue])
        {
            DDLogError(@"adding smacks handler for value *SMALLER* than current self.lastOutboundStanza, this handler will *never* be triggered!");
            return;
        }
        NSDictionary* dic = @{@"value":value, @"handler":handler};
        [_smacksAckHandler addObject:dic];
    }
}

-(void) resendUnackedStanzas
{
    @synchronized(_smacksSyncPoint) {
        NSMutableArray* sendCopy = [[NSMutableArray alloc] initWithArray:self.unAckedStanzas];
        //remove all stanzas from queue and correct the lastOutboundStanza counter accordingly
        self.lastOutboundStanza = [NSNumber numberWithInteger:[self.lastOutboundStanza integerValue] - [self.unAckedStanzas count]];
        //Send appends to the unacked stanzas. Not removing it now will create an infinite loop.
        //It may also result in mutation on iteration
        [self.unAckedStanzas removeAllObjects];
        [sendCopy enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *dic= (NSDictionary *) obj;
            [self send:(MLXMLNode*)[dic objectForKey:kStanza]];
        }];
        [self persistState];
    }
}

-(void) resendUnackedMessageStanzasOnly:(NSMutableArray*) stanzas
{
    if(stanzas)
    {
        @synchronized(_smacksSyncPoint) {
            NSMutableArray* sendCopy = [[NSMutableArray alloc] initWithArray:stanzas];
            //clear queue because we don't want to repeat resending these stanzas later if the var stanzas points to self.unAckedStanzas here
            [stanzas removeAllObjects];
            [sendCopy enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSDictionary* dic = (NSDictionary *) obj;
                MLXMLNode* stanza = [dic objectForKey:kStanza];
                if([stanza.element isEqualToString:@"message"])		//only resend message stanzas because of the smacks error condition
                    [self send:stanza];
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
    @synchronized(_smacksSyncPoint) {
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
    @synchronized(_smacksSyncPoint) {
        unsigned long unackedCount = (unsigned long)[self.unAckedStanzas count];
        NSDictionary* dic = @{
            kXMLNS:@"urn:xmpp:sm:3",
            @"lastHandledInboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledInboundStanza],
            @"lastHandledOutboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledOutboundStanza],
            @"lastOutboundStanza":[NSString stringWithFormat:@"%@", self.lastOutboundStanza],
            @"unAckedStanzasCount":[NSString stringWithFormat:@"%lu", unackedCount],
        };
        if(self.accountState>=kStateBound && self.connectionProperties.supportsSM3 &&
            ((!self.smacksRequestInFlight && unackedCount>0) || force)
        ) {
            DDLogVerbose(@"requesting smacks ack...");
            rNode =[[MLXMLNode alloc] initWithElement:@"r"];
            rNode.attributes=[dic mutableCopy];
            self.smacksRequestInFlight=YES;
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
        MLXMLNode* aNode = [[MLXMLNode alloc] initWithElement:@"a"];
        unsigned long unackedCount = 0;
        NSDictionary* dic;
        @synchronized(_smacksSyncPoint) {
            unackedCount = (unsigned long)[self.unAckedStanzas count];
            dic = @{
                kXMLNS:@"urn:xmpp:sm:3",
                @"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza],
                @"lastHandledInboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledInboundStanza],
                @"lastHandledOutboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledOutboundStanza],
                @"lastOutboundStanza":[NSString stringWithFormat:@"%@", self.lastOutboundStanza],
                @"unAckedStanzasCount":[NSString stringWithFormat:@"%lu", unackedCount],
            };
        }
        aNode.attributes = [dic mutableCopy];
        if(queuedSend)
            [self send:aNode];
        else      //this should only be done from sendQueue (e.g. by sendLastAck())
            [self writeToStream:aNode.XMLString];		// dont even bother queueing
    }
}


#pragma mark - stanza handling

-(void) processInput:(XMPPParser *) parsedStanza
{
    DDLogDebug(@"RECV Stanza: <%@> with namespace '%@' and id '%@'", parsedStanza.stanzaType, parsedStanza.stanzaNameSpace, parsedStanza.idval);

    //process most stanzas/nonzas after having a secure context only
    if(self.connectionProperties.server.isDirectTLS || self->_startTLSComplete)
    {
        if([parsedStanza.stanzaType isEqualToString:@"iq"] && [parsedStanza isKindOfClass:[ParseIq class]])
        {
            ParseIq* iqNode = (ParseIq*)parsedStanza;

#ifndef DISABLE_OMEMO
        MLIQProcessor *processor = [[MLIQProcessor alloc] initWithAccount:self
                                                               connection:self.connectionProperties
                                                                    omemo:self.omemo];
#else
        MLIQProcessor *processor = [[MLIQProcessor alloc] initWithAccount:self
                                                               connection:self.connectionProperties
                                    self.omemo:nil];
#endif
            processor.sendIq=^(MLXMLNode* _Nullable iq, monal_iq_handler_t resultHandler, monal_iq_handler_t errorHandler) {
                if(iq)
                {
                    DDLogInfo(@"sending iq stanza with handler");
                    [self sendIq:iq withResponseHandler:resultHandler andErrorHandler:errorHandler];
                }
            };
            processor.sendIqWithDelegate=^(MLXMLNode* _Nullable iq, id delegate, SEL method, NSArray* args) {
                if(iq)
                {
                    DDLogInfo(@"sending iq stanza with delegate");
                    [self sendIq:iq withDelegate:delegate andMethod:method andAdditionalArguments:args];
                }
            };

            //this will be called after mam catchup is complete
            processor.mamFinished = ^() {
                [self mamFinished];
            };
            
            //this will be called after bind
            processor.initSession = ^() {
                //init session and query disco, roster etc.
                [self initSession];

                //only do this if smacks is not supported because handling of the old queue will be already done on smacks enable/failed enable
                if(!self.connectionProperties.supportsSM3)
                {
                    @synchronized(_smacksSyncPoint) {
                        //resend stanzas still in the outgoing queue and clear it afterwards
                        //this happens if the server has internal problems and advertises smacks support
                        //but failes to resume the stream as well as to enable smacks on the new stream
                        //clean up those stanzas to only include message stanzas because iqs don't survive a session change
                        //message duplicates are possible in this scenario, but that's better than dropping messages
                        //the self.unAckedStanzas queue is not touched by initSession() above because smacks is disabled at this point
                        [self resendUnackedMessageStanzasOnly:self.unAckedStanzas];
                    }
                }
            };

            processor.enablePush = ^() {
                [self enablePush];
            };

            processor.getVcards = ^() {
                [self getVcards];
            };

            [processor processIq:iqNode];
            
            //process registered iq handlers
            if(_iqHandlers[iqNode.idval])
            {
                //call block-handlers
                if([@"result" isEqualToString:iqNode.type] && _iqHandlers[iqNode.idval][@"resultHandler"])
                    ((monal_iq_handler_t) _iqHandlers[iqNode.idval][@"resultHandler"])(iqNode);
                else if([@"error" isEqualToString:iqNode.type] && _iqHandlers[iqNode.idval][@"errorHandler"])
                    ((monal_iq_handler_t) _iqHandlers[iqNode.idval][@"errorHandler"])(iqNode);
                
                //call class delegate handlers
                if(_iqHandlers[iqNode.idval][@"delegate"] && _iqHandlers[iqNode.idval][@"method"])
                {
                    id cls = NSClassFromString(_iqHandlers[iqNode.idval][@"delegate"]);
                    SEL sel = NSSelectorFromString(_iqHandlers[iqNode.idval][@"method"]);
                    DDLogVerbose(@"Calling IQHandler [%@ %@]...", _iqHandlers[iqNode.idval][@"delegate"], _iqHandlers[iqNode.idval][@"method"]);
                    NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[cls methodSignatureForSelector:sel]];
                    [inv setTarget:cls];
                    [inv setSelector:sel];
                    //arguments 0 and 1 are self and _cmd respectively, automatically set by NSInvocation
                    NSInteger idx = 2;
                    [inv setArgument:&self atIndex:idx++];
                    [inv setArgument:&iqNode atIndex:idx++];
                    for(id arg in _iqHandlers[iqNode.idval][@"arguments"])
                        [inv setArgument:&arg atIndex:idx++];
                    [inv invoke];
                }
                
                //remove handler after calling it
                [_iqHandlers removeObjectForKey:iqNode.idval];
            }

#ifndef DISABLE_OMEMO
        if([iqNode.idval isEqualToString:self.omemo.deviceQueryId])
        {
            if([iqNode.type isEqualToString:kiqErrorType]) {
                //there are no devices published yet
                [self.omemo sendOMEMODevice];
            }
        }
#endif
        if([iqNode.from isEqualToString:self.connectionProperties.conferenceServer] && iqNode.discoItems)
        {
            self->_roomList=iqNode.items;
            [[NSNotificationCenter defaultCenter]
            postNotificationName: kMLHasRoomsNotice object: self];
        }

        if([iqNode.idval isEqualToString:self.jingle.idval]) {
            [self jingleResult:iqNode];
        }
        
        //only mark stanza as handled *after* processing it
        [self incrementLastHandledStanza];
        }
        else if([parsedStanza.stanzaType isEqualToString:@"message"] && [parsedStanza isKindOfClass:[ParseMessage class]])
        {
            ParseMessage* messageNode = (ParseMessage*)parsedStanza;
            MLMessageProcessor* messageProcessor = nil;
#ifndef DISABLE_OMEMO
            messageProcessor = [[MLMessageProcessor alloc] initWithAccount:self jid:self.connectionProperties.identity.jid connection:self.connectionProperties omemo:self.omemo];
#else
            messageProcessor = [[MLMessageProcessor alloc] initWithAccount:self jid:self.connectionProperties.identity.jid connection:self.connectionProperties omemo:nil];
#endif

            messageProcessor.sendStanza=^(MLXMLNode * _Nullable nodeResponse) {
                if(nodeResponse) {
                    [self send:nodeResponse];
                }
            };

            messageProcessor.postPersistAction = ^(BOOL success, BOOL encrypted, BOOL showAlert,  NSString* body, NSString* newMessageType) {
                if(success)
                {
                    if(messageNode.requestReceipt && ![messageNode.from isEqualToString:self.connectionProperties.identity.jid])
                    {
                        XMPPMessage *receiptNode = [[XMPPMessage alloc] init];
                        //the message type is needed so that the store hint is accepted by the server
                        [receiptNode.attributes setObject:messageNode.type forKey:@"type"];
                        [receiptNode.attributes setObject:messageNode.from forKey:@"to"];
                        [receiptNode setXmppId:[[NSUUID UUID] UUIDString]];
                        [receiptNode setReceipt:messageNode.idval];
                        [receiptNode setStoreHint];
                        [self send:receiptNode];
                    }

                    void(^notify)(BOOL) = ^(BOOL success) {
                        if(messageNode.from)
                        {
                            MLMessage* message = [self parseMessageToMLMessage:messageNode withBody:body andEncrypted:encrypted andShowAlert:showAlert andMessageType:newMessageType];

                            DDLogInfo(@"sending out kMonalNewMessageNotice notification");
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalNewMessageNotice object:self userInfo:@{@"message":message}];
                        }
                        else
                            DDLogInfo(@"no messageNode.from, not notifying");
                    };

                    if(![messageNode.from isEqualToString:self.connectionProperties.identity.jid])
                        notify([[DataLayer sharedInstance] addActiveBuddies:messageNode.from forAccount:self.accountNo]);
                    else
                        notify([[DataLayer sharedInstance] addActiveBuddies:messageNode.to forAccount:self.accountNo]);
                }
                else
                    DDLogError(@"error adding message");
            };
            //only process mam results when they are not for priming the database with the initial stanzaid (the id will be taken from the iq result)
            //we do this because we don't want to randomly add one single message to our history db after the user installs the app / adds a new account
            //if the user wants to see older messages he can retrieve them using the ui
            if(!(messageNode.mamResult && [messageNode.mamQueryId hasPrefix:@"MLignore:"]))
                [messageProcessor processMessage:messageNode];
            
            //add newest stanzaid to database *after* processing the message, but only for non-mam messages or mam catchup
            //(e.g. those messages going forward in time not backwards)
            if(messageNode.stanzaId && (!messageNode.mamResult || [messageNode.mamQueryId hasPrefix:@"MLcatchup:"]))
            {
                DDLogVerbose(@"Updating lastStanzaId in database to: %@", messageNode.stanzaId);
                [[DataLayer sharedInstance] setLastStanzaId:messageNode.stanzaId forAccount:self.accountNo];
            }
            
            //only mark stanza as handled *after* processing it
            [self incrementLastHandledStanza];
        }
        else if([parsedStanza.stanzaType  isEqualToString:@"presence"] && [parsedStanza isKindOfClass:[ParsePresence class]])
        {
            ParsePresence* presenceNode = (ParsePresence*)parsedStanza;
            NSString *recipient = presenceNode.to;

            //set own jid as recipient, if none given
            if(!recipient)
                recipient = self.connectionProperties.identity.jid;

            if([presenceNode.user isEqualToString:self.connectionProperties.identity.jid])
            {
                //ignore self presences for now
            }
            else
            {
                if([presenceNode.type isEqualToString:kpresencesSubscribe])
                {
                    MLContact *contact = [[MLContact alloc] init];
                    contact.accountId=self.accountNo;
                    contact.contactJid=presenceNode.user;

                    [[DataLayer sharedInstance] addContactRequest:contact];
                }

                if(presenceNode.MUC)
                {
                    for(NSString* code in presenceNode.statusCodes)
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

                    if([presenceNode.type isEqualToString:kpresenceUnavailable])
                    {
                        //handle this differently later
                        return;
                    }
                }

                if(presenceNode.type==nil)
                {
                    DDLogVerbose(@"presence notice from %@", presenceNode.user);

                    if(presenceNode.user!=nil && presenceNode.user.length>0)
                    {
                        MLContact *contact = [[MLContact alloc] init];
                        contact.accountId=self.accountNo;
                        contact.contactJid=presenceNode.user;
                        contact.state=presenceNode.show;
                        contact.statusMessage=presenceNode.status;

                        //add contact if possible (ignore already existing contacts)
                        [[DataLayer sharedInstance] addContact:[presenceNode.user copy] forAccount:self.accountNo fullname:@"" nickname:@"" andMucNick:nil];

                        //update buddy state
                        [[DataLayer sharedInstance] setOnlineBuddy:presenceNode forAccount:self.accountNo];
                        [[DataLayer sharedInstance] setBuddyState:presenceNode forAccount:self.accountNo];
                        [[DataLayer sharedInstance] setBuddyStatus:presenceNode forAccount:self.accountNo];

                        //handle last interaction time (dispatch database update in own background thread)
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            [[DataLayer sharedInstance] setLastInteraction:presenceNode.since forJid:presenceNode.user andAccountNo:self.accountNo];
                        });
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            [[NSNotificationCenter defaultCenter] postNotificationName:kMonalLastInteractionUpdatedNotice object:self userInfo:@{
                                @"jid": presenceNode.user,
                                @"accountNo": self.accountNo,
                                @"lastInteraction": presenceNode.since ? presenceNode.since : [[NSDate date] initWithTimeIntervalSince1970:0],    //nil cannot directly be saved in NSDictionary
                                @"isTyping": @NO
                            }];
                        });

                        if(!presenceNode.MUC)
                        {
                            //check for vcard change
                            if(presenceNode.photoHash)
                            {
                                NSString* iconHash = [[DataLayer sharedInstance]  contactHash:[presenceNode.user copy] forAccount:self.accountNo];
                                if([presenceNode.photoHash isEqualToString:iconHash])
                                {
                                    DDLogVerbose(@"photo hash is the  same");
                                }
                                else
                                {
                                    [[DataLayer sharedInstance] setContactHash:presenceNode forAccount:self.accountNo];
                                    [self getVCard:presenceNode.user];
                                }
                            }
                        }
                    }
                    else
                    {
                        DDLogError(@"ERROR: presence notice but no user name.");
                    }
                }
                else if([presenceNode.type isEqualToString:kpresenceUnavailable])
                {
                    [[DataLayer sharedInstance] setOfflineBuddy:presenceNode forAccount:self.accountNo];
                }

                //handle entity capabilities (this has to be done *after* setOnlineBuddy which sets the ver hash for the resource to "")
                if(presenceNode.capsHash && presenceNode.user && [presenceNode.user length]>0 && presenceNode.resource && [presenceNode.resource length]>0)
                {
                    NSString* ver = [[DataLayer sharedInstance] getVerForUser:presenceNode.user andResource:presenceNode.resource];
                    if(!ver || ![ver isEqualToString:presenceNode.capsHash])     //caps hash of resource changed
                        [[DataLayer sharedInstance] setVer:presenceNode.capsHash forUser:presenceNode.user andResource:presenceNode.resource];

                    if(![[DataLayer sharedInstance] getCapsforVer:presenceNode.capsHash])
                    {
                        DDLogInfo(@"Presence included unknown caps hash %@, querying disco", presenceNode.capsHash);
                        XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
                        [discoInfo setiqTo:presenceNode.from];
                        [discoInfo setDiscoInfoNode];
                        [self send:discoInfo];
                    }
                }

            }
            
            //only mark stanza as handled *after* processing it
            [self incrementLastHandledStanza];
        }
        else if([parsedStanza.stanzaType isEqualToString:@"enabled"] && [parsedStanza isKindOfClass:[ParseEnabled class]])
        {
            NSMutableArray* stanzas;
            @synchronized(_smacksSyncPoint) {
                //save old unAckedStanzas queue before it is cleared
                stanzas = self.unAckedStanzas;

                //init smacks state (this clears the unAckedStanzas queue)
                [self initSM3];

                //save streamID if resume is supported
                ParseEnabled* enabledNode = (ParseEnabled*)parsedStanza;
                if(enabledNode.resume)
                    self.streamID = enabledNode.streamID;
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
        else if([parsedStanza.stanzaType isEqualToString:@"r"] && [parsedStanza isKindOfClass:[ParseR class]] &&
            self.connectionProperties.supportsSM3 && self.accountState>=kStateBound)
        {
            [self sendSMAck:YES];
        }
        else if([parsedStanza.stanzaType isEqualToString:@"a"] && [parsedStanza isKindOfClass:[ParseA class]] &&
            self.connectionProperties.supportsSM3 && self.accountState>=kStateBound)
        {
            ParseA* aNode = (ParseA*)parsedStanza;

            @synchronized(_smacksSyncPoint) {
                //remove acked messages
                [self removeAckedStanzasFromQueue:aNode.h];

                self.smacksRequestInFlight=NO;			//ack returned
                [self requestSMAck:NO];					//request ack again (will only happen if queue is not empty)
            }
        }
        else if([parsedStanza.stanzaType isEqualToString:@"resumed"] && [parsedStanza isKindOfClass:[ParseResumed class]])
        {
            ParseResumed* resumeNode = (ParseResumed*)parsedStanza;
            self.resuming = NO;

            //now we are bound again
            _accountState = kStateBound;
            _connectedTime = [NSDate date];
            _usableServersList = [[NSMutableArray alloc] init];       //reset list to start again with the highest SRV priority on next connect
            _exponentialBackoff = 0;

            @synchronized(_smacksSyncPoint) {
                //remove already delivered stanzas and resend the (still) unacked ones
                [self removeAckedStanzasFromQueue:resumeNode.h];
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

            @synchronized(_smacksSyncPoint) {
                //signal finished catchup if our current outgoing stanza counter is acked, this introduces an additional roundtrip to make sure
                //all stanzas the *server* wanted to replay have been received, too
                //request an ack to accomplish this if stanza replay did not already trigger one (smacksRequestInFlight is false if replay did not trigger one)
                if(!self.smacksRequestInFlight)
                    [self requestSMAck:YES];    //force sending of the request even if the smacks queue is empty (needed to always trigger the smacks handler below after 1 RTT)
                [self addSmacksHandler:^{
                    if(!_catchupDone)
                    {
                        _catchupDone = YES;
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalFinishedCatchup object:self];
                    }
                }];
            }

            [self postConnectNotification];
        }
        else if([parsedStanza.stanzaType isEqualToString:@"failed"] && [parsedStanza isKindOfClass:[ParseFailed class]]) // smacks resume or smacks enable failed
        {
            if(self.resuming)   //resume failed
            {
                self.resuming = NO;

                @synchronized(_smacksSyncPoint) {
                    //invalidate stream id
                    self.streamID = nil;
                    //get h value, if server supports smacks revision 1.5.2
                    ParseFailed* failedNode = (ParseFailed*)parsedStanza;
                    DDLogInfo(@"++++++++++++++++++++++++ failed resume: h=%@", failedNode.h);
                    [self removeAckedStanzasFromQueue:failedNode.h];
                    //persist these changes
                    [self persistState];
                }

                //if resume failed. bind  a new resource like normal (supportsSM3 is still YES here but switches to NO on failed enable)
                [self bindResource];
            }
            else        //smacks enable failed
            {
                self.connectionProperties.supportsSM3 = NO;

                //init session and query disco, roster etc.
                [self initSession];

                //resend stanzas still in the outgoing queue and clear it afterwards
                //this happens if the server has internal problems and advertises smacks support
                //but failes to resume the stream as well as to enable smacks on the new stream
                //clean up those stanzas to only include message stanzas because iqs don't survive a session change
                //message duplicates are possible in this scenario, but that's better than dropping messages
                //the self.unAckedStanzas queue is not touched by initSession() above because smacks is disabled at this point
                [self resendUnackedMessageStanzasOnly:self.unAckedStanzas];
            }
        }
        else if([parsedStanza.stanzaType isEqualToString:@"failure"] && [parsedStanza isKindOfClass:[ParseFailure class]])
        {
            ParseFailure* failure = (ParseFailure*)parsedStanza;

            NSString* message = failure.text;
            if(failure.notAuthorized)
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

            if(failure.saslError || failure.notAuthorized)
            {
                [self disconnect];
            }
        }
        else if([parsedStanza.stanzaType isEqualToString:@"challenge"] && [parsedStanza isKindOfClass:[ParseChallenge class]])
        {
            ParseChallenge* challengeNode = (ParseChallenge*)parsedStanza;
            if(challengeNode.saslChallenge && self.accountState<kStateLoggedIn && (self.connectionProperties.server.isDirectTLS || self->_startTLSComplete))
            {
                MLXMLNode* responseXML = [[MLXMLNode alloc] initWithElement:@"response" andNamespace:@"urn:ietf:params:xml:ns:xmpp-sasl"];

                //TODO: implement SCRAM SHA1 and SHA256 based auth

                [self send:responseXML];
                return;
            }
        }
        else if([parsedStanza.stanzaType isEqualToString:@"success"] && [parsedStanza isKindOfClass:[ParseStream class]])
        {
            ParseStream* streamNode = (ParseStream*)parsedStanza;
            //perform logic to handle proceed
            if(streamNode.SASLSuccess && self.accountState<kStateLoggedIn)
            {
                DDLogInfo(@"Got SASL Success");
                self->_accountState = kStateLoggedIn;
                if(_cancelLoginTimer)
                {
                    _cancelLoginTimer();        //we are now logged in --> cancel running login timer
                    _cancelLoginTimer = nil;
                }
                self->_loggedInOnce=YES;
                [self startXMPPStream:YES];
            }
        }
        else if([parsedStanza.stanzaType isEqualToString:@"error"] && [parsedStanza isKindOfClass:[ParseStream class]])
        {
            DDLogWarn(@"Got *SECURE* XMPP stream error: %@ %@ (%@)", parsedStanza.errorType, parsedStanza.errorReason, parsedStanza.errorText);
            NSString *message=[NSString stringWithFormat:@"XMPP stream error: %@", parsedStanza.errorReason];
            if(parsedStanza.errorText && ![parsedStanza.errorText isEqualToString:@""])
                message=[NSString stringWithFormat:@"XMPP stream error %@: %@", parsedStanza.errorReason, parsedStanza.errorText];
            [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self,message ]];

            [self reconnect];
        }
        else if([parsedStanza isKindOfClass:[ParseStream class]] &&
            ([parsedStanza.stanzaType isEqualToString:@"stream"] || [parsedStanza.stanzaType isEqualToString:@"features"]))
        {
            ParseStream* streamNode = (ParseStream*)parsedStanza;

            //prevent reconnect attempt
            if(_accountState<kStateHasStream)
                _accountState=kStateHasStream;
            
            //perform logic to handle stream
            if(self.accountState<kStateLoggedIn)
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
                    //look at menchanisms presented
                    //TODO: implement SCRAM SHA1 and SHA256 based auth
                    if(streamNode.SASLPlain)
                    {
                        NSString* saslplain=[HelperTools encodeBase64WithString: [NSString stringWithFormat:@"\0%@\0%@",  self.connectionProperties.identity.user, self.connectionProperties.identity.password ]];

                        MLXMLNode* saslXML= [[MLXMLNode alloc]init];
                        saslXML.element=@"auth";
                        [saslXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:kXMLNS];
                        [saslXML.attributes setObject: @"PLAIN"forKey: @"mechanism"];

                        saslXML.data=saslplain;
                        [self send:saslXML];
                    }
                    else
                    {
                        //no supported auth mechanism
                        DDLogInfo(@"no supported auth mechanism, disconnecting!");
                        [self disconnect];
                    }
                }
            }
            else
            {
                if(streamNode.supportsClientState)
                {
                    self.connectionProperties.supportsClientState=YES;
                }
                
                if(streamNode.supportsSM3)
                    self.connectionProperties.supportsSM3=YES;
                
                if(streamNode.supportsRosterVer)
                    self.connectionProperties.supportsRosterVersion=YES;
                
                //under rare circumstances/bugs the appex could have changed the smacks state *after* our connect method was called
                //--> load newest saved smacks state to be up to date even in this case
                [self readSmacksStateOnly];
                //test if smacks is supported and allows resume
                if(self.connectionProperties.supportsSM3 && self.streamID)
                {
                    MLXMLNode *resumeNode = [[MLXMLNode alloc] initWithElement:@"resume"];
                    NSDictionary* dic;
                    @synchronized(_smacksSyncPoint) {
                        dic = @{
                            kXMLNS:@"urn:xmpp:sm:3",
                            @"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza],
                            @"previd":self.streamID,
                            
                            @"lastHandledInboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledInboundStanza],
                            @"lastHandledOutboundStanza":[NSString stringWithFormat:@"%@", self.lastHandledOutboundStanza],
                            @"lastOutboundStanza":[NSString stringWithFormat:@"%@", self.lastOutboundStanza],
                            @"unAckedStanzasCount":[NSString stringWithFormat:@"%lu", (unsigned long)[self.unAckedStanzas count]]
                        };
                    }
                    resumeNode.attributes = [dic mutableCopy];
                    self.resuming = YES;      //this is needed to distinguish a failed smacks resume and a failed smacks enable later on
                    [self send:resumeNode];
                }
                else
                    [self bindResource];
            }
        }
        else
        {
            DDLogWarn(@"Ignoring unhandled top-level xml element %@ of parser %@", parsedStanza.stanzaType, parsedStanza);
        }
    }
    //*NO* secure TLS context (yet)
    else
    {
        if([parsedStanza.stanzaType isEqualToString:@"error"] && [parsedStanza isKindOfClass:[ParseStream class]])
        {
            DDLogWarn(@"Got *INSECURE* XMPP stream error: %@ %@ (%@)", parsedStanza.errorType, parsedStanza.errorReason, parsedStanza.errorText);
            NSString *message=[NSString stringWithFormat:@"XMPP stream error: %@", parsedStanza.errorReason];
            if(parsedStanza.errorText && ![parsedStanza.errorText isEqualToString:@""])
                message=[NSString stringWithFormat:@"XMPP stream error %@: %@", parsedStanza.errorReason, parsedStanza.errorText];
            [[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self,message ]];

            [self reconnect];
        }
        else if([parsedStanza isKindOfClass:[ParseStream class]] &&
            ([parsedStanza.stanzaType isEqualToString:@"stream"] || [parsedStanza.stanzaType isEqualToString:@"features"]))
        {
            //ignore streamNode.callStartTLS (e.g. starttls stream feature) presence and opportunistically try starttls
            //(this is in accordance to RFC 7590: https://tools.ietf.org/html/rfc7590#section-3.1 )
            if([parsedStanza.stanzaType isEqualToString:@"features"])
            {
                MLXMLNode* startTLS = [[MLXMLNode alloc] initWithElement:@"starttls" andNamespace:@"urn:ietf:params:xml:ns:xmpp-tls"];
                [self send:startTLS];
                return;
            }
        }
        else if([parsedStanza.stanzaType isEqualToString:@"proceed"] && [parsedStanza isKindOfClass:[ParseStream class]])
        {
            ParseStream* streamNode = (ParseStream*)parsedStanza;
            //perform logic to handle proceed
            if(streamNode.startTLSProceed)
            {
                [_iPipe drainInputStream];      //remove all pending data before starting tls handshake
                [self initTLS];
                self->_startTLSComplete=YES;
                //stop everything coming after this (we don't want to process stanzas that came in *before* a secure TLS context was established!)
                //if we do not do this we could be prone to mitm attacks injecting xml elements into the stream before it gets encrypted
                //such xml elements would then get processed as received *after* the TLS initialization
                [self startXMPPStream:YES];
            }
        }
        else
        {
            DDLogError(@"Ignoring unhandled *INSECURE* top-level xml element %@, reconnecting", parsedStanza.stanzaType);
            [self reconnect];
        }
    }
}

#pragma mark stanza handling

-(void) postConnectNotification
{
    NSDictionary *dic = @{@"AccountNo":self.accountNo, @"AccountName": self.connectionProperties.identity.jid};
    [[NSNotificationCenter defaultCenter] postNotificationName:kMLHasConnectedNotice object:dic];
     [self accountStatusChanged];
}

-(void) sendIq:(XMPPIQ*) iq withResponseHandler:(monal_iq_handler_t) resultHandler andErrorHandler:(monal_iq_handler_t) errorHandler
{
    if(resultHandler || errorHandler)
        @synchronized(_iqHandlers) {
            _iqHandlers[[iq getId]] = @{@"id": [iq getId], @"resultHandler":resultHandler, @"errorHandler":errorHandler, @"invalidateOnDisconnect":@YES};
        }
    [self send:iq];
}

-(void) sendIq:(XMPPIQ*) iq withDelegate:(id) delegate andMethod:(SEL) method andAdditionalArguments:(NSArray*) args
{
    if(delegate && method)
    {
        DDLogVerbose(@"Adding delegate [%@ %@] to iqHandlers...", NSStringFromClass(delegate), NSStringFromSelector(method));
        @synchronized(_iqHandlers) {
            _iqHandlers[[iq getId]] = @{@"id": [iq getId], @"delegate":NSStringFromClass(delegate), @"method":NSStringFromSelector(method), @"arguments":(args ? args : @[]), @"invalidateOnDisconnect":@NO};
        }
    }
    [self send:iq];     //this will also call persistState --> we don't need to do this here explicitly (to make sure our iq delegate is stored to db)
}

-(void) send:(MLXMLNode*) stanza
{
    if(!stanza)
        return;
    
    if(((self.accountState>=kStateBound && self.connectionProperties.supportsSM3) || [self isHibernated]))
    {
        //only count stanzas, not nonzas
        if([stanza.element isEqualToString:@"iq"]
            || [stanza.element isEqualToString:@"message"]
            || [stanza.element isEqualToString:@"presence"])
        {
            MLXMLNode* queued_stanza = [stanza copy];
            if(![queued_stanza.element isEqualToString:@"iq"])
            {
                //check if a delay tag is already present
                BOOL found = NO;
                for(MLXMLNode* child in queued_stanza.children)
                {
                    if([child.element isEqualToString:@"delay"] && [[child.attributes objectForKey:kXMLNS] isEqualToString:@"urn:xmpp:delay"])
                    {
                        found = YES;
                        break;
                    }
                }
                //only add a delay tag if not already present
                if(!found)
                    [queued_stanza addDelayTagFrom:self.connectionProperties.identity.jid];
            }
            @synchronized(_smacksSyncPoint) {
                DDLogVerbose(@"ADD UNACKED STANZA: %@: %@", self.lastOutboundStanza, queued_stanza.XMLString);
                NSDictionary* dic = @{kQueueID:self.lastOutboundStanza, kStanza:queued_stanza};
                [self.unAckedStanzas addObject:dic];
                //increment for next call
                self.lastOutboundStanza = [NSNumber numberWithInteger:[self.lastOutboundStanza integerValue] + 1];
                //persist these changes (this has to be synchronous because we want so pesist sanzas to db before actually sending them)
                [self persistState];
            }
        }
    }
    
    if(self.accountState>kStateDisconnected)
    {
        [_sendQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
            DDLogDebug(@"SEND: %@", stanza.XMLString);
            [_outputQueue addObject:stanza];
            [self writeFromQueue];      // try to send if there is space
        }]];
    }
}

#pragma mark messaging

-(void) sendMessage:(NSString*) message toContact:(NSString*) contact isMUC:(BOOL) isMUC isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString *) messageId
{
    XMPPMessage* messageNode =[[XMPPMessage alloc] init];
    [messageNode.attributes setObject:contact forKey:@"to"];
    [messageNode setXmppId:messageId ];

#ifndef DISABLE_OMEMO
    // [encryptMessage:messageNode withMessage:message isMuc:isMuc toContact:contact fromSender:self.connectionProperties.identity.jid]
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

        MLXMLNode *request =[[MLXMLNode alloc] initWithElement:@"request"];
        [request.attributes setObject:@"urn:xmpp:receipts" forKey:kXMLNS];
        [messageNode.children addObject:request];
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
        [messageNode.children addObject:chatstate];
    }
    else
    {
        MLXMLNode* chatstate = [[MLXMLNode alloc] initWithElement:@"active" andNamespace:@"http://jabber.org/protocol/chatstates"];
        [messageNode.children addObject:chatstate];
    }
    [self send:messageNode];
}

#pragma mark set connection attributes

-(void) persistState
{
    //state dictionary
    NSMutableDictionary* values = [[NSMutableDictionary alloc] init];

    //collect smacks state
    @synchronized(_smacksSyncPoint) {
        [values setValue:self.lastHandledInboundStanza forKey:@"lastHandledInboundStanza"];
        [values setValue:self.lastHandledOutboundStanza forKey:@"lastHandledOutboundStanza"];
        [values setValue:self.lastOutboundStanza forKey:@"lastOutboundStanza"];
        [values setValue:[self.unAckedStanzas copy] forKey:@"unAckedStanzas"];
        [values setValue:self.streamID forKey:@"streamID"];
    }

    NSMutableDictionary* persistentIqHandlers = [[NSMutableDictionary alloc] init];
    @synchronized(_iqHandlers) {
        [_iqHandlers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            NSString* id = (NSString*)key;
            NSDictionary* data = (NSDictionary*)obj;
            //only serialize persistent handlers with delegate and method
            if([data[@"invalidateOnDisconnect"] isEqual:@NO] && data[@"delegate"] && data[@"method"])
            {
                DDLogVerbose(@"saving serialized iq handler for iq '%@'", id);
                [persistentIqHandlers setObject:data forKey:id];
            }
        }];
    }
    [values setObject:persistentIqHandlers forKey:@"iqHandlers"];

    [values setValue:[self.connectionProperties.serverFeatures copy] forKey:@"serverFeatures"];
    if(self.connectionProperties.uploadServer) {
        [values setObject:self.connectionProperties.uploadServer forKey:@"uploadServer"];
    }
    if(self.connectionProperties.conferenceServer) {
        [values setObject:self.connectionProperties.conferenceServer forKey:@"conferenceServer"];
    }

    [values setObject:[NSNumber numberWithBool:_loggedInOnce] forKey:@"loggedInOnce"];
    [values setObject:[NSNumber numberWithBool:self.connectionProperties.usingCarbons2] forKey:@"usingCarbons2"];
    [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPush] forKey:@"supportsPush"];
    [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsClientState] forKey:@"supportsClientState"];
    [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsMam2] forKey:@"supportsMAM"];
    [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPubSub] forKey:@"supportsPubSub"];
    [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsHTTPUpload] forKey:@"supportsHTTPUpload"];
    [values setObject:[NSNumber numberWithBool:self.connectionProperties.supportsPing] forKey:@"supportsPing"];

    if(self.connectionProperties.discoveredServices)
    {
        [values setObject:[self.connectionProperties.discoveredServices copy] forKey:@"discoveredServices"];
    }

    [values setObject:_lastInteractionDate forKey:@"lastInteractionDate"];
    [values setValue:[NSDate date] forKey:@"stateSavedAt"];

    //save state dictionary
    [[DataLayer sharedInstance] persistState:values forAccount:self.accountNo];

    //debug output
    @synchronized(_smacksSyncPoint) {
        DDLogVerbose(@"persistState(saved at %@):\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@\n\tlastInteractionDate=%@\n\tpersistentIqHandlers=%@",
            values[@"stateSavedAt"],
            self.lastHandledInboundStanza,
            self.lastHandledOutboundStanza,
            self.lastOutboundStanza,
            self.unAckedStanzas ? [self.unAckedStanzas count] : 0, self.unAckedStanzas ? "" : " (NIL)",
            self.streamID,
            _lastInteractionDate,
            persistentIqHandlers
        );
    }
}

-(void) readSmacksStateOnly
{
    NSMutableDictionary* dic = [[DataLayer sharedInstance] readStateForAccount:self.accountNo];
    if(dic)
    {
        //collect smacks state
        @synchronized(_smacksSyncPoint) {
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
                    DDLogDebug(@"readSmacksStateOnly unAckedStanza %@: %@", [dic objectForKey:kQueueID], ((MLXMLNode*)[dic objectForKey:kStanza]).XMLString);
            
            //always reset handler and smacksRequestInFlight when loading smacks state
            _smacksAckHandler = [[NSMutableArray alloc] init];
            self.smacksRequestInFlight = NO;
        }
    }
}

-(void) readState
{
    NSMutableDictionary* dic = [[DataLayer sharedInstance] readStateForAccount:self.accountNo];
    if(dic)
    {
        //collect smacks state
        @synchronized(_smacksSyncPoint) {
            self.lastHandledInboundStanza = [dic objectForKey:@"lastHandledInboundStanza"];
            self.lastHandledOutboundStanza = [dic objectForKey:@"lastHandledOutboundStanza"];
            self.lastOutboundStanza = [dic objectForKey:@"lastOutboundStanza"];
            NSArray* stanzas = [dic objectForKey:@"unAckedStanzas"];
            self.unAckedStanzas = [stanzas mutableCopy];
            self.streamID = [dic objectForKey:@"streamID"];
        }
        
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
        if(self.connectionProperties.uploadServer)
            self.connectionProperties.supportsHTTPUpload = YES;
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

        //debug output
        @synchronized(_smacksSyncPoint) {
            DDLogVerbose(@"readState(saved at %@):\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%lu%s,\n\tstreamID=%@,\n\tlastInteractionDate=%@\n\tpersistentIqHandlers=%@",
                dic[@"stateSavedAt"],
                self.lastHandledInboundStanza,
                self.lastHandledOutboundStanza,
                self.lastOutboundStanza,
                self.unAckedStanzas ? [self.unAckedStanzas count] : 0, self.unAckedStanzas ? "" : " (NIL)",
                self.streamID,
                _lastInteractionDate,
                persistentIqHandlers
            );
            if(self.unAckedStanzas)
                for(NSDictionary* dic in self.unAckedStanzas)
                    DDLogDebug(@"readState unAckedStanza %@: %@", [dic objectForKey:kQueueID], ((MLXMLNode*)[dic objectForKey:kStanza]).XMLString);
        }
    }
    
    @synchronized(_smacksSyncPoint) {
        //always reset handler and smacksRequestInFlight when loading smacks state
        _smacksAckHandler = [[NSMutableArray alloc] init];
        self.smacksRequestInFlight = NO;
    }
}

-(void) incrementLastHandledStanza {
    if(self.connectionProperties.supportsSM3 && self.accountState>=kStateBound)
    {
        @synchronized(_smacksSyncPoint) {
            self.lastHandledInboundStanza = [NSNumber numberWithInteger: [self.lastHandledInboundStanza integerValue]+1];
            [self persistState];
        }
    }
}

-(void) initSM3
{
    //initialize smacks state
    @synchronized(_smacksSyncPoint) {
        self.lastHandledInboundStanza = [NSNumber numberWithInteger:0];
        self.lastHandledOutboundStanza = [NSNumber numberWithInteger:0];
        self.lastOutboundStanza = [NSNumber numberWithInteger:0];
        self.unAckedStanzas = [[NSMutableArray alloc] init];
        self.streamID = nil;
        _smacksAckHandler = [[NSMutableArray alloc] init];
        DDLogDebug(@"initSM3 done");
    }
}

-(void) bindResource
{
    _accountState = kStateBinding;
    XMPPIQ* iqNode =[[XMPPIQ alloc] initWithType:kiqSetType];
    [iqNode setBindWithResource:self.connectionProperties.identity.resource];
    [self send:iqNode];
}

-(void) queryDisco
{
    XMPPIQ* discoItems = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoItems setiqTo:self.connectionProperties.identity.domain];
    [discoItems setDiscoItemNode];
    [self send:discoItems];

    XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
    [discoInfo setiqTo:self.connectionProperties.identity.domain];
    [discoInfo setDiscoInfoNode];
    [self send:discoInfo];
}


-(void) sendPresence
{
    //don't send presences if we are not bound
    if(_accountState < kStateBound)
        return;

    XMPPPresence* presence=[[XMPPPresence alloc] initWithHash:_versionHash];
    if(self.statusMessage) [presence setStatus:self.statusMessage];
    if(self.awayState) [presence setAway];
    
    //send last interaction date if not currently active
    // && the user prefers to send out lastInteraction date
    if(!_isCSIActive && self.sendIdleNotifications)
        [presence setLastInteraction:_lastInteractionDate];
    
    [self send:presence];
}

-(void) fetchRoster
{
    XMPPIQ* roster=[[XMPPIQ alloc] initWithType:kiqGetType];
    NSString *rosterVer;
    if(self.connectionProperties.supportsRosterVersion)
    {
        rosterVer=[[DataLayer sharedInstance] getRosterVersionForAccount:self.accountNo];
    }
    [roster setRosterRequest:rosterVer];

    [self send:roster];
}


-(void) initSession
{
    //delete old resources because we get new presences once we're done initializing the session
    [[DataLayer sharedInstance] resetContactsForAccount:self.accountNo];
    
    //we are now bound
    _accountState = kStateBound;
    _connectedTime = [NSDate date];
    [self postConnectNotification];
    _usableServersList = [[NSMutableArray alloc] init];       //reset list to start again with the highest SRV priority on next connect
    _exponentialBackoff = 0;
    _iqHandlers = [[NSMutableDictionary alloc] init];

    XMPPIQ* sessionQuery= [[XMPPIQ alloc] initWithType:kiqSetType];
    MLXMLNode* session = [[MLXMLNode alloc] initWithElement:@"session"];
    [session setXMLNS:@"urn:ietf:params:xml:ns:xmpp-session"];
    [sessionQuery.children addObject:session];
    [self send:sessionQuery];

    //force new disco queries because we landed here because of a failed smacks resume
    //(or the account got forcibly disconnected/reconnected or this is the very first login of this account)
    //--> all of this reasons imply that we had to start a new xmpp stream and our old cached disco data
    //    and other state values are stale now
    //(smacks state will be reset/cleared later on if appropriate, no need to handle smacks here)
    self.connectionProperties.serverFeatures=nil;
    self.connectionProperties.discoveredServices=nil;
    self.connectionProperties.uploadServer=nil;
    self.connectionProperties.conferenceServer=nil;
    self.connectionProperties.usingCarbons2=NO;
    self.connectionProperties.supportsPush=NO;
    self.connectionProperties.supportsClientState=NO;
    self.connectionProperties.supportsMam2=NO;
    self.connectionProperties.supportsPubSub=NO;
    self.connectionProperties.supportsHTTPUpload=NO;
    self.connectionProperties.supportsPing=NO;

    //now fetch roster, request disco and send initial presence
    [self fetchRoster];
    [self queryDisco];
    [self sendPresence];
    [self sendCurrentCSIState];
    
    //mam query will be done in MLIQProcessor once the disco result returns
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

-(void) getVcards
{
    for (NSDictionary *dic in self.rosterList)
    {
        NSArray* result = [[DataLayer sharedInstance] contactForUsername:[dic objectForKey:@"jid"] forAccount:self.accountNo];
        MLContact *row = result.firstObject;
        if (row.fullName.length==0)
        {
            [self getVCard:row.contactJid];
        }
    }

}

-(void)getVCard:(NSString *) user
{
    XMPPIQ* iqVCard= [[XMPPIQ alloc] initWithType:kiqGetType];
    [iqVCard getVcardTo:user];
    [self send:iqVCard];
}

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

#pragma mark query info

-(void) getServiceDetails
{
    if(_hasRequestedServerInfo)
        return;  // no need to call again on disconnect

    if(!self.connectionProperties.discoveredServices)
    {
        DDLogInfo(@"no discovered services");
        return;
    }

    for (NSDictionary *item in self.connectionProperties.discoveredServices)
    {
        XMPPIQ* discoInfo = [[XMPPIQ alloc] initWithType:kiqGetType];
        NSString* jid = [item objectForKey:@"jid"];
        if(jid)
        {
            [discoInfo setiqTo:jid];
            [discoInfo setDiscoInfoNode];
            [self send:discoInfo];

            _hasRequestedServerInfo=YES;
        } else
        {
            DDLogError(@"no jid on info");
        }
    }
}

-(BOOL) isHibernated
{
    BOOL hibernated = (_accountState < kStateReconnecting);
    hibernated &= (_streamID != nil);
    return hibernated;
}


#pragma mark HTTP upload

-(void) requestHTTPSlotWithParams:(NSDictionary*) params andCompletion:(void(^)(NSString *url,  NSError *error)) completion
{
    XMPPIQ* httpSlotRequest = [[XMPPIQ alloc] initWithType:kiqGetType];
    [httpSlotRequest setiqTo:self.connectionProperties.uploadServer];
    [httpSlotRequest
        httpUploadforFile:[params objectForKey:kFileName]
        ofSize:[NSNumber numberWithInteger:((NSData*)[params objectForKey:kData]).length]
        andContentType:[params objectForKey:kContentType]
    ];
    [self sendIq:httpSlotRequest withResponseHandler:^(ParseIq* response) {
        DDLogInfo(@"Got slot for upload: %@", response.getURL);
        //upload to server using HTTP PUT
        NSMutableDictionary* headers = [[NSMutableDictionary alloc] init];
        [headers addEntriesFromDictionary:@{@"Content-Type":[params objectForKey:kContentType]}];
        [headers addEntriesFromDictionary:response.uploadHeaders];
        dispatch_async(dispatch_get_main_queue(), ^{
            [MLHTTPRequest
                sendWithVerb:kPut path:response.putURL
                headers:headers
                withArguments:nil
                data:[params objectForKey:kData]
                andCompletionHandler:^(NSError *error, id result) {
                    if(!error)
                    {
                        DDLogInfo(@"Upload succeded, get url: %@", response.getURL);
                        //send get url to contact
                        if(completion)
                            completion(response.getURL, nil);
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
    } andErrorHandler:^(ParseIq* error) {
        if(completion)
            completion(nil, error.errorMessage);
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
    [self send:query];
}

-(void) setMAMQueryMostRecentForJid:(NSString*) jid before:(NSString*) uid withCompletion:(void (^)(NSArray* _Nullable)) completion
{
    NSMutableArray* __block messageList = [[NSMutableArray alloc] init];
    monal_iq_handler_t __block responseHandler;
    __block void (^query)(NSString* before);
    responseHandler = ^(ParseIq* response) {
        //insert messages having a body into the db and check if they are alread in there
        for(MLMessage* msg in [self getOrderedMamPageFor:response.mamQueryId])
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
                                            withCompletion:^(BOOL success, NSString* newMessageType) {
                    //add successfully added messages to our display list
                    if(success)
                        [messageList addObject:msg];
                }];
        DDLogVerbose(@"collected mam:2 before-pages now contain %d messages in summary not already in history", [messageList count]);
        //call completion to display all messages saved in db if we have enough messages or reached end of mam archive
        if([messageList count] >= 25)
            completion(messageList);
        else
        {
            //page through to get more messages (a page possibly contians fewer than 25 messages having a body)
            //but because we query for 50 stanzas we easily could get more than 25 messages having a body, too
            if(response.mam2First && !response.mam2fin)
                query(response.mam2First);
            else
            {
                DDLogVerbose(@"Reached upper end of mam:2 archive, returning %d messages to ui", [messageList count]);
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
        [self sendIq:query withResponseHandler:responseHandler andErrorHandler:^(ParseIq* error) {
            DDLogWarn(@"Got mam:2 before-query error, returning %d messages to ui", [messageList count]);
            if(![messageList count])
                completion(nil);            //call completion with nil, if there was an error or xmpp reconnect that prevented us to get any messages
            else
                completion(messageList);    //we had an error but did already load some messages --> update ui anyways
        }];
    };
    query(uid);
}

#pragma mark - MUC

-(void) getConferenceRooms
{
    if(self.connectionProperties.conferenceServer && !_roomList)
    {
        XMPPIQ *discoInfo =[[XMPPIQ alloc] initWithType:kiqGetType];
        [discoInfo setiqTo:self.connectionProperties.conferenceServer];
        [discoInfo setDiscoInfoNode];
        [self send:discoInfo];
    }
    else
    {
        if(!self.connectionProperties.conferenceServer)
            DDLogInfo(@"no conference server discovered");
        if(_roomList)
            [[NSNotificationCenter defaultCenter] postNotificationName:kMLHasRoomsNotice object:self];
    }
}


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

-(void) jingleResult:(ParseIq *) iqNode {
    //confirmation of set call after we accepted
    if([iqNode.idval isEqualToString:self.jingle.idval])
    {
        NSString* from = iqNode.user;
        NSString* fullName = [[DataLayer sharedInstance] fullNameForContact:from inAccount:self.accountNo];
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


-(void) processJingleSetIq:(ParseIq *) iqNode {
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

}


#pragma mark - account management

-(void) changePassword:(NSString *) newPass withCompletion:(xmppCompletion) completion
{
    XMPPIQ* iq =[[XMPPIQ alloc] initWithType:kiqSetType];
    [iq setiqTo:self.connectionProperties.identity.domain];
    [iq changePasswordForUser:self.connectionProperties.identity.user newPassword:newPass];
    [self sendIq:iq withResponseHandler:^(ParseIq* response) {
        //dispatch completion handler outside of the receiveQueue
        if(completion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(YES, @"");
            });
    } andErrorHandler:^(ParseIq* error) {
        //dispatch completion handler outside of the receiveQueue
        if(completion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                completion(NO, error ? error.errorMessage : @"");
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

    [self sendIq:iq withResponseHandler:^(ParseIq* result) {
        //dispatch completion handler outside of the receiveQueue
        if(_regFormCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                _regFormCompletion(result.captchaData, result.hiddenFormFields);
            });
    } andErrorHandler:^(ParseIq* error) {
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

    [self sendIq:iq withResponseHandler:^(ParseIq* result) {
        //dispatch completion handler outside of the receiveQueue
        if(_regFormSubmitCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                _regFormSubmitCompletion(YES, nil);
            });
    } andErrorHandler:^(ParseIq* error) {
        //dispatch completion handler outside of the receiveQueue
        if(_regFormSubmitCompletion)
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                _regFormSubmitCompletion(NO, error.errorMessage);
            });
    }];
}

#pragma mark - nsstream delegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    DDLogVerbose(@"Stream has event");
    switch(eventCode)
    {
        case NSStreamEventOpenCompleted:
        {
            DDLogVerbose(@"Stream open completed");
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
        BOOL success=[self writeToStream:node.XMLString];
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
        self.accountState>=kStateBound && self.connectionProperties.supportsPush &&
        self.pushNode!=nil && [self.pushNode length]>0 &&
        self.pushSecret!=nil && [self.pushSecret length]>0
    )
    {
        DDLogInfo(@"ENABLING PUSH: %@ < %@", self.pushNode, self.pushSecret);
        XMPPIQ* enable =[[XMPPIQ alloc] initWithType:kiqSetType];
        [enable setPushEnableWithNode:self.pushNode andSecret:self.pushSecret];
        [self send:enable];
        self.connectionProperties.pushEnabled=YES;
    }
    else
    {
        DDLogInfo(@" NOT enabling push: %@ < %@ (accountState: %d, supportsPush: %@)", self.pushNode, self.pushSecret, self.accountState, self.connectionProperties.supportsPush ? @"YES" : @"NO");
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

-(MLMessage* _Nonnull) parseMessageToMLMessage:(ParseMessage* _Nonnull) messageNode withBody:(NSString*_Nonnull) body andEncrypted:(BOOL) encrypted andShowAlert:(BOOL) showAlert andMessageType:(NSString* _Nonnull) messageType
{
    NSString* actuallyFrom = messageNode.actualFrom;
    if(!actuallyFrom)
        actuallyFrom = messageNode.from;
    MLMessage *message = [[MLMessage alloc] init];
    message.from = messageNode.from;
    message.actualFrom = actuallyFrom;
    message.messageText = [body copy];     //this need to be the processed value since it may be decrypted
    message.to = messageNode.to ? messageNode.to : self.connectionProperties.identity.jid;
    message.messageId = messageNode.idval ? messageNode.idval : @"";
    message.accountId = self.accountNo;
    message.encrypted = encrypted;
    message.delayTimeStamp = messageNode.delayTimeStamp;
    message.timestamp = [NSDate date];
    message.shouldShowAlert = showAlert;
    message.messageType = messageType;
    message.hasBeenSent = YES;      //if it came in it has been sent to the server
    message.stanzaId = messageNode.stanzaId;
    return message;
}

-(void) addMessageToMamPageArray:(ParseMessage* _Nonnull) messageNode withBody:(NSString* _Nonnull) body andEncrypted:(BOOL) encrypted andShowAlert:(BOOL) showAlert andMessageType:(NSString* _Nonnull) messageType
{
    MLMessage* message = [self parseMessageToMLMessage:messageNode withBody:body andEncrypted:encrypted andShowAlert:showAlert andMessageType:messageType];
    @synchronized(_mamPageArrays) {
        if(!_mamPageArrays[messageNode.mamQueryId])
            _mamPageArrays[messageNode.mamQueryId] = [[NSMutableArray alloc] init];
        [_mamPageArrays[messageNode.mamQueryId] addObject:message];
    }
}

-(NSArray* _Nullable) getOrderedMamPageFor:(NSString* _Nonnull) mamQueryId
{
    NSMutableArray* array;
    @synchronized(_mamPageArrays) {
        if(!_mamPageArrays[mamQueryId])
            return @[];     //return empty array if nothing can be found (after app crash etc.)
        array = _mamPageArrays[mamQueryId];
        [_mamPageArrays removeObjectForKey:mamQueryId];
    }
    if([mamQueryId hasPrefix:@"MLhistory:"])
        array = [[array reverseObjectEnumerator] allObjects];
    return [array copy];        //this creates an unmutable array from the mutable one
}

@end
