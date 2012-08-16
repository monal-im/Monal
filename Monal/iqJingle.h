//
//  iqJingle.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

//http://xmpp.org/extensions/xep-0166.html 

#include <ifaddrs.h>
#include <arpa/inet.h>

#import <Foundation/Foundation.h>
//RTP library (jrtlb obj-c wrapper)
#import "RTP.hh"

#include <arpa/inet.h>
#include <netdb.h>
#include <net/if.h>
#include <ifaddrs.h>


@interface iqJingle : NSObject
{
    NSString* me; 
    NSString* otherParty; 
    NSString* thesid; 
    NSString* theaddress; 
    NSString* destinationPort;
    NSString* destinationPort2;
    
    NSString* localPort;
    NSString* localPort2;
    NSString* theusername;
    NSString* thepass; 
    
    NSString* idval;
    
    RTP* rtp;
    RTP* rtp2;
    
    
    BOOL didReceiveTerminate;
    BOOL activeCall;
    BOOL didStartCall; 

}
-(NSString*) getGoogleInfo:(NSString*) idval;

-(NSString*) ack:(NSString*) to:(NSString*) iqid;
-(NSString*) acceptJingle;
-(NSString*) rejectJingle; 
-(NSString*) initiateJingle:(NSString*) to  :(NSString*)iqid:(NSString*) resource;
-(NSString*) terminateJingle;

-(void) resetVals;
-(id) init;

-(int) connect;



@property (nonatomic) NSString* me; 
@property (nonatomic) NSString* thesid;
@property (nonatomic)   NSString* otherParty; 

@property (nonatomic) NSString* theaddress;
@property (nonatomic) NSString* destinationPort;
@property (nonatomic) NSString* destinationPort2;

@property (nonatomic) NSString* localPort;
@property (nonatomic) NSString* localPort2;
@property (nonatomic) NSString* theusername;
@property (nonatomic) NSString* thepass;

@property (nonatomic) NSString* idval;


@property (nonatomic) BOOL didReceiveTerminate;

@end
