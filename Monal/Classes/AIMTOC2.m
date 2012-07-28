//
//  xmpp.m
//  SworIM
//
//  Created by Anurodh Pokharel on 11/18/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "AIMTOC2.h"


@implementation AIMTOC2



@synthesize theset; 

//port, server, domain and resource are ignored here 
-(id )init:(NSString*) theserver:(unsigned short) theport:(NSString*) theaccount: (NSString*) theresource: (NSString*) thedomain:(BOOL) SSLsetting : (DataLayer*) thedb:(NSString*) accountNo:(NSString*) tempPass
{
	accountNumber=accountNo;
	
	server=theserver; 
	port=theport; 
	
    statusMessage=nil; 
    ownName=theaccount;
    
    if(tempPass==nil) theTempPass=nil; else
    {
        theTempPass=[NSString stringWithString:tempPass];
    }
    
	return [self init2:theaccount:thedb];
	
}

-(id)init2:(NSString*) theaccount:(DataLayer*) thedb
{
self = [super init];

	mySequenceNo=37500; 
	SFLAP_SIGNON =1;
	SFLAP_DATA =2;
	SFLAP_KEEP_ALIVE=5;
	MAX_LENGTH=2048;
	
	loggedin=false; 
	
	domain=@"AIM";
	//server=@"toc.oscar.aol.com"; 
	//port=9898; 
	
	authHost = @"login.oscar.aol.com";
	authPort = 29999;
	
	account=theaccount; 



	
	
	responseUser=@""; 

	
	loginstate=0; 
	

	errorState=0; 
	
	listenThreadCounter=0; 
	

	//buddyListKeys=[NSArray arrayWithObjects:@"username", @"status", @"message", @"icon", @"count",@"fullname", nil];
	
	
	
	
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
	
	responseUser=nil;
	

	
		db=[DataLayer sharedInstance];
	
	loggedin=false; 
	
	

	
	
	// outer state machien
	loginstate=0; 
	
	return self;

}


-(void) parseData:(short) length
{
	
	int offset=sizeof(struct sflap_hdr); 
	
	NSString* msg =[[NSString alloc] initWithData:[theset subdataWithRange:NSMakeRange(offset, ntohs(length))] encoding:NSASCIIStringEncoding];
	debug_NSLog(@"Response is more than just header message: %@",msg ); 

	
	NSArray* parts=[msg componentsSeparatedByString:@"\n"]; 
	NSArray* topPart=[[parts objectAtIndex:0] componentsSeparatedByString:@":"];
	
	debug_NSLog(@"lines %d, Top Part is  %@", [parts count],[topPart objectAtIndex:0]);
	
	if([[topPart objectAtIndex:0] isEqualToString:@"ERROR"])
	{
		debug_NSLog(@"Got Error %@", [topPart objectAtIndex:1]);
		if(loggedin==false)
			[[NSNotificationCenter defaultCenter] 
			 postNotificationName: @"LoginFailed" object: self];
		
		fatal=true;
		
	}
	
		if([[topPart objectAtIndex:0] isEqualToString:@"SIGN_ON"])
		{
			debug_NSLog(@"sign_on ok. protocol %@", [topPart objectAtIndex:1]); 
		
			loggedin=true; 
			[[NSNotificationCenter defaultCenter] 
			 postNotificationName: @"LoggedIn" object: self];
			
		}
	
	
	if([[topPart objectAtIndex:0] isEqualToString:@"CONFIG2"])
	{
			debug_NSLog(@"config data ok sending init done"); 
			NSString*	xmpprequest=	[NSString stringWithFormat:@"toc_init_done"];
		 
		 [self sflapTalk:SFLAP_DATA :xmpprequest];
		
	}
	
	if([[topPart objectAtIndex:0] isEqualToString:@"UPDATE_BUDDY2"])
	{
		presenceFlag=true;
		debug_NSLog(@"got buddy update "); 
		if([[topPart objectAtIndex:2] isEqualToString:@"T"])
		{
			//add buddy to online
			if(![self isInAdd:[topPart objectAtIndex:1]])
			{
				if(![self isInAdd:[topPart objectAtIndex:1]]){
					
					debug_NSLog(@"Buddy not already in list"); 
					
					
					/*NSArray* elements =[NSArray arrayWithObjects:[topPart objectAtIndex:1],@"", @"", @"" , @"0",@"",nil];
					if([elements count]==[buddyListKeys count]) //some presence might be a not authorize message and not a buddy 
					{
						NSMutableDictionary* row = [NSMutableDictionary dictionaryWithObjects:elements forKeys:buddyListKeys];
						
						[buddyListAdded addObject:row]; //delta list to go out to UI
						[buddiesOnline addObject:row]; //full internal list 
						debug_NSLog(@"Buddy added to  list"); 
						
						
					}*/
					
					[db addBuddy:[topPart objectAtIndex:1]   :accountNumber :@"" :@""];
	
					[db setOnlineBuddy:[topPart objectAtIndex:1] :accountNumber];
					
				}
				else
				{
					debug_NSLog(@"Buddy already in list"); 
					//this is an update.
					
					//status or show?
					/*
					debug_NSLog(@"Status update, saving  status:%@ show:%@",presenceStatus,presenceShow); 
					
					
					NSArray* elements =[NSArray arrayWithObjects:presenceUser,[presenceShow retain], [presenceStatus retain], [presencePhoto retain] ,@"0",nil];
					NSMutableDictionary* row = [NSMutableDictionary dictionaryWithObjects:elements forKeys:buddyListKeys];
					
					[buddyListUpdated addObject:row];
					*/
					
					/*** Note: this is a problem here because it overwrites the show  with the status message.. it should just update the thing that changed
					 rather than  overwrirting the row **/
					
					
				}
			}
				
		} 
		else
		{
			debug_NSLog(@"Buddy offline"); 
			//remove from online
			[db setOfflineBuddy:[topPart objectAtIndex:1] :accountNumber];
			/*
			if(![self isInRemove:[topPart objectAtIndex:1]])
			{
				//[buddyListRemoved addObject:[topPart objectAtIndex:1]]; 
				
				
				//remove from online list
				int onlinecounter=0; 
				while(onlinecounter<[buddiesOnline count])
				{
					if([[topPart objectAtIndex:1] isEqualToString:[[buddiesOnline objectAtIndex:onlinecounter] objectForKey:@"username"]])
					{	
						[buddiesOnline removeObjectAtIndex:onlinecounter];
						break;
						
					}
					onlinecounter++;
				}
				
			}*/
			
		}
		
		
	}
	
	if([[topPart objectAtIndex:0] isEqualToString:@"IM_IN2"])
	{
		messagesFlag=true;
		debug_NSLog(@" got message"); 
		
		
		/*NSArray* objects	=[NSArray arrayWithObjects:[topPart objectAtIndex:1] ,[topPart objectAtIndex:4] ,nil];
		NSArray* keys =[NSArray arrayWithObjects:@"from", @"message",nil];
		
		
		NSDictionary* row =[NSDictionary dictionaryWithObjects:objects  forKeys:keys]; 
		[messagesIn addObject:row];*/
		
		[db addMessage:[topPart objectAtIndex:1] :account :accountNumber :[topPart objectAtIndex:4]:[topPart objectAtIndex:1]];
		
		
	//	debug_NSLog(@"%d messages messge body: %@ from %@",[messagesIn count], [row objectForKey:@"message"], [row objectForKey:@"from"] );
	}
	
		; 
	return; 
	
}

-(void) listenerThread
{
	
	
	listenThreadCounter++; 
	srand([[NSDate date] timeIntervalSince1970]);
	NSDate *now = [NSDate date];
	
	NSString* threadname=[NSString stringWithFormat:@"monal%d",random()%100000]; 
	
	
	while(listenerthread==true)
	{
		debug_NSLog(@"%@ listener thread sleeping onlock", threadname); 
		sleep(1); 
		int seconds=[[NSDate date] timeIntervalSinceDate:now];
		if(seconds>5)
		{
			debug_NSLog(@"%@ listener thread timing out", threadname); 
			; 
			listenThreadCounter--; 
			[NSThread exit]; 
		}
		
	}

	listenerthread=true;
		debug_NSLog(@"%@ listener thread got lock", threadname); 
	
	debug_NSLog(@"sleeping to get data.. "); 
	sleep(1); // gives it a second to gather some data
	NSMutableData* response=[self readData];
	
	if(response!=nil)
	{
		if(theset==nil)
			theset =[[NSMutableData alloc]initWithData:response];
		else [theset appendData:response];
	}
	
	
	if(theset==nil) return; 

	debug_NSLog(@" intial get:%@", [[NSString alloc] initWithData:theset encoding:NSASCIIStringEncoding] ); // xmpp is utf-8 encoded
	
	
	while(  [[[NSString alloc] initWithData:theset encoding:NSASCIIStringEncoding] characterAtIndex:0]  =='*')
		
	{
		debug_NSLog(@"checking flap header "); 
		const uint8_t * rawstring =
		(const uint8_t *)[theset bytes];
		
		struct sflap_hdr* hdr= 
		(struct sflap_hdr*)  rawstring; 
		
		debug_NSLog(@"header is: %d",hdr->type ); 
		if(hdr->type==1)
		{
		
		debug_NSLog(@"got FLAP SIGNON .. sequence: %d releaseing theset", hdr->seqno); 
			// clearing data
			
			theset=nil;
			[self login];
		
			 
			theset=nil;
			break;
			
		}
		
		else if(hdr->type==2)
		{
			
			// if it is an error
			int offset=sizeof(struct sflap_hdr); 
			if([theset length]>offset)
			{
			
				[self parseData:hdr->length]; 
				if(fatal==true)
				{
					debug_NSLog(@"Got fatal error. ending");
					
					theset=nil;
					break; 
				}
				
			}else
				debug_NSLog(@"ERROR: Did not get  response of the right size"); 
		
		
			//trim it 
			short length=ntohs(hdr->length);
			debug_NSLog(@"trimming"); 
			NSData* subset=[theset subdataWithRange:NSMakeRange(offset+length, [theset length]-offset-length)];
		
			theset=[[NSMutableData alloc] initWithData:subset] ;
			
			
			
			if([theset length]==0)
			{
				debug_NSLog(@"the set released"); 
				 
				theset=nil;
				
				break;
			}
		
			
		}
		
		

	}
	
	
	//if(frames==0)
//	{	
		
		[[NSNotificationCenter defaultCenter] 
		 postNotificationName: @"UpdateUI" object: self];	
		
		
		//unlock only after UI update to prevent modification of the same status vars by 2 threads
		debug_NSLog(@" unlocking thread"); 
		listenerthread=false;
		
	listenThreadCounter--; 
		debug_NSLog(@" left listener thread"); 
		[NSThread exit]; 
/*	}
	else
	{
		debug_NSLog(@" left listener frame"); 
		return; 
	}
*/	
	
}

//this is the xmpp listener thread for incoming communication
-(void) listener
{
		
	if(listenThreadCounter<3)
	{
	debug_NSLog(@" detaching new listener thread"); 
		[NSThread detachNewThreadSelector:@selector(listenerThread) toTarget:self withObject:nil];
	}
	;

}









-(void) getVcard:(NSString*) buddy
{
		
	
	;
	return ;
}

-(bool) removeBuddy:(NSString*) buddy
{

	//		
	NSString*	xmpprequest=[NSString stringWithFormat: @"toc2_remove_buddy %@", buddy];
	
	bool val= [self sflapTalk:SFLAP_DATA: xmpprequest];
	//	; 
	return val; 
	 
}

-(bool) addBuddy:(NSString*) buddy
{

//		
	NSString*	xmpprequest1=[NSString stringWithFormat: @"toc2_new_buddies g:Buddies\nb:%@:%@\n", buddy,buddy];
	bool val=[self sflapTalk:SFLAP_DATA: xmpprequest1];

//	; 
	return val; 
	
	 
}

-(bool)sendAuthorized:(NSString*) buddy
{




//		
	NSString*	xmpprequest=[NSString stringWithFormat: @"<presence to='%@' type='subscribed'/>", buddy];
	
	bool val= [self talk:xmpprequest];
//	; 
	return val; 
	
}

-(bool)sendDenied:(NSString*) buddy
{

//		
	NSString*	xmpprequest=[NSString stringWithFormat: @"<presence to='%@' type='unsubscribed'/>", buddy];
	
	bool val= [self talk:xmpprequest];
//	; 
	return val; 
	
}


-(NSInteger) getBuddies
{

}

-(bool) message:(NSString*) to:(NSString*) content:(BOOL) group
{

	// note remember to make name lowercase 
	//remember to escape content
	
//		
	NSString*	xmpprequest=[NSString stringWithFormat: @"toc_send_im %@ \"%@\""
							 , to, content];
	
	bool val= [self sflapTalk:SFLAP_DATA: xmpprequest];
//	; 
	return val; 
	
}






/**** presence functions ***/

-(NSInteger) setStatus:(NSString*) status
{
		
	
//		
	NSString*	xmpprequest=[NSString stringWithFormat: @"toc_set_away %@",status];

	bool val= [self sflapTalk:SFLAP_DATA: xmpprequest];

   
	statusMessage=[NSString stringWithString:status];

    
    
//	; 
	return val; 
	
	
}

-(NSInteger) setAway
{
	 
	
//		
	NSString*	xmpprequest=[NSString stringWithFormat: @"toc_set_away %@"];
	
	bool val= [self sflapTalk:SFLAP_DATA: xmpprequest];

//	; 
	return val; 
	
}

-(NSInteger) setAvailable
{
	
	
//		
	NSString*	xmpprequest=[NSString stringWithFormat: @"toc_set_away"];

	bool val= [self sflapTalk:SFLAP_DATA: xmpprequest];

//	; 
	return val; 
	
}


-(NSInteger) setInvisible
{
	
	
	//there is no invisible in TOC
    

	return true; 
	
}



-(bool) sflapTalk: (uint8_t ) type: (id) thecommand
{

	mySequenceNo++;
	//note : make sure less than max size and  take substring.. 
	
	
	NSMutableData* packet= [[NSMutableData alloc] init]; 
	NSMutableData* header= [[NSMutableData alloc] init]; 


	
	struct sflap_hdr hdr; 
	
	hdr.ast='*'; 
	hdr.type=(short)type;

debug_NSLog(@"frame type %u", hdr.type);
	
	if(type==SFLAP_SIGNON)
	{
			hdr.seqno=htons((short)mySequenceNo); 
		unsigned short datalength=[(NSData*)thecommand length]; 
		debug_NSLog(@"length %d", datalength);
		hdr.length=htons(datalength); // works for both data and string 
		
		char* serialized = malloc(sizeof(hdr)); 
		serialized=(char*) &hdr; 
		
		[header appendBytes:serialized length:sizeof(hdr)];
		
		[packet appendData:header]; 
		[packet appendData:thecommand];
	}
	else
	{
		hdr.seqno=htons((short)mySequenceNo); 
		unsigned short datalength=[(NSString*)thecommand length]; // works for both data and string 
		datalength+=1; // for null terminator
		debug_NSLog(@"length %d", datalength);
		hdr.length=htons(datalength); 
	
		char* serialized = malloc(sizeof(hdr)); 
		serialized=(char*) &hdr; 
		
		[header appendBytes:serialized length:sizeof(hdr)];
		
		[packet appendData:header]; 
	[packet appendBytes:[thecommand cStringUsingEncoding:NSASCIIStringEncoding] length:[thecommand length]];
	[packet appendBytes:"\0" length:1];
	}
	
	//debug_NSLog(@"header: %s ", [header bytes]);
	//debug_NSLog(@"binary packet:  %@", packet);
	

	
	
	
	[self talk: packet];
	return true; 
}

-(bool) talk: (NSData*) thecommand;
{
		
	if(oStream==nil) return false; 
	debug_NSLog(@"ostream ok..");
	if(thecommand==nil) return false; 
		
	const uint8_t * rawstring =
	(const uint8_t *)[thecommand bytes];
	 int len= [thecommand length]; 
	debug_NSLog(@"sending: %s length %d data %@", rawstring, len, thecommand);
	int wrote=[oStream write:rawstring maxLength:len]; 
	if(wrote!=-1)
	{
		debug_NSLog(@"sending: %d bytes ok", wrote); 
		;
		return true; 
	}
		else
		{
				debug_NSLog(@"sending: failed"); 
			;
		return false; 
		}
	
}


-(bool) keepAlive
{
	//	
	NSString* query =[NSString stringWithFormat:@""];
	
	bool val= [self sflapTalk:SFLAP_KEEP_ALIVE: query];
	//; 
	return val; 
}


-(NSMutableData*) readData
{
			
	NSMutableData* data= [NSMutableData alloc] ;
	uint8_t* buf=malloc(5120);
	 int len = 0;
	
	len = [iStream read:buf maxLength:5120];
	
	if(len>0) {
		
		[data appendBytes:(const void *)buf length:len];
	//	[bytesRead setIntValue:[bytesRead intValue]+len];
		

		free(buf); 
		debug_NSLog(@"read %d bytes", len); 
		
		; 
		return data ;
	} 
	else 
	{
		free(buf); 
		;
		return nil; 	
	}
}



//delegat function for nsstream

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
	
	switch(eventCode) 
	{
			//for writing
	case NSStreamEventHasSpaceAvailable:
	{
		debug_NSLog(@"has space"); 
	
		
		break;
	}
			
			//for reading
			case  NSStreamEventHasBytesAvailable:
		{
			debug_NSLog(@"has bytes"); 
			[self listener];
			break;
		}
			
		case NSStreamEventErrorOccurred:
		{
			/*debug_NSLog(@"Stream errror");
			NSError *theError = [stream streamError];
			debug_NSLog(@"%@ %d",[theError domain],[theError code]);*/
		} 
	}
	
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

-(void) disconnect
{

	
	
			
	//prevent any new read or write
	[iStream setDelegate:nil]; 
	 [oStream setDelegate:nil]; 
	
	[oStream removeFromRunLoop:[NSRunLoop currentRunLoop]
					   forMode:NSDefaultRunLoopMode];
	
	[iStream removeFromRunLoop:[NSRunLoop currentRunLoop]
					   forMode:NSDefaultRunLoopMode];
	
	
	
	
	NSDate *now = [NSDate date];
		
	// wait on all threads to end 

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
	
	

	
	parserCol=0;
		loggedin=false; 
	
	debug_NSLog(@"All closed and cleaned up"); 
	
}


-(bool) connect
{
	

	
	
	iStream=nil; 
	oStream=nil;
	
     //   NSHost *host = [NSHost hostWithName:server];
        // iStream and oStream are instance variables
       // [NSStream getStreamsToHost:host port:port inputStream:&iStream
		//			  outputStream:&oStream];
	
    CFReadStreamRef readRef= NULL; 
    CFWriteStreamRef writeRef= NULL; 
	
	CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)server, port, &readRef, &writeRef);
    debug_NSLog(@"stream  created to  server: %@ port: %d", server, port);
    
    iStream= (__bridge NSInputStream*)readRef; 
    oStream= (__bridge NSOutputStream*) writeRef; 
    

	if((iStream==nil) || (oStream==nil))
	{
		debug_NSLog(@"Connection failed");
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Connection Error"
														message:@"Could not connect to the AIM server."
													   delegate:self cancelButtonTitle:nil
											  otherButtonTitles:@"Close", nil] ;
		[alert show];
		
		
		;
		return false;
	}
		else
	debug_NSLog(@"Connected to  host");



	
	[self performSelectorOnMainThread :@selector(setRunLoop)  withObject:nil waitUntilDone:YES];
	
	
	// iOS4 VOIP socket.. one for all sockets doesnt matter what style connection it is
/*	if([tools isBackgroundSupported])
	{
		
		if((CFReadStreamSetProperty((CFReadStreamRef)iStream, 
									kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP)) &&
		   (CFWriteStreamSetProperty((CFWriteStreamRef)oStream, 
									 kCFStreamNetworkServiceType,  kCFStreamNetworkServiceTypeVoIP)))
			debug_NSLog(@"Set VOIP properties on streams.");
		else
			debug_NSLog(@"could not set VOIP properties on streams.");
		
	}
	*/
    
	
	[iStream open];
	[oStream open];

	
	

	
	

	
	[NSThread detachNewThreadSelector:@selector(initilize) toTarget:self withObject:nil];

	

	
	;
	return true;
}


//this is done as a new thread to prevent the writing from blocking the whole app on connect
-(void)initilize
{
	
	
	debug_NSLog(@"beginning login procedures"); 
	NSString*	xmpprequest1=@"FLAPON\r\n\r\n\0";
	[self talk: [xmpprequest1 dataUsingEncoding: NSASCIIStringEncoding]];
	
	//listen for flap signon.. then call login 
	
	


	
	;
	[NSThread exit];
}


-(bool) login
{
	
	
		
	debug_NSLog(@"Sending Login command"); 
	
	struct signon so; 
	so.ver=htonl(1); 
	so.tag=htons(1); 
	so.length=htons([account length]);
	strcpy(so.username, [account cStringUsingEncoding:NSUTF8StringEncoding]);
	
	int packsize=8+strlen(so.username); 
	
	char* serialized = malloc(packsize); 
	serialized=(char*) &so; 
	
	
	NSData* cmddata= [NSData dataWithBytes:serialized length:packsize];
	
	[self sflapTalk:SFLAP_SIGNON:cmddata];
	
	PasswordManager* passMan= [PasswordManager alloc] ; 
	[passMan init:[NSString stringWithFormat:@"%@", accountNumber]];
	debug_NSLog(@" accno %@", accountNumber ); 
	NSString* passval =[passMan getPassword];
    
    if([passval length]==0)
    {
        if(theTempPass!=NULL)
            passval=theTempPass; 
        
    }
	
	
	if([passval length]==0) passval=@" "; // stop crashing 
		

	NSString*	xmpprequest=	[NSString stringWithFormat:@"toc2_signon %@ %u %@ %@ english-US \"TIC:TOC2:MONAL\" 160 %@",
	authHost, authPort,account, [self roast:passval],[self coded:account:passval] ];
	
		 
	bool val= [self sflapTalk:SFLAP_DATA:xmpprequest];

	

	
	; 
	return val; 
}
	

#pragma mark AIM TOC 2 fns



-(NSString*) roast:(NSString*) pass
{
		
	NSString* roaststring = @"Tic/Toc";

	NSMutableString* toreturn=[[NSMutableString alloc] init] ;
	[toreturn appendString:@"0x"];
	int i=0; 
	while(i<[pass length])
	{
		
		NSString* temp=[NSString stringWithFormat:@"%02x",
						 [pass characterAtIndex:i] ^[roaststring characterAtIndex:(i%7)]];
		[toreturn appendString: temp ];
		//$roasted_password .= bin2hex($password[$i] ^ $roaststring[($i % 7)]);
		
		
		i++;
	}
	 
	return toreturn; 
}

-(NSString*) coded:(NSString*)user:(NSString*) thepass
{
		
	int userFirst= (int)  [user characterAtIndex:0]-96;
	int passFirst= (int) [thepass characterAtIndex:0]-96;
	
	int a = userFirst * 7696 + 738816;
int b = userFirst * 746512;
 int c = passFirst * a;
	
	int value= c - a + b + 71665152;
	
	
	NSString* val=[NSString stringWithFormat:@"%u", value];
	
	return val; 
}







- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	
	
	debug_NSLog(@"clicked button %d", buttonIndex); 
	//login or initial error
	
	if(buttonIndex==0) 
	{
		[self sendAuthorized:[alertView title]];
		[self addBuddy:[alertView title]];
	}
	else
		[self sendDenied:[alertView title]];
	
	
	
	
	
	;
}



	

@end
