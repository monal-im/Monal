//
//  xmpp.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <CommonCrypto/CommonCrypto.h>
#import "xmpp.h"
#import "DataLayer.h"
#import "EncodingTools.h"
#import "MLXMPPManager.h"

//objects
#import "XMPPIQ.h"
#import "XMPPPresence.h"
#import "XMPPMessage.h"

//parsers
#import "ParseStream.h"
#import "ParseIq.h"
#import "ParsePresence.h"
#import "ParseMessage.h"
#import "ParseChallenge.h"
#import "ParseFailure.h"

#import "MLImageManager.h"
#import "UIAlertView+Blocks.h"

#define kXMPPReadSize 51200 // bytes

#define kConnectTimeout 20ull //seconds

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@interface xmpp()
{

}
@end


@implementation xmpp

-(id) init
{
    self=[super init];
    
    _discoveredServerList=[[NSMutableArray alloc] init];
    _inputBuffer=[[NSMutableString alloc] init];
    _outputQueue=[[NSMutableArray alloc] init];
    _port=5552;
    _SSL=YES;
    _oldStyleSSL=NO;
    _resource=@"Monal";
    
    NSString* monalNetReadQueue =[NSString  stringWithFormat:@"im.monal.netReadQueue.%@", _accountNo];
    NSString* monalNetWriteQueue =[NSString  stringWithFormat:@"im.monal.netWriteQueue.%@", _accountNo];
    
    _netReadQueue = dispatch_queue_create([monalNetReadQueue UTF8String], DISPATCH_QUEUE_SERIAL);
    _netWriteQueue = dispatch_queue_create([monalNetWriteQueue UTF8String], DISPATCH_QUEUE_SERIAL);
    
    //placing more common at top to reduce iteration
    _stanzaTypes=[NSArray arrayWithObjects:
                  @"iq",
                  @"message",
                  @"presence",
                  @"stream:stream",
                  @"stream",
                  @"features",
                  @"proceed",
                  @"failure",
                  @"challenge",
                  @"response",
                  @"success",
                  nil];
    
    
    _versionHash=[self getVersionString];
    return self;
}

-(void)dealloc
{
    
}

-(void) setRunLoop
{
    
    dispatch_async(dispatch_get_current_queue(), ^{
        [_oStream setDelegate:self];
        [_oStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        [_iStream setDelegate:self];
        [_iStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        [[NSRunLoop currentRunLoop]run];
    });
}

-(void) createStreams
{
    
    NSDictionary* info=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                         kinfoTypeKey:@"connect", kinfoStatusKey:@"Opening Connection"};
    [self.contactsVC showConnecting:info];
    
    CFReadStreamRef readRef= NULL;
    CFWriteStreamRef writeRef= NULL;
	
    DDLogInfo(@"stream  creating to  server: %@ port: %d", _server, _port);
    
	CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)_server, _port, &readRef, &writeRef);
	
    _iStream= (__bridge NSInputStream*)readRef;
    _oStream= (__bridge NSOutputStream*) writeRef;
    
	if((_iStream==nil) || (_oStream==nil))
	{
		DDLogError(@"Connection failed");
		return;
	}
    else
        DDLogInfo(@"streams created ok");
    
    if((CFReadStreamSetProperty((__bridge CFReadStreamRef)_iStream,
                                kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP)) &&
       (CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_oStream,
                                 kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP)))
    {
        DDLogInfo(@"Set VOIP properties on streams.");
    }
    else
    {
        DDLogInfo(@"could not set VOIP properties on streams.");
    }
    
    if((_SSL==YES)  && (_oldStyleSSL==YES))
	{
		// do ssl stuff here
		DDLogInfo(@"securing connection.. for old style");
        
        NSMutableDictionary *settings = [ [NSMutableDictionary alloc ]
                                         initWithObjectsAndKeys:
                                         [NSNull null],kCFStreamSSLPeerName,
                                         kCFStreamSocketSecurityLevelNegotiatedSSL,
                                         kCFStreamSSLLevel,
                                         
                                         
                                         nil ];
        
        if(self.selfSigned)
        {
            NSDictionary* secureOFF= [ [NSDictionary alloc ]
                                      initWithObjectsAndKeys:
                                      [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
                                      [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredRoots,
                                      [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
                                      [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain, nil];
            
            [settings addEntriesFromDictionary:secureOFF];
            
            
            
        }
        
        
		CFReadStreamSetProperty((__bridge CFReadStreamRef)_iStream,
								kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings);
		CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_oStream,
								 kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings);
        
        DDLogInfo(@"connection secured");
	}
	
    
    [self startStream];
    [self setRunLoop];
    
    
    
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t streamTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,q_background
                                                           );
    
    dispatch_source_set_timer(streamTimer,
                              dispatch_time(DISPATCH_TIME_NOW, 5ull * NSEC_PER_SEC),
                              1ull * NSEC_PER_SEC
                              , 1ull * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(streamTimer, ^{
        DDLogError(@"stream connection timed out");
        dispatch_source_cancel(streamTimer);
        [self disconnect];
    });
    
    dispatch_source_set_cancel_handler(streamTimer, ^{
        DDLogError(@"stream timer cancelled");
        dispatch_release(streamTimer);
    });
    
    dispatch_resume(streamTimer);
    
    
    [_iStream open];
    [_oStream open];
    
    NSDictionary* info2=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                          kinfoTypeKey:@"connect", kinfoStatusKey:@"Logging in"};
    [self.contactsVC updateConnecting:info2];
    
    dispatch_source_cancel(streamTimer);
    
    
}

-(void) connectionTask
{
    
    _disconnected=NO;
    _xmppQueue=dispatch_get_current_queue();
    
    _fulluser=[NSString stringWithFormat:@"%@@%@", _username, _domain];
    
    if(_oldStyleSSL==NO)
    {
        // do DNS discovery if it hasn't already been set
        
        if([_discoveredServerList count]==0)
            [self dnsDiscover];
        
    }
    
    if([_discoveredServerList count]>0)
    {
        //sort by priority
        NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"priority"  ascending:YES];
        NSArray* sortArray =[NSArray arrayWithObjects:descriptor,nil];
        [_discoveredServerList sortUsingDescriptors:sortArray];
        
        // take the top one
        
        _server=[[_discoveredServerList objectAtIndex:0] objectForKey:@"server"];
        _port=[[[_discoveredServerList objectAtIndex:0] objectForKey:@"port"] integerValue];
    }
    
    [self createStreams];
    
    
}

-(void) connect
{
    if(_loggedIn || _logInStarted)
    {
        DDLogError(@"assymetrical call to login without a teardown");
        return;
    }
    
    _logInStarted=YES;
    DDLogInfo(@"XMPP connnect  start");
    [self connectionTask];
    
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t loginCancelOperation = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                                    q_background);
    
    dispatch_source_set_timer(loginCancelOperation,
                              dispatch_time(DISPATCH_TIME_NOW, kConnectTimeout* NSEC_PER_SEC),
                              kConnectTimeout* NSEC_PER_SEC,
                              1ull * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(loginCancelOperation, ^{
        DDLogInfo(@"login cancel op");
        
        
        dispatch_async(_xmppQueue, ^{
            //hide connecting message
            NSDictionary* info=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                                 kinfoTypeKey:@"connect", kinfoStatusKey:@""};
            [self.contactsVC hideConnecting:info];
            // try again
            if((!self.loggedIn) && (_loggedInOnce))
            {
                   DDLogInfo(@"trying to login again");
                [self reconnect];
            }
            
        });
        
        dispatch_source_cancel(loginCancelOperation);
        
    });
    
    dispatch_source_set_cancel_handler(loginCancelOperation, ^{
        DDLogInfo(@"login timer cancelled");
        dispatch_release(loginCancelOperation);
        
    });
    
    dispatch_resume(loginCancelOperation);
    
}

-(void) disconnect
{
    
    _loginError=NO;
    
    DDLogInfo(@"removing streams");
    
	//prevent any new read or write
	[_iStream setDelegate:nil];
	[_oStream setDelegate:nil];
	
	[_oStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                        forMode:NSDefaultRunLoopMode];
	
	[_iStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                        forMode:NSDefaultRunLoopMode];
	DDLogInfo(@"removed streams");
	
    dispatch_sync(_netReadQueue, ^{
        @try
        {
            [_iStream close];
            _inputBuffer=[[NSMutableString alloc] init];
        }
        @catch(id theException)
        {
            DDLogError(@"Exception in istream close");
        }
    });
    
    dispatch_sync(_netWriteQueue, ^{
       	@try
        {
            [_oStream close];
            _outputQueue=[[NSMutableArray alloc] init];
        }
        @catch(id theException)
        {
            DDLogError(@"Exception in ostream close");
        }
        
    });
    
    
	[_contactsVC clearContactsForAccount:_accountNo];
    [[DataLayer sharedInstance] resetContactsForAccount:_accountNo];
    
	DDLogInfo(@"Connections closed");
	
	DDLogInfo(@"All closed and cleaned up");
    
    
    _startTLSComplete=NO;
    _streamHasSpace=NO;
    
    
    _loggedIn=NO;
    _disconnected=YES;
    _logInStarted=NO;
	
    //for good measure
    NSDictionary* info=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                         kinfoTypeKey:@"connect", kinfoStatusKey:@""};
    [self.contactsVC hideConnecting:info];
    
    NSDictionary* info2=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                          kinfoTypeKey:@"connect", kinfoStatusKey:@"Disconnected"};
    
    
    if(!_loggedInOnce)
    {
        info2=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                kinfoTypeKey:@"connect", kinfoStatusKey:@"Could not login."};
    }
    
    [self.contactsVC showConnecting:info2];
    dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3ull * NSEC_PER_SEC), q_background,  ^{
        [self.contactsVC hideConnecting:info2];
    });
    
    
    [[DataLayer sharedInstance]  resetContactsForAccount:_accountNo];
    
    
}


-(void) reconnect
{
    DDLogVerbose(@"reconnecting ");
    __block UIBackgroundTaskIdentifier reconnectBackgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^(void) {
        
        DDLogVerbose(@"Reconnect bgtask took too long. closing");
        [[UIApplication sharedApplication] endBackgroundTask:reconnectBackgroundTask];
        reconnectBackgroundTask=UIBackgroundTaskInvalid;
        
    }];
    
    if (reconnectBackgroundTask != UIBackgroundTaskInvalid) {
        [self disconnect];
        DDLogInfo(@"Trying to connect again in 5 seconds. ");
        dispatch_queue_t q_background = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5ull * NSEC_PER_SEC), q_background,  ^{
            [self connect];
            [[UIApplication sharedApplication] endBackgroundTask:reconnectBackgroundTask];
        });
    }
    
}

#pragma mark XMPP

-(void) startStream
{
    //flush read buffer since its all nont needed
    DDLogInfo(@"waiting read queue");
    dispatch_sync(_netReadQueue, ^{
        _inputBuffer=[[NSMutableString alloc] init];
    });
    
    DDLogInfo(@" got read queue");
    
    XMLNode* stream = [[XMLNode alloc] init];
    stream.element=@"stream:stream";
    [stream.attributes setObject:@"jabber:client" forKey:@"xmlns"];
    [stream.attributes setObject:@"http://etherx.jabber.org/streams" forKey:@"xmlns:stream"];
    [stream.attributes setObject:@"1.0" forKey:@"version"];
    if(_domain)
        [stream.attributes setObject:_domain forKey:@"to"];
    [self send:stream];
}


-(void) sendPing
{
    if(!_loggedIn && !_logInStarted)
    {
        DDLogInfo(@" ping calling reconnect");
        [self reconnect];
        return;
    }
    
    XMPPIQ* ping =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
    [ping setiqTo:_domain];
    [ping setPing];
    [self send:ping];
}

-(void) sendWhiteSpacePing
{
    if(!_loggedIn && !_logInStarted)
    {
        DDLogInfo(@" whitespace ping calling reconnect");
        [self reconnect];
        return;
    }
    
    XMLNode* ping =[[XMLNode alloc] initWithElement:@"whitePing"]; // no such element. Node has logic to  print white space
    [self send:ping];
}




-(NSMutableDictionary*) nextStanza
{
    NSString* __block toReturn=nil;
    NSString* __block stanzaType=nil;
    
    dispatch_sync(_netReadQueue, ^{
        int stanzacounter=0;
        int maxPos=[_inputBuffer length];
        DDLogVerbose(@"maxPos %d", maxPos);
        
        if(maxPos<2)
        {
            toReturn= nil;
            return;
        }
        //accouting for white space
        NSRange startrange=[_inputBuffer rangeOfString:@"<"
                                               options:NSCaseInsensitiveSearch range:NSMakeRange(0, [_inputBuffer length])];
        if (startrange.location==NSNotFound)
        {
            toReturn= nil;
            return;
        }
        
        
        int finalstart=0;
        int finalend=0;
        
        
        int startpos=startrange.location;
        DDLogVerbose(@"start pos%d", startpos);
        
        if(maxPos>startpos)
            while(stanzacounter<[_stanzaTypes count])
            {
                //look for the beginning of stanza
                NSRange pos=[_inputBuffer rangeOfString:[NSString stringWithFormat:@"<%@",[_stanzaTypes objectAtIndex:stanzacounter]]
                                                options:NSCaseInsensitiveSearch range:NSMakeRange(startpos, maxPos-startpos)];
                if((pos.location<maxPos) && (pos.location!=NSNotFound))
                {
                    stanzaType=[_stanzaTypes objectAtIndex:stanzacounter];
                    
                    if([[_stanzaTypes objectAtIndex:stanzacounter] isEqualToString:@"stream:stream"])
                    {
                        //no children and one line stanza
                        NSRange endPos=[_inputBuffer rangeOfString:@">"
                                                           options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location, maxPos-pos.location)];
                        
                        if((endPos.location<maxPos) && (endPos.location!=NSNotFound))
                        {
                            
                            finalstart=pos.location;
                            finalend=endPos.location+1;//+2 to inclde closing />
                            DDLogVerbose(@"at  1");
                            break;
                        }
                        
                        
                    }
                    else
                    {
                        
                        
                        NSRange dupePos=[_inputBuffer rangeOfString:[NSString stringWithFormat:@"<%@",[_stanzaTypes objectAtIndex:stanzacounter]]
                                                            options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location+1, maxPos-pos.location-1)];
                        //since there is another block of the same stanza, short cuts dont work.check to find beginning of next element
                        if((dupePos.location<maxPos) && (dupePos.location!=NSNotFound))
                        {
                            //reduce search to within the set of this and at max the next element of the same kind
                            maxPos=dupePos.location;
                            
                        }
                        
                        //  we need to find the end of this stanza
                        NSRange closePos=[_inputBuffer rangeOfString:[NSString stringWithFormat:@"</%@",[_stanzaTypes objectAtIndex:stanzacounter]]
                                                             options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location, maxPos-pos.location)];
                        
                        if((closePos.location<maxPos) && (closePos.location!=NSNotFound))
                        {
                            //we have the start of the stanza close
                            
                            NSRange endPos=[_inputBuffer rangeOfString:@">"
                                                               options:NSCaseInsensitiveSearch range:NSMakeRange(closePos.location, maxPos-closePos.location)];
                            
                            finalstart=pos.location;
                            finalend=endPos.location+1; //+1 to inclde closing <
                            DDLogVerbose(@"at  3");
                            break;
                        }
                        else
                        {
                            //no children and one line stanzas
                            NSRange endPos=[_inputBuffer rangeOfString:@"/>"
                                                               options:NSCaseInsensitiveSearch range:NSMakeRange(pos.location, maxPos-pos.location)];
                            
                            if((endPos.location<maxPos) && (endPos.location!=NSNotFound))
                            {
                                
                                finalstart=pos.location;
                                finalend=endPos.location+2; //+2 to inclde closing />
                                DDLogVerbose(@"at  4");
                                break;
                            }
                            else
                                if([[_stanzaTypes objectAtIndex:stanzacounter] isEqualToString:@"stream"])
                                {
                                    
                                    //stream will have no terminal.
                                    finalstart=pos.location;
                                    finalend=maxPos;
                                    DDLogVerbose(@"at  5");
                                }
                            
                        }
                        
                        
                    }
                }
                stanzacounter++;
            }
        
        //if this happens its  probably a stream error.sanity check is  preventing crash
        if((finalend-finalstart<=maxPos) && finalend!=NSNotFound && finalstart!=NSNotFound)
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
            if((finalend-finalstart<=maxPos) && finalend!=NSNotFound && finalstart!=NSNotFound)
            {
                DDLogVerbose(@"to del start %d end %d: %@", finalstart, finalend, _inputBuffer);
                [_inputBuffer deleteCharactersInRange:NSMakeRange(finalstart, finalend-finalstart) ];
                
                
                DDLogVerbose(@"result: %@", _inputBuffer);
            }
        }
    });
    
    NSMutableDictionary* returnDic=nil;
    
    if(stanzaType && toReturn)
    {
        returnDic=[[NSMutableDictionary alloc]init];
        [returnDic setObject:toReturn forKey:@"stanzaString"];
        [returnDic setObject:stanzaType forKey:@"stanzaType"];
    }
    
	return  returnDic;
}

-(void) processInput
{
    
    NSDictionary* nextStanzaPos=[self nextStanza];
    while (nextStanzaPos)
    {
        DDLogVerbose(@"got stanza %@", nextStanzaPos);
        
        if([[nextStanzaPos objectForKey:@"stanzaType"]  isEqualToString:@"iq"])
        {
            ParseIq* iqNode= [[ParseIq alloc]  initWithDictionary:nextStanzaPos];
            if(iqNode.shouldSetBind)
            {
                _jid=iqNode.jid;
                DDLogVerbose(@"Set jid %@", _jid);
                
                XMPPIQ* sessionQuery= [[XMPPIQ alloc] initWithId:_sessionKey andType:kiqSetType];
                XMLNode* session = [[XMLNode alloc] initWithElement:@"stream"];
                [session setXMLNS:@"urn:ietf:params:xml:ns:xmpp-session"];
                [sessionQuery.children addObject:session];
                [self send:sessionQuery];
                
                XMPPIQ* discoItems =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
                [discoItems setiqTo:_domain];
                XMLNode* items = [[XMLNode alloc] initWithElement:@"query"];
                [items setXMLNS:@"http://jabber.org/protocol/disco#items"];
                [discoItems.children addObject:items];
                [self send:discoItems];
                
                XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
                [discoInfo setiqTo:_domain];
                [discoInfo setDiscoInfoNode];
                [self send:discoInfo];
                
                
                //no need to pull roster on every call if disconenct
                if(!_rosterList)
                {
                    XMPPIQ* roster =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
                    [roster setRosterRequest];
                    [self send:roster];
                }
                
                self.priority= [[[NSUserDefaults standardUserDefaults] stringForKey:@"XMPPPriority"] integerValue];
                self.statusMessage=[[NSUserDefaults standardUserDefaults] stringForKey:@"StatusMessage"];
                self.awayState=[[NSUserDefaults standardUserDefaults] boolForKey:@"Away"];
                self.visibleState=[[NSUserDefaults standardUserDefaults] boolForKey:@"Visible"];
                
                XMPPPresence* presence =[[XMPPPresence alloc] initWithHash:_versionHash];
                [presence setPriority:self.priority];
                if(self.statusMessage) [presence setStatus:self.statusMessage];
                if(self.awayState) [presence setAway];
                if(!self.visibleState) [presence setInvisible];
                
                [self send:presence];
                
            }
            
            if((iqNode.discoInfo)  && [iqNode.from isEqualToString:self.server])
            {
                
                XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqResultType];
                [discoInfo setiqTo:iqNode.from];
                [discoInfo setDiscoInfoWithFeatures];
                
                [self send:discoInfo];
                
            }
            
            if(iqNode.vCard)
            {
                NSString* fullname=iqNode.fullName;
                if(iqNode.fullName)
                {
                    [[DataLayer sharedInstance] setFullName:iqNode.fullName forBuddy:iqNode.user andAccount:_accountNo];
                }
                
                if(iqNode.photoBinValue)
                {
                    [[MLImageManager sharedInstance] setIconForContact:iqNode.user andAccount:_accountNo WithData:iqNode.photoBinValue ];
                }
                
                if(!fullname) fullname=iqNode.user;
                
                NSDictionary* userDic=@{kusernameKey: iqNode.user,
                                        kfullNameKey: fullname,
                                        kaccountNoKey:_accountNo
                                        };
                
                dispatch_async(_xmppQueue, ^{
                    [self.contactsVC addOnlineUser:userDic];
                });
                
            }
            
            if(iqNode.ping)
            {
                XMPPIQ* pong =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqResultType];
                [pong setiqTo:_domain];
                [self send:pong];
            }
            
            if(iqNode.ping)
            {
                XMPPIQ* pong =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqResultType];
                [pong setiqTo:_domain];
                [self send:pong];
            }
            
            if ([iqNode.type isEqualToString:kiqResultType])
            {
                if(iqNode.discoItems==YES)
                {
                    if([iqNode.from isEqualToString:self.server])
                    {
                        for (NSDictionary* item in iqNode.items)
                        {
                            if(!_discoveredServices) _discoveredServices=[[NSMutableArray alloc] init];
                            [_discoveredServices addObject:item];
                        }
                    }
                    else
                    {
                        
                    }
                }
                else if (iqNode.roster==YES)
                {
                    self.rosterList=iqNode.items;
                    
                    for(NSDictionary* contact in self.rosterList)
                    {
                        
                        if([[contact objectForKey:@"subscription"] isEqualToString:@"both"])
                        {
                            if(![[DataLayer sharedInstance] isBuddyInList:[contact objectForKey:@"jid"] forAccount:_accountNo])
                            {
                                [[DataLayer sharedInstance] addBuddy:[contact objectForKey:@"jid"]?[contact objectForKey:@"jid"]:@"" forAccount:_accountNo fullname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@"" nickname:[contact objectForKey:@"name"]?[contact objectForKey:@"name"]:@""];
                            }
                        }
                        else
                        {
                            
                        }
                    }
                    
                }
            }
            
            
            //*** MUC related
            if(iqNode.conferenceServer)
            {
                _conferenceServer=iqNode.conferenceServer;
            }
            
            if([iqNode.from isEqualToString:_conferenceServer] && iqNode.discoItems)
            {
                _roomList=iqNode.items;
                [[NSNotificationCenter defaultCenter]
                 postNotificationName: kMLHasRoomsNotice object: self];
            }
            
            
        }
        else  if([[nextStanzaPos objectForKey:@"stanzaType"]  isEqualToString:@"message"])
        {
            ParseMessage* messageNode= [[ParseMessage alloc]  initWithDictionary:nextStanzaPos];
            if([messageNode.type isEqualToString:kMessageErrorType])
            {
                //TODO: mark message as error
                return;
            }
            
            
            if(messageNode.mucInvite)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"You have been invited to a conversation %@?", nil), messageNode.from ];
                    RIButtonItem* cancelButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Cancel", nil) action:^{
                        
                    }];
                    
                    RIButtonItem* yesButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Join", nil) action:^{
                        
                        [self joinRoom:messageNode.from withPassword:nil];
                    }];
                    
                    UIAlertView* alert =[[UIAlertView alloc] initWithTitle:@"Chat Invite" message:messageString cancelButtonItem:cancelButton otherButtonItems:yesButton, nil];
                    [alert show];
                });
                
            }
            
            if(messageNode.hasBody)
            {
                if ([messageNode.type isEqualToString:kMessageGroupChatType]
                    && [messageNode.actualFrom isEqualToString:_username])
                {
                    //this is just a muc echo
                }
                else
                {
                    [[DataLayer sharedInstance] addMessageFrom:messageNode.from to:_fulluser
                                                    forAccount:_accountNo withBody:messageNode.messageText
                                                  actuallyfrom:messageNode.actualFrom];
                    
                    [[DataLayer sharedInstance] addActiveBuddies:messageNode.from forAccount:_accountNo];
                    
                    NSDictionary* userDic=@{@"from":messageNode.from,
                                            @"actuallyfrom":messageNode.actualFrom,
                                            @"messageText":messageNode.messageText,
                                            @"to":_fulluser,
                                            @"accountNo":_accountNo
                                            };
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalNewMessageNotice object:self userInfo:userDic];
                }
            }
            
            if(messageNode.avatarData)
            {
                [[MLImageManager sharedInstance] setIconForContact:messageNode.actualFrom andAccount:_accountNo WithData:messageNode.avatarData];
                
            }
            
        }
        else  if([[nextStanzaPos objectForKey:@"stanzaType"]  isEqualToString:@"presence"])
        {
            ParsePresence* presenceNode= [[ParsePresence alloc]  initWithDictionary:nextStanzaPos];
            if([presenceNode.user isEqualToString:_fulluser])
                return; //ignore self
            
            if([presenceNode.type isEqualToString:kpresencesSubscribe])
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString* messageString = [NSString  stringWithFormat:NSLocalizedString(@"Do you wish to allow %@ to add you to their contacts?", nil), presenceNode.from ];
                    RIButtonItem* cancelButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"No", nil) action:^{
                        [self rejectFromRoster:presenceNode.from];
                        
                    }];
                    
                    RIButtonItem* yesButton = [RIButtonItem itemWithLabel:NSLocalizedString(@"Yes", nil) action:^{
                        [self approveToRoster:presenceNode.from];
                        [self addToRoster:presenceNode.from];
                        
                    }];
                    
                    UIAlertView* alert =[[UIAlertView alloc] initWithTitle:@"Approve Contact" message:messageString cancelButtonItem:cancelButton otherButtonItems:yesButton, nil];
                    [alert show];
                });
                
                
                
            }
            
            if(presenceNode.type ==nil)
            {
                DDLogVerbose(@"presence priority notice from %@", presenceNode.user);
                
                if((presenceNode.user!=nil) && ([[presenceNode.user stringByTrimmingCharactersInSet:
                                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0))
                {
                    if(![[DataLayer sharedInstance] isBuddyInList:presenceNode.user forAccount:_accountNo])
                    {
                        DDLogVerbose(@"Buddy not already in list");
                        [[DataLayer sharedInstance] addBuddy:presenceNode.user forAccount:_accountNo fullname:@"" nickname:@"" ];
                    }
                    else
                    {
                        DDLogVerbose(@"Buddy already in list");
                    }
                    
                    DDLogVerbose(@" showing as online now");
                    
                    [[DataLayer sharedInstance] setOnlineBuddy:presenceNode forAccount:_accountNo];
                    [[DataLayer sharedInstance] setBuddyState:presenceNode forAccount:_accountNo];
                    [[DataLayer sharedInstance] setBuddyStatus:presenceNode forAccount:_accountNo];
                    
                    NSString* state=presenceNode.show;
                    if(!state) state=@"";
                    NSString* status=presenceNode.status;
                    if(!status) status=@"";
                    NSDictionary* userDic=@{kusernameKey: presenceNode.user,
                                            kaccountNoKey:_accountNo,
                                            kstateKey:state,
                                            kstatusKey:status
                                            };
                    dispatch_async(_xmppQueue, ^{
                        [self.contactsVC addOnlineUser:userDic];
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactOnlineNotice object:self userInfo:userDic];
                    });
                    
                    // do not do this in the background
                    if([UIApplication sharedApplication].applicationState!=UIApplicationStateBackground)
                    {
                        //check for vcard change
                        if([presenceNode.photoHash isEqualToString:[[DataLayer sharedInstance]  buddyHash:presenceNode.user forAccount:_accountNo]])
                        {
                            DDLogVerbose(@"photo hash is the  same");
                        }
                        else
                        {
                            [[DataLayer sharedInstance]  setBuddyHash:presenceNode forAccount:_accountNo];
                            XMPPIQ* iqVCard= [[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
                            [iqVCard getVcardTo:presenceNode.user];
                            [self send:iqVCard];
                        }
                    }
                    else
                    {
                        // just set and request when in foreground if needed
                        [[DataLayer sharedInstance]  setBuddyHash:presenceNode forAccount:_accountNo];
                    }
                    
                    
                }
                else
                {
                    DDLogError(@"ERROR: presence priority notice but no user name.");
                    
                }
            }
            else if([presenceNode.type isEqualToString:kpresenceUnavailable])
            {
                if ([[DataLayer sharedInstance] setOfflineBuddy:presenceNode forAccount:_accountNo] ) {
                NSDictionary* userDic=@{kusernameKey: presenceNode.user,
                                        kaccountNoKey:_accountNo};
                dispatch_async(_xmppQueue, ^{
                    [self.contactsVC removeOnlineUser:userDic];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMonalContactOfflineNotice object:self userInfo:userDic];
                });
                }
                
            }
            
        }
        else  if([[nextStanzaPos objectForKey:@"stanzaType"] isEqualToString:@"stream:stream"])
        {
            //  ParseStream* streamNode= [[ParseStream alloc]  initWithDictionary:nextStanzaPos];
        }
        else  if([[nextStanzaPos objectForKey:@"stanzaType"] isEqualToString:@"stream"])
        {
            ParseStream* streamNode= [[ParseStream alloc]  initWithDictionary:nextStanzaPos];
            
            //perform logic to handle stream
            if(streamNode.error)
            {
                return;
                
            }
            
            if(!_loggedIn)
            {
                
                if(streamNode.callStartTLS)
                {
                    XMLNode* startTLS= [[XMLNode alloc] init];
                    startTLS.element=@"starttls";
                    [startTLS.attributes setObject:@"urn:ietf:params:xml:ns:xmpp-tls" forKey:@"xmlns"];
                    [self send:startTLS];
                    
                }
                
                if ((_SSL && _startTLSComplete) || (!_SSL && !_startTLSComplete))
                {
                    //look at menchanisms presented
                    
                    if(streamNode.SASLPlain)
                    {
                        NSString* saslplain=[EncodingTools encodeBase64WithString: [NSString stringWithFormat:@"\0%@\0%@",  _username, _password ]];
                        
                        XMLNode* saslXML= [[XMLNode alloc]init];
                        saslXML.element=@"auth";
                        [saslXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:@"xmlns"];
                        [saslXML.attributes setObject: @"PLAIN"forKey: @"mechanism"];
                        
                        //google only uses sasl plain
                        [saslXML.attributes setObject:@"http://www.google.com/talk/protocol/auth" forKey: @"xmlns:ga"];
                        [saslXML.attributes setObject:@"true" forKey: @"ga:client-uses-full-bind-result"];
                        
                        saslXML.data=saslplain;
                        [self send:saslXML];
                        
                    }
                    else
                        if(streamNode.SASLDIGEST_MD5)
                        {
                            XMLNode* saslXML= [[XMLNode alloc]init];
                            saslXML.element=@"auth";
                            [saslXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:@"xmlns"];
                            [saslXML.attributes setObject: @"DIGEST-MD5"forKey: @"mechanism"];
                            
                            [self send:saslXML];
                        }
                        else
                        {
                            //no supported auth mechanism
                            [self disconnect];
                        }
                }
            }
            else
            {
                XMPPIQ* iqNode =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqSetType];
                [iqNode setBindWithResource:_resource];
                
                [self send:iqNode];
                
            }
            
        }
        else  if([[nextStanzaPos objectForKey:@"stanzaType"] isEqualToString:@"features"])
        {
            
        }
        else  if([[nextStanzaPos objectForKey:@"stanzaType"] isEqualToString:@"proceed"])
        {
            
            ParseStream* streamNode= [[ParseStream alloc]  initWithDictionary:nextStanzaPos];
            //perform logic to handle proceed
            if(!streamNode.error)
            {
                if(streamNode.startTLSProceed)
                {
                    NSMutableDictionary *settings = [ [NSMutableDictionary alloc ]
                                                     initWithObjectsAndKeys:
                                                     [NSNull null],kCFStreamSSLPeerName,
                                                     kCFStreamSocketSecurityLevelNegotiatedSSL,
                                                     kCFStreamSSLLevel,
                                                     nil ];
                    
                    if(self.selfSigned)
                    {
                        NSDictionary* secureOFF= [ [NSDictionary alloc ]
                                                  initWithObjectsAndKeys:
                                                  [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredCertificates,
                                                  [NSNumber numberWithBool:YES], kCFStreamSSLAllowsExpiredRoots,
                                                  [NSNumber numberWithBool:YES], kCFStreamSSLAllowsAnyRoot,
                                                  [NSNumber numberWithBool:NO], kCFStreamSSLValidatesCertificateChain, nil];
                        
                        [settings addEntriesFromDictionary:secureOFF];
                        
                        
                        
                    }
                    
                    if ( 	CFReadStreamSetProperty((__bridge CFReadStreamRef)_iStream,
                                                    kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings) &&
                        CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_oStream,
                                                 kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings)	 )
                        
                    {
                        DDLogInfo(@"Set TLS properties on streams.");
                        NSDictionary* info2=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                                              kinfoTypeKey:@"connect", kinfoStatusKey:@"Securing Connection"};
                        [self.contactsVC updateConnecting:info2];
                    }
                    else
                    {
                        DDLogError(@"not sure.. Could not confirm Set TLS properties on streams.");
                        
                        //                        NSDictionary* info2=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                        //                                              kinfoTypeKey:@"connect", kinfoStatusKey:@"Could not secure connection"};
                        //                        [self.contactsVC updateConnecting:info2];
                        
                    }
                    
                    [self startStream];
                    
                    _startTLSComplete=YES;
                }
            }
        }
        else  if([[nextStanzaPos objectForKey:@"stanzaType"] isEqualToString:@"failure"])
        {
            ParseFailure* failure = [[ParseFailure alloc] initWithDictionary:nextStanzaPos];
            if(failure.saslError && failure.notAuthorized)
            {
                _loginError=YES;
            }
            
        }
        else  if([[nextStanzaPos objectForKey:@"stanzaType"] isEqualToString:@"challenge"])
        {
            ParseChallenge* challengeNode= [[ParseChallenge alloc]  initWithDictionary:nextStanzaPos];
            if(challengeNode.saslChallenge)
            {
                XMLNode* responseXML= [[XMLNode alloc]init];
                responseXML.element=@"response";
                [responseXML.attributes setObject: @"urn:ietf:params:xml:ns:xmpp-sasl"  forKey:@"xmlns"];
                
                
                NSString* decoded=[[NSString alloc]  initWithData: (NSData*)[EncodingTools dataWithBase64EncodedString:challengeNode.challengeText] encoding:NSASCIIStringEncoding];
                DDLogVerbose(@"decoded challenge to %@", decoded);
                NSArray* parts =[decoded componentsSeparatedByString:@","];
                if([parts count]<2)
                {
                    //this is a success message  form challenge
                    
                    NSArray* rspparts= [[parts objectAtIndex:0] componentsSeparatedByString:@"="];
                    if([[rspparts objectAtIndex:0] isEqualToString:@"rspauth"])
                    {
                        DDLogVerbose(@"digest-md5 success");
                        
                    }
                    
                }
                else{
                    
                    NSArray* realmparts= [[parts objectAtIndex:0] componentsSeparatedByString:@"="];
                    NSArray* nonceparts= [[parts objectAtIndex:1] componentsSeparatedByString:@"="];
                    
                    NSString* realm=[[realmparts objectAtIndex:1] substringWithRange:NSMakeRange(1, [[realmparts objectAtIndex:1] length]-2)] ;
                    NSString* nonce=[nonceparts objectAtIndex:1] ;
                    nonce=[nonce substringWithRange:NSMakeRange(1, [nonce length]-2)];
                    
                    //if there is no realm
                    if(![[realmparts objectAtIndex:0]  isEqualToString:@"realm"])
                    {
                        realm=@"";
                        nonce=[realmparts objectAtIndex:1];
                    }
                    
                    NSData* cnonce_Data=[EncodingTools MD5: [NSString stringWithFormat:@"%d",arc4random()%100000]];
                    NSString* cnonce =[EncodingTools hexadecimalString:cnonce_Data];
                    
                    
                    //                if([password length]==0)
                    //                {
                    //                    if(theTempPass!=NULL)
                    //                        password=theTempPass;
                    //
                    //                }
                    
                    //  nonce=@"580F35C1AE408E7DA57DE4DEDC5B9CA7";
                    //    cnonce=@"B9E01AE3-29E5-4FE5-9AA0-72F99742428A";
                    
                    
                    // ****** digest stuff going on here...
                    NSString* X= [NSString stringWithFormat:@"%@:%@:%@", self.username, realm, self.password ];
                    DDLogVerbose(@"X: %@", X);
                    
                    NSData* Y = [EncodingTools MD5:X];
                    
                    // above is correct
                    
                    /*
                     NSString* A1= [NSString stringWithFormat:@"%@:%@:%@:%@@%@/%@",
                     Y,[nonce substringWithRange:NSMakeRange(1, [nonce length]-2)],cononce,account,domain,resource];
                     */
                    
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
                    
                    
                    //this hash is wrong..
                    NSData* HA1=[EncodingTools DataMD5:HA1data];
                    
                    //below is correct
                    
                    NSString* A2=[NSString stringWithFormat:@"AUTHENTICATE:xmpp/%@", realm];
                    DDLogVerbose(@"%@", A2);
                    NSData* HA2=[EncodingTools MD5:A2];
                    
                    NSString* KD=[NSString stringWithFormat:@"%@:%@:00000001:%@:auth:%@",
                                  [EncodingTools hexadecimalString:HA1], nonce,
                                  cnonce,
                                  [EncodingTools hexadecimalString:HA2]];
                    
                    // DDLogVerbose(@" ha1: %@", [self hexadecimalString:HA1] );
                    //DDLogVerbose(@" ha2: %@", [self hexadecimalString:HA2] );
                    
                    DDLogVerbose(@" KD: %@", KD );
                    NSData* responseData=[EncodingTools MD5:KD];
                    // above this is ok
                    NSString* response=[NSString stringWithFormat:@"username=\"%@\",realm=\"%@\",nonce=\"%@\",cnonce=\"%@\",nc=00000001,qop=auth,digest-uri=\"xmpp/%@\",response=%@,charset=utf-8",
                                        self.username,realm, nonce, cnonce, realm, [EncodingTools hexadecimalString:responseData]];
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
        else  if([[nextStanzaPos objectForKey:@"stanzaType"] isEqualToString:@"response"])
        {
            
        }
        else  if([[nextStanzaPos objectForKey:@"stanzaType"] isEqualToString:@"success"])
        {
            ParseStream* streamNode= [[ParseStream alloc]  initWithDictionary:nextStanzaPos];
            //perform logic to handle proceed
            if(!streamNode.error)
            {
                if(streamNode.SASLSuccess)
                {
                    DDLogInfo(@"Got SASL Success");
                    
                    srand([[NSDate date] timeIntervalSince1970]);
                    // make up a random session key (id)
                    _sessionKey=[NSString stringWithFormat:@"monal%ld",random()%100000];
                    DDLogVerbose(@"session key: %@", _sessionKey);
                    
                    [self startStream];
                    _loggedIn=YES;
                    _loggedInOnce=YES;
                    
                    
                    NSDictionary* info=@{kaccountNameKey:_fulluser, kaccountNoKey:_accountNo,
                                         kinfoTypeKey:@"connect", kinfoStatusKey:@""};
                    dispatch_async(_xmppQueue, ^{
                        [self.contactsVC hideConnecting:info];
                    });
                    
                }
            }
        }
        
        nextStanzaPos=[self nextStanza];
    }
}



-(void) send:(XMLNode*) stanza
{
    dispatch_async(_xmppQueue, ^{
        dispatch_async(_netWriteQueue, ^{
            [_outputQueue addObject:stanza];
            [self writeFromQueue];  // try to send if there is space
        });
    });
}


#pragma mark messaging

-(void) sendMessage:(NSString*) message toContact:(NSString*) contact isMUC:(BOOL) isMUC
{
    XMPPMessage* messageNode =[[XMPPMessage alloc] init];
    [messageNode.attributes setObject:contact forKey:@"to"];
    [messageNode setBody:message];
    
    if(isMUC)
    {
        [messageNode.attributes setObject:kMessageGroupChatType forKey:@"type"];
    }
    
    [self send:messageNode];
}


#pragma mark set connection attributes
-(void) setStatusMessageText:(NSString*) message
{
    if([message length]>0)
        self.statusMessage=message;
    else
        message=nil;
    
    XMPPPresence* node =[[XMPPPresence alloc] init];
    if(message)[node setStatus:message];
    
    if(self.awayState) [node setAway];
    
    [self send:node];
}

-(void) setAway:(BOOL) away
{
    self.awayState=away;
    XMPPPresence* node =[[XMPPPresence alloc] init];
    if(away)
        [node setAway];
    else
        [node setAvailable];
    
    if(self.statusMessage) [node setStatus:self.statusMessage];
    [self send:node];
}

-(void) setVisible:(BOOL) visible
{
    self.visibleState=visible;
    XMPPPresence* node =[[XMPPPresence alloc] init];
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
    
    XMPPPresence* node =[[XMPPPresence alloc] init];
    [node setPriority:priority];
    [self send:node];
    
}



#pragma mark query info

-(NSString*)getVersionString
{
    
    NSString* unhashed=[NSString stringWithFormat:@"client/pc//Monal %@<http://jabber.org/protocol/caps<http://jabber.org/protocol/disco#info<http://jabber.org/protocol/disco#items<http://jabber.org/protocol/muc<<http://jabber.org/protocol/offline<", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ];
    NSData* hashed;
    
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    NSData *stringBytes = [unhashed dataUsingEncoding: NSUTF8StringEncoding]; /* or some other encoding */
    if (CC_SHA1([stringBytes bytes], [stringBytes length], digest)) {
        hashed =[NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
    }
    
    NSString* hashedBase64= [EncodingTools encodeBase64WithData:hashed];
    
    
    return hashedBase64;
    
}


-(void) getServiceDetails
{
    if(_hasRequestedServerInfo)
        return;  // no need to call again on disconnect
    
    if(!_discoveredServices)
    {
        DDLogInfo(@"no discovered services");
        return;
    }
    
    for (NSDictionary *item in _discoveredServices)
    {
        XMPPIQ* discoInfo =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
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

#pragma mark  MUC

-(void) getConferenceRooms
{
    if(_conferenceServer)
    {
        XMPPIQ* discoItem =[[XMPPIQ alloc] initWithId:_sessionKey andType:kiqGetType];
        [discoItem setiqTo:_conferenceServer];
        [discoItem setDiscoItemNode];
        [self send:discoItem];
    }
    else
    {
        DDLogInfo(@"no conference server discovered");
    }
}


-(void) joinRoom:(NSString*) room withPassword:(NSString *)password
{
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    NSArray* parts =[room componentsSeparatedByString:@"@"];
    if([parts count]>1)
    {
        [presence joinRoom:[parts objectAtIndex:0] withPassword:password onServer:[parts objectAtIndex:1] withName:_username];
        //allow nick name in the future
        
    }
    else{
        [presence joinRoom:room withPassword:password onServer:_conferenceServer withName:_username]; //allow nick name in the future
        
    }
    [self send:presence];
}

-(void) leaveRoom:(NSString*) room
{
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    [presence leaveRoom:room onServer:_conferenceServer withName:_username];
    [self send:presence];
}


#pragma mark XMPP add and remove contact
-(void) removeFromRoster:(NSString*) contact
{
    XMPPIQ* iq = [[XMPPIQ alloc] initWithId:_sessionKey andType:kiqSetType];
    [iq setRemoveFromRoster:contact];
    [self send:iq];
    
    XMPPPresence* presence =[[XMPPPresence alloc] init];
    [presence unsubscribeContact:contact];
    [self send:presence];
    
    
    XMPPPresence* presence2 =[[XMPPPresence alloc] init];
    [presence2 unsubscribedContact:contact];
    [self send:presence2];
    
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
    [self send:presence];
    
    
}

-(void) approveToRoster:(NSString*) contact
{
    
    XMPPPresence* presence2 =[[XMPPPresence alloc] init];
    [presence2 subscribedContact:contact];
    [self send:presence2];
}

#pragma mark nsstream delegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
	DDLogVerbose(@"Stream has event");
	switch(eventCode)
	{
			//for writing
        case NSStreamEventHasSpaceAvailable:
        {
            dispatch_async(_xmppQueue, ^{
                dispatch_async(_netWriteQueue, ^{
                    _streamHasSpace=YES;
                    
                    DDLogVerbose(@"Stream has space to write");
                    [self writeFromQueue];
                });
            });
            break;
        }
			
			//for reading
        case  NSStreamEventHasBytesAvailable:
		{
			DDLogVerbose(@"Stream has bytes to read");
            dispatch_async(_xmppQueue, ^{
                [self readToBuffer];
            });
            
			
			break;
		}
			
		case NSStreamEventErrorOccurred:
		{
			NSError* st_error= [stream streamError];
            DDLogError(@"Stream error code=%d domain=%@   local desc:%@ ",st_error.code,st_error.domain,  st_error.localizedDescription);
            
            
            if(st_error.code==2)// operation couldnt be completed
            {
                
            }
            
            
            if(st_error.code==2)// socket not connected
            {
                
            }
            
            if(st_error.code==61)// Connection refused
            {
                
            }
            
            
            if(st_error.code==64)// Host is down
            {
                
            }
            
            if(st_error.code==-9807)// Could not complete operation. SSL probably
            {
                [self disconnect];
                return;
            }
            
            if(_loggedInOnce)
            {
                DDLogInfo(@" stream error calling reconnect");
                [self reconnect];
            }
            
            else
            {
                // maybe account never worked and should be disabled and reachability should be removed
                //                [[DataLayer sharedInstance] disableEnabledAccount:_accountNo];
                //                [[MLXMPPManager sharedInstance] disconnectAccount:_accountNo];
                
            }
            break;
            
		}
		case NSStreamEventNone:
		{
            //DDLogVerbose(@"Stream event none");
			break;
			
		}
			
			
		case NSStreamEventOpenCompleted:
		{
			DDLogInfo(@"Stream open completed");
            break;
		}
			
			
		case NSStreamEventEndEncountered:
		{
			DDLogInfo(@"%@ Stream end encoutered", [stream class] );
            [self disconnect];
			break;
		}
			
	}
	
}

#pragma mark network I/O
-(void) writeFromQueue
{
    if(!_streamHasSpace)
    {
        DDLogVerbose(@"no space to write. returning. ");
        return;
    }
    
    for(XMLNode* node in _outputQueue)
    {
        [self writeToStream:node.XMLString];
    }
    
    [_outputQueue removeAllObjects];
    
}

-(void) writeToStream:(NSString*) messageOut
{
    _streamHasSpace=NO; // triggers more has space messages
    
    //we probably want to break these into chunks
    DDLogVerbose(@"sending: %@ ", messageOut);
    const uint8_t * rawstring = (const uint8_t *)[messageOut UTF8String];
    int len= strlen((char*)rawstring);
    DDLogVerbose(@"size : %d",len);
    if([_oStream write:rawstring maxLength:len]!=-1)
    {
        DDLogVerbose(@"done writing ");
    }
    else
    {
        NSError* error= [_oStream streamError];
        DDLogVerbose(@"sending: failed with error %d domain %@ message %@",error.code, error.domain, error.userInfo);
    }
    
    return;
    
}

-(void) readToBuffer
{
    
	if(![_iStream hasBytesAvailable])
	{
        DDLogVerbose(@"no bytes  to read");
		return;
	}
	
    uint8_t* buf=malloc(kXMPPReadSize);
    int len = 0;
    
	len = [_iStream read:buf maxLength:kXMPPReadSize];
    DDLogVerbose(@"done reading %d", len);
	if(len>0) {
        NSData* data = [NSData dataWithBytes:(const void *)buf length:len];
        //  DDLogVerbose(@" got raw string %s nsdata %@", buf, data);
        if(data)
        {
            // DDLogVerbose(@"waiting on net read queue");
            dispatch_async(_netReadQueue, ^{
                // DDLogVerbose(@"got net read queue");
                [_inputBuffer appendString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
            });
            
        }
        free(buf);
	}
	else
	{
		free(buf);
		return;
	}
    
    
    [self processInput];
    
}

#pragma mark DNS

-(void) dnsDiscover
{
    
	DNSServiceRef sdRef;
	DNSServiceErrorType res;
	
	NSString* serviceDiscoveryString=[NSString stringWithFormat:@"_xmpp-client._tcp.%@", _domain];
	
	res=DNSServiceQueryRecord(
							  &sdRef, 0, 0,
							  [serviceDiscoveryString UTF8String],
							  kDNSServiceType_SRV,
							  kDNSServiceClass_IN,
							  query_cb,
							  ( __bridge void *)(self)
							  );
	if(res==kDNSServiceErr_NoError)
	{
		int sock=DNSServiceRefSockFD(sdRef);
		
        fd_set set;
        struct timeval timeout;
        
        /* Initialize the file descriptor set. */
        FD_ZERO (&set);
        FD_SET (sock, &set);
        
        /* Initialize the timeout data structure. */
        timeout.tv_sec = 2ul;
        timeout.tv_usec = 0;
        
        /* select returns 0 if timeout, 1 if input available, -1 if error. */
        int ready= select (FD_SETSIZE,&set, NULL, NULL,
                           &timeout) ;
        
        if(ready>0)
        {
            
            DNSServiceProcessResult(sdRef);
            DNSServiceRefDeallocate(sdRef);
        }
        else
        {
            DDLogVerbose(@"dns call timed out");
        }
        
    }
}






char *ConvertDomainLabelToCString_withescape(const domainlabel *const label, char *ptr, char esc)
{
    const u_char *      src = label->c;                         // Domain label we're reading
    const u_char        len = *src++;                           // Read length of this (non-null) label
    const u_char *const end = src + len;                        // Work out where the label ends
    if (len > MAX_DOMAIN_LABEL) return(NULL);           // If illegal label, abort
    while (src < end)                                           // While we have characters in the label
	{
        u_char c = *src++;
        if (esc)
		{
            if (c == '.')                                       // If character is a dot,
                *ptr++ = esc;                                   // Output escape character
            else if (c <= ' ')                                  // If non-printing ascii,
			{                                                   // Output decimal escape sequence
                *ptr++ = esc;
                *ptr++ = (char)  ('0' + (c / 100)     );
                *ptr++ = (char)  ('0' + (c /  10) % 10);
                c      = (u_char)('0' + (c      ) % 10);
			}
		}
        *ptr++ = (char)c;                                       // Copy the character
	}
    *ptr = 0;                                                   // Null-terminate the string
    return(ptr);                                                // and return
}

char *ConvertDomainNameToCString_withescape(const domainname *const name, char *ptr, char esc)
{
    const u_char *src         = name->c;                        // Domain name we're reading
    const u_char *const max   = name->c + MAX_DOMAIN_NAME;      // Maximum that's valid
	
    if (*src == 0) *ptr++ = '.';                                // Special case: For root, just write a dot
	
    while (*src)                                                                                                        // While more characters in the domain name
	{
        if (src + 1 + *src >= max) return(NULL);
        ptr = ConvertDomainLabelToCString_withescape((const domainlabel *)src, ptr, esc);
        if (!ptr) return(NULL);
        src += 1 + *src;
        *ptr++ = '.';                                           // Write the dot after the label
	}
	
    *ptr++ = 0;                                                 // Null-terminate the string
    return(ptr);                                                // and return
}

// print arbitrary rdata in a readable manned
void print_rdata(int type, int len, const u_char *rdata, void* context)
{
    int i;
    srv_rdata *srv;
    char targetstr[MAX_CSTRING];
    struct in_addr in;
    
    switch (type)
	{
        case T_TXT:
        {
            // print all the alphanumeric and punctuation characters
            for (i = 0; i < len; i++)
                if (rdata[i] >= 32 && rdata[i] <= 127) printf("%c", rdata[i]);
            printf("\n");
            ;
            return;
        }
        case T_SRV:
        {
            srv = (srv_rdata *)rdata;
            ConvertDomainNameToCString_withescape(&srv->target, targetstr, 0);
            //  DDLogVerbose(@"pri=%d, w=%d, port=%d, target=%s\n", ntohs(srv->priority), ntohs(srv->weight), ntohs(srv->port), targetstr);
			
			xmpp* client=(__bridge xmpp*) context;
			int portval=ntohs(srv->port);
			NSString* theserver=[NSString stringWithUTF8String:targetstr];
			NSNumber* num=[NSNumber numberWithInt:ntohs(srv->priority)];
			NSNumber* theport=[NSNumber numberWithInt:portval];
			NSDictionary* row=[NSDictionary dictionaryWithObjectsAndKeys:num,@"priority", theserver, @"server", theport, @"port",nil];
			[client.discoveredServerList addObject:row];
            //	DDLogVerbose(@"DISCOVERY: server  %@", theserver);
			
            return;
        }
        case T_A:
        {
            assert(len == 4);
            memcpy(&in, rdata, sizeof(in));
            //   DDLogVerbose(@"%s\n", inet_ntoa(in));
            
            return;
        }
        case T_PTR:
        {
            ConvertDomainNameToCString_withescape((domainname *)rdata, targetstr, 0);
            //  DDLogVerbose(@"%s\n", targetstr);
            
            return;
        }
        default:
        {
            //   DDLogVerbose(@"ERROR: I dont know how to print RData of type %d\n", type);
            
            return;
        }
	}
}

void query_cb(const DNSServiceRef DNSServiceRef, const DNSServiceFlags flags, const u_int32_t interfaceIndex, const DNSServiceErrorType errorCode, const char *name, const u_int16_t rrtype, const u_int16_t rrclass, const u_int16_t rdlen, const void *rdata, const u_int32_t ttl, void *context)
{
    (void)DNSServiceRef;
    (void)flags;
    (void)interfaceIndex;
    (void)rrclass;
    (void)ttl;
    (void)context;
    
    if (errorCode)
	{
        // DDLogVerbose(@"query callback: error==%d\n", errorCode);
        return;
	}
    // DDLogVerbose(@"query callback - name = %s, rdata=\n", name);
    print_rdata(rrtype, rdlen, rdata, context);
}


/*
 // this is useful later for ichat bonjour
 
 #pragma mark DNS service discovery
 - (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)netServiceBrowser
 {
 DDLogVerbose(@"began service search of domain %@", domain);
 }
 
 
 - (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didNotSearch:(NSDictionary *)errorInfo
 {
 DDLogVerbose(@"did not  service search");
 }
 
 - (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
 {
 [netService retain];
 DDLogVerbose(@"Add service %@. %@ %@\n", [netService name], [netService type], [netService domain]);
 }
 
 - (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)netServiceBrowser
 {
 DDLogVerbose(@"stopped service search"); 
 }
 */



@end
