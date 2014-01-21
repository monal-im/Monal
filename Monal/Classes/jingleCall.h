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

#import "XMPPIQ.h"


@interface jingleCall : NSObject
{
    
    NSString *_activeresource;
    NSString *_resource;
    NSString *_iqid;
    NSString *_to;
    NSString *_ownIP;
    
    RTP* rtp;
    RTP* rtp2;
    
    BOOL didStartCall;
    
    // jingle object elements
}
-(NSString*) getGoogleInfo:(NSString*) idval;

-(XMPPIQ*) acceptJingle:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource;
-(XMPPIQ*) rejectJingle:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource;
-(XMPPIQ*) initiateJingle:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource;
-(XMPPIQ*) terminateJingle:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource;

-(int) rtpConnect;

@property (nonatomic, strong) NSString* me;
@property (nonatomic, strong) NSString* thesid;
@property (nonatomic, strong) NSString* otherParty;

@property (nonatomic, strong) NSString* theaddress;
@property (nonatomic, strong) NSString* destinationPort;
@property (nonatomic, strong) NSString* destinationPort2;

@property (nonatomic, strong) NSString* localPort;
@property (nonatomic, strong) NSString* localPort2;
@property (nonatomic, strong) NSString* theusername;
@property (nonatomic, strong) NSString* thepass;

@property (nonatomic, strong) NSString* idval;

@property (nonatomic, strong) NSString* action;

@property (nonatomic,assign) BOOL didReceiveTerminate;
@property (nonatomic,assign) BOOL activeCall;
@property (nonatomic,assign) BOOL waitingOnUserAccept;

@property (nonatomic, strong) NSString* initiator;
@property (nonatomic, strong) NSString* responder;

@end
