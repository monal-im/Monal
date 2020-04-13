//
//  xmpp.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <Network/Network.h>
#import <CommonCrypto/CommonCrypto.h>

#import "xmpp.h"
#import "DataLayer.h"
#import "EncodingTools.h"
#import "MLXMPPManager.h"

#import "MLImageManager.h"

//XMPP objects
#import "XMPPIQ.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"

#import "MLXMLNode.h"

//parsers
#import "ParseStream.h"
#import "ParseIq.h"
#import "ParsePresence.h"
#import "ParseMessage.h"
#import "ParseChallenge.h"
#import "ParseFailure.h"
#import "ParseEnabled.h"
#import "ParseA.h"
#import "ParseResumed.h"
#import "ParseFailed.h"

//processors
#import "MLMessageProcessor.h"
#import "MLIQProcessor.h"
#import "MLPresenceProcessor.h"

#import "MLHTTPRequest.h"
#import "AESGcm.h"

#define kXMPPReadSize 5120 // bytes

#define kConnectTimeout 20ull //seconds
#define kPingTimeout 120ull //seconds



NSString *const kMessageId=@"MessageID";
NSString *const kSendTimer=@"SendTimer";

NSString *const kStanzaID=@"stanzaID";
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
    nw_connection_t _connection;
    NSMutableData* _inputDataBuffer;
    NSMutableString* _inputBuffer;
    NSMutableArray* _outputQueue;
    
    NSArray* _stanzaTypes;
    
    BOOL _startTLSComplete;
    BOOL _ConnectionSendIsLooping;
    BOOL _stopConnectionSendLoop;
    BOOL _stopConnectionReceiveLoop;
    
    //does not reset at disconnect
    BOOL _loggedInOnce;
    BOOL _hasRequestedServerInfo;
    
}

@property (nonatomic, assign) BOOL smacksRequestInFlight;

@property (nonatomic, assign) BOOL loginStarted;
@property (nonatomic, assign) BOOL reconnectScheduled;

@property (nonatomic ,strong) NSDate *loginStartTimeStamp;

@property (nonatomic, strong) NSString *pingID;
@property (nonatomic, strong) NSOperationQueue *receiveQueue;
@property (nonatomic, strong) NSOperationQueue *sendQueue;

//HTTP upload
@property (nonatomic, strong) NSMutableArray *httpUploadQueue;


@property (nonatomic, assign) BOOL resuming;
@property (nonatomic, strong) NSString *streamID;

@property (nonatomic, assign) BOOL hasDiscoAndRoster;

/**
 h to go out in r stanza
 */
@property (nonatomic, strong) NSNumber *lastHandledInboundStanza;

/**
 h from a stanza
 */
@property (nonatomic, strong) NSNumber *lastHandledOutboundStanza;

/**
 internal counter that should match lastHandledOutboundStanza
 */
@property (nonatomic, strong) NSNumber *lastOutboundStanza;

/**
 Array of NSdic with stanzas that have not been acked.
 NSDic {stanzaID, stanza}
 */
@property (nonatomic, strong) NSMutableArray *unAckedStanzas;

@property (nonatomic, strong) dispatch_source_t loginCancelOperation;


@property (nonatomic, strong) NSMutableDictionary *xmppCompletionHandlers;
@property (nonatomic, strong) xmppCompletion loginCompletion;
@property (nonatomic, strong) xmppCompletion regFormSubmitCompletion;

/**
 ID of the signal device query
 */
@property (nonatomic, strong) NSString *deviceQueryId;

@end

@implementation xmpp

-(void) setupObjects
{
    _accountState = kStateLoggedOut;
    
    _discoveredServersList=[[NSMutableArray alloc] init];
	if(!_usableServersList)
		_usableServersList=[[NSMutableArray alloc] init];
    _inputDataBuffer=[[NSMutableData alloc] init];
    _inputBuffer=[[NSMutableString alloc] init];
    _outputQueue=[[NSMutableArray alloc] init];
    
    self.receiveQueue=[[NSOperationQueue alloc] init];
    self.receiveQueue.name=@"ReceiveQueue";
    self.receiveQueue.qualityOfService=NSQualityOfServiceUtility;
    self.receiveQueue.maxConcurrentOperationCount=1;
    
    self.sendQueue=[[NSOperationQueue alloc] init];
    self.sendQueue.name=@"SendQueue";
    self.sendQueue.qualityOfService=NSQualityOfServiceUtility;
    self.sendQueue.maxConcurrentOperationCount=1;
    
    //placing more common at top to reduce iteration
    _stanzaTypes=[NSArray arrayWithObjects:
                  @"a", // one of the most frequent
                  @"iq",
                  @"message",
                  @"presence",
                  @"stream:stream",
                  @"stream:error",
                  @"stream",
                  @"csi",
                  @"features",
                  @"proceed",
                  @"failure",
                  @"challenge",
                  @"response",
                  @"success",
                  @"enabled",
                  @"resumed", // should be before r since that will match many things
                  @"failed",
                  @"r",
                  nil];
    
    
    _versionHash=[self getVersionString];
    
    
    self.priority=[[[NSUserDefaults standardUserDefaults] stringForKey:@"XMPPPriority"] integerValue];
    self.statusMessage=[[NSUserDefaults standardUserDefaults] stringForKey:@"StatusMessage"];
    self.awayState=[[NSUserDefaults standardUserDefaults] boolForKey:@"Away"];
    
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"Visible"]){
        self.visibleState=[[NSUserDefaults standardUserDefaults] boolForKey:@"Visible"];
    }
    else  {
        self.visibleState=YES;
    }
    
    self.xmppCompletionHandlers = [[NSMutableDictionary alloc] init];
    
}


-(id) initWithServer:(nonnull MLXMPPServer *) server andIdentity:(nonnull MLXMPPIdentity *)identity {
    self=[super init];
    
    self.connectionProperties = [[MLXMPPConnection alloc] initWithServer:server andIdentity:identity];
    [self setupObjects];
    
    return self;
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) connectWithCompletion:(xmppCompletion) completion
{
    [self connect];
    if(completion) self.loginCompletion = completion;
}

-(void) connect
{
    if(self.airDrop){
        DDLogInfo(@"using airdrop. No XMPP connection.");
        return;
    }
    
    if(self.explicitLogout) return;
    if(self.accountState>=kStateLoggedIn )
    {
        DDLogError(@"assymetrical call to login without a teardown logout");
        return;
    }
    self->_accountState=kStateReconnecting;
    _loginStarted=YES;
    self.loginStartTimeStamp=[NSDate date];
    self.pingID=nil;
    
    DDLogInfo(@"XMPP connnect  start");
    
    //read persisted state
    [self readState];
    
    [self openConnection];
    
    if(self.registration) return;
    
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    if(self.loginCancelOperation)  dispatch_source_cancel(self.loginCancelOperation);
    
    self.loginCancelOperation = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                       q_background);
    
    dispatch_source_set_timer(self.loginCancelOperation,
                              dispatch_time(DISPATCH_TIME_NOW, kConnectTimeout* NSEC_PER_SEC),
                              DISPATCH_TIME_FOREVER,
                              1ull * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(self.loginCancelOperation, ^{
        DDLogInfo(@"login cancel op");
        
        self->_loginStarted=NO;
        // try again
        if((self.accountState<kStateHasStream) && (self->_loggedInOnce))
        {
            DDLogInfo(@"trying to login again");
            //make sure we are enabled still.
            if([[DataLayer sharedInstance] isAccountEnabled:[NSString stringWithFormat:@"%@",self.accountNo]]) {
                [self reconnect];
            }
        }
        else if (self.accountState>=kStateLoggedIn ) {
            NSDictionary *dic =@{@"AccountNo":self.accountNo, @"AccountName":self.connectionProperties.identity.jid};
            [[NSNotificationCenter defaultCenter] postNotificationName:kMLHasConnectedNotice object:dic];
        }
        else {
            DDLogInfo(@"failed to login and not retrying");
        }
        
    });
    
    dispatch_source_set_cancel_handler(self.loginCancelOperation, ^{
        DDLogInfo(@"login timer cancelled");
        if(self.accountState<kStateHasStream)
        {
            if(!self->_reconnectScheduled)
            {
                self->_loginStarted=NO;
                DDLogInfo(@"login client does not have stream");
                self->_accountState=kStateReconnecting;
                [self reconnect];
            }
        }
    });
    
    dispatch_resume(self.loginCancelOperation);
}

-(void) disconnect
{
    if(self.loginCancelOperation)  dispatch_source_cancel(self.loginCancelOperation);
    [self disconnectWithCompletion:nil];
}

-(void) resetValues
{
    _startTLSComplete=NO;
    _loginStarted=NO;
    _loginStartTimeStamp=nil;
    _loginError=NO;
    _accountState=kStateDisconnected;
    _reconnectScheduled =NO;
    
    self.httpUploadQueue =nil;
}

-(void) cleanUpState
{
    if(self.explicitLogout)
        [[DataLayer sharedInstance] resetContactsForAccount:_accountNo];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalAccountStatusChanged object:nil];
    if(_accountNo)
        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalAccountClearContacts object:nil userInfo:@{kAccountID:_accountNo}];
    
    
    DDLogInfo(@"Connections closed");
    
    [self resetValues];
    
    DDLogInfo(@"All closed and cleaned up");
    
}

-(void) disconnectWithCompletion:(void(^)(void))completion
{
    [self.xmppCompletionHandlers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        xmppCompletion completion = (xmppCompletion) obj;
        completion(NO,@"");
    }];
    [self.xmppCompletionHandlers removeAllObjects];
    
    if(self.regFormCompletion) {
        self.regFormCompletion(nil, nil);
        self.regFormCompletion=nil;
    }
    
    if(self.regFormSubmitCompletion) {
        self.regFormSubmitCompletion(NO, @"");
        self.regFormSubmitCompletion=nil;
    }
    
    if(self.explicitLogout && _accountState>=kStateHasStream)
    {
		[self clearNetworkQueues];
		[self.sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
			if(_accountState>=kStateBound)
			{
				//disable push for this node
				if(self.pushNode && [self.pushNode length]>0 && self.connectionProperties.supportsPush)
				{
					XMPPIQ* disable=[[XMPPIQ alloc] initWithType:kiqSetType];
					[disable setPushDisableWithNode:self.pushNode];
					[self writeNodeToConnection:disable withCompletion:nil];		// dont even bother queueing
				}
				
				[self sendLastAck];
			}
			
			//close stream
			MLXMLNode* node = [[MLXMLNode alloc] init];
			node.element = @"/stream:stream";	//hack to close stream
			[self writeNodeToConnection:node withCompletion:nil];	// dont even bother queueing
		}]] waitUntilFinished:YES];			//block until finished because we are closing the socket directly afterwards
        
        //preserve unAckedStanzas even on explicitLogout and resend them on next connect
        //if we don't do this messages could be lost when logging out directly after sending them
        //and: sending messages twice is less intrusive than silently losing them
        NSMutableArray* stanzas = self.unAckedStanzas;
        
        //reset smacks state to sane values (this can be done even if smacks is not supported)
        [self initSM3];
        self.unAckedStanzas=stanzas;
        
        //persist these changes
        [self persistState];
        
    }
    
    [self closeConnection];
    
    [self.receiveQueue addOperationWithBlock:^{
        [self cleanUpState];
        if(completion) completion();
    }];
    
}

-(void) reconnect
{
    [self reconnect:5.0];
}

-(void) reconnect:(NSInteger) scheduleWait
{
    if(self.registration || self.registrationSubmission) return;  //we never want to
    [self.receiveQueue cancelAllOperations];
    
    [self.receiveQueue addOperationWithBlock: ^{
        DDLogVerbose(@"reconnecting ");
        //can be called multiple times
        
        if(!self.loginStartTimeStamp)  self.loginStartTimeStamp=[NSDate date]; // can be destroyed by threads resulting in a deadlock
        if (self->_loginStarted && [[NSDate date] timeIntervalSinceDate:self.loginStartTimeStamp]>10)
        {
            DDLogVerbose(@"reconnect called while one already in progress that took more than 10 seconds. disconnect before reconnect.");
            [self disconnectWithCompletion:^{
                [self reconnect];
            }];
            return;
        }
        else if(self->_loginStarted) {
            DDLogVerbose(@"reconnect called while one already in progress. Stopping.");
            return;
        }
        
        DDLogVerbose(@"Login started state: %d timestamp diff from start point %f",self->_loginStarted, [[NSDate date] timeIntervalSinceDate:self.loginStartTimeStamp]);
        
        
        self->_loginStarted=YES;
        
        NSTimeInterval wait=scheduleWait;
//        if(!self->_loggedInOnce) {
//            wait=0;
//        }
#if TARGET_OS_IPHONE
        
        if(self.connectionProperties.pushEnabled)
        {
            DDLogInfo(@"Using Push path for reconnct");
            
            if(!self->_reconnectScheduled)
            {
                self->_reconnectScheduled=YES;
                DDLogInfo(@"Trying to connect again in %f seconds. ", wait);
                dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, wait * NSEC_PER_SEC), q_background,  ^{
                    //there may be another login operation freom reachability or another timer
                    if(self.accountState<kStateReconnecting) {
                        [self connect];
                    }
                });
            } else  {
                DDLogInfo(@"reconnect scheduled already" );
            }
        }
        else  {
            DDLogInfo(@"Using non push path for reconnct");
            
            if(self->_accountState>=kStateReconnecting) {
                DDLogInfo(@" account sate >=reconencting, disconnecting first" );
                [self disconnectWithCompletion:^{
                    [self reconnect:0];
                }];
                return;
            }
            
            if(!self->_reconnectScheduled)
            {
                self->_reconnectScheduled=YES;
                DDLogInfo(@"Trying to connect again in %f seconds. ", wait);
                dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, wait * NSEC_PER_SEC), q_background,  ^{
                    //there may be another login operation freom reachability or another timer
                    if(self.accountState<kStateReconnecting) {
                        [self connect];
                    }
                });
            } else  {
                DDLogInfo(@"reconnect scheduled already" );
            }
        }
#else
        if(_accountState>=kStateReconnecting) {
            DDLogInfo(@" account sate >=reconencting, disconnecting first" );
            [self disconnectWithCompletion:^{
                [self reconnect:0];
            }];
            return;
        }
        
        
        if(!_reconnectScheduled)
        {
            _loginStarted=YES;
            _reconnectScheduled=YES;
            DDLogInfo(@"Trying to connect again in %f seconds. ", wait);
            dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, wait * NSEC_PER_SEC), q_background,  ^{
                //there may be another login operation freom reachability or another timer
                if(self.accountState<kStateReconnecting) {
                    [self connect];
                }
            });
        } else  {
            DDLogInfo(@"reconnect scheduled already" );
        }
        
#endif
        
        DDLogInfo(@"reconnect exits");
    }];
}

#pragma mark XMPP

-(void) startStream
{
	//flush buffer to ignore all prior input
	self->_inputDataBuffer=[[NSMutableData alloc] init];
	self->_inputBuffer=[[NSMutableString alloc] init];
	
	DDLogInfo(@" got read queue");
	
	MLXMLNode* stream = [[MLXMLNode alloc] init];
	stream.element=@"stream:stream";
	[stream.attributes setObject:@"jabber:client" forKey:kXMLNS];
	[stream.attributes setObject:@"http://etherx.jabber.org/streams" forKey:@"xmlns:stream"];
	[stream.attributes setObject:@"1.0" forKey:@"version"];
	if(self.connectionProperties.identity.domain) {
		[stream.attributes setObject:self.connectionProperties.identity.domain forKey:@"to"];
	}
	[self send:stream];
}

-(void) processRegistration:(ParseIq *) iqNode
{
    BOOL success =YES;
    
    if([iqNode.type isEqualToString:kiqErrorType]) success=NO;
    if(self.registrationState==kStateSubmittingForm && self.regFormSubmitCompletion)
    {
        self.registrationState=kStateRegistered;
        self.regFormSubmitCompletion(success, iqNode.errorMessage);
        self.regFormSubmitCompletion=nil;
    }
    
    xmppCompletion completion = [self.xmppCompletionHandlers objectForKey:iqNode.idval];
    if(completion)  {
        [self.xmppCompletionHandlers removeObjectForKey:iqNode.idval]; // remove first to prevent an infinite loop
        completion(success, iqNode.errorMessage);
    }
    
    
    if(self.registration && [iqNode.queryXMLNS isEqualToString:kRegisterNameSpace])
    {
        if(self.regFormCompletion) {
            self.regFormCompletion(iqNode.captchaData, iqNode.hiddenFormFields);
            self.regFormCompletion=nil;
        }
    }
    
}


-(void)setPingTimerForID:(NSString *)pingID
{
    DDLogInfo(@"setting timer for ping %@", pingID);
    self.pingID=pingID;
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t pingTimeOut = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                           q_background);
    
    dispatch_source_set_timer(pingTimeOut,
                              dispatch_time(DISPATCH_TIME_NOW, kPingTimeout* NSEC_PER_SEC),
                              DISPATCH_TIME_FOREVER,
                              1ull * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(pingTimeOut, ^{
        
        if(self.pingID)
        {
            DDLogVerbose(@"ping timed out without a reply to %@",self.pingID);
            _accountState=kStateReconnecting;
            [self reconnect];
        }
        else
        {
            DDLogVerbose(@"ping reply was seen");
            
        }
        
        dispatch_source_cancel(pingTimeOut);
        
    });
    
    dispatch_source_set_cancel_handler(pingTimeOut, ^{
        DDLogInfo(@"ping timer cancelled");
    });
    
    dispatch_resume(pingTimeOut);
}

-(void) sendPing
{
      
        if(self.accountState<kStateReconnecting  && !self->_reconnectScheduled)
        {
            DDLogInfo(@" ping calling reconnect");
            self->_accountState=kStateReconnecting;
            [self reconnect:0];
            return;
        }
        
        if(self.accountState<kStateBound)
        {
            if(self->_loginStarted && [[NSDate date] timeIntervalSinceDate:self.loginStartTimeStamp]<=10) {
                DDLogInfo(@"ping attempt before logged in and bound. returning.");
                return;
            }
            else if (self->_loginStarted && [[NSDate date] timeIntervalSinceDate:self.loginStartTimeStamp]>10)
            {
                DDLogVerbose(@"ping called while one already in progress that took more than 10 seconds. disconnect before reconnect.");
                [self reconnect:0];
            }
            
        }
        else {
            //always use smacks pings if supported (they are shorter and better than whitespace pings)
            if(self.connectionProperties.supportsSM3 )
            {
                [self requestSMAck];
            }
            else  {
                if(self.connectionProperties.supportsPing) {
                    XMPPIQ* ping =[[XMPPIQ alloc] initWithType:kiqGetType];
                    [ping setiqTo:self.connectionProperties.identity.domain];
                    [ping setPing];
                    [self send:ping];
                } else  {
                    [self sendWhiteSpacePing];
                }
            }
        }

}

-(void) sendWhiteSpacePing
{
    if(self.accountState<kStateReconnecting  )
    {
        DDLogInfo(@" whitespace ping calling reconnect");
        _accountState=kStateReconnecting;
        [self reconnect:0];
        return;
    }
    
    MLXMLNode* ping =[[MLXMLNode alloc] initWithElement:@"whitePing"]; // no such element. Node has logic to  print white space
    [self send:ping];
}

-(void) enablePush
{
#ifndef TARGET_IS_EXTENSION
#if TARGET_OS_IPHONE
    if(self.accountState>=kStateBound && [self.pushNode length]>0 && [self.pushSecret length]>0 && self.connectionProperties.supportsPush)
    {
        DDLogInfo(@"ENABLING PUSH: %@ < %@", self.pushNode, self.pushSecret);
        XMPPIQ* enable =[[XMPPIQ alloc] initWithType:kiqSetType];
        [enable setPushEnableWithNode:self.pushNode andSecret:self.pushSecret];
        [self send:enable];
        self.connectionProperties.pushEnabled=YES;
    }
    else {
        DDLogInfo(@" NOT enabling push: %@ < %@", self.pushNode, self.pushSecret);
    }
#endif
#endif
}


-(NSMutableDictionary*) nextStanza
{
    NSString* __block toReturn=nil;
    NSString* __block stanzaType=nil;
    
    //   DDLogVerbose(@"maxPos %ld", _inputBuffer.length );
    
    if(_inputBuffer.length<2)
    {
        return nil;
    }
    //accouting for white space
    NSRange startrange=[_inputBuffer rangeOfString:@"<"
                                           options:NSCaseInsensitiveSearch range:NSMakeRange(0, [_inputBuffer length])];
    if (startrange.location==NSNotFound)
    {
        toReturn= nil;
        return nil;
    }
    // DDLogVerbose(@"input bufffer  %@", _inputBuffer);
    NSInteger finalstart=0;
    NSInteger finalend=0;
    
    NSInteger startpos=startrange.location;
    DDLogVerbose(@"start pos%ld", (long)startpos);
    if(startpos!=0)
    {
        //this shoudlnt happen
        DDLogVerbose(@"start in the middle. there was a glitch or whitespace");
    }
    
    
    if(_inputBuffer.length>startpos)
    {
        NSString *element;
        NSRange pos;
        NSRange endPos=[_inputBuffer rangeOfString:@">"
                                           options:NSCaseInsensitiveSearch range:NSMakeRange(startpos, _inputBuffer.length-startpos)];
        //we have the max bounds of he XML tag.
        if(endPos.location==NSNotFound) {
            DDLogVerbose(@"dont have the end. exit at 0 ");
            return nil;
        }
        else  {
            //look for a space if there is one
            NSRange spacePos=[_inputBuffer rangeOfString:@" "
                                                 options:NSCaseInsensitiveSearch range:NSMakeRange(startpos, endPos.location-startpos)];
            pos=endPos;
            
            if(spacePos.location!=NSNotFound) {
                pos=spacePos;
            }
            
            element= [_inputBuffer substringWithRange:NSMakeRange(startpos+1, pos.location-(startpos+1))];
            DDLogVerbose(@"got element %@", element);
            
            if([element isEqualToString:@"?xml"] || [element isEqualToString:@"stream:stream"] || [element isEqualToString:@"stream"])
            {
                stanzaType= element;
                element =nil;
                NSRange endPos=[_inputBuffer rangeOfString:@">"
                                                   options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location, _inputBuffer.length-pos.location)];
                
                finalstart=startpos;
                finalend=endPos.location+1;
                DDLogVerbose(@"exiting at 1 ");
                
            }
        }
        
        if(element)
        {
            stanzaType= element;
            
            {
                NSRange dupePos=[_inputBuffer rangeOfString:[NSString stringWithFormat:@"<%@",stanzaType]
                                                    options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location+1, _inputBuffer.length-pos.location-1)];
                
                
                if([stanzaType isEqualToString:@"message"] && dupePos.location!=NSNotFound) {
                    //check for carbon forwarded
                    NSRange forwardPos=[_inputBuffer rangeOfString:@"<forwarded"
                                                           options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location, dupePos.location-pos.location-1)];
                    
                    NSRange firstClose=[_inputBuffer rangeOfString:@"</message"
                                                           options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location, dupePos.location-pos.location-1)];
                    //if message clsoed before forwarded, not the same
                    
                    
                    if(forwardPos.location!=NSNotFound && firstClose.location==NSNotFound) {
                        
                        //look for next message close
                        NSRange forwardClosePos=[_inputBuffer rangeOfString:@"</forwarded"
                                                                    options:NSCaseInsensitiveSearch range:NSMakeRange(forwardPos.location, _inputBuffer.length-forwardPos.location)];
                        
                        if(forwardClosePos.location!=NSNotFound) {
                            NSRange messageClose =[_inputBuffer rangeOfString:[NSString stringWithFormat:@"</%@",stanzaType]
                                                                      options:NSCaseInsensitiveSearch range:NSMakeRange(forwardClosePos.location, _inputBuffer.length-forwardClosePos.location)];
                            //ensure it is set to future max
                            
                            finalstart=startpos;
                            finalend=messageClose.location+messageClose.length+1; //+1 to inclde closing <
                            DDLogVerbose(@"at  2.5");
                            // break;
                        }
                        else {
                            DDLogVerbose(@"Incomplete stanza  missing forward close. at 2.6");
                            return nil;
                        }
                        
                    }
                    else if(firstClose.location!=NSNotFound) {
                        DDLogVerbose(@"found close without forward . at 2.7");
                        finalend=firstClose.location+firstClose.length+1;
                    }
                }
                NSRange firstClose;
                if(dupePos.location!=NSNotFound) {
                    firstClose=[_inputBuffer rangeOfString:[NSString stringWithFormat:@"</%@",stanzaType]
                                                   options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location, dupePos.location-pos.location-1)];
                }
                
                if([stanzaType isEqualToString:@"presence"] && dupePos.location!=NSNotFound && firstClose.location==NSNotFound) {
                    //did not find close between dupe and start
                    NSRange messageClose =[_inputBuffer rangeOfString:[NSString stringWithFormat:@"</%@",stanzaType]
                                                                                     options:NSCaseInsensitiveSearch range:NSMakeRange(dupePos.location, _inputBuffer.length-dupePos.location)];
                    if(messageClose.location!=NSNotFound){
                        finalstart=startpos;
                        finalend=messageClose.location+messageClose.length+1; //+1 to inclde closing >
                    }
                }
                else {
                    
                    //since there is another block of the same stanza, short cuts dont work.check to find beginning of next element
                    NSInteger maxPos=_inputBuffer.length;
                    if((dupePos.location<_inputBuffer.length) && (dupePos.location!=NSNotFound))
                    {
                        //reduce search to within the set of this and at max the next element of the same kind
                        maxPos=dupePos.location;
                        
                    }
                    
                    //  we need to find the end of this stanza
                    NSRange closePos=[_inputBuffer rangeOfString:[NSString stringWithFormat:@"</%@",stanzaType]
                                                         options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location, maxPos-pos.location)];
                    
                    if((closePos.location<maxPos) && (closePos.location!=NSNotFound)){
                        //we have the start of the stanza close
                        
                        NSRange endPos=[_inputBuffer rangeOfString:@">"
                                                           options:NSCaseInsensitiveSearch range:NSMakeRange(closePos.location, maxPos-closePos.location)];
                        
                        finalstart=startpos;
                        finalend=endPos.location+1; //+1 to inclde closing >
                        DDLogVerbose(@"at  3");
                        //  break;
                    }
                    else {
                        
                        //check if self closed
                        NSRange endPos=[_inputBuffer rangeOfString:@"/>"
                                                           options:NSCaseInsensitiveSearch range:NSMakeRange(startpos, _inputBuffer.length-startpos)];
                        
                        //are ther children, then not self closed
                        if(endPos.location<_inputBuffer.length && endPos.location!=NSNotFound)
                        {
                            NSRange childPos=[_inputBuffer rangeOfString:[NSString stringWithFormat:@"<"]
                                                                 options:NSCaseInsensitiveSearch range:NSMakeRange(startpos+1, endPos.location-startpos)];
                            if((childPos.location<_inputBuffer.length) && (childPos.location!=NSNotFound)){
                                DDLogVerbose(@"at 3.5 looks like incomplete stanza. need to get more. loc %d", childPos.location);
                                return nil;
                                // break;
                            }
                        }
                        
                        
                        if((endPos.location<_inputBuffer.length) && (endPos.location!=NSNotFound)) {
                            finalstart=startpos;
                            finalend=endPos.location+2; //+2 to inclde closing />
                            DDLogVerbose(@"at  4 self closed");
                            // break;
                        }
                        else
                            if([stanzaType isEqualToString:@"stream"]) {
                                //stream will have no terminal.
                                finalstart=pos.location;
                                finalend=maxPos;
                                DDLogVerbose(@"at  5 stream");
                            }
                        
                    }
                }
            }
        }
    }
    
    
    
    //if this happens its  probably a stream error.sanity check is  preventing crash
    
    if((finalend-finalstart<=_inputBuffer.length) && finalend!=NSNotFound && finalstart!=NSNotFound && finalend>=finalstart)
    {
        toReturn=  [_inputBuffer substringWithRange:NSMakeRange(finalstart,finalend-finalstart)];
    }
    if([toReturn length]==0) toReturn=nil;
    
    if(!stanzaType)
    {
        //this is junk data no stanza start
        _inputBuffer=[[NSMutableString alloc] init];
        DDLogVerbose(@"wiped input buffer with no start");
        
    }
    else{
        if((finalend-finalstart<=_inputBuffer.length) && finalend!=NSNotFound && finalstart!=NSNotFound && finalend>=finalstart)
        {
            //  DDLogVerbose(@"to del start %d end %d: %@", finalstart, finalend, _inputBuffer);
            if(finalend <=[_inputBuffer length] ) {
                [_inputBuffer deleteCharactersInRange:NSMakeRange(finalstart, finalend-finalstart) ];
            } else {
                DDLogVerbose(@"Something wrong with lengths."); //This should not happen
                [_inputBuffer deleteCharactersInRange:NSMakeRange(finalstart, [_inputBuffer length] -finalstart) ];
            }
            
        }
    }
    
    NSMutableDictionary* returnDic=nil;
    
    if(stanzaType && toReturn)
    {
        returnDic=[[NSMutableDictionary alloc]init];
        [returnDic setObject:toReturn forKey:@"stanzaString"];
        [returnDic setObject:stanzaType forKey:@"stanzaType"];
    }
    
    return  returnDic;
}

#pragma mark smacks
-(void) resendUnackedStanzas
{
    /**
     Send appends to the unacked stanzas. Not removing it now will create an infinite loop.
     It may also result in mutation on iteration
	*/
	NSMutableArray *sendCopy = [[NSMutableArray alloc] initWithArray:self.unAckedStanzas];
	[self.unAckedStanzas removeAllObjects];
	[sendCopy enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		NSDictionary *dic= (NSDictionary *) obj;
		[self send:(MLXMLNode*)[dic objectForKey:kStanza]];
	}];
	[self persistState];
}

-(void) resendUnackedMessageStanzasOnly:(NSMutableArray*) stanzas
{
    /**
     Send appends to the unacked stanzas. Not removing it now will create an infinite loop.
     It may also result in mutation on iteration
	*/
	if(stanzas)
	{
		NSMutableArray *sendCopy = [[NSMutableArray alloc] initWithArray:stanzas];
		//clear queue because we don't want to repeat resending these stanzas later if the var stanzas points to self.unAckedStanzas here
		[stanzas removeAllObjects];
		[sendCopy enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
			NSDictionary *dic= (NSDictionary *) obj;
			MLXMLNode *stanza=[dic objectForKey:kStanza];
			if([stanza.element isEqualToString:@"message"])		//only resend message stanzas because of the smacks error condition
				[self send:stanza];
		}];
		//persist these changes (the queue can now be empty because smacks enable failed
		//or contain all the resent stanzas (e.g. only resume failed))
		[self persistState];
	}
}

-(void) removeAckedStanzasFromQueue:(NSNumber*) hvalue
{
	if([self.unAckedStanzas count]>0)
	{
		NSMutableArray *iterationArray = [[NSMutableArray alloc] initWithArray:self.unAckedStanzas];
		DDLogDebug(@"removeAckedStanzasFromQueue: hvalue %@, lastOutboundStanza %@", hvalue, self.lastOutboundStanza);
		NSMutableArray *discard =[[NSMutableArray alloc] initWithCapacity:[self.unAckedStanzas count]];
		for(NSDictionary *dic in iterationArray)
		{
			NSNumber *stanzaNumber = [dic objectForKey:kStanzaID];
			//having a h value of 1 means the first stanza was acked and the first stanza has a kStanzaID of 0
			if([stanzaNumber integerValue]<[hvalue integerValue])
				[discard addObject:dic];
		}
		
		[iterationArray removeObjectsInArray:discard];
		if(self.unAckedStanzas) self.unAckedStanzas= iterationArray; // if it was set to nil elsewhere, dont restore
		
		//persist these changes (but only if we actually made some changes)
		if([discard count])
			[self persistState];
	}
}

-(void) requestSMAck
{
    if(self.accountState>=kStateBound && self.connectionProperties.supportsSM3 &&
		!self.smacksRequestInFlight && [self.unAckedStanzas count]>0 ) {
        
		DDLogVerbose(@"requesting smacks ack...");
        MLXMLNode* rNode =[[MLXMLNode alloc] initWithElement:@"r"];
        NSDictionary *dic=@{kXMLNS:@"urn:xmpp:sm:3"};
        rNode.attributes=[dic mutableCopy];
		[self send:rNode];
		self.smacksRequestInFlight=YES;
    } else  {
        DDLogDebug(@"no smacks request, there is nothing pending or a request already in flight...");
    }
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
        MLXMLNode *aNode = [[MLXMLNode alloc] initWithElement:@"a"];
        NSDictionary *dic= @{kXMLNS:@"urn:xmpp:sm:3",@"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza] };
        aNode.attributes = [dic mutableCopy];
        if(queuedSend) {
            [self send:aNode];
        } else  {		//this should only be done from sendQueue (e.g. by sendLastAck())
            [self writeNodeToConnection:aNode withCompletion:nil];		// dont even bother queueing
        }
    }
}


#pragma mark stanza handling

-(void) processInput
{
    //prevent reconnect attempt
    if(_accountState<kStateHasStream)
		_accountState=kStateHasStream;
	NSDictionary* stanzaToParse=[self nextStanza];
	while(stanzaToParse)
	{
		DDLogDebug(@"RECV: %@", stanzaToParse);
		
		if([[stanzaToParse objectForKey:@"stanzaType"]  isEqualToString:@"iq"])
		{
			[self incrementLastHandledStanza];
			
			ParseIq* iqNode= [[ParseIq alloc]  initWithDictionary:stanzaToParse];
			
			MLIQProcessor *processor = [[MLIQProcessor alloc] initWithAccount:self.accountNo connection:self.connectionProperties signalContex:self.signalContext andSignalStore:self.monalSignalStore];
			processor.sendIq=^(MLXMLNode * _Nullable iqResponse) {
				if(iqResponse) {
					DDLogInfo(@"sending iq stanza");
					[self send:iqResponse];
				}
			};
			
			//this will be called after bind
			processor.initSession = ^() {
				//init session and query disco, roster etc.
				[self initSession];
				
				//only do this if smacks is not supported because handling of the old queue will be already done on smacks enable/failed enable
				if(!self.connectionProperties.supportsSM3)
				{
					//resend stanzas still in the outgoing queue and clear it afterwards
					//this happens if the server has internal problems and advertises smacks support
					//but failes to resume the stream as well as to enable smacks on the new stream
					//clean up those stanzas to only include message stanzas because iqs don't survive a session change
					//message duplicates are possible in this scenario, but that's better than dropping messages
					//the self.unAckedStanzas queue is not touched by initSession() above because smacks is disabled at this point
					[self resendUnackedMessageStanzasOnly:self.unAckedStanzas];
				}
			};
			
			processor.enablePush = ^() {
				[self enablePush];
			};

#ifndef DISABLE_OMEMO
			processor.sendSignalInitialStanzas = ^() {
				[self sendSignalInitialStanzas];
			};
#endif
			
			processor.getVcards = ^() {
				[self getVcards];
			};
			
			[processor processIq:iqNode];
			
			
			if([iqNode.idval isEqualToString:self.deviceQueryId])
			{
				if([iqNode.type isEqualToString:kiqErrorType]) {
					//there are no devices published yet
					DDLogInfo(@"No signal device items. Adding new to pubsub");
					XMPPIQ *signalDevice = [[XMPPIQ alloc] initWithType:kiqSetType];
					NSString * deviceString=[NSString stringWithFormat:@"%d", self.monalSignalStore.deviceid];
					[signalDevice publishDevices:@[deviceString]];
					[self send:signalDevice];
				}
			}
			
			//TODO these result iq need to be moved elsewhere/refactored
			//kept outside intentionally
			if([iqNode.idval isEqualToString:self.pingID])
			{
				//response to my ping
				self.pingID=nil;
			}
			
			
			if([iqNode.from isEqualToString:self.connectionProperties.conferenceServer] && iqNode.discoItems)
			{
				self->_roomList=iqNode.items;
				[[NSNotificationCenter defaultCenter]
					postNotificationName: kMLHasRoomsNotice object: self];
			}
			
			if([iqNode.idval isEqualToString:self.jingle.idval]) {
				[self jingleResult:iqNode];
			}
			
			[self processRegistration:iqNode];
			
			[self processHTTPIQ:iqNode];
			
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"]  isEqualToString:@"message"])
		{
			[self incrementLastHandledStanza];
			
			ParseMessage* messageNode= [[ParseMessage alloc]  initWithDictionary:stanzaToParse];
			
			MLMessageProcessor *messageProcessor = [[MLMessageProcessor alloc] initWithAccount:self.accountNo jid:self.connectionProperties.identity.jid connection:self.connectionProperties signalContex:self.signalContext andSignalStore:self.monalSignalStore];
			
			messageProcessor.sendStanza=^(MLXMLNode * _Nullable nodeResponse) {
				if(nodeResponse) {
					[self send:nodeResponse];
				}
			};
			
			messageProcessor.postPersistAction = ^(BOOL success, BOOL encrypted, BOOL showAlert,  NSString *body, NSString *newMessageType) {
				if(success)
				{
					if(messageNode.requestReceipt && ![messageNode.from isEqualToString:
							self.connectionProperties.identity.jid]
						)
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
						if(messageNode.from  ) {
							NSString* actuallyFrom= messageNode.actualFrom;
							if(!actuallyFrom) actuallyFrom=messageNode.from;
							
							MLMessage *message = [[MLMessage alloc] init];
							message.from=messageNode.from;
							message.actualFrom= actuallyFrom;
							message.messageText= body; //this need to be the processed value since it may be decrypted
							message.to=messageNode.to?messageNode.to:self.connectionProperties.identity.jid;
							message.messageId=messageNode.idval?messageNode.idval:@"";
							message.accountId=self.accountNo;
							message.encrypted=encrypted;
							message.delayTimeStamp=messageNode.delayTimeStamp;
							message.timestamp =[NSDate date];
							message.shouldShowAlert= showAlert;
							message.messageType=newMessageType;
							message.hasBeenSent=YES; //if it came in it has been sent to the server
							
							[[NSNotificationCenter defaultCenter] postNotificationName:kMonalNewMessageNotice object:self userInfo:@{@"message":message}];
						}
					};
					
					if(![messageNode.from isEqualToString:
							self.connectionProperties.identity.jid]) {
						[[DataLayer sharedInstance] addActiveBuddies:messageNode.from forAccount:self->_accountNo withCompletion:notify];
					} else  {
						[[DataLayer sharedInstance] addActiveBuddies:messageNode.to forAccount:self->_accountNo withCompletion:notify];
					}
				}
				else {
					DDLogError(@"error adding message");
				}
			};
			
			messageProcessor.signalAction = ^(void) {
				[self manageMyKeys];
			};
			
			[messageProcessor processMessage:messageNode];
			
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"]  isEqualToString:@"presence"])
		{
			[self incrementLastHandledStanza];
			ParsePresence* presenceNode= [[ParsePresence alloc]  initWithDictionary:stanzaToParse];
			NSString *recipient=presenceNode.to;
			
			if(!recipient)
			{
				recipient= self.connectionProperties.identity.jid;
			}
			
			
			if([presenceNode.user isEqualToString:self.connectionProperties.identity.jid]) {
				//ignore self
			}
			else {
				if([presenceNode.type isEqualToString:kpresencesSubscribe])
				{
					MLContact *contact = [[MLContact alloc] init];
					contact.accountId=self.accountNo;
					contact.contactJid=presenceNode.user;
					
					[[DataLayer sharedInstance] addContactRequest:contact];
					
				}
				
				if(presenceNode.MUC)
				{
					for (NSString* code in presenceNode.statusCodes) {
						if([code isEqualToString:@"201"]) {
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
				
				if(presenceNode.type ==nil)
				{
					DDLogVerbose(@"presence notice from %@", presenceNode.user);
					
					if((presenceNode.user!=nil) && (presenceNode.user.length >0))
					{
						
						MLContact *contact = [[MLContact alloc] init];
						contact.accountId=self.accountNo;
						contact.contactJid=presenceNode.user;
						contact.state=presenceNode.show;
						contact.statusMessage=presenceNode.status;
						
						[[DataLayer sharedInstance] setOnlineBuddy:presenceNode forAccount:self->_accountNo];
						[[DataLayer sharedInstance] setBuddyState:presenceNode forAccount:self->_accountNo];
						[[DataLayer sharedInstance] setBuddyStatus:presenceNode forAccount:self->_accountNo];
						
						[[DataLayer sharedInstance] addContact:[presenceNode.user copy] forAccount:self->_accountNo fullname:@"" nickname:@"" andMucNick:nil withCompletion:^(BOOL success) {
							if(!success)
							{
								DDLogVerbose(@"Contact already in list");
							}
							else
							{
								DDLogVerbose(@"Contact not already in list");
							}
							
							DDLogVerbose(@" showing as online from presence");
							
							
							[[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactOnlineNotice object:self userInfo:@{@"contact":contact}];
							
						}];
						
						if(!presenceNode.MUC) {
							// do not do this in the background
							
							__block  BOOL checkChange = YES;
							
							if(checkChange)
							{
								//check for vcard change
								if(presenceNode.photoHash) {
									[[DataLayer sharedInstance]  contactHash:[presenceNode.user copy] forAccount:self->_accountNo withCompeltion:^(NSString *iconHash) {
										if([presenceNode.photoHash isEqualToString:iconHash])
										{
											DDLogVerbose(@"photo hash is the  same");
										}
										else
										{
											[[DataLayer sharedInstance]  setContactHash:presenceNode forAccount:self->_accountNo];
											
											[self getVCard:presenceNode.user];
										}
										
									}];
									
								}
							}
							else
							{
								// just set and request when in foreground if needed
								[[DataLayer sharedInstance]  setContactHash:presenceNode  forAccount:self->_accountNo];
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
					if ([[DataLayer sharedInstance] setOfflineBuddy:presenceNode forAccount:self->_accountNo] ) {
						NSDictionary* userDic=@{kusernameKey: presenceNode.user,
												kaccountNoKey:self->_accountNo};
						[[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactOfflineNotice object:self userInfo:userDic];
					}
					
				}
			}
			
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"stream:error"])
		{
			NSString *message=@"XMPP stream error";
			[[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self,message ]];
			if(self.loginCompletion)  {
				self.loginCompletion(NO, message);
				self.loginCompletion=nil;
			}
			
			[self disconnectWithCompletion:^{
				[self reconnect:5];
			}];
			
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"stream:stream"])
		{
			//  ParseStream* streamNode= [[ParseStream alloc]  initWithDictionary:nextStanzaPos];
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"stream"] ||  [[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"stream:features"])
		{
			ParseStream* streamNode= [[ParseStream alloc]  initWithDictionary:stanzaToParse];
			
			//perform logic to handle stream
			if(streamNode.error)
			{
				return;
				
			}
			
			if(self.accountState<kStateLoggedIn )
			{
				
				if(streamNode.callStartTLS && self.connectionProperties.server.SSL)
				{
					MLXMLNode* startTLS= [[MLXMLNode alloc] init];
					startTLS.element=@"starttls";
					[startTLS.attributes setObject:@"urn:ietf:params:xml:ns:xmpp-tls" forKey:kXMLNS];
					[self send:startTLS];
					
				}
				
				if ((self.connectionProperties.server.SSL && self->_startTLSComplete)
					|| (!self.connectionProperties.server.SSL && !self->_startTLSComplete)
					|| (self.connectionProperties.server.connectTLS==YES))
				{
					if(self.registration){
						[self requestRegForm];
					}
					else if(self.registrationSubmission) {
						[self submitRegForm];
					}
					
					else {
						//look at menchanisms presented
						
						if (streamNode.SASLPlain)
						{
							NSString* saslplain=[EncodingTools encodeBase64WithString: [NSString stringWithFormat:@"\0%@\0%@",  self.connectionProperties.identity.user, self.connectionProperties.identity.password ]];
							
							MLXMLNode* saslXML= [[MLXMLNode alloc]init];
							saslXML.element=@"auth";
							[saslXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:kXMLNS];
							[saslXML.attributes setObject: @"PLAIN"forKey: @"mechanism"];
							
							saslXML.data=saslplain;
							[self send:saslXML];
							
						}
						else
							if(streamNode.SASLDIGEST_MD5)
							{
								MLXMLNode* saslXML= [[MLXMLNode alloc]init];
								saslXML.element=@"auth";
								[saslXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:kXMLNS];
								[saslXML.attributes setObject: @"DIGEST-MD5"forKey: @"mechanism"];
								
								[self send:saslXML];
							}
							else
							{
								
								//no supported auth mechanism try legacy
								//[self disconnect];
								DDLogInfo(@"no auth mechanism. will try legacy auth");
								XMPPIQ* iqNode =[[XMPPIQ alloc] initWithElement:@"iq"];
								[iqNode getAuthwithUserName:self.connectionProperties.identity.user ];
								[self send:iqNode];
							}
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
				{
					self.connectionProperties.supportsSM3=YES;
				} else {
					[[DataLayer sharedInstance] resetContactsForAccount:self.accountNo];
				}
				
				if(streamNode.supportsRosterVer)
				{
					self.connectionProperties.supportsRosterVersion=YES;
					
				}
				
				//test if smacks is supported and allows resume
				if(self.connectionProperties.supportsSM3 && self.streamID) {
					MLXMLNode *resumeNode=[[MLXMLNode alloc] initWithElement:@"resume"];
					NSDictionary *dic=@{kXMLNS:@"urn:xmpp:sm:3",@"h":[NSString stringWithFormat:@"%@",self.lastHandledInboundStanza], @"previd":self.streamID };
					resumeNode.attributes=[dic mutableCopy];
					self.resuming=YES;      //this is needed to distinguish a failed smacks resume and a failed smacks enable later on
					[self send:resumeNode];
				}
				else {
					[self bindResource];
					
					if(self.loginCompletion) {
						self.loginCompletion(YES, @"");
						self.loginCompletion=nil;
					}
				}
				
			}
			
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"enabled"])
		{
			//save old unAckedStanzas queue before it is cleared
			NSMutableArray *stanzas = self.unAckedStanzas;
			
			//init smacks state (this clears the unAckedStanzas queue)
			[self initSM3];
			
			//save streamID if resume is supported
			ParseEnabled* enabledNode= [[ParseEnabled alloc]  initWithDictionary:stanzaToParse];
			if(enabledNode.resume) {
				self.streamID=enabledNode.streamID;
				
			}
			else {
				self.streamID=nil;
			}
			
			//persist these changes (streamID and initSM3)
			[self persistState];
			
			//init session and query disco, roster etc.
			[self initSession];
			
			//resend unacked stanzas saved above (this happens only if the server provides smacks support without resumption support)
			//or if the resumption failed for other reasons the server is responsible for
			//clean up those stanzas to only include message stanzas because iqs don't survive a session change
			//message duplicates are possible in this scenario, but that's better than dropping messages
			[self resendUnackedMessageStanzasOnly:stanzas];
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"r"] && self.connectionProperties.supportsSM3 && self.accountState>=kStateBound)
		{
			[self sendSMAck:YES];
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"a"] && self.connectionProperties.supportsSM3 && self.accountState>=kStateBound)
		{
			ParseA* aNode=[[ParseA alloc] initWithDictionary:stanzaToParse];
			self.lastHandledOutboundStanza=aNode.h;
			
			//remove acked messages
			[self removeAckedStanzasFromQueue:aNode.h];
			
			self.smacksRequestInFlight=NO;			//ack returned
			[self requestSMAck];					//request ack again (will only happen if queue is not empty)
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"resumed"])
		{
			self.resuming=NO;
			
			//now we are bound again
			self->_accountState=kStateBound;
			[self postConnectNotification];
			
			//remove already delivered stanzas and resend the (still) unacked ones
			ParseResumed* resumeNode= [[ParseResumed alloc]  initWithDictionary:stanzaToParse];
			[self removeAckedStanzasFromQueue:resumeNode.h];
			[self resendUnackedStanzas];
			
			[self sendInitalPresence];
			
			//force push (re)enable on session resumption
			self.connectionProperties.pushEnabled=NO;
			if(self.connectionProperties.supportsPush)
			{
				[self enablePush];
			}
			
			if(self.loginCompletion) {
				self.loginCompletion(YES, @"");
				self.loginCompletion=nil;
			}
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"failed"]) // smacks resume or smacks enable failed
		{
			if(self.resuming)   //resume failed
			{
				[[DataLayer sharedInstance] resetContactsForAccount:self->_accountNo];
				
				self.resuming=NO;
				
				//invalidate stream id
				self.streamID=nil;
				//get h value, if server supports smacks revision 1.5.2
				ParseFailed* failedNode= [[ParseFailed alloc]  initWithDictionary:stanzaToParse];
				DDLogInfo(@"++++++++++++++++++++++++ failed resume: h=%@", failedNode.h);
				[self removeAckedStanzasFromQueue:failedNode.h];
				//persist these changes
				[self persistState];
				
				//if resume failed. bind  a new resource like normal (supportsSM3 is still YES here but switches to NO on failed enable)
				[self bindResource];
				
				if(self.loginCompletion) {
					self.loginCompletion(YES, @"");
					self.loginCompletion=nil;
				}
			}
			else        //smacks enable failed
			{
				self.connectionProperties.supportsSM3=NO;
				
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
		
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"features"])
		{
			
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"proceed"])
		{
			ParseStream* streamNode= [[ParseStream alloc]  initWithDictionary:stanzaToParse];
			//perform logic to handle proceed
			if(!streamNode.error)
			{
				if(streamNode.startTLSProceed)
				{
					[self initTLS];
					
					[self startStream];
					
					self->_startTLSComplete=YES;
				}
			}
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"failure"])
		{
			
			ParseFailure* failure = [[ParseFailure alloc] initWithDictionary:stanzaToParse];
			
			NSString *message=failure.text;
			if(failure.notAuthorized)
			{
				if(!message) message =@"Not Authorized. Please check your credentials.";
			}
			else  {
				if(!message) message =@"There was a SASL error on the server.";
			}
			
			[[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, message]];
			if(self.loginCompletion)  {
				self.loginCompletion(NO, message);
				self.loginCompletion=nil;
			}
			
			if(failure.saslError || failure.notAuthorized)
			{
				self->_loginError=YES;
				[self disconnect];
		
			}
			
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"challenge"])
		{
			ParseChallenge* challengeNode= [[ParseChallenge alloc]  initWithDictionary:stanzaToParse];
			if(challengeNode.saslChallenge)
			{
				MLXMLNode* responseXML= [[MLXMLNode alloc]init];
				responseXML.element=@"response";
				[responseXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:kXMLNS];
				
				
				NSString* decoded=[[NSString alloc]  initWithData: (NSData*)[EncodingTools dataWithBase64EncodedString:challengeNode.challengeText] encoding:NSASCIIStringEncoding];
				DDLogVerbose(@"decoded challenge to %@", decoded);
				NSArray* parts =[decoded componentsSeparatedByString:@","];
				
				if([parts count]<2)
				{
					//this is a success message  from challenge
					
					NSArray* rspparts= [[parts objectAtIndex:0] componentsSeparatedByString:@"="];
					if([[rspparts objectAtIndex:0] isEqualToString:@"rspauth"])
					{
						DDLogVerbose(@"digest-md5 success");
						
					}
					
				}
				else{
					
					NSString* realm;
					NSString* nonce;
					
					for(NSString* part in parts)
					{
						NSArray* split = [part componentsSeparatedByString:@"="];
						if([split count]>1)
						{
							if([split[0] isEqualToString:@"realm"]) {
								realm=[split[1]  substringWithRange:NSMakeRange(1, [split[1]  length]-2)] ;
							}
							
							if([split[0] isEqualToString:@"nonce"]) {
								nonce=[split[1]  substringWithRange:NSMakeRange(1, [split[1]  length]-2)] ;
							}
							
						}
					}
					
					if(!realm) realm=@"";
					
					NSData* cnonce_Data=[EncodingTools MD5: [NSString stringWithFormat:@"%d",arc4random()%100000]];
					NSString* cnonce =[EncodingTools hexadecimalString:cnonce_Data];
					
					// ****** digest stuff going on here...
					NSString* X= [NSString stringWithFormat:@"%@:%@:%@", self.connectionProperties.identity.user, realm,  self.connectionProperties.identity.password ];
					DDLogVerbose(@"X: %@", X);
					
					NSData* Y = [EncodingTools MD5:X];
					
					//  if you have the authzid  here you need it below too but it wont work on som servers
					// so best not include it
					
					NSString* A1Str=[NSString stringWithFormat:@":%@:%@",
										nonce,cnonce];
					NSData* A1= [A1Str
									dataUsingEncoding:NSUTF8StringEncoding];
					
					NSMutableData *HA1data = [NSMutableData dataWithCapacity:([Y length] + [A1 length])];
					[HA1data appendData:Y];
					[HA1data appendData:A1];
					DDLogVerbose(@" HA1data : %@",HA1data  );
					
					NSData* HA1=[EncodingTools DataMD5:HA1data];
					
					NSString* A2=[NSString stringWithFormat:@"AUTHENTICATE:xmpp/%@", realm];
					DDLogVerbose(@"%@", A2);
					NSData* HA2=[EncodingTools MD5:A2];
					
					NSString* KD=[NSString stringWithFormat:@"%@:%@:00000001:%@:auth:%@",
									[EncodingTools hexadecimalString:HA1], nonce,
									cnonce,
									[EncodingTools hexadecimalString:HA2]];
					
					DDLogVerbose(@" KD: %@", KD );
					NSData* responseData=[EncodingTools MD5:KD];
					// above this is ok
					NSString* response=[NSString stringWithFormat:@"username=\"%@\",realm=\"%@\",nonce=\"%@\",cnonce=\"%@\",nc=00000001,qop=auth,digest-uri=\"xmpp/%@\",response=%@,charset=utf-8",
											self.connectionProperties.identity.user,realm, nonce, cnonce, realm, [EncodingTools hexadecimalString:responseData]];
					//,authzid=\"%@@%@/%@\"  ,account,domain, resource
					
					DDLogVerbose(@"  response :  %@", response);
					NSString* encoded=[EncodingTools encodeBase64WithString:response];
					
					//                NSString* xmppcmd = [NSString stringWithFormat:@"<response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>%@</response>", encoded]
					//                [self talk:xmppcmd];
					
					responseXML.data=encoded;
				}
				
				[self send:responseXML];
				return;
				
			}
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"response"])
		{
			
		}
		else  if([[stanzaToParse objectForKey:@"stanzaType"] isEqualToString:@"success"])
		{
			ParseStream* streamNode= [[ParseStream alloc]  initWithDictionary:stanzaToParse];
			//perform logic to handle proceed
			if(!streamNode.error)
			{
				if(streamNode.SASLSuccess)
				{
					DDLogInfo(@"Got SASL Success");
					
					srand([[NSDate date] timeIntervalSince1970]);
					
					[self startStream];
					self->_accountState=kStateLoggedIn;
					self.connectedTime=[NSDate date];
					self->_loggedInOnce=YES;
					self->_loginStarted=NO;
					self.loginStartTimeStamp=nil;
					
					//reset usable servers list so that the next connect starts with the highest prio server again
					_usableServersList=[[NSMutableArray alloc] init];
					
				}
			}
		}
		stanzaToParse=[self nextStanza];
	}
}

-(void) postConnectNotification
{
    NSDictionary *dic =@{@"AccountNo":self.accountNo, @"AccountName": self.connectionProperties.identity.jid};
    [[NSNotificationCenter defaultCenter] postNotificationName:kMLHasConnectedNotice object:dic];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalAccountStatusChanged object:nil];
    
}


-(void) send:(MLXMLNode*) stanza
{
	if(!stanza) return;
	
	if(self.accountState>=kStateBound && self.connectionProperties.supportsSM3 && self.unAckedStanzas)
	{
		//only count stanzas, not nonzas
		if([stanza.element isEqualToString:@"iq"]
			|| [stanza.element isEqualToString:@"message"]
			|| [stanza.element isEqualToString:@"presence"])
		{
			DDLogVerbose(@"ADD UNACKED STANZA: %@: %@", self.lastOutboundStanza, stanza.XMLString);
			NSDictionary *dic =@{kStanzaID:self.lastOutboundStanza, kStanza:stanza};
			[self.unAckedStanzas addObject:dic];
			//increment for next call
			self.lastOutboundStanza=[NSNumber numberWithInteger:[self.lastOutboundStanza integerValue]+1];
			
			//persist these changes
			[self persistState];
		}
    }
	
	[self enqueueStanzaToSend:stanza];
}


#pragma mark messaging

-(void) sendMessage:(NSString*) message toContact:(NSString*) contact isMUC:(BOOL) isMUC isEncrypted:(BOOL) encrypt isUpload:(BOOL) isUpload andMessageId:(NSString *) messageId
{
    XMPPMessage* messageNode =[[XMPPMessage alloc] init];
    [messageNode.attributes setObject:contact forKey:@"to"];
    [messageNode setXmppId:messageId ];
#ifndef DISABLE_OMEMO
    if(self.signalContext && !isMUC && encrypt) {
        [messageNode setBody:@"[This message is OMEMO encrypted]"];
        
        NSArray *devices = [self.monalSignalStore allDeviceIdsForAddressName:contact];
        NSArray *myDevices = [self.monalSignalStore allDeviceIdsForAddressName:self.connectionProperties.identity.jid];
        if(devices.count>0 ){
            
            NSData *messageBytes=[message dataUsingEncoding:NSUTF8StringEncoding];
            
            MLEncryptedPayload *encryptedPayload = [AESGcm encrypt:messageBytes keySize:16];
            
            MLXMLNode *encrypted =[[MLXMLNode alloc] initWithElement:@"encrypted"];
            [encrypted.attributes setObject:@"eu.siacs.conversations.axolotl" forKey:kXMLNS];
            [messageNode.children addObject:encrypted];
            
            MLXMLNode *payload =[[MLXMLNode alloc] initWithElement:@"payload"];
            [payload setData:[EncodingTools encodeBase64WithData:encryptedPayload.body]];
            [encrypted.children addObject:payload];
            
            
            NSString *deviceid=[NSString stringWithFormat:@"%d",self.monalSignalStore.deviceid];
            MLXMLNode *header =[[MLXMLNode alloc] initWithElement:@"header"];
            [header.attributes setObject:deviceid forKey:@"sid"];
            [encrypted.children addObject:header];
            
            MLXMLNode *ivNode =[[MLXMLNode alloc] initWithElement:@"iv"];
            [ivNode setData:[EncodingTools encodeBase64WithData:encryptedPayload.iv]];
            [header.children addObject:ivNode];
            
            
            [devices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSNumber *device = (NSNumber *)obj;
                SignalAddress *address = [[SignalAddress alloc] initWithName:contact deviceId:(uint32_t)device.intValue];
                NSData *identity=[self.monalSignalStore getIdentityForAddress:address];
                if([self.monalSignalStore isTrustedIdentity:address identityKey:identity]) {
                    
                    SignalSessionCipher *cipher = [[SignalSessionCipher alloc] initWithAddress:address context:self.signalContext];
                    NSError *error;
                    SignalCiphertext* deviceEncryptedKey=[cipher encryptData:encryptedPayload.key error:&error];
                    
                    MLXMLNode *keyNode =[[MLXMLNode alloc] initWithElement:@"key"];
                    [keyNode.attributes setObject:[NSString stringWithFormat:@"%@",device] forKey:@"rid"];
                    if(deviceEncryptedKey.type==SignalCiphertextTypePreKeyMessage)
                    {
                        [keyNode.attributes setObject:@"1" forKey:@"prekey"];
                    }
                    
                    [keyNode setData:[EncodingTools encodeBase64WithData:deviceEncryptedKey.data]];
                    [header.children addObject:keyNode];
                }
                
            }];
            
            [myDevices enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSNumber *device = (NSNumber *)obj;
                SignalAddress *address = [[SignalAddress alloc] initWithName:self.connectionProperties.identity.jid deviceId:(uint32_t)device.intValue];
                NSData *identity=[self.monalSignalStore getIdentityForAddress:address];
                if([self.monalSignalStore isTrustedIdentity:address identityKey:identity]) {
                    SignalSessionCipher *cipher = [[SignalSessionCipher alloc] initWithAddress:address context:self.signalContext];
                    NSError *error;
                    SignalCiphertext* deviceEncryptedKey=[cipher encryptData:encryptedPayload.key error:&error];
                    
                    MLXMLNode *keyNode =[[MLXMLNode alloc] initWithElement:@"key"];
                    [keyNode.attributes setObject:[NSString stringWithFormat:@"%@",device] forKey:@"rid"];
                    if(deviceEncryptedKey.type==SignalCiphertextTypePreKeyMessage)
                    {
                        [keyNode.attributes setObject:@"1" forKey:@"prekey"];
                    }
                    
                    [keyNode setData:[EncodingTools encodeBase64WithData:deviceEncryptedKey.data]];
                    [header.children addObject:keyNode];
                }
            }];
        }
    }
    else  {
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
    
    if(self.airDrop) {
        DDLogInfo(@"Writing to file for Airdop");
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0]; // Get documents directory
        
        [messageNode.attributes setObject:self.connectionProperties.identity.jid forKey:@"from"];
        
        NSString  *myString =[messageNode XMLString];
        NSError *error;
        NSString *path =[documentsDirectory stringByAppendingPathComponent:@"message.xmpp"];
        BOOL succeed = [myString writeToFile:path
                                  atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (!succeed){
            // Handle e@rror here
            DDLogError(@"Error writing to airdrop file");
        }
        
    } else  {
        [self send:messageNode];
    }
}


#pragma mark set connection attributes

-(void) persistState
{
    //state dictionary
    NSMutableDictionary* values = [[NSMutableDictionary alloc] init];
    
    //collect smacks state
    [values setValue:self.lastHandledInboundStanza forKey:@"lastHandledInboundStanza"];
    [values setValue:self.lastHandledOutboundStanza forKey:@"lastHandledOutboundStanza"];
    [values setValue:self.lastOutboundStanza forKey:@"lastOutboundStanza"];
    [values setValue:[self.unAckedStanzas copy] forKey:@"unAckedStanzas"];
    [values setValue:self.streamID forKey:@"streamID"];
    [values setValue:[NSDate date] forKey:@"streamTime"];
    
    [values setValue:[self.connectionProperties.serverFeatures copy] forKey:@"serverFeatures"];
    if(self.connectionProperties.uploadServer) {
        [values setObject:self.connectionProperties.uploadServer forKey:@"uploadServer"];
    }
    if(self.connectionProperties.conferenceServer) {
        [values setObject:self.connectionProperties.conferenceServer forKey:@"conferenceServer"];
    }
    
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
    
    if(self.connectionProperties.pubSubHost)
    {
        [values setObject:self.connectionProperties.pubSubHost forKey:@"pubSubHost"];
    }
    
    //save state dictionary
    [[DataLayer sharedInstance] persistState:values forAccount:self.accountNo];
    
    //debug output
    DDLogVerbose(@"persistState:\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%d%s,\n\tstreamID=%@\n",
                 self.lastHandledInboundStanza,
                 self.lastHandledOutboundStanza,
                 self.lastOutboundStanza,
                 self.unAckedStanzas ? [self.unAckedStanzas count] : 0,
                 self.unAckedStanzas ? "" : " (NIL)",
                 self.streamID
                 );
}

-(void) readState
{
    NSMutableDictionary* dic=[[DataLayer sharedInstance] readStateForAccount:self.accountNo];
    if(dic)
    {
        //collect smacks state
        self.lastHandledInboundStanza=[dic objectForKey:@"lastHandledInboundStanza"];
        self.lastHandledOutboundStanza=[dic objectForKey:@"lastHandledOutboundStanza"];
        self.lastOutboundStanza=[dic objectForKey:@"lastOutboundStanza"];
        NSArray *stanzas= [dic objectForKey:@"unAckedStanzas"];
        self.unAckedStanzas=[stanzas mutableCopy];
        self.streamID=[dic objectForKey:@"streamID"];
        
        self.connectionProperties.serverFeatures = [dic objectForKey:@"serverFeatures"];
        self.connectionProperties.discoveredServices=[dic objectForKey:@"discoveredServices"];
        
        
        self.connectionProperties.uploadServer=[dic objectForKey:@"uploadServer"];
        if(self.connectionProperties.uploadServer)
        {
            self.connectionProperties.supportsHTTPUpload=YES;
        }
        self.connectionProperties.conferenceServer = [dic objectForKey:@"conferenceServer"];
        
        if([dic objectForKey:@"usingCarbons2"])
        {
            NSNumber *carbonsNumber = [dic objectForKey:@"usingCarbons2"];
            self.connectionProperties.usingCarbons2 = carbonsNumber.boolValue;
        }
        
        if([dic objectForKey:@"supportsPush"])
        {
            NSNumber *pushNumber = [dic objectForKey:@"supportsPush"];
            self.connectionProperties.supportsPush = pushNumber.boolValue;
        }
        
        if([dic objectForKey:@"supportsClientState"])
        {
            NSNumber *csiNumber = [dic objectForKey:@"supportsClientState"];
            self.connectionProperties.supportsClientState = csiNumber.boolValue;
        }
        
        if([dic objectForKey:@"supportsMAM"])
        {
            NSNumber *mamNumber = [dic objectForKey:@"supportsMAM"];
            self.connectionProperties.supportsMam2 = mamNumber.boolValue;
        }
        
        if([dic objectForKey:@"supportsPubSub"])
        {
            NSNumber *supportsPubSub = [dic objectForKey:@"supportsPubSub"];
            self.connectionProperties.supportsPubSub = supportsPubSub.boolValue;
        }
        
        if([dic objectForKey:@"supportsHTTPUpload"])
        {
            NSNumber *supportsHTTPUpload = [dic objectForKey:@"supportsHTTPUpload"];
            self.connectionProperties.supportsHTTPUpload = supportsHTTPUpload.boolValue;
        }
        
        if([dic objectForKey:@"supportsPing"])
        {
            NSNumber *supportsPing = [dic objectForKey:@"supportsPing"];
            self.connectionProperties.supportsPing = supportsPing.boolValue;
        }
        
        if([dic objectForKey:@"pubSubHost"])
        {
            NSString *pubSubHost = [dic objectForKey:@"pubSubHost"];
            self.connectionProperties.pubSubHost = pubSubHost;
        }
        
        //debug output
        DDLogVerbose(@"readState:\n\tlastHandledInboundStanza=%@,\n\tlastHandledOutboundStanza=%@,\n\tlastOutboundStanza=%@,\n\t#unAckedStanzas=%d%s,\n\tstreamID=%@",
                     self.lastHandledInboundStanza,
                     self.lastHandledOutboundStanza,
                     self.lastOutboundStanza,
                     self.unAckedStanzas ? [self.unAckedStanzas count] : 0,
                     self.unAckedStanzas ? "" : " (NIL)",
                     self.streamID
                     );
        if(self.unAckedStanzas)
            for(NSDictionary *dic in self.unAckedStanzas)
                DDLogDebug(@"readState unAckedStanza %@: %@", [dic objectForKey:kStanzaID], ((MLXMLNode*)[dic objectForKey:kStanza]).XMLString);
    }
}


-(void) incrementLastHandledStanza {
    if(self.connectionProperties.supportsSM3 && self.accountState>=kStateBound) {
        self.lastHandledInboundStanza=[NSNumber numberWithInteger: [self.lastHandledInboundStanza integerValue]+1];
    }
}

-(void) initSM3
{
    //initialize smacks state
    self.lastHandledInboundStanza=[NSNumber numberWithInteger:0];
    self.lastHandledOutboundStanza=[NSNumber numberWithInteger:0];
    self.lastOutboundStanza=[NSNumber numberWithInteger:0];
    self.unAckedStanzas=[[NSMutableArray alloc] init];
    self.streamID=nil;
    DDLogDebug(@"initSM3 done");
}

-(void) bindResource
{
    XMPPIQ* iqNode =[[XMPPIQ alloc] initWithType:kiqSetType];
    [iqNode setBindWithResource:self.connectionProperties.identity.resource];
    [self send:iqNode];
    
    //now the app is initialized and the next smacks resume will have full disco and presence state information
    self.hasDiscoAndRoster=YES;
}

-(void) disconnectToResumeWithCompletion:(void (^)(void))completion
{
	if(_accountState==kStateLoggedIn)		// race condition. socket may be closed so dont trigger a reconnect
	{
		[self clearNetworkQueues];
		[self.sendQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
			[self sendLastAck];
		}]] waitUntilFinished:YES];			//block until finished because we are closing the socket directly afterwards
	}
	[self closeConnection];		// just closing socket to simulate a unintentional disconnect
	[self.receiveQueue addOperationWithBlock:^{
		[self resetValues];
		if(completion) completion();
	}];
}

-(void) queryDisco
{
    XMPPIQ* discoItems =[[XMPPIQ alloc] initWithType:kiqGetType];
    [discoItems setiqTo:self.connectionProperties.identity.domain];
    MLXMLNode* items = [[MLXMLNode alloc] initWithElement:@"query"];
    [items setXMLNS:@"http://jabber.org/protocol/disco#items"];
    [discoItems.children addObject:items];
    [self send:discoItems];
    
    XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithType:kiqGetType];
    [discoInfo setiqTo:self.connectionProperties.identity.domain];
    [discoInfo setDiscoInfoNode];
    [self send:discoInfo];
}


-(void) sendInitalPresence
{
    XMPPPresence* presence=[[XMPPPresence alloc] initWithHash:_versionHash];
    [presence setPriority:self.priority];
    if(self.statusMessage) [presence setStatus:self.statusMessage];
    if(self.awayState) [presence setAway];
    if(!self.visibleState) [presence setInvisible];
    
    [self send:presence];
#ifndef TARGET_IS_EXTENSION
#if TARGET_OS_IPHONE
    dispatch_async(dispatch_get_main_queue(), ^{
        if([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
        {
#endif
            [self setClientInactive];
#if TARGET_OS_IPHONE
        }
    });
#endif
#endif
    
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalAccountClearContacts object:self userInfo:@{kAccountID:self.accountNo}];
    
    //now we are bound
    _accountState=kStateBound;
    [self postConnectNotification];
    
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
    self.connectionProperties.pubSubHost=nil;
    self.connectionProperties.supportsHTTPUpload=NO;
    self.connectionProperties.supportsPing=NO;
    
    //now fetch roster, request disco and send initial presence
    [self fetchRoster];
    [self queryDisco];
    [self sendInitalPresence];
    
    [self queryMAMSinceLastMessageDate];
}

-(void) setStatusMessageText:(NSString*) message
{
    if([message length]>0)
        self.statusMessage=message;
    else
        message=nil;
    
    XMPPPresence* node =[[XMPPPresence alloc] initWithHash:self.versionHash];
    if(message)[node setStatus:message];
    
    if(self.awayState) [node setAway];
    
    [self send:node];
}

-(void) setAway:(BOOL) away
{
    self.awayState=away;
    XMPPPresence* node =[[XMPPPresence alloc] initWithHash:self.versionHash];
    if(away) {
        [node setAway];
    }
    else {
        [node setAvailable];
    }
    
    if(self.statusMessage) [node setStatus:self.statusMessage];
    [self send:node];
}

-(void) setVisible:(BOOL) visible
{
    self.visibleState=visible;
    XMPPPresence* node =[[XMPPPresence alloc] initWithHash:self.versionHash];
    if(!visible)
        [node setInvisible];
    else
    {
        if(self.statusMessage) [node setStatus:self.statusMessage];
        if(self.awayState) [node setAway];
    }
    
    [self send:node];
}

-(void) updatePriority:(NSInteger) priority
{
    self.priority=priority;
    
    XMPPPresence* node =[[XMPPPresence alloc] initWithHash:self.versionHash];
    [node setPriority:priority];
    [self send:node];
    
}

#pragma mark - OMEMO
                 
#ifndef DISABLE_OMEMO
-(void) setupSignal
{
    self.monalSignalStore = [[MLSignalStore alloc] initWithAccountId:_accountNo];
    
    //signal store
    SignalStorage *signalStorage = [[SignalStorage alloc] initWithSignalStore:self.monalSignalStore];
    //signal context
    self.signalContext= [[SignalContext alloc] initWithStorage:signalStorage];
    //signal helper
    SignalKeyHelper *signalHelper = [[SignalKeyHelper alloc] initWithContext:self.signalContext];
    
    if(self.monalSignalStore.deviceid==0)
    {
        self.monalSignalStore.deviceid=[signalHelper generateRegistrationId];
        
        self.monalSignalStore.identityKeyPair= [signalHelper generateIdentityKeyPair];
        self.monalSignalStore.signedPreKey= [signalHelper generateSignedPreKeyWithIdentity:self.monalSignalStore.identityKeyPair signedPreKeyId:1];
        self.monalSignalStore.preKeys= [signalHelper generatePreKeysWithStartingPreKeyId:0 count:100];
        
        [self.monalSignalStore saveValues];
        
        SignalAddress *address = [[SignalAddress alloc] initWithName:self.connectionProperties.identity.jid deviceId:self.monalSignalStore.deviceid];
        [self.monalSignalStore saveIdentity:address identityKey:self.monalSignalStore.identityKeyPair.publicKey];
        
    }
    
}

-(void) sendSignalInitialStanzas
{
#ifndef TARGET_IS_EXTENSION
    [self queryOMEMODevicesFrom:self.connectionProperties.identity.jid];
    [self sendOMEMOBundle];
#endif
}



-(void) sendOMEMOBundle
{
    if(!self.connectionProperties.supportsPubSub) return;
    NSString *deviceid=[NSString stringWithFormat:@"%d",self.monalSignalStore.deviceid];
    XMPPIQ *signalKeys = [[XMPPIQ alloc] initWithType:kiqSetType];
    [signalKeys publishKeys:@{@"signedPreKeyPublic":self.monalSignalStore.signedPreKey.keyPair.publicKey, @"signedPreKeySignature":self.monalSignalStore.signedPreKey.signature, @"identityKey":self.monalSignalStore.identityKeyPair.publicKey, @"signedPreKeyId": [NSString stringWithFormat:@"%d",self.monalSignalStore.signedPreKey.preKeyId]} andPreKeys:self.monalSignalStore.preKeys withDeviceId:deviceid];
    [signalKeys.attributes setValue:[NSString stringWithFormat:@"%@/%@",self.connectionProperties.identity.jid, self.connectionProperties.identity.resource ] forKey:@"from"];
    [self send:signalKeys];
}

-(void) manageMyKeys
{
    //get current count. If less than 20
    NSMutableArray *keys = [self.monalSignalStore readPreKeys];
    if(keys.count<20) {
        SignalKeyHelper *signalHelper = [[SignalKeyHelper alloc] initWithContext:self.signalContext];
        
        self.monalSignalStore.preKeys= [signalHelper generatePreKeysWithStartingPreKeyId:0 count:80];
        [self.monalSignalStore saveValues];
        
        //load up from db (combined list)
        keys= [self.monalSignalStore readPreKeys];
        self.monalSignalStore.preKeys = keys;
        [self sendOMEMOBundle];
    }
    
}

-(void) subscribeOMEMODevicesFrom:(NSString *) jid
{
    if(!self.connectionProperties.supportsPubSub) return;
       XMPPIQ* query =[[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
       [query setiqTo:self.connectionProperties.pubSubHost];
       [query subscribeDevices:jid];
     
       [self send:query];
}

-(void) queryOMEMODevicesFrom:(NSString *) jid
{
    if(!self.connectionProperties.supportsPubSub) return;
    XMPPIQ* query =[[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqGetType];
    [query setiqTo:jid];
    [query requestDevices];
    if([jid isEqualToString:self.connectionProperties.identity.jid]) {
        self.deviceQueryId=query.stanzaID;
    }
    
    [self send:query];
    
}
#endif

#pragma mark vcard

-(void) getVcards
{
    for (NSDictionary *dic in self.rosterList)
    {
        [[DataLayer sharedInstance] contactForUsername:[dic objectForKey:@"jid"] forAccount:self.accountNo withCompletion:^(NSArray * result) {
            
            MLContact *row = result.firstObject;
            if (row.fullName.length==0)
            {
                [self getVCard:row.contactJid];
            }
            
        }];
    }
    
}

-(void)getVCard:(NSString *) user
{
    XMPPIQ* iqVCard= [[XMPPIQ alloc] initWithType:kiqGetType];
    [iqVCard getVcardTo:user];
    [self send:iqVCard];
}

#pragma mark query info

-(NSString*)getVersionString
{
    // We may need this later
    NSString* unhashed=[NSString stringWithFormat:@"client/phone//Monal %@<%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"], [XMPPIQ featuresString]];
    
    NSData* hashed;
    // <http://jabber.org/protocol/offline<
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    NSData *stringBytes = [unhashed dataUsingEncoding: NSUTF8StringEncoding]; /* or some other encoding */
    if (CC_SHA1([stringBytes bytes], (UInt32)[stringBytes length], digest)) {
        hashed =[NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
    }
    
    NSString* hashedBase64= [EncodingTools encodeBase64WithData:hashed];
    
    DDLogVerbose(@"ver string: unhashed %@, hashed %@, hashed-64 %@", unhashed, hashed, hashedBase64);
    
    
    return hashedBase64;
    
}


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
        XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithType:kiqGetType];
        NSString* jid =[item objectForKey:@"jid"];
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


#pragma mark HTTP upload

-(void) requestHTTPSlotWithParams:(NSDictionary *)params andCompletion:(void(^)(NSString *url,  NSError *error)) completion
{
    NSString *uuid = [[NSUUID UUID] UUIDString];
    XMPPIQ* httpSlotRequest =[[XMPPIQ alloc] initWithId:uuid andType:kiqGetType];
    [httpSlotRequest setiqTo:self.connectionProperties.uploadServer];
    NSData *data= [params objectForKey:kData];
    NSNumber *size=[NSNumber numberWithInteger: data.length];
    
    NSMutableDictionary *iqParams =[NSMutableDictionary dictionaryWithDictionary:params];
    [iqParams setObject:uuid forKey:kId];
    [iqParams setObject:completion forKey:kCompletion];
    
    if(!self.httpUploadQueue)
    {
        self.httpUploadQueue = [[NSMutableArray alloc] init];
    }
    
    [self.httpUploadQueue addObject:iqParams];
    [httpSlotRequest httpUploadforFile:[params objectForKey:kFileName] ofSize:size andContentType:[params objectForKey:kContentType]];
    [self send:httpSlotRequest];
}

-(void) processHTTPIQ:(ParseIq *) iqNode
{
    if(iqNode.httpUpload)
    {
        NSDictionary *matchingRow;
        //look up id val in upload queue array
        for(NSDictionary * row in self.httpUploadQueue)
        {
            if([[row objectForKey:kId] isEqualToString:iqNode.idval])
            {
                matchingRow= row;
                break;
            }
        }
        
        if(matchingRow) {
            
            //upload to put
            dispatch_async(dispatch_get_main_queue(), ^{
                [MLHTTPRequest sendWithVerb:kPut path:iqNode.putURL
                                    headers:@{@"Content-Type":[matchingRow objectForKey:kContentType]}
                              withArguments:nil data:[matchingRow objectForKey:kData] andCompletionHandler:^(NSError *error, id result) {
                    void (^completion) (NSString *url,  NSError *error)  = [matchingRow objectForKey:kCompletion];
                    if(!error)
                    {
                        //send get to contact
                        if(completion)
                        {
                            completion(iqNode.getURL, nil);
                        }
                    } else  {
                        if(completion)
                        {
                            completion(nil, error);
                        }
                    }
                    
                }];
            });
            
        }
    }
}

#pragma mark client state
-(void) setClientActive
{
    if(!self.connectionProperties.supportsClientState) return;
    MLXMLNode *activeNode =[[MLXMLNode alloc] initWithElement:@"active" ];
    [activeNode setXMLNS:@"urn:xmpp:csi:0"];
    [self send:activeNode];
}

-(void) setClientInactive
{
    if(!self.connectionProperties.supportsClientState) return;
    MLXMLNode *activeNode =[[MLXMLNode alloc] initWithElement:@"inactive" ];
    [activeNode setXMLNS:@"urn:xmpp:csi:0"];
    [self send:activeNode];
}

#pragma mark - Message archive


-(void) setMAMPrefs:(NSString *) preference
{
    XMPPIQ* query =[[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
    [query updateMamArchivePrefDefault:preference];
    [self send:query];
}


-(void) getMAMPrefs
{
    XMPPIQ* query =[[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqGetType];
    [query mamArchivePref];
    [self send:query];
}


-(void) setMAMQueryMostRecentForJid:(NSString *)jid
{
    XMPPIQ* query =[[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
    [query setMAMQueryLatestMessagesForJid:jid];
    [self send:query];
}

-(void) setMAMQueryFromStart:(NSDate *) startDate toDate:(NSDate *) endDate withMax:(NSString *) max andJid:(NSString *)jid
{
    XMPPIQ* query =[[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
    [query setMAMQueryFromStart:startDate toDate:endDate withMax:max andJid:jid];
    [self send:query];
}

/* query everything after a certain sanza id
 */
-(void) setMAMQueryFromStart:(NSDate *) startDate after:(NSString *) after  withMax:(NSString *) max andJid:(NSString *)jid
{
    XMPPIQ* query =[[XMPPIQ alloc] initWithId:[[NSUUID UUID] UUIDString] andType:kiqSetType];
    [query setMAMQueryFromStart:startDate after:after withMax:max andJid:jid];
    [self send:query];
}

//-(void) queryMAMSinceLastStanza
//{
//    if(self.connectionProperties.supportsMam2) {
//        [[DataLayer sharedInstance] lastMessageSanzaForAccount:_accountNo  andJid:self.connectionProperties.identity.jid withCompletion:^(NSString *lastStanza) {
//            if(lastStanza) {
//                [self setMAMQueryFromStart:nil after:lastStanza andJid:nil];
//            }
//        }];
//    }
//}


-(void) queryMAMSinceLastMessageDateForContact:(NSString *) contactJid
{
    if(self.connectionProperties.supportsMam2) {
        [[DataLayer sharedInstance] lastMessageDateForContact:contactJid andAccount:self.accountNo withCompletion:^(NSDate *lastDate) {
            if(lastDate) {
                [self setMAMQueryFromStart:[lastDate dateByAddingTimeInterval:1] toDate:nil  withMax:nil andJid:contactJid];
            }
        }];
    }
}

-(void) queryMAMSinceLastMessageDate
{
    if(self.connectionProperties.supportsMam2) {
        [[DataLayer sharedInstance] synchPointforAccount:self.accountNo  withCompletion:^(NSDate *synchDate) {
            [[DataLayer sharedInstance] lastMessageDateForContact:self.connectionProperties.identity.jid andAccount:self.accountNo withCompletion:^(NSDate *lastDate) {
                if(lastDate.timeIntervalSince1970>synchDate.timeIntervalSince1970) { // if there is no last date, there are no messages yet.
                    [self setMAMQueryFromStart:[lastDate dateByAddingTimeInterval:1] toDate:nil withMax:nil andJid:nil];
                }
                else  {
					//TODO: this has a race condition here and doesnt play well with changing the time on the phone
					//use the date of the last message received instead!!
                    [self setMAMQueryFromStart:synchDate toDate:nil withMax:nil andJid:nil];
                }
                [[DataLayer sharedInstance] setSynchpointforAccount:self.accountNo];
            }];
        }];
    }
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
        if(!self.connectionProperties.conferenceServer) DDLogInfo(@"no conference server discovered");
        if(_roomList){
            [[NSNotificationCenter defaultCenter] postNotificationName: kMLHasRoomsNotice object: self];
        }
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
        NSString* from= iqNode.user;
        [[DataLayer sharedInstance] fullNameForContact:from inAccount:self.accountNo withCompeltion:^(NSString *name) {
            NSString *fullName=name;
            if(!fullName) fullName=from;
            
            NSDictionary* userDic=@{@"buddy_name":from,
                                    @"full_name":fullName,
                                    kAccountID:self->_accountNo
            };
            
            [[NSNotificationCenter defaultCenter]
             postNotificationName: kMonalCallStartedNotice object: userDic];
            
            [self.jingle rtpConnect];
        }];
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
                                             kAccountName: self.connectionProperties.identity.jid
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
    if(completion) {
        [self.xmppCompletionHandlers setObject:completion forKey:iq.stanzaID];
    }
    [self send:iq];
}

-(void) requestRegForm
{
    XMPPIQ* iq =[[XMPPIQ alloc] initWithType:kiqGetType];
    [iq setiqTo:self.connectionProperties.identity.domain];
    [iq getRegistrationFields];
    self.registrationState=kStateRequestingForm;
    [self send:iq];
}

-(void) submitRegForm
{
    XMPPIQ* iq =[[XMPPIQ alloc] initWithType:kiqSetType];
    [iq registerUser:self.regUser withPassword:self.regPass captcha:self.regCode andHiddenFields:self.regHidden];
    self.registrationState=kStateSubmittingForm;
    
    [self send:iq];
}


-(void) registerUser:(NSString *) username withPassword:(NSString *) password captcha:(NSString *) captcha andHiddenFields:(NSDictionary *)hiddenFields withCompletion:(xmppCompletion) completion
{
    self.registrationSubmission=YES;
    self.registration=NO;
    self.regUser=username;
    self.regPass=password;
    self.regCode=captcha;
    self.regHidden= hiddenFields;
    
    if(completion) {
        self.regFormSubmitCompletion = completion;
    }
    
}


#pragma mark network I/O

-(void) handleConnectionError: (nw_error_t) error
{
	NSError* st_error = (__bridge NSError*)nw_error_copy_cf_error(error);
	
	DDLogError(@"Stream error code=%ld domain=%@ local desc:%@ ",(long)st_error.code,st_error.domain,  st_error.localizedDescription);
	
	NSString *message =st_error.localizedDescription;
	
	switch(st_error.code)
	{
		case errSSLXCertChainInvalid: {
			message = @"SSL Error: Certificate chain is invalid";
			break;
		}
			
		case errSSLUnknownRootCert: {
			message = @"SSL Error: Unknown root certificate";
			break;
		}
			
		case errSSLCertExpired: {
			message = @"SSL Error: Certificate expired";
			break;
		}
			
		case errSSLHostNameMismatch: {
			message = @"SSL Error: Host name mismatch";
			break;
		}
			
	}
	
	if(!self.registration) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, message, st_error]];
		if(self.loginCompletion)  {
			self.loginCompletion(NO, message);
			self.loginCompletion=nil;
		}
	}
	
	if(_loggedInOnce)
	{
#ifndef TARGET_IS_EXTENSION
#if TARGET_OS_IPHONE
		dispatch_async(dispatch_get_main_queue(), ^{
			if(([UIApplication sharedApplication].applicationState==UIApplicationStateBackground)
				|| ([UIApplication sharedApplication].applicationState==UIApplicationStateInactive )
				&& (self.accountState>=kStateLoggedIn)){
				DDLogInfo(@" Stream error in the background. Ignoring");
				return;
			} else  {
#endif
#endif
				
				
				DDLogInfo(@" stream error calling reconnect for account that logged in once ");
				[self disconnectWithCompletion:^{
					[self reconnect:5];
				}];
				return;
				
#ifndef TARGET_IS_EXTENSION
#if TARGET_OS_IPHONE
			}
		});
#endif
#endif
	}
	
	
	if(st_error.code==2 )// operation couldnt be completed // socket not connected
	{
		[self disconnectWithCompletion:^{
			[self reconnect:5];
		}];
		return;
	}
	
	
	if(st_error.code==60)// could not complete operation
	{
		[self disconnectWithCompletion:^{
			[self reconnect:5];
		}];
		return;
	}
	
	if(st_error.code==64)// Host is down
	{
		[self disconnectWithCompletion:^{
			[self reconnect:5];
		}];
		return;
	}
	
	if(st_error.code==32)// Broken pipe
	{
		[self disconnectWithCompletion:^{
			[self reconnect:5];
		}];
		return;
	}
	
	
	if(st_error.code==-9807)// Could not complete operation. SSL probably
	{
		[self disconnect];
		return;
	}
	

	DDLogInfo(@"unhandled stream error");
	[self disconnectWithCompletion:^{
		[self reconnect:5];
	}];
}

-(void) clearNetworkQueues
{
	//suspend queues to stop not already running tasks
	self.receiveQueue.suspended=YES;
	self.sendQueue.suspended=YES;
	//force running or future loop tasks to stop immediately without processing any data
	_stopConnectionSendLoop=YES;		//force-stop send loop
	_stopConnectionReceiveLoop=YES;		//force-stop receive loop
	//cancel all queued tasks in our network queues
	[self.receiveQueue cancelAllOperations];
	[self.sendQueue cancelAllOperations];
	//clear _outputQueue inside the sendQueue thread
	[self.sendQueue addOperationWithBlock:^{
		_outputQueue=[[NSMutableArray alloc] init];
	}];
	//clear _inputDataBuffer and _inputBuffer inside the receiveQueue thread
	[self.receiveQueue addOperationWithBlock:^{
		_inputDataBuffer=[[NSMutableData alloc] init];
		_inputBuffer=[[NSMutableString alloc] init];
	}];
	//restart queues again
	self.sendQueue.suspended=NO;
	self.receiveQueue.suspended=NO;
}

-(void) initTLS
{
	/*
	NSMutableDictionary *settings = [[NSMutableDictionary alloc] init];
	[settings setObject:self.connectionProperties.identity.domain forKey:kCFStreamSSLPeerName];
	if(self.connectionProperties.server.selfSignedCert)
	{
		DDLogInfo(@"configured self signed SSL");
		[settings setObject:@NO forKey:kCFStreamSSLValidatesCertificateChain];
	}
	
	//this will create an sslContext and, if the underlying TCP socket is already connected, immediately start the ssl handshake
	DDLogInfo(@"configuring SSL handshake");
	if(CFReadStreamSetProperty((__bridge CFReadStreamRef)self->_iStream, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings))
		DDLogInfo(@"Set TLS properties on streams. Security level %@", [self->_iStream propertyForKey:NSStreamSocketSecurityLevelKey]);
	else
	{
		DDLogError(@"not sure.. Could not confirm Set TLS properties on streams.");
		DDLogInfo(@"Set TLS properties on streams.security level %@", [self->_iStream propertyForKey:NSStreamSocketSecurityLevelKey]);
	}
	
	//see this for extracting the sslcontext of the cfstream: https://stackoverflow.com/a/26726525/3528174
	//the ssl context methods (like SSLSetALPNData) are declared in Security/SecureTransportPriv.h and can be found here:
	//https://opensource.apple.com/source/Security/Security-57740.31.2/OSX/libsecurity_ssl/lib/sslContext.c.auto.html
	//this will only have an effect if the TLS handshake was not already started (e.g. the TCP socket is not connected)
	SSLContextRef sslContext = (__bridge SSLContextRef) [_iStream propertyForKey: (__bridge NSString *) kCFStreamPropertySSLContext ];
	SSLSetAllowsAnyRoot(sslContext, 1);
	tls_handshake_set_alpn_data(sslContext->hdsk, alpnData);
	//SSLSetALPNData(sslContext, "\x0Bxmpp-client", 12);
	*/
	
	
	nw_parameters_t parameters = nw_connection_copy_parameters(_connection);
	nw_protocol_stack_t stack = nw_parameters_copy_default_protocol_stack(parameters);
	
	nw_protocol_stack_iterate_application_protocols(stack, ^(nw_protocol_options_t protocol) {
		DDLogInfo(@"initTLS stack entry: %@", protocol);
	});
	
	
	/*
	nw_protocol_definition_t tls = nw_protocol_copy_tls_definition();
	
	nw_protocol_stack_prepend_application_protocol();
	
	configure_tls = ^(nw_protocol_options_t tls_options) {
	};
	sec_protocol_options_t options = nw_tls_copy_sec_protocol_options(tls_options);
	
	sec_protocol_options_set_tls_server_name(options, [self.connectionProperties.identity.domain cStringUsingEncoding:NSUTF8StringEncoding]);
	if(self.connectionProperties.server.selfSignedCert)
	{
		DDLogInfo(@"configured self signed SSL");
		sec_protocol_options_set_peer_authentication_required(options, 0);
	}
	sec_protocol_options_add_tls_application_protocol(options, "\x0Bxmpp-client");
	sec_protocol_options_set_tls_resumption_enabled(options, 1);
	sec_protocol_options_set_tls_tickets_enabled(options, 1);
	*/
}

-(void) openConnection
{
	// do DNS discovery if it hasn't already been set
	if([_discoveredServersList count]==0) {
		_discoveredServersList=[[[MLDNSLookup alloc] init] dnsDiscoverOnDomain:self.connectionProperties.identity.domain];
	}
	
	//if all servers have been tried start over with the first one again
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
	
    if([_usableServersList count]>0) {
		DDLogInfo(@"Using connection parameters discovered via SRV dns record: server=%@, port=%@, isSecure=%s, priority=%@",
			[[_usableServersList objectAtIndex:0] objectForKey:@"server"],
			[[_usableServersList objectAtIndex:0] objectForKey:@"port"],
			[[[_usableServersList objectAtIndex:0] objectForKey:@"isSecure"] boolValue] ? "YES" : "NO",
			[[_usableServersList objectAtIndex:0] objectForKey:@"priority"]
		);
        [self.connectionProperties.server updateConnectServer: [[_usableServersList objectAtIndex:0] objectForKey:@"server"]];
        [self.connectionProperties.server updateConnectPort: [[_usableServersList objectAtIndex:0] objectForKey:@"port"]];
		[self.connectionProperties.server updateConnectTLS: [[[_usableServersList objectAtIndex:0] objectForKey:@"isSecure"] boolValue]];
		//remove this server so that the next connection attempt will try the next server in the list
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
	
	
	DDLogInfo(@"connection creating to  server: %@ port: %@ directTLS: %@", self.connectionProperties.server.connectServer, self.connectionProperties.server.connectPort, self.connectionProperties.server.connectTLS ? @"YES" : @"NO");
	
	dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_source_t streamTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,q_background);
	dispatch_source_set_timer(streamTimer,
							dispatch_time(DISPATCH_TIME_NOW, 5ull * NSEC_PER_SEC),
							DISPATCH_TIME_FOREVER,
							1ull * NSEC_PER_SEC);
	
	dispatch_source_set_event_handler(streamTimer, ^{
		DDLogError(@"stream connection timed out");
		dispatch_source_cancel(streamTimer);
		
		[self disconnect];
	});
	dispatch_source_set_cancel_handler(streamTimer, ^{
		DDLogError(@"stream timer cancelled");
	});
	dispatch_resume(streamTimer);
	
	nw_endpoint_t endpoint = nw_endpoint_create_host(
		[self.connectionProperties.server.connectServer cStringUsingEncoding:NSUTF8StringEncoding],
		[[self.connectionProperties.server.connectPort stringValue] cStringUsingEncoding:NSUTF8StringEncoding]
	);
	//always configure tls
	nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
	
	//extract preconfigured tls_protocol_options for use with nw_protocol_stack_prepend_application_protocol
	nw_parameters_t parameters_with_tls = nw_parameters_create_secure_tcp(^(nw_protocol_options_t tls_options) {
		sec_protocol_options_t options = nw_tls_copy_sec_protocol_options(tls_options);
		sec_protocol_options_set_tls_server_name(options, [self.connectionProperties.identity.domain cStringUsingEncoding:NSUTF8StringEncoding]);
		if(self.connectionProperties.server.selfSignedCert)
		{
			DDLogInfo(@"configured self signed SSL");
			sec_protocol_options_set_peer_authentication_required(options, 0);
		}
		sec_protocol_options_add_tls_application_protocol(options, "xmpp-client");
		sec_protocol_options_set_tls_resumption_enabled(options, 1);
		sec_protocol_options_set_tls_tickets_enabled(options, 1);
	}, NW_PARAMETERS_DEFAULT_CONFIGURATION);
	nw_protocol_stack_t tls_stack = nw_parameters_copy_default_protocol_stack(parameters_with_tls);
	__block nw_protocol_options_t tls_protocol_options;
	nw_protocol_stack_iterate_application_protocols(tls_stack, ^(nw_protocol_options_t protocol) {
		DDLogInfo(@"preconfig stack entry: %@", protocol);
		tls_protocol_options = protocol;
	});
	
	_connection = nw_connection_create(endpoint, parameters_with_tls);
	nw_connection_set_queue(_connection, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
	nw_connection_set_state_changed_handler(_connection, ^(nw_connection_state_t state, nw_error_t error) {
		if(state == nw_connection_state_waiting) {
			//do nothing here, documentation says the connection will be automatically retried "when conditions are favourable"
			//which seems to mean: if the network path changed (for example connectivity regained)
			//if this happens inside the connection timeout all is ok
			//if not, the connection will be cancelled already and everything will be ok, too
		} else if(state == nw_connection_state_failed) {
			DDLogError(@"Connection failed");
			dispatch_source_cancel(streamTimer);
			NSString *message=@"Unable to connect to server";
			[[NSNotificationCenter defaultCenter] postNotificationName:kXMPPError object:@[self, message]];
			if(self.loginCompletion)  {
				self.loginCompletion(NO, message);
				self.loginCompletion=nil;
			}
			[self disconnect];
		} else if(state == nw_connection_state_ready) {
			DDLogInfo(@"Connection established");
			dispatch_source_cancel(streamTimer);
			
			if(self.connectionProperties.server.connectTLS==YES)
			{
				DDLogInfo(@"starting directSSL");
				
				//add tls
				//nw_protocol_stack_t stack = nw_parameters_copy_default_protocol_stack(parameters);
				//nw_protocol_stack_prepend_application_protocol(stack, tls_protocol_options);
				
				[self initTLS];
			}
			
			//allow looping (again)
			_stopConnectionSendLoop=NO;
			_stopConnectionReceiveLoop=NO;
			
			//start receive loop (send looping will be automatically started on first send)
			[self.receiveQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
				[self receiveLoop];
			}]];
			
			//start xml stream
			MLXMLNode* xmlOpening = [[MLXMLNode alloc] initWithElement:@"xml"];
			[self send:xmlOpening];
			[self startStream];
		} else if(state == nw_connection_state_cancelled) {
			DDLogInfo(@"Connection closed");
		}
	});
	
	//clear network queues and start connection
	[self clearNetworkQueues];
	nw_connection_start(_connection);
}

-(void) closeConnection
{
	[self clearNetworkQueues];
	[self.receiveQueue addOperations: @[[NSBlockOperation blockOperationWithBlock:^{
		self.connectedTime =nil;
		self.pingID=nil;
		
		if(_connection)
			nw_connection_cancel(_connection);
		_connection = NULL;
	//block until finished if we are not already in the receiveQueue
	}]] waitUntilFinished:([NSOperationQueue currentQueue]!=self.receiveQueue)];
}

-(void) enqueueStanzaToSend: (MLXMLNode*) stanza
{
	if(_stopConnectionSendLoop) return;			//ignore new request if we are clearing/shutting down the sendQueue
	[self.sendQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
		if(_stopConnectionSendLoop) return;			//ignore new request if we are clearing/shutting down the sendQueue
		
		//add stanza to _outputQueue
		DDLogDebug(@"QUEUED SEND: %@", stanza.XMLString);
		[_outputQueue addObject:stanza];
		
		if(_ConnectionSendIsLooping) return;		//don't start a new loop if already running
		[self sendLoopWithRequestAck:NO];
	}]];
}

-(void) writeNodeToConnection:(MLXMLNode*) node withCompletion: (void (^)(nw_error_t _Nullable error))completion
{
	//don't do anything if no connection is established
	if(!_connection)
	{
		DDLogDebug(@"NOT sending (no connection established): %@", node.XMLString);
		return;
	}
	
	DDLogDebug(@"really sending: %@", node.XMLString);
	const uint8_t *rawstring = (const uint8_t *)[node.XMLString UTF8String];
	dispatch_data_t data = dispatch_data_create(rawstring, strlen((char*)rawstring), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
	nw_connection_send(_connection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t  _Nullable error) {
		//[data release];
		if(completion) {
			completion(error);
		}
	});
}

-(void) sendLoopWithRequestAck: (BOOL) _requestAck
{
	if(!_connectedTime && self.explicitLogout) return;
	__block BOOL requestAck = _requestAck;
	
	//extract the first stanza from the _outputQueue and utf8-encode it into a dispatch_data_t object
	MLXMLNode* node = [_outputQueue firstObject];
	
	//send data
	_ConnectionSendIsLooping=YES;		//this is used to prevent multiple send loops from running
	[self writeNodeToConnection:node withCompletion:^(nw_error_t  _Nullable send_error) {
		//stop looping if *forced* to do so (this will only be done when clearing/shutting down the sendQueue)
		if(_stopConnectionSendLoop)
		{
			_ConnectionSendIsLooping=NO;		//we are not looping anymore
			return;
		}
		//process completion handler in a sendQueue block to make sure everything instruction in this method
		//is always done in the sendQueue thread
		[self.sendQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
			//stop looping if *forced* to do so (this will only be done when clearing/shutting down the sendQueue)
			//do this inside the block again to counter race conditions with clearNetworkQueues
			if(_stopConnectionSendLoop)
			{
				_ConnectionSendIsLooping=NO;		//we are not looping anymore
				return;
			}
			
			[_outputQueue removeObject:node];
			if(send_error != NULL)
			{
				_ConnectionSendIsLooping=NO;		//we are not looping anymore
				DDLogError(@"sending: failed with error %ld (%@)", (long)nw_error_get_error_code(send_error), send_error);
				[self handleConnectionError: send_error];
				return;		//stop send loop
			}
			else
			{
				DDLogVerbose(@"stanza sent to socket...");
				
				if([node isKindOfClass:[XMPPMessage class]])
				{
					XMPPMessage *messageNode = (XMPPMessage *) node;
					NSDictionary *dic =@{kMessageId:messageNode.xmppId};
					[[NSNotificationCenter defaultCenter] postNotificationName: kMonalSentMessageNotice object:self userInfo:dic];
					
				}
				else if([node isKindOfClass:[XMPPIQ class]])
				{
					XMPPIQ *iq = (XMPPIQ *)node;
					if([iq.children count]>0)
					{
						MLXMLNode *child =[iq.children objectAtIndex:0];
						if ([[child element] isEqualToString:@"ping"])
						{
							[self setPingTimerForID:[iq.attributes objectForKey:@"id"]];
						}
					}
				}
				
				//only react to stanzas, not nonzas
				if([node.element isEqualToString:@"iq"]
					|| [node.element isEqualToString:@"message"]
					|| [node.element isEqualToString:@"presence"]) {
					requestAck=YES;
				}
				
				//continue looping over the rest of _outputQueue
				if([_outputQueue count])
					[self sendLoopWithRequestAck:requestAck];
				//the loop ended --> check if we need to request a smacks ack
				else
				{
					if(requestAck)
					{
						//adding the smacks request to the receiveQueue will make sure that we send the request
						//*after* processing an incoming burst of stanzas (which is potentially causing an outgoing burst of stanzas)
						//this reduces the requests to an absolute minimum while still maintaining the rule to request an ack
						//for every outgoing stanza (e.g. one request after prcessing the full queue) while not sending an ack if one is already in flight
						DDLogVerbose(@"adding smacks request to receiveQueue...");
						[self.receiveQueue addOperationWithBlock: ^{
							DDLogVerbose(@"requesting smacks ack...");
							[self requestSMAck];
						}];
					}
					else
						DDLogVerbose(@"NOT requesting smacks ack...");
					
					_ConnectionSendIsLooping=NO;		//we are not looping anymore
					return;
				}
			}
		}]];
	}];
}

-(void) receiveLoop
{
	//stop looping if forced to do so
	if(_stopConnectionReceiveLoop)
		return;
	
	//don't do anything if no connection is established
	if(!_connection)
	{
		DDLogDebug(@"NOT running receiveLoop (no connection established)");
		return;
	}
	
	nw_connection_receive(_connection, 1, UINT32_MAX, ^(dispatch_data_t content, nw_content_context_t context, bool is_complete, nw_error_t receive_error) {
		//stop processing incoming data if forced to do so
		if(_stopConnectionReceiveLoop)
			return;
		
		[self.receiveQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
			//stop processing incoming data if forced to do so
			//do this inside the block again to counter race conditions with clearNetworkQueues
			if(_stopConnectionReceiveLoop)
				return;
			
			//handle content received
			if(content != NULL) {
				DDLogVerbose(@"connection received data");
				[self->_inputDataBuffer appendData:(NSData *)content];
				NSString* inputString=[[NSString alloc] initWithData:self->_inputDataBuffer encoding:NSUTF8StringEncoding];
				if(inputString) {
					[self->_inputBuffer appendString:inputString];
					[self->_inputDataBuffer setLength:0];		//remove all data because it got decoded as utf-8 string now
					[self processInput];
				}
				else {
					DDLogError(@"got data but not string (utf-8 decoding error possibly data is incomplete)");
				}
			}
			
			//check if we're read-closed and stop our loop if true
			//this has to be done *after* processing content
			if(is_complete)
			{
				if(_loggedInOnce)
				{
					DDLogInfo(@"%@ Stream end encoutered.. reconnecting.");
					_loginStarted=NO;
					[self disconnectWithCompletion:^{
						self->_accountState=kStateReconnecting;
						[self reconnect:5];
					}];
				}
				return;		//stop this read loop
			}
			
			//check for errors
			//this has to be done *after* processing content
			if(receive_error != NULL)
			{
				DDLogError(@"receiving: failed with error %ld (%@)", (long)nw_error_get_error_code(receive_error), receive_error);
				[self handleConnectionError: receive_error];
				return;		//stop this read loop
			}
			
			//receive more data
			[self receiveLoop];
		}]];
	});
}

@end
