//
//  xmpp.m
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import "xmpp.h"
#import "DataLayer.h"


#define kXMPPReadSize 51200 // bytes

#define kMonalNetReadQueue "im.monal.netReadQueue"
#define kMonalNetWriteQueue "im.monal.netWriteQueue"


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
    
    _netReadQueue = dispatch_queue_create(kMonalNetReadQueue, DISPATCH_QUEUE_SERIAL);
    _netWriteQueue = dispatch_queue_create(kMonalNetWriteQueue, DISPATCH_QUEUE_SERIAL);
    
    return self;
}


-(void) setRunLoop
{
	[_oStream setDelegate:self];
    [_oStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	
	[_iStream setDelegate:self];
   [_iStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
  
}

-(void) createStreams
{
    CFReadStreamRef readRef= NULL;
    CFWriteStreamRef writeRef= NULL;
	
    debug_NSLog(@"stream  creating to  server: %@ port: %d", _server, _port);
    
	CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)_server, _port, &readRef, &writeRef);
	
    _iStream= (__bridge NSInputStream*)readRef;
    _oStream= (__bridge NSOutputStream*) writeRef;
    
	if((_iStream==nil) || (_oStream==nil))
	{
		debug_NSLog(@"Connection failed");
		return;
	}
    else
        debug_NSLog(@"streams created ok");
    
    if((CFReadStreamSetProperty((__bridge CFReadStreamRef)_iStream,
                                kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP)) &&
       (CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_oStream,
                                 kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP)))
    {
        debug_NSLog(@"Set VOIP properties on streams.")
    }
    else
    {
        debug_NSLog(@"could not set VOIP properties on streams.");
    }
    
   if((_SSL==YES)  && (_oldStyleSSL==YES))
	{
		// do ssl stuff here
		debug_NSLog(@"securing connection.. for old style");
  	
		//allowing it to accept the peers cert if the host doesnt match.
		NSDictionary *settings = [ [NSDictionary alloc ]
								  initWithObjectsAndKeys:
								  [NSNumber numberWithBool:YES], @"kCFStreamSSLAllowsExpiredCertificates",
								  [NSNumber numberWithBool:YES], @"kCFStreamSSLAllowsExpiredRoots",
								  [NSNumber numberWithBool:YES], @"kCFStreamSSLAllowsAnyRoot",
								  [NSNumber numberWithBool:NO], @"kCFStreamSSLValidatesCertificateChain",
								  [NSNull null],@"kCFStreamSSLPeerName",
                                  
                                  kCFStreamSocketSecurityLevelSSLv3,
								  @"kCFStreamSSLLevel",
								  nil ];
		CFReadStreamSetProperty((__bridge CFReadStreamRef)_iStream,
								kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings);
		CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_oStream,
								 kCFStreamPropertySSLSettings, (__bridge CFTypeRef)settings);

        debug_NSLog(@"connection secured");
		//[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(login:) name: @"XMPPMech" object:self];
		// for new style this is only done AFTER start tls is sent to not conflict with the earlier mech
	}
	
    //start stream
    XMLNode* stream = [[XMLNode alloc] init];
    stream.element=@"stream:stream";
    [stream.attributes setObject:@"jabber:client" forKey:@"xmlns"];
    [stream.attributes setObject:@"http://etherx.jabber.org/streams" forKey:@"xmlns:stream"];
    [stream.attributes setObject:@"1.0" forKey:@"version"];
    if(_domain)
    [stream.attributes setObject:_domain forKey:@"to"];
    [self send:stream];
    
    [self setRunLoop];
    
#warning this needs to time out propery
    [_iStream open];
    [_oStream open];
    

}

-(void) connect
{
    if((_port==5553) || (_port==443))
    {
        _oldStyleSSL=YES;
    }
    
    //allow gtalk on 443
    if(_oldStyleSSL==NO)
    {
    // do DNS discovery
        #warning  this needs to time it self out properly
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

-(void) disconnect
{
    debug_NSLog(@"removing streams");
    
	//prevent any new read or write
	[_iStream setDelegate:nil];
	[_oStream setDelegate:nil];
	
	[_oStream removeFromRunLoop:[NSRunLoop currentRunLoop]
					   forMode:NSDefaultRunLoopMode];
	
	[_iStream removeFromRunLoop:[NSRunLoop currentRunLoop]
					   forMode:NSDefaultRunLoopMode];
	debug_NSLog(@"removed streams");
	
	@try
	{
        [_iStream close];
	}
	@catch(id theException)
	{
		debug_NSLog(@"Exception in istream close");
	}
	
	@try
	{
		[_oStream close];
	}
	@catch(id theException)
	{
		debug_NSLog(@"Exception in ostream close");
	}
	
	debug_NSLog(@"Connections closed");
	
	debug_NSLog(@"All closed and cleaned up"); 
	
}




#pragma mark XMPP

-(void) send:(XMLNode*) stanza
{
    dispatch_sync(_netWriteQueue, ^{
        [_outputQueue addObject:stanza];
    });
}

#pragma mark nsstream delegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
	debug_NSLog(@"Stream has event");
	switch(eventCode)
	{
			//for writing
        case NSStreamEventHasSpaceAvailable:
        {
            debug_NSLog(@"Stream has space to write");
            [self writeFromQueue];
            
            break;
        }
			
			//for reading
        case  NSStreamEventHasBytesAvailable:
		{
			debug_NSLog(@"Stream has bytes to read");
            [self readToBuffer];
			
			break;
		}
			
		case NSStreamEventErrorOccurred:
		{
			debug_NSLog(@"Stream error");
            NSError* st_error= [stream streamError];
            
            debug_NSLog(@"Stream error code=%d domain=%@   local desc:%@ ",st_error.code,st_error.domain,  st_error.localizedDescription);
            
            
            if(st_error.code==61)// Connection refused
            {
                break;
            }
            
            
            if(st_error.code==64)// Host is down
            {
                break;
            }
            
			break;
            
		}
		case NSStreamEventNone:
		{
			debug_NSLog(@"Stream event none");
			break;
			
		}
			
			
		case NSStreamEventOpenCompleted:
		{
			debug_NSLog(@"Stream open completed");
			
            break;
		}
			
			
		case NSStreamEventEndEncountered:
		{
			debug_NSLog(@"Stream end encoutered");
			break;
		}
			
			
            
			
	}
	
}

#pragma mark network I/O
-(void) writeFromQueue
{
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
                   });
    
    dispatch_sync(_netWriteQueue, ^{
        for(XMLNode* node in _outputQueue)
        {
            [self writeToStream:node.XMLString];
        }
        
        [_outputQueue removeAllObjects];
    });
    
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                   });
    
}

-(void) writeToStream:(NSString*) messageOut
{
    debug_NSLog(@"sending: %@ ", messageOut);
    const uint8_t * rawstring = (const uint8_t *)[messageOut UTF8String];
    int len= strlen((char*)rawstring);
    if([_oStream write:rawstring maxLength:len]!=-1)
    {
        //     debug_NSLog(@"sending: ok");
    }
    else
    {
        NSError* error= [_oStream streamError];
        debug_NSLog(@"sending: failed with error %d domain %@",error.code, error.domain);
    }
    
    return;
    
}

-(void) readToBuffer
{
	uint8_t* buf=malloc(kXMPPReadSize);
    int len = 0;

	if(![_iStream hasBytesAvailable])
	{
		free(buf);
		return;
	}
	
	len = [_iStream read:buf maxLength:kXMPPReadSize];
	if(len>0) {
		//[_inputBuffer appendBytes:(const void *)buf length:len];
        NSString* newString=[NSString stringWithUTF8String:(char*)buf];
        if(newString)
            [_inputBuffer appendString:newString];
        free(buf);
	}
	else
	{
		free(buf);
		return;
	}

    debug_NSLog(@"read buffer: %@ ", _inputBuffer);
 
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
		DNSServiceRefSockFD(sdRef);
		
		DNSServiceProcessResult(sdRef);
		DNSServiceRefDeallocate(sdRef);
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
            debug_NSLog(@"pri=%d, w=%d, port=%d, target=%s\n", ntohs(srv->priority), ntohs(srv->weight), ntohs(srv->port), targetstr);
			
			xmpp* client=(__bridge xmpp*) context;
			int portval=ntohs(srv->port);
			NSString* theserver=[NSString stringWithUTF8String:targetstr];
			NSNumber* num=[NSNumber numberWithInt:ntohs(srv->priority)];
			NSNumber* theport=[NSNumber numberWithInt:portval];
			NSDictionary* row=[NSDictionary dictionaryWithObjectsAndKeys:num,@"priority", theserver, @"server", theport, @"port",nil];
			[client.discoveredServerList addObject:row];
			debug_NSLog(@"DISCOVERY: server  %@", theserver);
			;
            return;
        }
        case T_A:
        {
            assert(len == 4);
            memcpy(&in, rdata, sizeof(in));
            debug_NSLog(@"%s\n", inet_ntoa(in));
            ;
            return;
        }
        case T_PTR:
        {
            ConvertDomainNameToCString_withescape((domainname *)rdata, targetstr, 0);
            debug_NSLog(@"%s\n", targetstr);
            ;
            return;
        }
        default:
        {
            debug_NSLog(@"ERROR: I dont know how to print RData of type %d\n", type);
            ;
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
        debug_NSLog(@"query callback: error==%d\n", errorCode);
        return;
	}
    debug_NSLog(@"query callback - name = %s, rdata=\n", name);
    print_rdata(rrtype, rdlen, rdata, context);
}


/*
 // this is useful later for ichat bonjour
 
 #pragma mark DNS service discovery
 - (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)netServiceBrowser
 {
 debug_NSLog(@"began service search of domain %@", domain);
 }
 
 
 - (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didNotSearch:(NSDictionary *)errorInfo
 {
 debug_NSLog(@"did not  service search");
 }
 
 - (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing
 {
 [netService retain];
 debug_NSLog(@"Add service %@. %@ %@\n", [netService name], [netService type], [netService domain]);
 }
 
 - (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)netServiceBrowser
 {
 debug_NSLog(@"stopped service search"); 
 }
 */



@end
