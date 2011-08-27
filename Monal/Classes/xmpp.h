//
//  xmpp.h
//  SworIM
//
//  Created by Anurodh Pokharel on 11/18/08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>


#import <CoreFoundation/CoreFoundation.h>

#import "protocol.h"

//stanza objects 
#import "iqSearch.h"
#import "iqJingle.h"

#import <unistd.h>
#import <sys/types.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#import <nameser.h>
#import <dns_sd.h>

#ifndef T_SRV
#define T_SRV 33
#endif

#ifndef T_PTR
#define T_PTR 12
#endif

#ifndef T_A
#define T_A 1
#endif

#ifndef T_TXT
#define T_TXT 16
#endif

#define MAX_DOMAIN_LABEL 63
#define MAX_DOMAIN_NAME 255
#define MAX_CSTRING 2044



@interface xmpp : protocol  <UIAlertViewDelegate,NSNetServiceBrowserDelegate>{
	


    NSInputStream *iStream;
    NSOutputStream *oStream;
	
	NSString* messageUser; 
	NSString* mucUser; 
	
	
	NSMutableString* messageBuffer;
    NSMutableArray* serverList; 
    
    NSString* chatServer; // this is for MUC got via discoinfo
    NSString* chatSearchServer; 
    NSString* userSearchServer; // this is for user serach got via discoinfo
    
    NSMutableArray* serverDiscoItems; 
    
    
    NSMutableArray* userSearchItems; 
    
	//response data
	NSString* responseUser; 
	
	//error messages

	BOOL  errorState; 
	
	int parserCol;
	NSMutableData* theset;


	BOOL fatal; 
	int loginstate;
	
	NSString* lastEndedElement; 
	
	int listenThreadCounter; 
	
	
	
	// server attributes
    BOOL legacyAuth; 
	BOOL SASLSupported; 
	BOOL SASLPlain; 
	BOOL SASLCRAM_MD5; 
	BOOL SASLDIGEST_MD5;
	
	BOOL ClearSupported; 
	
	NSString* sessionkey;
	
	int keepAliveCounter;
	bool disconnecting; 
	NSNetServiceBrowser* resolver;
	bool DNSthreadreturn; 
	
	int XMPPPriority; 
    
    
    //stanza objects
    
    iqSearch* iqsearch; 
    iqJingle* jingleCall; 
 

}
-(void) setRunLoop; 

-(void) dnsDiscover;
 void query_cb(const DNSServiceRef DNSServiceRef, const DNSServiceFlags flags, const u_int32_t interfaceIndex, const DNSServiceErrorType errorCode, const char *name, const u_int16_t rrtype, const u_int16_t rrclass, const u_int16_t rdlen, const void *rdata, const u_int32_t ttl, void *context) ; 

-(id)init:(NSString*) theserver:(unsigned short) theport:(NSString*) theaccount: (NSString*) theresource:(NSString*) thedomain: (BOOL) SSLsetting : (DataLayer*) thedb:(NSString*) accontNo;
-(bool) connect;
-(void) disconnect;

-(NSMutableData*) readData;




-(bool) login;

-(NSInteger) getBuddies;



-(bool) sendLast:(NSString*) to:(NSString*) userid;
-(bool) sendVersion:(NSString*) to:(NSString*) userid;

#pragma mark User Search

-(bool) requestSearchInfo;
-(bool) userSearch:(NSString*) buddy; 


#pragma mark service discovery
-(bool) queryDiscoItems:(NSString*) to:(NSString*) userid;
-(bool) queryDiscoInfo:(NSString*) to:(NSString*) userid;
-(bool) sendDiscoInfo:(NSString*) to:(NSString*) userid;


-(bool)sendAuthorized:(NSString*) buddy; 
-(bool)sendDenied:(NSString*) buddy; 

-(bool) talk: (NSString*) xmpprequest;

- (void)PostSasl:(id)sender;

// variable interface
-(NSString*) getAccount; 
-(NSString*) getServer; 
-(NSString*) getResource; 

-(NSMutableArray*) getBuddyListArray;
-(NSMutableArray*) getBuddyListAdded; 
-(NSMutableArray*) getBuddyListRemoved; 
-(NSMutableArray*) getBuddyListUpdated; 

-(NSArray*) getRoster;

-(NSMutableArray*) getMessagesIn;
-(void) readMessages; 

-(void) buddyListUpdateRead;

-(BOOL) isInRemove:(NSString*) name;
-(BOOL) isInAdd:(NSString*) name;

//threads
-(void) listener;
-(bool) keepAlive;

//stream delegate
- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode;




typedef union { unsigned char b[2]; unsigned short NotAnInteger; } Opaque16;

typedef struct { u_char c[ 64]; } domainlabel;
typedef struct { u_char c[256]; } domainname;


typedef struct 
{ 
    uint16_t priority; 
    uint16_t weight; 
    uint16_t port; 
    domainname target;
} srv_rdata;


@property (nonatomic, retain)  NSMutableArray* userSearchItems;
@property (nonatomic, retain)  NSMutableArray* serverList;
@property (nonatomic, readonly) NSMutableData* theset;
@property (nonatomic, retain)  NSString* chatServer;
@property (nonatomic, retain)  NSString*  chatSearchServer;
@property (nonatomic, retain)  NSString* userSearchServer;

@end
