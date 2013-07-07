//
//  xmpp.h
//  Monal
//
//  Created by Anurodh Pokharel on 6/29/13.
//
//

#import <Foundation/Foundation.h>
#import "XMLNode.h"
#import "EncodingTools.h"

// networking objects
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



@interface xmpp : NSObject <NSStreamDelegate>
{
    
    NSInputStream *_iStream;
    NSOutputStream *_oStream;
    NSMutableString* _inputBuffer;
	NSMutableArray* _outputQueue;
    
    dispatch_queue_t _xmppQueue; 
    dispatch_queue_t _netReadQueue ;
    dispatch_queue_t _netWriteQueue ;
    
    NSArray* _stanzaTypes;
    NSString* _sessionKey;
    
    BOOL _startTLSComplete;
    
    BOOL _streamHasSpace;
  
}

-(void) connect;
-(void) disconnect;

/**
 Adds the stanza to the output Queue
 */
-(void) send:(XMLNode*) stanza;

// connection attributes
@property (nonatomic,strong) NSString* username;
@property (nonatomic,strong) NSString* domain;
@property (nonatomic,strong, readonly) NSString* jid;
@property (nonatomic,strong) NSString* password;
@property (nonatomic,strong) NSString* server;
@property (nonatomic,assign) NSInteger port;
@property (nonatomic,strong) NSString* resource;
@property (nonatomic,assign) BOOL SSL;
@property (nonatomic,assign) BOOL oldStyleSSL;
@property (nonatomic,assign) NSInteger priority;

// DB info
@property (nonatomic,strong) NSString* accountNo;

@property (nonatomic,assign,readonly) BOOL loggedIn;

// discovered properties
@property (nonatomic,strong)  NSMutableArray* discoveredServerList;

//calculated
@property (nonatomic,strong, readonly) NSString* versionHash;

@end
