//
//  xmpp.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/18/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "xmpp.h"


@implementation xmpp


@synthesize serverList; 
@synthesize theset; 
@synthesize chatServer; 
@synthesize chatSearchServer; 
@synthesize userSearchServer; 
@synthesize userSearchItems; 

-(id)init:(NSString*) theserver:(unsigned short) theport:(NSString*) theaccount: (NSString*) theresource: (NSString*) thedomain:(BOOL) SSLsetting : (DataLayer*) thedb:(NSString*) accountNo:(NSString*) tempPass
{
	self = [super init];
	loggedin=false; 
	away=false; 
	statusMessage=nil; 
	domain=thedomain;
	server=theserver; 
	port=(unsigned short)theport; 
	account= theaccount;
	
	resource=theresource;
	
	debug_NSLog(@"%@  %@", account, resource); 
	
    if(tempPass==nil) theTempPass=nil; else
    {
    theTempPass=[NSString stringWithString:tempPass];
    [theTempPass retain];
    }
    
	accountNumber=accountNo;
	SSL=SSLsetting;
	[server retain]; 
	
	[accountNumber retain];
	[domain retain];
	[resource retain];
	[account retain]; 
		
    chatServer=@""; // blank for start
    chatSearchServer=@""; // blank for start
    userSearchServer=@""; // blank for start
    
    iqsearch=[[[iqSearch alloc] init] retain]; 
    jingleCall=[[[iqJingle alloc] init] retain]; 
    
    messageUser=@"";
	
	responseUser=@""; 
	[responseUser retain];
	
	loginstate=0; 
	keepAliveCounter=0;

	errorState=0; 
	
	listenThreadCounter=0; 
	
	streamOpen=0; 
	
//	buddyListKeys=[NSArray arrayWithObjects:@"username", @"status", @"message", @"icon", @"count",@"fullname", nil];
	
	userSearchItems=[[[NSMutableArray alloc] init] retain]; 
	
	
	State=nil; 
	presenceUser=nil;
		presenceUserid=nil; 

	presenceUserFull=nil;
	presenceShow=nil;
	presenceStatus=nil; 
	presencePhoto=nil;
	presenceType=nil;
	theset=nil;
	
	lastEndedElement=nil;
	vCardUser=nil; 
	vCardFullName=nil; 
	
	responseUser=nil; // this is the JID we get from the server
	
	mucUser=nil;
	
	db=thedb;
	
	loggedin=false; 
	
	DNSthreadreturn=false; 

	
	
	// outer state machien
	loginstate=0; 
	

	
    
	serverDiscoItems=[[NSMutableArray alloc] init];
	
	serverList=[[NSMutableArray alloc] init];

	
	[NSThread detachNewThreadSelector:@selector(dnsDiscover) toTarget:self withObject:nil];
	
	
	//discover the SRV server if there is one for local
	/*
	// override the server used if found
  resolver = [[NSNetServiceBrowser alloc] init] ;
	[resolver setDelegate:self];
	
	//ichat bonjour
	//[resolver searchForServicesOfType:@"_presence._tcp." inDomain:@""];
	
	
//	[resolver stop];
	*/
	
	return self;

}

-(void) dnsDiscover
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	
	DNSServiceRef sdRef;
	DNSServiceErrorType res;
	
	NSString* serviceDiscoveryString=[NSString stringWithFormat:@"_xmpp-client._tcp.%@", domain];
	
	res=DNSServiceQueryRecord(
							  &sdRef, 0, 0,
							  [serviceDiscoveryString UTF8String],
							  kDNSServiceType_SRV,
							  kDNSServiceClass_IN,
							  query_cb,
							  self
							  );
	if(res==kDNSServiceErr_NoError)
	{
		int sock= DNSServiceRefSockFD(sdRef);
		
		DNSServiceProcessResult(sdRef);
		DNSServiceRefDeallocate(sdRef);
	}
	DNSthreadreturn=true; 
	[pool release];
	[NSThread exit]; 
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
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
    int i;
    srv_rdata *srv;
    char targetstr[MAX_CSTRING];
    struct in_addr in;
    
    switch (type)
	{
        case T_TXT:
            // print all the alphanumeric and punctuation characters
            for (i = 0; i < len; i++)
                if (rdata[i] >= 32 && rdata[i] <= 127) printf("%c", rdata[i]);
            printf("\n");
				[pool release]; 
            return;
        case T_SRV:
            srv = (srv_rdata *)rdata;
            ConvertDomainNameToCString_withescape(&srv->target, targetstr, 0);
            debug_NSLog(@"pri=%d, w=%d, port=%d, target=%s\n", ntohs(srv->priority), ntohs(srv->weight), ntohs(srv->port), targetstr);
			
			xmpp* client=(xmpp*) context; 
			int portval=ntohs(srv->port);
			NSString* theserver=[NSString stringWithUTF8String:targetstr];
			NSNumber* num=[NSNumber numberWithInt:ntohs(srv->priority)];
			NSNumber* theport=[NSNumber numberWithInt:portval];
			NSArray* row=[NSArray arrayWithObjects:num,theserver,theport,nil];
			
			[client.serverList addObject:row];
			debug_NSLog(@"DISCOVERY: server  %@", theserver); 
			[pool release]; 
            return;
        case T_A:
            assert(len == 4);
            memcpy(&in, rdata, sizeof(in));
            debug_NSLog(@"%s\n", inet_ntoa(in));
				[pool release]; 
            return;
        case T_PTR:
            ConvertDomainNameToCString_withescape((domainname *)rdata, targetstr, 0);
            debug_NSLog(@"%s\n", targetstr);
				[pool release]; 
            return;
        default:
            debug_NSLog(@"ERROR: I dont know how to print RData of type %d\n", type);
				[pool release]; 
            return;
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


#pragma mark regular XMPP stuff

- (void)parserDidStartDocument:(NSXMLParser *)parser{	
	debug_NSLog(@"parsing"); 
	parserCol=0;
	
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict{			
   		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	 debug_NSLog(@"began this element: %@", elementName);

	
	
	
	//recoverding from stream error
	if([elementName isEqualToString:@"stream:error"])
	{
		loginstate++;  
	
		[pool release];
		return; 
		
	}
	
	
	//getting login mechanisms
	if([elementName isEqualToString:@"stream:features"])
	{
	    if(State!=nil) [State release]; 
		State=@"Features";
		[State retain];
			[pool release];
		return; 
		
	}
	
    if(([State isEqualToString:@"Features"]) &&([elementName isEqualToString:@"auth"]))
	{
        debug_NSLog(@"Supports legacy auth"); 
        legacyAuth=true; 
        [pool release];
		return; 
    }
    
    if(([State isEqualToString:@"Features"]) &&([elementName isEqualToString:@"register"]))
	{
        debug_NSLog(@"Supports user registration"); 
        [pool release];
		return; 
    }
    
	if(([State isEqualToString:@"Features"]) &&([elementName isEqualToString:@"starttls"]))
	{
	
	if((SSL==true) ) //&& (port==5222) if starttls no need to check for 5222
	{
		debug_NSLog(@"Using new style SSL"); 
		NSString* xmpprequest=[NSString stringWithString:@"<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>"]; 
		[self talk:xmpprequest];
	}
	
		[pool release];
		return; 
	}
		
		
	if(([elementName isEqualToString:@"proceed"]) && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-tls"]) )
	{
		debug_NSLog(@"Got SartTLS procced");
		//trying to switch to TLS
	
		
		NSDictionary *settings = [ [NSDictionary alloc ] 
								  initWithObjectsAndKeys:
								  [NSNumber numberWithBool:YES], @"kCFStreamSSLAllowsExpiredCertificates",
								  [NSNumber numberWithBool:YES], @"kCFStreamSSLAllowsExpiredRoots",
								  [NSNumber numberWithBool:YES], @"kCFStreamSSLAllowsAnyRoot",
								  [NSNumber numberWithBool:NO], @"kCFStreamSSLValidatesCertificateChain",
								  [NSNull null],@"kCFStreamSSLPeerName",
								  @"kCFStreamSocketSecurityLevelNegotiatedSSL", 
								  @"kCFStreamSocketSecurityLevelTLSv1",
								  
								  nil ];
	
		
		

		if ( 	CFReadStreamSetProperty((CFReadStreamRef)iStream, 
										@"kCFStreamPropertySSLSettings", (CFTypeRef)settings) &&
			CFWriteStreamSetProperty((CFWriteStreamRef)oStream, 
									 @"kCFStreamPropertySSLSettings", (CFTypeRef)settings)	 )
			
		{
			debug_NSLog(@"Set TLS properties on streams.");
			
			
		}
		else 
		{
			debug_NSLog(@"not sure.. Could not confirm Set TLS properties on streams.");
			//fatal=true; 	
		}
		
		
	
		
		
		NSString* xmpprequest;
	  if([domain length]>0)
		
		 xmpprequest=[NSString stringWithFormat:
							   @"<stream:stream to='%@' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'  version='1.0'>",domain];
        else
            xmpprequest=[NSString stringWithFormat:
                         @"<stream:stream  xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'  version='1.0'>"];
            
		[self talk:xmpprequest];
		[xmpprequest retain]; 
		loginstate=1; // reset everything
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(login:) name: @"XMPPMech" object:self];
		
		[pool release];
		return; 
		
	} 
		
	// state >1 at the end of sasl and then reset to 1 in bind. so if it is 1 then bind was already sent
	if(([State isEqualToString:@"Features"]) && ([elementName isEqualToString:@"bind"])
	   && (loginstate!=1) )
	{
		loginstate=1; //reset for new stream
	NSString* bindString=[NSString stringWithFormat:@"<iq id='%@' type='set' ><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><resource>%@</resource></bind></iq>", sessionkey,resource];
		[self talk:bindString]; 
		
			[pool release];
		return;
		}
	
	

	
	

	// first time it is read loginstate  will always be 1
	
	if(([State isEqualToString:@"Features"]) && [elementName isEqualToString:@"mechanisms"] && (loginstate<2))
	{
		loginstate++;
		debug_NSLog(@"mechanisms xmlns:%@ ", [attributeDict objectForKey:@"xmlns"]); 
		if([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
		{
			debug_NSLog(@"SASL supported"); 
			SASLSupported=true; 
		}
		
		[State release]; 
		State=@"Mechanisms";
		[State retain];
		
		[pool release];
		return;
		
	
	}
	
	if(([State isEqualToString:@"Mechanisms"]) && [elementName isEqualToString:@"mechanism"])
	{
		debug_NSLog(@"Reading mechanism"); 
		[State release]; 
		State=@"Mechanism";
		[State retain];
		
		[pool release];
		return;
		
		
	}
	
	
	
	
	
	//****** failure
	//sasl failure = login failure
	if(([elementName isEqualToString:@"failure"]) && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"]) )
	{
		/*UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Login Error"
														 message:@"Could not login to server. Make sure username and password are correct.  "
														delegate:self cancelButtonTitle:nil
											   otherButtonTitles:@"Close", nil] autorelease];
		[alert show];
		*/
		
		[[NSNotificationCenter defaultCenter] 
		 postNotificationName: @"LoginFailed" object: self];
	
		
	}
	
	
	if([elementName isEqualToString:@"failure"])
	{
		if(State!=nil) [State release]; 
		State=@"Failure";
		[State retain];
		[pool release]; 
		return; 
		
	}
	
	
	// Digest MD5 handler
	if((SASLDIGEST_MD5==true)   &&
		(([elementName isEqualToString:@"challenge"]) && ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"]) ))
	{
		
		if(State!=nil) 
			if([State isEqualToString:@"DigestClientResponse"])
			{
				//this is a challenge after our response .. finsih up digest
				NSString* xmppcmd= @"<response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>";
				[self talk:xmppcmd]; //this should get us a success
				[pool release]; 
				return; 
				
			}
		
		if(State!=nil) [State release]; 
		State=@"DigestChallenge";
		[State retain];
		
		if(messageBuffer!=nil) 
		{
			[messageBuffer release]; 
			messageBuffer=nil; 
		}
		
		[pool release]; 
		return;
		
	}
	
	
	
	
	if([State isEqualToString:@"Failure"])
	{
		//fatal=true; 
		
		[pool release];
		//[parser abortParsing];
		return;
	}
	
	
	
	//***** begin error handling
	if(([elementName isEqualToString:@"iq"]) &&  ([[attributeDict objectForKey:@"type"] isEqualToString:@"error"])
	   )
		
	{
		if(State!=nil) [State release]; 
		State=@"error";  // this would be an iq error
		[State retain];
		[pool release];
		return; 
	}
    
    
    //specifically a presence error
    if(([State isEqualToString:@"presence"])&&([elementName isEqualToString:@"error"]))
    {
        
        //also code 401 but that is deprecated
        if([[attributeDict objectForKey:@"type"] isEqualToString:@"auth"])
        {
            NSString* askmsg=[NSString stringWithFormat:@"%@ says, you were not authorized to access this resource. Check your password.", presenceUser]; 
            //ask for authorization 
            
            UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Error"
                                                             message:askmsg
                                                            delegate:self cancelButtonTitle:@"Close"
                                                   otherButtonTitles:nil, nil] autorelease];
            [alert show];
            
        }
        [pool release]; 
        return; 
    }
    
	//any other error
	if([elementName isEqualToString:@"error"] ) // this would be a returning error code
		
	{
		if(State!=nil) [State release]; 
		State=@"errormsg"; 
		[pool release];
		return; 
	}
	
	
	
	
	
	
	
	
	//****** nothing below should be processed unless there was a login attempt suff*****
	
	// Login mechanisms
	if(([elementName isEqualToString:@"mechanisms"]) &&  ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
		 )
		
	{
		if(State!=nil) [State release]; 
		State=@"SASLmechanisms";  // this would be an iq error
		[State retain];
		[pool release];
		return; 
	}
	
	if(([elementName isEqualToString:@"mechanism"]) && ([State isEqualToString:@"SASLmechanisms"]))
	{
		if(State!=nil) [State release]; 
		State=@"SASLmethod"; 
		[State retain];
			[pool release];
		return; 
	}
		

	
	//***** sasl success...
	if(([elementName isEqualToString:@"success"]) &&  ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:ietf:params:xml:ns:xmpp-sasl"])
	   )
		
	{
		loginstate++;
		if(State!=nil) [State release]; 
		State=@"SASLSuccess"; 
		[State retain];
		
		//start tracking messages now
	
		
		[pool release];
		return; 
		
	}
	
	//start sessionafter bind reply
	if(([elementName isEqualToString:@"jid"]) && [State isEqualToString:@"Bind"]
	   )
	{
		if(State!=nil) [State release]; 
		State=@"Jid"; 
		[State retain];
		
		if(messageBuffer!=nil) 
		{
			[messageBuffer release]; 
			messageBuffer=nil; 
		}
		
		[pool release];
		return;
	}

	
	
	//start sessionafter bind reply
	if(([elementName isEqualToString:@"bind"]) && [State isEqualToString:@"iq"]
		)
	{
		

		NSString* sessionQuery=[NSString stringWithFormat:@"<iq id='%@' type='set'><session xmlns='urn:ietf:params:xml:ns:xmpp-session'/></iq>", sessionkey];
		[self talk:sessionQuery];
        
        [self queryDiscoItems:domain : sessionkey ];
        
        [self queryDiscoInfo:domain : sessionkey ];
		
	
		
        
        
		
		debug_NSLog(@"startign bind "); 
		if(State!=nil) [State release]; 
		State=@"Bind"; 
		[State retain];
	
		
			[pool release];
		return; 
	}
	

	
	
	//***** begin auth handling > not in xmpp 1 
	/*if(([elementName isEqualToString:@"iq"]) &&  ([[attributeDict objectForKey:@"type"] isEqualToString:@"result"])
		 &&  ([[attributeDict objectForKey:@"id"] isEqualToString:@"auth2"])
		)
	{
		[responseUser release];
		responseUser=[attributeDict objectForKey:@"to"];
		[responseUser retain];
		[pool release];
		return;
	}
	*/

	
	
	
	//******* begin roster state machine
	if([elementName isEqualToString:@"iq"])
	{
		if(State!=nil) [State release]; 
		State=@"iq";
		[State retain];
		
        // who is the stanza from.. despite the name presence user it is used for other requests too 
        
        if(presenceUserFull!=nil) [presenceUserFull release]; 
        //if they are requesting stuff.. they are online		
        presenceUserFull=[attributeDict objectForKey:@"from"];
        [presenceUserFull retain];
        debug_NSLog(@"iq from full user : %@", presenceUserFull); 
        
        
        //iq set request
        if( [[attributeDict objectForKey:@"type"] isEqualToString:@"set"])
		{
			if(presenceUser!=nil) [presenceUser release]; 
			presenceUser=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
			[presenceUser retain];
            debug_NSLog(@"iq set user: %@", presenceUser); 
			
			if(presenceUserid!=nil) [presenceUserid release]; 
			//if they are requesting stuff.. they are online		
			presenceUserid=[attributeDict objectForKey:@"id"];
			[presenceUserid retain];
			debug_NSLog(@"iq set id: %@", presenceUserid); 
            
          
            
          
            
            
            if(State!=nil) [State release]; 
            State=@"iqSet";
            [State retain];
        }
        
	
		//iq get request
	//	if(([[attributeDict objectForKey:@"get"] length]>0))
		if( [[attributeDict objectForKey:@"type"] isEqualToString:@"get"])
		{
			
			
			if(presenceUser!=nil) [presenceUser release]; 
			presenceUser=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
			[presenceUser retain];
				debug_NSLog(@"iq get user: %@", presenceUser); 
			
			if(presenceUserid!=nil) [presenceUserid release]; 
			//if they are requesting stuff.. they are online		
			presenceUserid=[attributeDict objectForKey:@"id"];
			[presenceUserid retain];
			debug_NSLog(@"iq get id: %@", presenceUserid); 
            
            if(State!=nil) [State release]; 
            State=@"iqGet";
            [State retain];
			
		}
		
        
        else
		//iq resutl vc2 
		if( [[attributeDict objectForKey:@"type"] isEqualToString:@"result"])
        {
		
            	if( [[attributeDict objectForKey:@"id"] isEqualToString:@"auth2"])
                {
                    debug_NSLog(@"legacy login success");
                    loggedin=true; 
                //successful legacy login
                    [self setAvailable]; 
                    
                    // this has to come after set available becasue the post login functions in appdelegate set default status and messages
                    [[NSNotificationCenter defaultCenter] 
                     postNotificationName: @"LoggedIn" object: self];
                    
                    // send command to download the roster
                    [self getBuddies];
                    
                    
                    [pool release]; 
                    return; 
                    
                }
            
			if(loggedin==false)
			{
			
		
				
			}
			else
			
			if([[attributeDict objectForKey:@"from"] isEqualToString:server])
			{
				debug_NSLog(@"result from the server: %@", server); 
			}
		
			else
			{
				
			if(vCardUser!=nil) [vCardUser release]; 
			//request from a user 		
			vCardUser=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
			[vCardUser retain];
			debug_NSLog(@"result from user: %@", vCardUser); 
			}
			
			if(vCardUser==nil)
			{
				
				
			}
			
			
		}
		
		[pool release];
		return;
	}
	
    

    //iqSet->jingle
    if(([State isEqualToString:@"iqSet"]) 
       && (([elementName isEqualToString: @"jingle"]) ||
           ([elementName isEqualToString: @"jin:jingle"])
       )
       )
	{
        debug_NSLog(@"got Jingle message, sent ack"); 
        //send ack of message
        [self talk:[jingleCall ack:presenceUserFull:presenceUserid]]; 
        
       // if(	[[attributeDict objectForKey:@"xmlns"] isEqualToString:@"urn:xmpp:jingle:1"])
      //  {
            if(	[[attributeDict objectForKey:@"action"] isEqualToString:@"session-initiate"])
            {
                debug_NSLog(@"got Jingle session initiate "); 
                
                jingleCall.thesid= [attributeDict objectForKey:@"sid"] ;
               
                
                
                
            }
        
        if(	[[attributeDict objectForKey:@"action"] isEqualToString:@"transport-info"])
        {
            debug_NSLog(@"got Jingle transport info.  reading candidates ");
         
              
        }
        
        

        
        if(	[[attributeDict objectForKey:@"action"] isEqualToString:@"transport-info"])
        {
         // set Sid
           // [attributeDict objectForKey:@"sid"]
        }
        
            
            if(	[[attributeDict objectForKey:@"action"] isEqualToString:@"session-accept"])
            {
                debug_NSLog(@"got Jingle session accept"); 
            }
            
            if(	[[attributeDict objectForKey:@"action"] isEqualToString:@"session-terminate"])
            {
                debug_NSLog(@"got Jingle session terminate"); 
            }
            
            
        
      //  }
      
        if(State!=nil) [State release]; 
        State=@"jingleAction";
        [State retain];
        
        return; 
        
    }

    //iqSet->jingle->transport
    if(([State isEqualToString:@"jingleAction"]) 
       && (([elementName isEqualToString: @"transport"]) ||
           ([elementName isEqualToString: @"p:transport"])
           )
       )
	{
        debug_NSLog(@"got Jingle transport list"); 
        
        if(State!=nil) [State release]; 
        State=@"jingleTransport";
        [State retain];
        
        return; 
        
    }
    
    
    //iqSet->jingle->transport->candidate
    if(([State isEqualToString:@"jingleTransport"]) 
       && (([elementName isEqualToString: @"candidate"]) ||
           ([elementName isEqualToString: @"p:candidate"])
                      )
       )
	{
        debug_NSLog(@"got Jingle transport candidate"); 
        
       /* if(State!=nil) [State release]; 
        State=nil;*/
        if(	[[attributeDict objectForKey:@"type"] isEqualToString:@"stun"])
        {
            debug_NSLog(@"got Jingle stun candidate.. sending accept"); 
            [self talk: [jingleCall acceptJingle:presenceUserFull 
                                    :[attributeDict objectForKey:@"address"]
                                    :[attributeDict objectForKey:@"port"]
                                    :[attributeDict objectForKey:@"username"]
                                    :[attributeDict objectForKey:@"password"]
             
                                                :presenceUserid             ]];
            [jingleCall connect]; 
            
        }
        
        
        return; 
        
    }
    
    


    //iqGet->time
    if(([State isEqualToString:@"iqGet"]) && ([elementName isEqualToString: @"time"]))
	{
        debug_NSLog(@"got time request"); 
        //respond with time info
    [self sendTime:presenceUserFull:presenceUserid];
        [State release]; 
        State=nil; 
        return;
        
    }
    
    
    //iqGet->query
    if(([State isEqualToString:@"iqGet"]) && ([elementName isEqualToString: @"query"]))
	{
     
        if(	[[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:version"])//going to roster
		{
            debug_NSLog(@"got version request"); 
			//respond with version info
			[self sendVersion:presenceUserFull:presenceUserid];
			[State release]; 
			State=nil; 
			return;
		}
		
		if(	[[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:last"])
		{
			
            debug_NSLog(@"got last activity request"); 
			//respond with last activity
			
			[self sendLast:presenceUserFull:presenceUserid];
			[State release]; 
			State=nil; 
			return;
		}
     
        
		if(	[[attributeDict objectForKey:@"xmlns"] isEqualToString:@"http://jabber.org/protocol/disco#info"])//going to disco info
		{
			
			
            debug_NSLog(@"got disco info request"); 
			
			[self sendDiscoInfo:presenceUserFull:presenceUserid];
            [State release]; 
			State=nil; 
			return;
		}
        
    }
    
    
	//iq->query
// ******** iq->query parser ******* 
	
	   if(([State isEqualToString:@"iq"]) && ([elementName isEqualToString: @"query"]))
	{
		if(	[[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:roster"])//going to roster
		{
			
			debug_NSLog(@"result is roster"); 
			[State release]; 
			State=@"roster";
			[State retain];
		}
		
		if(	[[attributeDict objectForKey:@"xmlns"] isEqualToString:@"http://jabber.org/protocol/disco#info"])//going to disco info
		{
			[State release]; 
			State=@"discoinfo";
			 debug_NSLog(@"got disco info"); 
			
		
			[State retain];
		}
        
        if(	[[attributeDict objectForKey:@"xmlns"] isEqualToString:@"http://jabber.org/protocol/disco#items"])//going to disco info
		{
			[State release]; 
			State=@"discoitems";
            debug_NSLog(@"got disco items"); 
			
			
			[State retain];
		}
        
		
        //iq->query (usersearch)
     
             if(	[[attributeDict objectForKey:@"xmlns"] isEqualToString:@"jabber:iq:search"])
        {
            if(State!=nil) [State release]; 
            State=@"UserSearch";
            [State retain];
            
           
        }
        

		
	}


//iq->query->item  (usersearch)
if(([State isEqualToString:@"UserSearch"]) && ([elementName isEqualToString: @"item"]))
{
    
    debug_NSLog(@"got user search item"); 
    [userSearchItems addObject:[attributeDict objectForKey:@"jid"]];
    
    [pool release]; 
    return; 
}
    //standard NS fields
    if(([State isEqualToString:@"UserSearch"]) && ([elementName isEqualToString: @"first"]))
    {
        [iqsearch.userFields addObject:@"first"]; 
        
        [pool release]; 
        return; 
    }
    
    if(([State isEqualToString:@"UserSearch"]) && ([elementName isEqualToString: @"last"]))
    {
        [iqsearch.userFields addObject:@"last"]; 
        
        [pool release]; 
        return; 
    }
    
    if(([State isEqualToString:@"UserSearch"]) && ([elementName isEqualToString: @"nick"]))
    {
        [iqsearch.userFields addObject:@"nick"]; 
        
        [pool release]; 
        return; 
    }
    
    if(([State isEqualToString:@"UserSearch"]) && ([elementName isEqualToString: @"email"]))
    {
        [iqsearch.userFields addObject:@"email"]; 
        
        [pool release]; 
        return; 
    }


	//iq->query->item  (roster)
	  if(([State isEqualToString:@"roster"]) && ([elementName isEqualToString: @"item"]))
	  {
		  if([attributeDict objectForKey:@"name"]!=nil)
		  {
		  debug_NSLog(@"setting full name for %@ to %@",[attributeDict objectForKey:@"jid"], [attributeDict objectForKey:@"name"] ); 
		  // set the full name 
			  if([[attributeDict objectForKey:@"name"] length]>0)
		  [db setFullName:[attributeDict objectForKey:@"jid"]  :accountNumber:[attributeDict objectForKey:@"name"] ];
			  else
				    [db setFullName:[attributeDict objectForKey:@"jid"]  :accountNumber:[attributeDict objectForKey:@"jid"] ];
			  presenceFlag=true; // tell it to update
		  }
		  else
                if([attributeDict objectForKey:@"jid"]!=nil)
			   [db setFullName:[attributeDict objectForKey:@"jid"]  :accountNumber:[attributeDict objectForKey:@"jid"] ];
		  
		  [pool release]; 
		  return;
	  }
    
    
    ///iq->query->item (discoitems)
    if(([State isEqualToString:@"discoitems"]) && ([elementName isEqualToString: @"item"]))
    {
        [serverDiscoItems addObject:[attributeDict objectForKey:@"jid"] ];
        
            debug_NSLog(@"Disco Item: %@ %@",[attributeDict objectForKey:@"name"], [attributeDict objectForKey:@"jid"]   ); 
        
        //query the service fro more info
        [self queryDiscoInfo:[attributeDict objectForKey:@"jid"] : sessionkey ];
        
        [pool release];
        return; 
        
        
    }
	
    //iq->query->identity
    if(([State isEqualToString:@"discoinfo"]) && ([elementName isEqualToString: @"identity"]))
    {
        
        
            
            
            if(	[[attributeDict objectForKey:@"category"] isEqualToString:@ "conference"])
            {
                debug_NSLog(@"Identity: conference server as %@", presenceUserFull); 
                // send message enabling offline messages 
              //  if(chatServer!=nil) [chatServer release]; 
                chatServer= presenceUserFull;
                [chatServer retain];
                
                [pool release]; 
                return; 
            }
            
        
        if(	[[attributeDict objectForKey:@"category"] isEqualToString:@ "directory"]
           && 
           [[attributeDict objectForKey:@"type"] isEqualToString:@ "chatroom"])
        {
            debug_NSLog(@"Identity: conference search server as %@", presenceUserFull); 
            // send message enabling offline messages 
            //  if(chatServer!=nil) [chatServer release]; 
            chatSearchServer= presenceUserFull;
            [chatSearchServer retain];
            
            [pool release]; 
            return; 
        }
        
            
        if(	[[attributeDict objectForKey:@"category"] isEqualToString:@ "directory"]
           && 
           [[attributeDict objectForKey:@"type"] isEqualToString:@ "user"])
        {
            debug_NSLog(@"Identity: user search server as %@", presenceUserFull); 
            // send message enabling offline messages 
            //  if(chatServer!=nil) [chatServer release]; 
            userSearchServer= presenceUserFull;
            [userSearchServer retain];
            [self requestSearchInfo]; 
            
            [pool release]; 
            return; 
        }
            
           
        
       
    }
    
	//iq->query->feature
	 if(([State isEqualToString:@"discoinfo"]) && ([elementName isEqualToString: @"feature"]))
	 {
		
		 if(	[[attributeDict objectForKey:@"var"] isEqualToString:@"http://jabber.org/protocol/disco#info"])
		 {
			  debug_NSLog(@"FEATURE: disco info"); 
          
		
		 }
         
         if(	[[attributeDict objectForKey:@"var"] isEqualToString:@ "http://jabber.org/protocol/muc"])
		 {
			 debug_NSLog(@"FEATURE: supports MUC"); 
			 // send message enabling offline messages 
			 
		
			 [pool release]; 
			 return; 
		 }
         
        
		 
		 if(	[[attributeDict objectForKey:@"var"] isEqualToString:@"http://jabber.org/protocol/offline"])
		 {
			 debug_NSLog(@"FEATURE: supports offline messages"); 
			 // send message enabling offline messages 
			 
			 [self talk:@"<iq type='get' id='fetch1'><offline xmlns='http://jabber.org/protocol/offline'><fetch/></offline></iq>"];
			 [pool release]; 
			 return; 
		 }
		 
		 
		 if(	[[attributeDict objectForKey:@"var"] isEqualToString:@"msgoffline"])
		 {
			 debug_NSLog(@"FEATURE: supports offline messages (msgoffline)"); 
			 // send message enabling offline messages 
			 
			// [self talk:@"<iq type='get' id='fetch1'><offline xmlns='http://jabber.org/protocol/offline'><fetch/></offline></iq>"];
			 [pool release]; 
			 return; 
		 }
		 
	 }
	
	
	
	


	
// ******** buddy icons parser******* 
	
	//iq->vcard
	if(([State isEqualToString:@"iq"]) && ([elementName isEqualToString: @"vCard"]))
	{
	
		
		debug_NSLog(@"vcard"); 
		 [State release]; 
		 State=@"vCard";
		 [State retain];
			[pool release];
		return; 
		
	}
	
	
	if(([State isEqualToString:@"vCard"]) && ([elementName isEqualToString: @"FN"]))
	{
		debug_NSLog(@"vcard FN"); 
		[State release]; 
		State=@"vCardFN";
		[State retain];
		
		if(messageBuffer!=nil) 
		{
			[messageBuffer release]; 
			messageBuffer=nil; 
		}
		
		[pool release];
		return; 
		
	}
	
	if(([State isEqualToString:@"vCard"]) && ([elementName isEqualToString: @"NICKNAME"]))
	{
		debug_NSLog(@"vcard Nickname"); 
		[State release]; 
		State=@"vCardNickname";
		[State retain];
		
		if(messageBuffer!=nil) 
		{
			[messageBuffer release]; 
			messageBuffer=nil; 
		}
		
		[pool release];
		return; 
		
	}
	
	
	if((([State isEqualToString:@"vCard"]) || ([State isEqualToString:@"vCardFN"])
		|| ([State isEqualToString:@"vCardNickname"])
		
		) && ([elementName isEqualToString: @"PHOTO"]))
	{
				debug_NSLog(@"vcard photo"); 
		[State release]; 
		State=@"vCardPhoto";
		[State retain];
			[pool release];
		return; 
		
	}
	
	
	if(([State isEqualToString:@"vCardPhoto"]) && ([elementName isEqualToString: @"TYPE"]))
	{
		
		[State release]; 
		State=@"vCardPhotoType";
		[State retain];
		
		if(messageBuffer!=nil) 
		{
			[messageBuffer release]; 
			messageBuffer=nil; 
		}
			[pool release];
		return; 
		
	}

	
	if(([State isEqualToString:@"vCardPhotoType"]) && ([elementName isEqualToString: @"BINVAL"]))
	{
		
	//	NSLog(@"binval"); 
		[State release]; 
		State=@"vCardPhotoBinval";
		[State retain];
		
		if(messageBuffer!=nil) 
		{
			[messageBuffer release]; 
			messageBuffer=nil; 
		}
			[pool release];
		return; 
		
	}
	
    
   
   
    
	
	//****** begin presence state machine
	if([elementName isEqualToString:@"presence"])
	{
		if(State!=nil) [State release]; 
		State=@"presence";
		[State retain];
	
		//reset all vars on the opening of a new presence block
	
		if(presenceUser!=nil) 
		{
			//[presenceUser release];
			presenceUser=nil;
		}
 
			if(presenceShow!=nil) 
		{
			//[presenceShow release];
			presenceShow=nil;
		}
		
		
		if(presenceStatus!=nil) 
		{
		//	[presenceStatus release];
			presenceStatus=nil;
		}
		
		if(presencePhoto!=nil) 
		{
			//[presencePhoto release];
			presencePhoto=nil;
		}

		if(presenceType!=nil) 
		{
			//[presenceType release];
			presenceType=nil;
		}
		
		
		
		//remove any  resource markers and get user
		presenceUser=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
		[presenceUser retain];
		debug_NSLog(@"Presence from %@", presenceUser); 
		
		
		//get photo hash
		
		//what type?
		debug_NSLog(@" presence notice %@",[attributeDict objectForKey:@"type"] ); 
		
		if([[attributeDict objectForKey:@"type"] isEqualToString:@"error"])
		{
			presenceType=@"error";
            
            
            //we are done, parse next element
            [pool release]; 
            return; 
			
		}
		else
			
			if([[attributeDict objectForKey:@"type"] isEqualToString:@"subscribed"])
			{
				presenceType=@"subscribed";
			}
			else
				
				if([[attributeDict objectForKey:@"type"] isEqualToString:@"unsubscribed"])
				{
					presenceType=@"unsubscribed";
				}
				else
					if([[attributeDict objectForKey:@"type"] isEqualToString:@"unsubscribe"])
					{
						presenceType=@"unsubscribe";
					}
					else
						if([[attributeDict objectForKey:@"type"] isEqualToString:@"probe"])
						{
							presenceType=@"probe";
						}
						else
		
		if([[attributeDict objectForKey:@"type"] isEqualToString:@"unavailable"])
		{
				
		
			presenceType=@"unavailable";
			//a buddy logout 
			//make sure not already there
				if(![self isInRemove:presenceUser])
				{
					debug_NSLog(@"removing from list"); 
					[db setOfflineBuddy:presenceUser :accountNumber]; 
					//remove from online list
				}
			
		
		}
		else
	
			if([[attributeDict objectForKey:@"type"] isEqualToString:@"subscribe"])
		{
			
			NSString* askmsg=[NSString stringWithFormat:@"This user would like to add you to his/her list. Allow?"]; 
			//ask for authorization 
			
			UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:presenceUser
															message:askmsg
														   delegate:self cancelButtonTitle:@"Yes"
												  otherButtonTitles:@"No", nil] autorelease];
			[alert show];
						
			presenceType=@"subscribe";
			
		}
        
     
			
		if(presenceType ==nil)
		{
			
			debug_NSLog(@"presence priority notice"); 	
			
			if((presenceUser!=nil) && ([[presenceUser stringByTrimmingCharactersInSet:
										 [NSCharacterSet whitespaceAndNewlineCharacterSet]] length]>0))
				if(![db isBuddyInList:presenceUser:accountNumber]){
					
					debug_NSLog(@"Buddy not already in list"); 
					
					
					[db addBuddy:presenceUser :accountNumber :@"" :@""];
					[db setOnlineBuddy:presenceUser :accountNumber];
					
					
					debug_NSLog(@"Buddy added to  list"); 
					
					
				}
				else
				{
					debug_NSLog(@"Buddy already in list, showing as online now"); 
					[db setOnlineBuddy:presenceUser :accountNumber];
					
					
					
					
				}
		}
		
	[pool release];
		return;
	}
	
	

	

	if((([elementName isEqualToString:@"photo"])  || ([elementName isEqualToString:@"ns13:photo"]) 
	   )
	   && ([State isEqualToString:@"presence"]))
		
	{
		if(State!=nil)  [State release]; 
		State=@"Photo";
		[State retain];
		[pool release];		
		return;
	}
	
	
	if(([elementName isEqualToString:@"status"]) && ([State isEqualToString:@"presence"]))
	{
		if(State!=nil)  [State release]; 
		State=@"Status";
		[State retain];
		[pool release];
		return;
	}
	
	
	

	if(([elementName isEqualToString:@"show"]) && ([State isEqualToString:@"presence"]))
	{
		if(State!=nil)  [State release]; 
		State=@"Show";
 [State retain];
		[pool release];
		return;
	}
	

	
	if(([elementName isEqualToString:@"photo"]) && ([State isEqualToString:@"presence"]))
	{
		if(State!=nil) [State release]; 
		State=@"PresencePhoto";
 [State retain];
			[pool release];
		return;
	}
	
	
	

	
	//********* message state machine
	
	//ignore error message
	if(([elementName isEqualToString:@"message"])  && ([[attributeDict objectForKey:@"type"] isEqualToString:@"error"]))
	{
		debug_NSLog(@"ignoring message error"); 
		
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Message error"
														 message:@"Message could no be delivered"
														delegate:self cancelButtonTitle:nil
											   otherButtonTitles:@"Close", nil] autorelease];
		[alert show];
		
		
		[pool release];
		return;
	}
	
	
	
	if(([elementName isEqualToString:@"message"])  && ([[attributeDict objectForKey:@"type"] isEqualToString:@"groupchat"]))
	{
		if(State!=nil) [State release]; 
		State=@"Message";
		[State retain];
		if(messageUser!=nil) [messageUser release];
		if(mucUser!=nil) [mucUser  release];
		NSArray*  parts=[[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/"];
		
		if([parts count]>1)
		{
            debug_NSLog(@"group chat message"); 
		messageUser=[parts objectAtIndex:0]; 
			mucUser=[parts objectAtIndex:1]; //stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"_%@", domain] 
												//					   withString:[NSString stringWithFormat:@"@%@", domain]] ;
		
		
			
		}
        else
            
        {
		debug_NSLog(@"group chat message from room "); 
        messageUser=[attributeDict objectForKey:@"from"]; 
        mucUser=    [attributeDict objectForKey:@"from"]; 
		}
        [messageUser retain];
        [mucUser retain]; 
        
        
		[pool release];
		return;
	}
	else
	if(([elementName isEqualToString:@"message"]) )//&& ([[attributeDict objectForKey:@"type"] isEqualToString:@"chat"]))
	{
		if(State!=nil) [State release]; 
		State=@"Message";
		[State retain];
		if(messageUser!=nil) [messageUser release];
	  messageUser=[[(NSString*)[attributeDict objectForKey:@"from"] componentsSeparatedByString:@"/" ] objectAtIndex:0];
		
		[messageUser retain];
	
		
		[pool release];
		return;
	}
	
	//message->body
	if(([State isEqualToString:@"Message"]) && ([elementName isEqualToString: @"body"]))
	{
		if(State!=nil) [State release]; 
		State=@"MessageBody";
		[State retain];
		
		if(messageBuffer!=nil) 
		{
			[messageBuffer release];
			messageBuffer=nil; 
		}
		[pool release];
		return; 
	}
	
	//multi user chat
	//message->user:X
	if(([State isEqualToString:@"Message"]) && ( ([elementName isEqualToString: @"user:invite"]) || ([elementName isEqualToString: @"invite"]))
	  // && (([[attributeDict objectForKey:@"xmlns:user"] isEqualToString:@"http://jabber.org/protocol/muc#user"]) || 
		//  ([[attributeDict objectForKey:@"xmlns"] isEqualToString:@"http://jabber.org/protocol/muc#user"]) 
		//   )
	   )
	{
		if(State!=nil) [State release]; 
		State=@"MucUser";
		[State retain];
		
		[pool release];
		
       // [self joinMuc:messageUser:@""]; // since we dont have a pw, leave it blank
        
        NSString* askmsg=[NSString stringWithFormat:@"%@: You have been invited to this group chat. Join? ", messageUser]; 
        //ask for authorization 
        
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Invite"
                                                         message:askmsg
                                                        delegate:self cancelButtonTitle:@"Yes"
                                               otherButtonTitles:@"No", nil] autorelease];
        [alert show];
        
		return; 
	}
	
	if(([State isEqualToString:@"MucUser"]) && (([elementName isEqualToString: @"user:invite"]) || ([elementName isEqualToString: @"invite"]))
	   
	   )
	{
	//	messageUser=[attributeDict objectForKey:@"from"] ;		
	
		
		
		[pool release];
		return; 
	}
	
	if(([State isEqualToString:@"MucUser"]) && (([elementName isEqualToString: @"user:reason"])) || ([elementName isEqualToString: @"reason"]))
	{
		debug_NSLog(@"user reason set"); 
		if(State!=nil) [State release]; 
		State=@"MucUserReason";
		[State retain];
		
		if(messageBuffer!=nil) 
		{
			[messageBuffer release];
			messageBuffer=nil; 
		}
		[pool release];	
		

		return; 
	}
	
	
	[pool release];
	
}


- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName{     
  
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	if(lastEndedElement!=nil) [lastEndedElement release]; 
	lastEndedElement=elementName;
	[lastEndedElement retain]; 
	
debug_NSLog(@"ended this element: %@", elementName);

	
	//******* login functons ******* 
	if([elementName isEqualToString:@"stream:features"])
	{
		
		[State release]; 
	
       /* if(SASLSupported!=true) 
        {
        //initialte login if it nevre triggered through MECHs
            [self login:nil]; 
        }
        else
        {*/
            
            [[NSNotificationCenter defaultCenter] 
             postNotificationName: @"XMPPMech" object: self];
            
            debug_NSLog(@" posted mechanisms notification to login"); 
            
			[[NSNotificationCenter defaultCenter] removeObserver:self  name: @"XMPPMech" object:self]; // no longer needed
        //}
        
		[pool release];
		return;
		//[parser abortParsing]; 
		
	}
	
	if( [elementName isEqualToString:@"mechanisms"] ) 	
	{
		debug_NSLog(@" got mechanisms"); 
	
        [State release]; 
		State=@"Features";
        
		[pool release];
		return; 
	}	
	
	if( ([elementName isEqualToString:@"mechanism"]) && ([State isEqualToString:@"Mechanism"])) 
	{
		
		[State release]; 
		State=@"Mechanisms"; 
		
		debug_NSLog(@"got login mechanism: %@", messageBuffer); 
		if([messageBuffer isEqualToString:@"PLAIN"])
		{
			debug_NSLog(@"SASL PLAIN is supported"); 
			SASLPlain=true; 
		}
		
		if([messageBuffer isEqualToString:@"CRAM-MD5"])
		{
			debug_NSLog(@"SASL CRAM-MD5 is supported"); 
			SASLCRAM_MD5=true; 
		}
		
		if([messageBuffer isEqualToString:@"DIGEST-MD5"])
		{
			debug_NSLog(@"SASL DIGEST-MD5 is supported"); 
			SASLDIGEST_MD5=true; 
		}
		
		[messageBuffer release];
		messageBuffer =nil;
	[pool release];
		return; 
		
	}
	

	if([elementName isEqualToString:@"jid"])  
	{
		[responseUser release];
		responseUser=messageBuffer;
		[responseUser retain];
	
		debug_NSLog(@"read JID to get user:%@", responseUser); 
		[messageBuffer release];
		messageBuffer =nil;
		
        //set jingle call my own  jid var 
        jingleCall.me =responseUser; 
        
		[self setAvailable]; 
		loggedin=true; 
		
        NSRange pos=[server rangeOfString:@"google"]; 
		// for google connections 
        if(pos.location!=NSNotFound)
        {
            [self talk:[jingleCall getGoogleInfo]];
        }

        
        
		
		// this has to come after set available becasue the post login functions in appdelegate set default status and messages
		[[NSNotificationCenter defaultCenter] 
		 postNotificationName: @"LoggedIn" object: self];
		
         //send jingle call --testing
        //[self talk:  [jingleCall initiateJingle:@"monaltest@gmail.com"]];
      
        
		// send command to download the roster
		[self getBuddies];

		[pool release];
		return;
	}

	
	//******** Digest MD5 handler
	if((SASLDIGEST_MD5==true)   &&
	   (([elementName isEqualToString:@"challenge"]) && ([State isEqualToString:@"DigestChallenge"])))
	{
		NSString* challengeText=[NSString stringWithString:messageBuffer];
		debug_NSLog(@"challenge text: %@", challengeText); 
		
		NSString* decoded=[[NSString alloc]  initWithData: (NSData*)[self dataWithBase64EncodedString:challengeText] encoding:NSASCIIStringEncoding];
		debug_NSLog(@"decoded challenge to %@", decoded); 
		NSArray* parts =[decoded componentsSeparatedByString:@","]; 
		
		NSArray* realmparts= [[parts objectAtIndex:0] componentsSeparatedByString:@"="];
		NSArray* nonceparts= [[parts objectAtIndex:1] componentsSeparatedByString:@"="];
		
		NSString* realm=[[realmparts objectAtIndex:1] substringWithRange:NSMakeRange(1, [[realmparts objectAtIndex:1] length]-2)] ;
		NSString* nonce=[nonceparts objectAtIndex:1] ;
		
		//if there is no realm
		if(![[realmparts objectAtIndex:0]  isEqualToString:@"realm"])
		{
			realm=@"";
			nonce=[realmparts objectAtIndex:1];
		}
		
		
		
		NSString* cononce=[self MD5: [NSString stringWithFormat:@"%d",random()%100000]]; 
	
		PasswordManager* pass= [PasswordManager alloc] ; 
		[pass init:accountNumber];
	
        NSString* password=[pass getPassword];
        if([password length]==0)
        {
            if(theTempPass!=NULL)
                password=theTempPass; 
            
        }
		
		
		// ****** digest stuff going on here...
		NSString* X= [NSString stringWithFormat:@"%@:%@:%@", account, realm, password ];
		NSString* Y= [self MD5_16:X];
		
		/*NSString* A1= [NSString stringWithFormat:@"%@:%@:%@:%@@%@/%@", 
					   Y,[nonce substringWithRange:NSMakeRange(1, [nonce length]-2)],cononce,account,domain,resource];
		 */
		
		//  if you have the authzid  here you need it below too but it wont work on som servers
		// so best not include it
		
		NSString* A1= [NSString stringWithFormat:@"%@:%@:%@", 
					   Y,[nonce substringWithRange:NSMakeRange(1, [nonce length]-2)],cononce];
		
		
		
		NSString* HA1=[self MD5:A1];
		
		
		
		NSString* A2=[NSString stringWithFormat:@"AUTHENTICATE:xmpp/%@", server]; 
		NSString* HA2=[self MD5:A2];
		
	
		
		NSString* KD=[NSString stringWithFormat:@"%@:%@:00000001:%@:auth:%@", HA1, [nonce substringWithRange:NSMakeRange(1, [nonce length]-2)], cononce, HA2];
		
		
		NSString* responseData=[self MD5:KD];
		
		
		
		NSString* response=[NSString stringWithFormat:@"username=\"%@\",realm=\"%@\",nonce=%@,cnonce=\"%@\",nc=00000001,qop=auth,digest-uri=\"xmpp/%@\",response=%@,charset=utf-8",
						   account,realm, nonce, cononce, server, responseData];
		//,authzid=\"%@@%@/%@\"  ,account,domain, resource
		
		
		debug_NSLog(@"sending  response to %@", response);
		
		NSString* encoded=[self base64Encoding:response];
		
		
		NSString* xmppcmd = [NSString stringWithFormat:@"<response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>%@</response>", encoded];

		[self talk:xmppcmd];
		
		[State release]; 
		State=@"DigestClientResponse"; 
		[State retain];
		
		
		[pool release];
		return; 
		
	}
	
	
	//***** sasl success...
	if(([elementName isEqualToString:@"success"]) &&  ([State isEqualToString:@"SASLSuccess"])
	   )
		
	{
		if(State!=nil) [State release]; 
		State=nil; 
		
		
		debug_NSLog(@"sasl complete..restarting stream"); 
		
		srand([[NSDate date] timeIntervalSince1970]);
		// make up a random session key (id)
		sessionkey=[NSString stringWithFormat:@"monal%d",random()%100000]; 
		[sessionkey retain];
		
		NSString* xmpprequest2; 
        if([domain length]>0)
        xmpprequest2=[NSString stringWithFormat:
								@"<stream:stream to='%@' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'  version='1.0'>",domain];
        else
            xmpprequest2=[NSString stringWithFormat:
                          @"<stream:stream  xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'  version='1.0'>"];
            
		
		[self talk:xmpprequest2];		
		
		
		[pool release];
		
		return;
		
		
	}
	
	
	//****** other functions****** 
		if([elementName isEqualToString: @"user:reason"])
		{
			debug_NSLog(@"got user reason: %@", messageBuffer); 
		}
	
	
	if([elementName isEqualToString:@"vCard"])
	{
		if(vCardUser!=nil)
		{
			// insert into ot update table 	
		//trigger update
	
		
		//note that these "" fields might wipe out status and stuff.. thi sis just to trigger count>0
		//NSArray* elements =[NSArray arrayWithObjects:vCardUser,@"", @"", @"" ,@"0",userfull,nil];
		//NSMutableDictionary* row = [NSMutableDictionary dictionaryWithObjects:elements forKeys:buddyListKeys];
		
		
			[db setOnlineBuddy:vCardUser :accountNumber];

		[vCardUser release];
		vCardUser=nil; 
		}
		
		if(vCardFullName!=nil)
		{
		[vCardFullName release];
		vCardFullName=nil; 	
		}
		
		[pool release]; 
		return;
	}
	
	if ( ([State isEqualToString:@"vCardFN"]) && [elementName isEqualToString:@"FN"] && (messageBuffer!=nil))
	{
		if(vCardUser!=nil) //sanity check 
		{
		vCardFullName=[NSString stringWithString:messageBuffer];
		
		[vCardFullName retain];
			
			[messageBuffer release];
			messageBuffer =nil;
	
		debug_NSLog(@"Got full name %@ for %@,  account %@", vCardFullName, vCardUser, accountNumber); 
		
		// insert into table or update	
			
					[db setFullName:vCardUser :accountNumber:vCardFullName];
			
		
		}
		
		//we dont wantt o record last ended element because it might trim
		if(lastEndedElement!=nil) [lastEndedElement release]; 
		//lastEndedElement=nil;
	
		[pool release];
		lastEndedElement=nil;
		return; 
	}
	
	if ( ([State isEqualToString:@"vCardNickname"]) && [elementName isEqualToString:@"NICKNAME"] && (messageBuffer!=nil))
	{
		if(vCardUser!=nil) //sanity check 
		{
			NSString* vCardNickName=[NSString stringWithString:messageBuffer];
			
		
			
			[messageBuffer release];
			messageBuffer =nil;
			
			debug_NSLog(@"Got nick name %@ for %@,  account %@", vCardNickName, vCardUser, accountNumber); 
			
			// insert into table or update	
			[db setNickName:vCardUser :accountNumber:vCardNickName];
			
		}
		
		//we dont wantt o record last ended element because it might trim
		if(lastEndedElement!=nil) [lastEndedElement release]; 
		//lastEndedElement=nil;
		
		[pool release];
		lastEndedElement=nil;
		return; 
	}
	
	
	
 	if ( ([State isEqualToString:@"vCardPhotoType"]) && [elementName isEqualToString:@"TYPE"] && (messageBuffer!=nil))
	{
		vCardPhotoType=[NSString stringWithString:messageBuffer];
		debug_NSLog(@"Photo type: %@",vCardPhotoType) ; 
		[vCardPhotoType retain];
	[pool release];
		return; 
	}
	
	
	
	if ( ([State isEqualToString:@"vCardPhotoBinval"])  && ([elementName isEqualToString:@"iq"]))
	{

		[State release];
		State=@"";
		[State retain];
		
		[pool release];
		
		return;
	
		//[parser abortParsing]; 
		
	}
	

	
	// for blank ones with no vcard 
	if( ([elementName isEqualToString:@"iq"]))
	{
		if(vCardUser!=nil) 
		{
			[vCardUser release]; 
			vCardUser=nil; 
		}
	}
	
	if(([State isEqualToString:@"vCardPhotoBinval"])  &&
	   [elementName isEqualToString:@"BINVAL"] 
	   &&(messageBuffer!=nil)
		)
	{
		
		
		vCardPhotoBinval=[NSString stringWithString:messageBuffer];
		[messageBuffer release];
		messageBuffer =nil;
		
		NSString* extension=nil; 
		// we have type and data..  save it
		if([vCardPhotoType isEqualToString:@"image/png"])  
		{
			extension=@"png"; 
		}
		
		if([vCardPhotoType isEqualToString:@"image/jpeg"])  
		{
			extension=@"jpg"; 
		}
			
	//	debug_NSLog(@"contents: %@",vCardPhotoBinval) ; 
		
		
		debug_NSLog(@"saving file %@ ", vCardPhotoType);
		if((vCardUser!=nil)  && (extension!=nil))// prevent wrong user icon situation
		{
		NSString* filename=[NSString stringWithFormat:@"/buddyicons/%@.%@", vCardUser,extension];
			NSString* clean_filename=[NSString stringWithFormat:@"%@.%@", vCardUser,extension];
			
			
	
		NSFileManager* fileManager = [NSFileManager defaultManager]; 
		
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *documentsDirectory = [paths objectAtIndex:0];
		NSString *writablePath = [documentsDirectory stringByAppendingPathComponent:filename];
	//	debug_NSLog(@"see if file ther %@", filename);
		//if( ![fileManager fileExistsAtPath:writablePath])
		{
			// The buddy icon
	
		debug_NSLog(@"file: %@",writablePath) ; 
			//[fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:&error];
			if([[self dataWithBase64EncodedString:vCardPhotoBinval] writeToFile:writablePath 
							   atomically:NO 
				] ) debug_NSLog(@"wrote file"); else  debug_NSLog(@"failed to write"); 
			
		
			//set db entry
			[db setIconName:vCardUser :accountNumber:clean_filename];
			
		} 
		
			
			
		
	
			
		}
	
		
		[vCardPhotoType release];
		
		
		[pool release];
		return; 
	}
	
	if(([State isEqualToString:@"errormsg"]) &&  (
												  //subset of allowed errors for now
													([elementName isEqualToString:@"<bad-request/>"]) ||
												    ([elementName isEqualToString:@"<conflict/>"]) ||
												    ([elementName isEqualToString:@"<feature-not-implemented/>"]) ||
												    ([elementName isEqualToString:@"<item-not-found/>"]) ||
												    ([elementName isEqualToString:@"<gone/>"]) ||
												  
												     ([elementName isEqualToString:@"<recipient-unavailable/>"]) ||
												     ([elementName isEqualToString:@"<registration-required/>"]) ||
												     ([elementName isEqualToString:@"<remote-server-timeout/>"]) ||
												     ([elementName isEqualToString:@"<service-unavailable/>"]) ||
												    ([elementName isEqualToString:@"<subscription-required/>"]) ||
												    ([elementName isEqualToString:@"<undefined-condition/>"]) ||
												    ([elementName isEqualToString:@"<unexpected-request/>"]) 
												  
	 )
	 ) //hust show the first error.
	{
		
		//error=[attributeDict objectForKey:@"code"] ;
		//show message
		
		//NSString* alertMsg=[NSString stringWithFormat:@"The server returned an error Code: %@", error];
		
		// we want to parse messages here
		/*
		 
		 
		 */
		
		
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"XMPP error"
														message:elementName
													   delegate:self cancelButtonTitle:nil
											  otherButtonTitles:@"Close", nil] autorelease];
		[alert show];
		
		
		
		errorState=true; 
		[State release];
		State=@"";
		[State retain];
		[pool release];
		return; 
	}
	
	

	
	//this is the photo hash
	if([State isEqualToString:@"Photo"])
	{
		
		// see if user is online first.
		if([db isBuddyInList:presenceUser :accountNumber])
		{
		
		// grab buffer string
		if(messageBuffer!=nil)
		{
			NSString* hash =[NSString stringWithString:messageBuffer];
			debug_NSLog(@"got photo hash:%@",hash); 
			// check current hash
			if([hash isEqualToString:[db buddyHash:presenceUser :accountNumber]])
			{
				// same nothing
				debug_NSLog(@"hash same");  
			}
			else
			{
			//differnt-> update  and call vcard
				[db setBuddyHash:presenceUser :accountNumber:hash];
					debug_NSLog(@"hash different"); 
				[self getVcard:presenceUser];
				 	debug_NSLog(@"requested vcard"); 
			}
		
			
		
			
		}
		}
		[messageBuffer release];
		messageBuffer =nil;
		
		[State release];
		State=@"presence"; 
		[State retain];
		
	}
	
	
	//this is the status (onine,away etc)
	if([State isEqualToString:@"Show"])
	{
		// grab buffer string
		if(messageBuffer!=nil)
		{
		 presenceShow=[NSString stringWithString:messageBuffer];
			debug_NSLog(@"got show:%@",presenceShow); 
			[db setBuddyState:presenceUser :accountNumber:presenceShow];
		[messageBuffer release];
		messageBuffer =nil;
		}
		
		[State release];
		State=@"presence"; 
		[State retain];
	
	}
	
	
	//this is the status message
	if([State isEqualToString:@"Status"])
	{
			// grab buffer string
		if(messageBuffer!=nil)
		{
		presenceStatus=[NSString stringWithString:messageBuffer];
			debug_NSLog(@"got status:%@",presenceStatus); 
			[db setBuddyStatus:presenceUser :accountNumber:presenceStatus];
		[messageBuffer release];
		messageBuffer =nil;
		}	
		[State release];
		State=@"presence"; 
		[State retain];
	}
	
	
	if([State isEqualToString:@"PresencePhoto"])
	{
		if(messageBuffer!=nil)
		{
		presencePhoto=[NSString stringWithString:messageBuffer];
		[messageBuffer release];
		messageBuffer =nil;
		}
			// grab buffer string
		[State release];
		State=@"presence"; 
		[State retain];
	}
	
	
	if([elementName isEqualToString:@"presence"]) 
	   {
		   if(presenceShow==nil) 
		   {
			   
			   
			   debug_NSLog(@"setting blank state"); 
			   [db setBuddyState:presenceUser :accountNumber:@""];
		   }
		   
		   
		   if(presenceStatus==nil) 
		   {
			   
			  
			    debug_NSLog(@"setting blank status");
			   [db setBuddyStatus:presenceUser :accountNumber:@""];
		   }
		   
		  
		   [State release];
		   State=@"";
		   [State retain];
		   
		   
		   [presenceUser release];
		   presenceUser=@"";
		   [State retain];
		   
		   [pool release];
		   return;
		   
		   
	   }
	
	

	
	
	
	if([State isEqualToString:@"SASLmethod"])
	{
		if([messageBuffer isEqualToString:@"PLAIN"])
		{
			//sasl plain allowed
			
		}
		
		[messageBuffer release];
		messageBuffer =nil;
			[pool release];
		return;
	}
	
	if(([State isEqualToString:@"MessageBody"] ) 
	   && ([elementName isEqualToString:@"body"]) )
	{
				
		if(State!=nil) [State release]; 
		State=@"Message";
		[State retain];
		
		[pool release];
		return;
	}
	
	
	if( ([elementName isEqualToString:@"message"]) )
	{

		if(messageBuffer!=nil)
		{
		//add message from user
		NSString* messagetext=[NSString stringWithFormat:messageBuffer];
		[messageBuffer release];
		messageBuffer =nil;
		//NSArray* objects	=[NSArray arrayWithObjects:messageUser,messagetext,nil];
		//NSArray* keys =[NSArray arrayWithObjects:@"from", @"message",nil];
		
		
		//NSDictionary* row =[NSDictionary dictionaryWithObjects:objects  forKeys:keys]; 
		//[messagesIn addObject:row];
		if(messagetext!=nil)
		{
			debug_NSLog(@" message : %@", messagetext); 
			if(mucUser==nil) 
				[db addMessage:messageUser : [NSString stringWithFormat:@"%@@%@", account, domain] :accountNumber :messagetext:messageUser];
			else
			[db addMessage:messageUser : [NSString stringWithFormat:@"%@@%@", account, domain] :accountNumber :messagetext:mucUser];
		}
			
			//debug_NSLog(@"%d messages messge body: %@ from %@",[messagesIn count], [row objectForKey:@"message"], messageUser);
		}
		
		//debug_NSLog(@"messge ended aborting pasrsing"); 
		//trimAtLast=true; 
		[pool release];
		//[parser abortParsing]; 
	}
    
    
    
    //end of usersearch
	if(([State isEqualToString:@"UserSearch"]) && ([elementName isEqualToString: @"item"]))
    {
        [[NSNotificationCenter defaultCenter] 
         postNotificationName: @"UserSearchResult" object: self];
    }
	
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	
	//meshanisms->mechanism (SASLmechanisms->SASLmethod)
	if (([State isEqualToString:@"SASLmethod"]) 
		||([State isEqualToString:@"Mechanism"])
			||([State isEqualToString:@"Jid"])
		
		|| ([State isEqualToString:@"Show"]) ||
		([State isEqualToString:@"Status"]) ||([State isEqualToString:@"PresencePhoto"])
		
			||([State isEqualToString:@"vCardFN"])
		||([State isEqualToString:@"vCardPhotoBinval"])
		||([State isEqualToString:@"vCardPhotoType"])
		
				||([State isEqualToString:@"DigestChallenge"])
		
		|| ([State isEqualToString:@"MessageBody"] )
			
				|| ([State isEqualToString:@"Photo"] ) 
			|| ([State isEqualToString:@"MucUserReason"] ) 
		
		)
	{
		if(messageBuffer==nil)
		{
			messageBuffer=[[[NSMutableString alloc] initWithString:string] autorelease];
			
		
			
		}
		else
		{
			[messageBuffer appendString:string];
		}
	}
	
 


	
if(messageBuffer!=nil)	[messageBuffer retain]; 
	[pool release];
}

- (void)parser:(NSXMLParser *)parser foundIgnorableWhitespace:(NSString *)whitespaceString
{
	debug_NSLog(@"foudn ignorable whitespace: %@", whitespaceString);
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{

	
	parserCol=[parser columnNumber];
	debug_NSLog(@"Error: line: %d , col: %d desc: %@ ",[parser lineNumber],
		  [parser columnNumber], [parseError localizedDescription]); 
	
	
	
	//if(parserCol==1) [parser abortParsing];
//	debug_NSLog(@"freeing parse error"); 
//	[parseError release];
}

//says when the next stanza starts (ie you want to chop off there
-(int) nextStanza:(NSString*) theString
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	/*
	 XMPP stanzas recognized
	 stream
	 features
	 error
	 starttls
	 proceed
	 failure
	 mechanisms
	 challenge
	 response
	 success
	 auth
	 iq
	 message
	 presence
	 bind
	 
	 */
	
	
	NSArray* stanzas=[NSArray arrayWithObjects:	 @"<stream",
					  @"<features",
					//	@"<error",
					//  @"<starttls",
					  @"<proceed",
					  @"<failure",
					 // @"<mechanisms",
					  @"<challenge",
					  @"<response",
					  @"<success",
					  //@"<auth",
					  @"<iq",
					  @"<message",
					  @"<presence",
					// @"<bind",
					  nil];
	
	int stanzacounter=0; 
	int minpos=[theString length];
	debug_NSLog(@"minpos %d", minpos); 
	 
	if(minpos<2)
	{
		[pool release];
		return minpos;
	
	} 
	//accouting for white space
	NSRange startrange=[theString rangeOfString:@"<"
	
										options:NSCaseInsensitiveSearch range:NSMakeRange(0, [theString length])];
	
	
	if (startrange.location==NSNotFound) 
	{
		[pool release]; 
		return minpos;
	}
	int startpos=startrange.location; 
	startpos++;
	debug_NSLog(@"start pos%d", startpos); 
	
	if(minpos>startpos) 
	while(stanzacounter<[stanzas count])
	{
	
		// start at startpos to prevent picking up the beginning of the NEXT stanza itself
		NSRange pos=[theString rangeOfString:[stanzas objectAtIndex:stanzacounter] 
									 options:NSCaseInsensitiveSearch range:NSMakeRange(startpos, [theString length]-startpos)]; 
		if((pos.location<minpos) && (pos.location!=NSNotFound)) 
		{
			minpos=pos.location; 
		
			
		}
			stanzacounter++;
	}
	 
	[pool release];
	//minpos++; 
	return minpos;
}

-(void) listenerThread
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	listenThreadCounter++; 
	srand([[NSDate date] timeIntervalSince1970]);
	NSDate *now = [NSDate date];
	
	NSString* threadname=[NSString stringWithFormat:@"monal%d",random()%100000]; 
	
	
	while(listenerthread==true)
	{
		debug_NSLog(@"%@ listener thread sleeping onlock", threadname); 
		usleep(500000); 
		int seconds=[[NSDate date] timeIntervalSinceDate:now];
		if(seconds>5) // longer time out because more data is grabbed in one
		{
			debug_NSLog(@"%@ listener thread timing out", threadname); 
			[pool release]; 
			listenThreadCounter--; 
			[NSThread exit]; 
		}
		
	}

	listenerthread=true;
		debug_NSLog(@"%@ listener thread got lock", threadname); 
	

	
	debug_NSLog(@"sleeping to get data.. "); 
	usleep(250000); // gives it a second to gather some data
	NSMutableData* response=[self readData];
	if(response!=nil)
	{
			[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
		if(theset==nil)
			theset =[[[NSMutableData alloc]initWithData:response] autorelease];
		else [theset appendData:response];
	}
	

	debug_NSLog(@" intial get:%@", [[NSString alloc] initWithData:theset encoding:NSUTF8StringEncoding] ); // xmpp is utf-8 encoded
	
	
	/*
	 
	 
	 find begnning of next stanza
	 substring that
	 pass into parser
	 
	 
	 */
	
	
	NSMutableString* block=[[[NSMutableString alloc] initWithData:theset encoding:NSUTF8StringEncoding] autorelease]; 
//fix %
	[block replaceOccurrencesOfString:@"%" withString:@"%%"
							  options:NSCaseInsensitiveSearch
								range:NSMakeRange(0, [block length])];
	
	parserCol=0; 
	
	int itercount=0; 
	
	while(parserCol==0)
	{
		itercount++; 
		if(itercount%3==3) {[[NSNotificationCenter defaultCenter] 
							 postNotificationName: @"UpdateUI" object: self];	
		}
		
	int blockpos=[self nextStanza:block];
		debug_NSLog(@"%d pos ",blockpos);
		
		if((blockpos==[block length])	 
		   && 
		   ([block rangeOfString:@"urn:xmpp:avatar:data"].location!=NSNotFound )  // get more avatar data
		   )
		   break; // there is more to read here
		
	NSString* stanza =  //extract
		[[block substringToIndex:blockpos] stringByTrimmingCharactersInSet:
		 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
			debug_NSLog(@" got stanza %@", stanza);
		if(
		   ([stanza characterAtIndex:[stanza length]-1]!='>') // dont trim to end if it isnt really a stanza
		   )
		{
			debug_NSLog(@"last char is: %c", [stanza characterAtIndex:[stanza length]-1]); 
			if([stanza length]<[block length]) debug_NSLog(@"malformed xml .. recovering"); 
			else
			{
				debug_NSLog(@" there is more to read"); 
			break; // there is more to read here
			}
		}
		
		if ([stanza rangeOfString:@"<message"].location!=NSNotFound )  
		{
			messagesFlag=true;
		}
		
		if (([stanza rangeOfString:@"<presence"].location!=NSNotFound )  ||
			([stanza rangeOfString:@"<vCard"].location!=NSNotFound )  
			)
		{
			presenceFlag=true;
		}
		
	[block deleteCharactersInRange:NSMakeRange(0, blockpos)]; //remove from bufffer

		UInt8* utf8stanza=[stanza UTF8String]; 
	
	NSData* stanzaData=[[[NSData alloc] initWithBytes:utf8stanza length:strlen(utf8stanza)] autorelease] ;
		
		
		//xml parsing 
	NSXMLParser* parser = [[[NSXMLParser alloc] initWithData:stanzaData] autorelease];
	[parser setShouldProcessNamespaces:NO];
    [parser setShouldReportNamespacePrefixes:NO];
    [parser setShouldResolveExternalEntities:NO];
	[parser setDelegate:self];
	
	[parser parse];
		
		
		//ignore for stream start
		if((parserCol>0)&& (
		   ([stanza rangeOfString:@"<stream:stream"].location!=NSNotFound ) ||
		    ([stanza rangeOfString:@"<?xml"].location!=NSNotFound )
		   ) 
		   )
		{
			debug_NSLog(@"ignoring error on stream start"); 
			parserCol=0; 
		}
		// bad XML in a stanza might be a problem
		else if((parserCol>0) && ([block rangeOfString:@"<"].location!=NSNotFound ) )
		{
			debug_NSLog(@"recovering from a possible bad stanza");
			[State release];
			State=@""; 
			parserCol=0; 
		}
		
		else if(parserCol>0)
		{
			[State release];
			State=@""; 
		}
		
	
	}
	
	//the set is what gets carried over when ther eis an incmplete stanza
	if([block length]>0)
    {
        UInt8* utf8stanza=[block UTF8String]; 
        theset=[[[NSMutableData alloc] initWithBytes:utf8stanza length:strlen(utf8stanza)] autorelease] ;
	
    }
    else
		theset=nil; 
	
	
		
	
	debug_NSLog(@"about to leave listener"); 
	
	if(theset!=nil) [theset retain]; 
	[pool release];
	

	
	
	// do not update anything since many objects are destoyed
		if(disconnecting!=true)
		[[NSNotificationCenter defaultCenter] 
		
		 postNotificationName: @"UpdateUI" object: self];	
		
		
		//unlock only after UI update to prevent modification of the same status vars by 2 threads
		debug_NSLog(@" unlocking thread"); 
		listenerthread=false;
		
	listenThreadCounter--; 
		debug_NSLog(@" left listener thread"); 
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
		[NSThread exit]; 
	
	
}

//this is the xmpp listener thread for incoming communication
-(void) listener
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	if(listenThreadCounter<3)
	{
	debug_NSLog(@" detaching new listener thread"); 
		[NSThread detachNewThreadSelector:@selector(listenerThread) toTarget:self withObject:nil];
	}
	[pool release];

}





#pragma mark managing contacts 


-(void) getVcard:(NSString*) buddy
{
    if([db isBuddyMuc:buddy:accountNumber]!=true) // no muc vcard
    {
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
   
   
	vCardDone=false; 

	NSString*	xmpprequest=[NSString stringWithFormat: @"<iq type='get' to='%@'><vCard xmlns='vcard-temp'/></iq>", buddy];
	
	NSDate *now = [NSDate date];
	if ([self talk:xmpprequest])
	/*while(vCardDone!=true)
	{
		
		
			sleep(1);  // try every second 
			int seconds=[[NSDate date] timeIntervalSinceDate:now];
	
		if(seconds> 5)  break; 
	}*/
		
       
    [pool release]; 
         }
	return ;
}




-(bool) removeBuddy:(NSString*) buddy
{

	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
    bool val=false; 
    
 
    //regular contact 
    
	NSString*	xmpprequest1=[NSString stringWithFormat: @"<iq type='set'> <query xmlns='jabber:iq:roster'> <item jid='%@' subscription='remove'/> </query> </iq>", buddy];
	[self talk:xmpprequest1];
	NSString*	xmpprequest=[NSString stringWithFormat: @"<presence to='%@' type='unsubscribe'/>", buddy];

	val= [self talk:xmpprequest];
    
    
    
    // remove from database 
    [db removeBuddy:buddy :accountNumber];
	[pool release]; 
	return val;  
	 
}

-(bool) addBuddy:(NSString*) buddy
{

	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString*	xmpprequest1=[NSString stringWithFormat: @"<iq type='set'> <query xmlns='jabber:iq:roster'> <item jid='%@'/> </query> </iq>", buddy];
	[self talk:xmpprequest1];
	NSString*	xmpprequest=[NSString stringWithFormat: @"<presence to='%@' type='subscribe'/>", buddy];
	
	bool val= [self talk:xmpprequest];
	[pool release]; 
	return val; 
	
	 
}

-(bool)sendAuthorized:(NSString*) buddy
{




	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString*	xmpprequest=[NSString stringWithFormat: @"<presence to='%@' type='subscribed'/>", buddy];
	
	bool val= [self talk:xmpprequest];
[pool release]; 
	return val; 
	
}

-(bool)sendDenied:(NSString*) buddy
{

	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString*	xmpprequest=[NSString stringWithFormat: @"<presence to='%@' type='unsubscribed'/>", buddy];
	
	bool val= [self talk:xmpprequest];
	[pool release]; 
	return val; 
	
}


-(NSInteger) getBuddies
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString* xmpprequest;
	NSRange pos=[server rangeOfString:@"google"]; 
	if(pos.location!=NSNotFound)
		xmpprequest=[NSString stringWithFormat: @"<iq id='%@' from='%@' type='get'><query xmlns='jabber:iq:roster' xmlns:gr='google:roster' gr:ext='2'/></iq>",sessionkey, responseUser];
	else
		xmpprequest=[NSString stringWithFormat: @"<iq id='%@'  from='%@' type='get' ><query xmlns='jabber:iq:roster'/></iq>",sessionkey, responseUser];

	
	bool val= [self talk:xmpprequest];
	[pool release]; 
	return val; 
}

-(bool) message:(NSString*) to:(NSString*) content:(BOOL) group
{

	//<x xmlns='jabber:x:event'><offline/></x>
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	
	NSString*	xmpprequest; 
	
	if(group==true)
xmpprequest=[NSString stringWithFormat: @"<message type='groupchat' to='%@' ><body>%@</body> </message>"
							 , to, content];
	else
	xmpprequest=	[NSString stringWithFormat: @"<message type='chat' to='%@' ><body>%@</body> </message>"
		 , to, content];
	
	bool val= [self talk:xmpprequest];
	[pool release]; 
	return val; 
	
}
#pragma mark responses to Get

 -(bool) sendLast:(NSString*) to:(NSString*) userid
{
	
	
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString*	xmpprequest=[NSString stringWithFormat: @"<iq  type='result'  to='%@' id='%@' ><query xmlns='jabber:iq:last' seconds='0'/></iq>"
							 , to,userid];
	
	bool val= [self talk:xmpprequest];
		[pool release]; 
	return val; 
	
}


-(bool) sendVersion:(NSString*) to:(NSString*) userid
{
	
	
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString*	xmpprequest=[NSString stringWithFormat: @"<iq  type='result'  to='%@' id='%@' ><query xmlns='jabber:iq:version'><name>Monal</name><version>%@</version><os>iOS</os></query></iq>"
							 , to,userid,[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
	
	bool val= [self talk:xmpprequest];
		[pool release]; 
	return val; 
	
}


-(bool) sendTime:(NSString*) to:(NSString*) userid
{

	
    //we can eenable this later. 
	/*
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
    NSString* timezone =[NSString stringWithFormat:@"%d:%d",[[NSTimeZone localTimeZone] secondsFromGMT]/3600, ([[NSTimeZone localTimeZone] secondsFromGMT]%3600)/60];
    

    NSDate *myDate = [NSDate date];

    
    NSString* time=[myDate descriptionWithCalendarFormat:@"%Y-%m-%dT%H:%M:%SZ" timeZone: [NSTimeZone timeZoneWithAbbreviation:@"GMT"] locale:nil];
   
    
    
    
	NSString*	xmpprequest=[NSString stringWithFormat: @"<iq  type='result'  to='%@' id='%@' ><time xmlns='rn:xmpp:time'><tzo> %@</tzo> <utc>%@ </utc> </time>"
							 , to,userid,timezone, time];
	
	bool val= [self talk:xmpprequest];
    [pool release]; */
    
	return true;  
	
}
#pragma mark Jinge Call 
-(bool)rejectCallUser:(NSString*) buddy
{

}

-(bool) acceptCallUser:(NSString*) buddy
{
   // return [self talk:[jingleCall initiateJingle:buddy]]; 
}

-(bool) startCallUser:(NSString*) buddy
{
   return [self talk:[jingleCall initiateJingle:buddy]]; 
}

-(bool) endCall
{
  return [self talk:[jingleCall terminateJingle]];
}


#pragma mark User Search

-(bool) requestSearchInfo
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
    bool val=false; 
    NSString*	xmpprequest1=[NSString stringWithFormat: @"<iq type='get' to='%@' id='search1'> <query xmlns='jabber:iq:search'/> </iq>", userSearchServer];
    val=  [self talk:xmpprequest1];
    
    [pool release]; 
	return val;  
}


-(bool) userSearch:(NSString*) buddy
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
    bool val=false; 
    
    
    //clear search result  array
    [userSearchItems removeAllObjects];
    
    
    NSString*	xmpprequest2= [iqsearch constructUserSearch:userSearchServer: buddy]; 
    
    val= [self talk:xmpprequest2];
    
    [pool release]; 
	return val;  
    
}


#pragma mark MUC

-(void) joinMuc:(NSString*) to :(NSString*) password
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
    NSString* passwordclause; 
    
    if([password isEqualToString:@""])
        passwordclause=@"";
    else passwordclause=[NSString stringWithFormat:@"<password>%@</password>",password]; 
    
	NSString* query =[NSString stringWithFormat:@"<presence to='%@/%@@%@'><x xmlns='http://jabber.org/protocol/muc'><history maxstanzas='5'/> %@</x></presence>"
                      ,to, account, domain, passwordclause]; 
    [self talk:query];
    
    
    
    
  /*  NSString* query2= [NSString stringWithFormat:@"<iq type='get'  to='%@'><query xmlns='http://jabber.org/protocol/disco#info' node='http://jabber.org/protocol/muc#traffic'/></iq>",to];
    
    [self talk:query2];*/
    
    
    [pool release]; 
}


-(bool) closeMuc:(NSString*) buddy
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
    bool val=false; 
    // see if it is a muc name and not a buddy 
    if([db isBuddyMuc:buddy :accountNumber])
    {
        //set offline
       // [db setOfflineBuddy:buddy :accountNumber];
        
        //leave room
        NSString*	xmpprequest1=[NSString stringWithFormat: @"<presence  to='%@/%@@%@' type='unavailable'></presence>", buddy, account, domain];
        val= [self talk:xmpprequest1];
    }
    [pool release]; 
	return val;  
    
}

#pragma mark service discovery

-(bool) queryDiscoItems:(NSString*) to:(NSString*) userid
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
    NSString* discoQuery1=
    [NSString stringWithFormat:@"<iq id='%@' type='get' to='%@'><query xmlns='http://jabber.org/protocol/disco#items' /></iq>",userid, to];
    
    
    bool val= [self talk:discoQuery1];
    [pool release]; 
	return val;
}

-(bool) queryDiscoInfo:(NSString*) to:(NSString*) userid
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
    NSString* discoQuery=
    [NSString stringWithFormat: @"<iq id='%@' type='get' to='%@'><query xmlns='http://jabber.org/protocol/disco#info'/></iq>",userid, to];		
    
    [self talk:discoQuery];
    
    bool val= [self talk:discoQuery];;
    [pool release]; 
	return val;

}




-(bool) sendDiscoInfo:(NSString*) to:(NSString*) userid
{
	
	
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString*	xmpprequest=[NSString stringWithFormat: @"<iq  type='result'  to='%@' id='%@' ><query xmlns='http://jabber.org/protocol/disco#info'> <feature var='http://jabber.org/protocol/disco#items'/> <feature var='http://jabber.org/protocol/disco#info'/> <identity category='client' type='phone' name='monal'/><feature var='http://jabber.org/protocol/si/profile/file-transfer'/> <feature var='http://jabber.org/protocol/si'/> <feature var='jabber:iq:version'/> <feature var='http://jabber.org/protocol/muc#user'/> <feature var='urn:xmpp:jingle:1'/> <feature var='urn:xmpp:jingle:apps:rtp:1'/> <feature var='urn:xmpp:jingle:apps:rtp:audio'/> </query></iq>"
							 , to,userid,[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
	
    //<feature var='urn:xmpp:time'/>
    
    
	bool val= [self talk:xmpprequest];
		[pool release]; 
	return val; 
	
}


# pragma mark  presence functions 

-(NSInteger) setStatus:(NSString*) status
{
		
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString*	xmpprequest; 
	
	if(statusMessage!=nil) [statusMessage release]; 
	statusMessage=[NSString stringWithString:status];
	[statusMessage retain];
 
	
	if(away!=true)
	xmpprequest=[NSString stringWithFormat: @"<presence> <status>%@</status>   </presence>",status, XMPPPriority];
	else
	xmpprequest=[NSString stringWithFormat: @"<presence> <show>away</show> <status>%@</status>  </presence>",status];
	
	

	bool val= [self talk:xmpprequest];
	[pool release]; 
	return val; 
	
	
}

-(NSInteger) setAway
{
	 
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString*	xmpprequest;
	bool val=false; 
	debug_NSLog(@"status %@", statusMessage); 
	if(away!=true) // no need to resend if away is already set
	{
	if((statusMessage==nil)||
		([statusMessage isEqualToString:@""]))                                                                                 
	xmpprequest=[NSString stringWithFormat: @"<presence><show>away</show><status>Away</status></presence>"];
	else
		xmpprequest=[NSString stringWithFormat: @"<presence><show>away</show><status>%@</status></presence>", statusMessage];
	
		
	away=true; 
	 val= [self talk:xmpprequest];
	}
	else val=true;
	[pool release]; 
	return val; 
	
}

-(void) setPriority:(int) val
{
	XMPPPriority=val; 
}

-(NSInteger) setAvailable
{
    /*
     voice-v1: indicates the user is capable of sending and receiving voice media.
     video-v1: indicates the user is capable of receiving video media.
     camera-v1: indicates the user is capable of sending video media.
     */
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSString*	xmpprequest; 
	
	if((statusMessage==nil)
		|| ([statusMessage isEqualToString:@""]))
		xmpprequest=[NSString stringWithFormat: @"<presence> <priority>%d</priority> <c   xmlns=\"http://jabber.org/protocol/caps\"  node=\"http://monal.im\" ver=\"%@\"  ext='avatar voice-v1' />  </presence>",XMPPPriority, [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
	else
		xmpprequest=[NSString stringWithFormat: @"<presence><priority>%d</priority> <c  ext='avatar voice-v1' xmlns=\"http://jabber.org/protocol/caps\" ver=\"1.0\"  />   <status>%@</status></presence>",XMPPPriority,
                     [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"],   statusMessage];
	
	
	away=false; 
	bool val= [self talk:xmpprequest];
	[pool release]; 
	return val; 
	
}


-(NSInteger) setInvisible
{
	
	
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	// note XMPP doesnt have invisible .. need to add later
	NSString*	xmpprequest=[NSString stringWithFormat: @"<presence type=\"unavailable\"> <priority>-5</priority> </presence>"];

	bool val= [self talk:xmpprequest];
	[pool release]; 
	return val; 
	
}

#pragma mark core fucntions

-(bool) talk: (NSString*) xmpprequest;
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	

	
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	if(oStream==nil) return false; 
	if(xmpprequest==nil) return false; 
		debug_NSLog(@"sending: %@ ", xmpprequest);
	const uint8_t * rawstring =
	(const uint8_t *)[xmpprequest UTF8String];
	 int len= strlen(rawstring); 
	if([oStream write:rawstring maxLength:len]!=-1)
	{
		//debug_NSLog(@"sending: ok"); 
		[pool release];
		[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
		
		return true; 
	}
		else
		{
				debug_NSLog(@"sending: failed"); 
			[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
			[pool release];
		
		return false; 
		}
	
}


-(bool) keepAlive
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	//NSString* query =[NSString stringWithFormat:@"<iq id='%@' type='get'><ping xmlns='urn:xmpp:ping'/></iq>", sessionkey];
	
	NSString* query =[NSString stringWithFormat:@" "]; // white space ping because it is less resource intensive and more support
	
	
	bool val= [self talk:query];

	if(streamError==true)
	{
		debug_NSLog(@"stream talking error"); 
		val=false;
	}
	
	
	[pool release]; 
	
	
	return val;
	/* if(val!=true)
 {
	 keepAliveCounter++ ;
 } else keepAliveCounter=0;
	
	if(keepAliveCounter>1) return false; else return true; // needs 2 concurrent keep alive send fails
*/	

}


-(NSMutableData*) readData
{
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];	
	NSMutableData* data= [[NSMutableData alloc] autorelease];
	uint8_t* buf=malloc(51200);
	 int len = 0;
	
	
	if(![iStream hasBytesAvailable]) 
	{
		free(buf);
		[pool release]; 
		return nil; 
	}
	
	len = [iStream read:buf maxLength:51200];
	
	if(len>0) {
		
		[data appendBytes:(const void *)buf length:len];
	//	[bytesRead setIntValue:[bytesRead intValue]+len];
		

		free(buf); 
		//debug_NSLog(@"read %d bytes", len); 
		[data retain]; 
		[pool release]; 
		return [data autorelease];
	} 
	else 
	{
		free(buf); 
		[pool release];
		return nil; 	
	}
}



//delegat function for nsstream

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
	debug_NSLog(@"has event"); 
	switch(eventCode) 
	{
			//for writing
	case NSStreamEventHasSpaceAvailable:
	{
		debug_NSLog(@"Stream has space to write"); 
	
		
		break;
	}
			
			//for reading
			case  NSStreamEventHasBytesAvailable:
		{
			debug_NSLog(@"Stream has bytes to read"); 
			[self listener];
			break;
		}
			
		case NSStreamEventErrorOccurred:
		{
			debug_NSLog(@"Stream errror");
			streamError=true;
			
		//[[NSNotificationCenter defaultCenter] 
		//	 postNotificationName: @"LoginFailed" object: self];

			//reconnect 
			[[NSNotificationCenter defaultCenter] 
			 postNotificationName: @"Reconnect" object: self];
			
			[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
					
			
		
		} 
		case NSStreamEventNone:
		{
			debug_NSLog(@"Stream event none");
			
			
		}
			
			
		case NSStreamEventOpenCompleted:
		{
			debug_NSLog(@"Stream open completed");
			streamOpen++; //this should be called twice, once for each stream
			
		}
			
			
		case NSStreamEventEndEncountered:
		{
			debug_NSLog(@"Stream end encoutered");
			
		}
			
			
		
			
	}
	
}


-(void) disconnect
{

	
	
			[[NSNotificationCenter defaultCenter] removeObserver:self  name: @"XMPPMech" object:self]; // no longer needed
	debug_NSLog(@"removing streams"); 

	//prevent any new read or write
	[iStream setDelegate:nil]; 
	[oStream setDelegate:nil]; 
	
	[oStream removeFromRunLoop:[NSRunLoop currentRunLoop]
					   forMode:NSDefaultRunLoopMode];
	
	[iStream removeFromRunLoop:[NSRunLoop currentRunLoop]
					   forMode:NSDefaultRunLoopMode];
	debug_NSLog(@"removed streams"); 
	
	streamOpen=0; 
	NSDate *now = [NSDate date];
		
	// wait on all threads to end 
	disconnecting=true; 
	listenerthread=true; // lock out other threads
	
// remove any threads that might have been waiting 
	while(listenThreadCounter>0)
	{
		debug_NSLog(@" threads locked out waiting on timeout. left: %d", listenThreadCounter); 
		sleep(2); 
		
		int seconds=[[NSDate date] timeIntervalSinceDate:now];
		if(seconds>5)
		{
			debug_NSLog(@"discocnnect wait timing out. breaking." ); 
			
			break; 
		}
	}
	
	
	@try
	{
	[iStream close];
	//	[iStream release];

	}
	@catch(id theException)
	{
		debug_NSLog(@"Exception in istream close, release"); 
	}
	
	@try
	{
	
		[oStream close];
		
	//	[oStream release];
	}
	@catch(id theException)
	{
		debug_NSLog(@"Exception in ostream close, release"); 
	}
	
	debug_NSLog(@"Connections closed"); 
	
	if(loggedin==true)
	{
	if(messageUser!=nil) [messageUser release];
	if(lastEndedElement!=nil) [lastEndedElement release];
        
        messageUser=nil; 
        lastEndedElement=nil;
	}
	if(theset!=nil) [theset release];
	
	parserCol=0;
		loggedin=false; 
	
	debug_NSLog(@"All closed and cleaned up"); 
	
}


-(void) setRunLoop
{
	[oStream setDelegate:self];
    [oStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
					   forMode:NSDefaultRunLoopMode];
	
	[iStream setDelegate:self];
    [iStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
					   forMode:NSDefaultRunLoopMode];
}

-(bool) connect
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	streamError=false;
	streamOpen=0; 
	if((SSL==true) && (port==5223)) debug_NSLog(@"Using Old style SSL");
	
	
	if(DNSthreadreturn==false) sleep(2); // sleep to let it finsih
	//servers from DNS SRV
	if([serverList count]>0)
	{
		 debug_NSLog(@"Using discovered server, port for domain");
		[server release]; 
		int counter=0; 
		int min=0; 
		while(counter<[serverList count])
		{
			if([[[serverList objectAtIndex:min] objectAtIndex:0] intValue]>
			   [[[serverList objectAtIndex:counter] objectAtIndex:0] intValue])
				min=counter;
			counter++; 
		}
		
		server=[[serverList objectAtIndex:min] objectAtIndex:1];
		port=[[[serverList objectAtIndex:min] objectAtIndex:2] intValue];
		 debug_NSLog(@"set to %@ port: %d", server, port);
	}
	
	iStream=nil; 
	oStream=nil;
	

	// block commented out for being non piblic iphone API
       // NSHost *host = [NSHost hostWithName:server];
        // iStream and oStream are instance variables
      //  [NSStream getStreamsToHost:host port:port inputStream:&iStream
	//				  outputStream:&oStream];
	
	CFStreamCreatePairWithSocketToHost(NULL, (CFStringRef)server, port, &iStream, &oStream);
	
    
	[iStream retain];
	[oStream retain];
	if((iStream==nil) || (oStream==nil))
	{
		debug_NSLog(@"Connection failed");
		UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Connection Error"
														message:@"Could not connect to the server."
													   delegate:self cancelButtonTitle:nil
											  otherButtonTitles:@"Close", nil] autorelease];
		[alert show];
		
		
		[pool release];
		return false;
	}
		else
	debug_NSLog(@"streams created ok");

	[self performSelectorOnMainThread:@selector(setRunLoop)  withObject:nil waitUntilDone:YES];
	
	
	
	
	// iOS4 VOIP socket.. one for all sockets doesnt matter what style connection it is
	if([tools isBackgroundSupported])
	{
		
		if((CFReadStreamSetProperty((CFReadStreamRef)iStream, 
								kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP)) &&
		(CFWriteStreamSetProperty((CFWriteStreamRef)oStream, 
								 kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP)))
		debug_NSLog(@"Set VOIP properties on streams.");
		else
			debug_NSLog(@"could not set VOIP properties on streams.");
		
	}
	

	
	
	if((SSL==true)  && (port==5223))
	{
		// do ssl stuff here
		debug_NSLog(@"securing connection.."); 

		
		
	
		
		//allowing it to accept the peers cert if the host doesnt match.
		NSDictionary *settings = [ [NSDictionary alloc ] 
								  initWithObjectsAndKeys:
								  [NSNumber numberWithBool:YES], @"kCFStreamSSLAllowsExpiredCertificates",
								  [NSNumber numberWithBool:YES], @"kCFStreamSSLAllowsExpiredRoots",
								  [NSNumber numberWithBool:YES], @"kCFStreamSSLAllowsAnyRoot",
								  [NSNumber numberWithBool:NO], @"kCFStreamSSLValidatesCertificateChain",
								  [NSNull null],@"kCFStreamSSLPeerName",
								  @"kCFStreamSocketSecurityLevelNegotiatedSSL", 
								  @"kCFStreamSSLLevel",
								  nil ];
		CFReadStreamSetProperty((CFReadStreamRef)iStream, 
								@"kCFStreamPropertySSLSettings", (CFTypeRef)settings);
		CFWriteStreamSetProperty((CFWriteStreamRef)oStream, 
								 @"kCFStreamPropertySSLSettings", (CFTypeRef)settings);
		
	
	
		
		
		debug_NSLog(@"connection secured"); 
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(login:) name: @"XMPPMech" object:self];
		// for new style this is only done AFTER start tls is sent to not conflict with the earlier mech
	}
	
	[iStream open];
	[oStream open];
	debug_NSLog(@"connection created");
	
	
	//check status before talking.. to prevent block
	if([oStream streamStatus]== NSStreamStatusError)
	 {
	 debug_NSLog(@"stream connect error"); 
	 [pool release]; 
	 return false;
	 }

	
	NSDate *now = [NSDate date];
	
	NSString* threadname=[NSString stringWithFormat:@"monal%d",random()%100000]; 
	
	
	while(streamOpen<2)
	{
		debug_NSLog(@"connect thread sleeping onlock"); 
		usleep(600000); 
		int seconds=[[NSDate date] timeIntervalSinceDate:now];
		if(seconds>3)
		{
			debug_NSLog(@"connect thread timing out.. sending reconnect "); 
			
           // sleep(2); 
            /*[[NSNotificationCenter defaultCenter] 
			 postNotificationName: @"Reconnect" object: self];
			
			[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
            */
            
			[pool release]; 
		return false; 
		}
		
	}
	
	
	
	
	
	[self talk:@"<?xml version='1.0'?>"]; 
	
	if(streamError==true)
	{
		debug_NSLog(@"stream talking error"); 
		[pool release]; 
		return false;
	}
	
	
	if(SSL==false)
	{
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(login:) name: @"XMPPMech" object:self];

	}
	
	
	

	
	[NSThread detachNewThreadSelector:@selector(initilize) toTarget:self withObject:nil];

	

	
	[pool release];
	return true;
}


//this is done as a new thread to prevent the writing from blocking the whole app on connect
-(void)initilize
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	//send XML start
//	NSString* xmpprequest1=[NSString stringWithFormat:@"<?xml version='1.0'?>"];
//	[self talk:xmpprequest1];
	//send stream star
	NSString* xmpprequest; 
      if([domain length]>0)
          xmpprequest=[NSString stringWithFormat:
						   @"<stream:stream to='%@' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'  version='1.0'>",domain];
    else
        xmpprequest=[NSString stringWithFormat:
                     @"<stream:stream  xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'  version='1.0'>"];
        
	[self talk:xmpprequest];

	
	
	
	
	
	[pool release];
	[NSThread exit];
}


-(bool) login:(id)sender
{
	
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
		

		debug_NSLog(@"beginning login procedures"); 
	

	
	//checking fro sasl support

	/*if(SASLSupported!=true)
	{
		//exit on fail
		UIAlertView *addError = [[UIAlertView alloc] 
								 initWithTitle:@"SASL  not supported" 
								 message:@"Your server does not support SASL authentication. Monal can't connect to this server. "
								 delegate:nil cancelButtonTitle:@"Close"
								 otherButtonTitles: nil];
		[addError show];
		[addError release];
		[[NSNotificationCenter defaultCenter] 
		 postNotificationName: @"LoginFailed" object: self];
		
		[pool release];
		return false; 
	}*/
	
    
    //no sasl method and lo negacy
    if((legacyAuth!=true) &&(SASLSupported==true)
	&& (SASLPlain!=true) && (SASLDIGEST_MD5!=true))
	{
		//exit on fail
		UIAlertView *addError = [[UIAlertView alloc] 
								 initWithTitle:@"SASL PLAIN, DIGEST-MD5 not supported" 
								 message:@"While your server does support SASL authentication, it does not support the SASL PLAIN or DIGEST MD5 mechanisms. Monal can't connect to this server. "
								 delegate:nil cancelButtonTitle:@"Close"
								 otherButtonTitles: nil];
		[addError show];
		[addError release];
		
		[[NSNotificationCenter defaultCenter] 
		 postNotificationName: @"LoginFailed" object: self];
		
		[pool release];
		return false; 
	}
 
/*	if((SSL==false) && ((SASLPlain==true) && (SASLDIGEST_MD5!=true)))
	{
		UIAlertView *addError = [[UIAlertView alloc] 
								 initWithTitle:@"Insecure Login" 
								 message:@"Your server does not support a non plaintext login mechanism and is't using SSL.   "
								 delegate:nil cancelButtonTitle:@"Close"
								 otherButtonTitles: nil];
		//You can enable plaintext login in the account settings.
		[addError show];
		[addError release];
		
		[[NSNotificationCenter defaultCenter] 
		 postNotificationName: @"LoginFailed" object: self];
		
		[pool release];
		return false; 
		
		
		
	}*/
	
 
	bool val; 

	
	//use saslplain if it is available instead ofdigest md5

	PasswordManager* pass= [PasswordManager alloc] ; 
	debug_NSLog(@"accno %@", accountNumber); 
	[pass init:accountNumber];
	NSString* password=[pass getPassword] ;
    
    if([password length]==0)
    {
        if(theTempPass!=NULL)
        password=theTempPass; 
        
    }
        
	
	//only sasl plain if SSL is true
	if((SASLPlain==true) & (SSL==true))
	{
		
		
	
		
		
		
		//********sasl plain
		NSString* saslplain=[self base64Encoding: [NSString stringWithFormat:@"\0%@\0%@",  account, password ]];
		
		
		//[xmpprequest release];
		NSString*	xmpprequest; 
		
		// for regular 
		xmpprequest=	[NSString stringWithFormat:@"<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='PLAIN'>%@</auth>",saslplain];
		
		NSRange pos=[server rangeOfString:@"google"]; 
		// for google connections 
		 if(pos.location!=NSNotFound)
			{
		
		xmpprequest=	[NSString stringWithFormat:@"<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' xmlns:ga='http://www.google.com/talk/protocol/auth' ga:client-uses-full-bind-result='true'  mechanism='PLAIN'>%@</auth>",saslplain];
			}
		
		val= [self talk:xmpprequest];
	}
	

	
	else if((SASLPlain==true) & (SSL==false))
	{
	
		 
		
		//sasls plain wihtout SSL
		NSString* saslplain=[self base64Encoding: [NSString stringWithFormat:@"\0%@\0%@",  account,  password]];
		
		
		//[xmpprequest release];
		NSString*	xmpprequest; 
		xmpprequest=	[NSString stringWithFormat:@"<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='PLAIN'>%@</auth>",saslplain];
		
		val= [self talk:xmpprequest];
		
	}
	else if(SASLDIGEST_MD5==true)
	{
		NSString*	xmpprequest; 
		//initiate
		xmpprequest=	[NSString stringWithFormat:@"<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='DIGEST-MD5'/>"];
		
		val= [self talk:xmpprequest];
	}
	
    //legacy auth possible and no other path available
    
 if((legacyAuth==true)
    &&((SASLSupported!=true) ||
       (  (SASLSupported==true)
        && (SASLPlain!=true) && (SASLDIGEST_MD5!=true)
       )
    )
    )
{
	

	

	 // This is a clear text login.. try not to use. not in XMPP 1.0
	
	NSString* xmpprequest=[NSString stringWithFormat:
	 @"<iq type='set' id='auth2'><query xmlns='jabber:iq:auth'><username>%@</username><password>%@</password><resource>%@</resource></query></iq>", account, password, resource];
	val= [self talk:xmpprequest];
	 
	 
	
}

	
	[pool release]; 
	return val; 
}
	










- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	debug_NSLog(@"clicked button %d", buttonIndex); 
	//login or initial error
	if(([[alertView title] isEqualToString:@"Connection Error"])
	   
	   ||([[alertView title] isEqualToString: @"Login Error"])
        ||([[alertView title] isEqualToString: @"Error"])
	  
	   )
	{
		[pool release];
		return; 
	}
	
    if([[alertView title] isEqualToString:@"Invite"])
    {
    
        if(buttonIndex==0) 
        {
            [self joinMuc:messageUser:@""];
       
        }
        
        [pool release]; 
        return; 
    }
	
	//otherwise request 
	if(buttonIndex==0) 
	{
		[self sendAuthorized:[alertView title]];
		[self addBuddy:[alertView title]];
	}
	else
		[self sendDenied:[alertView title]];
	
	
	
	
	
	[pool release];
}


-(void) dealloc
{
	
	[serverList release];
	[iStream release];
	[oStream release];
	
	[iqsearch release]; 
    [jingleCall release];
    
	[server release]; 	
	[accountNumber release];
	
	[account release]; 
	
	[State release]; 
	
	if(responseUser!=nil) [responseUser release];
	
	
	
	[super dealloc]; 
}
	

@end
