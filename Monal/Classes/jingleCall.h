//
//  iqJingle.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

//http://xmpp.org/extensions/xep-0166.html


#import <Foundation/Foundation.h>
//RTP library (jrtlb obj-c wrapper)
#import "RTP.hh"

#import "XMPPIQ.h"
#import "IPAddress.h"

@interface jingleCall : NSObject
{
    
    NSString *_activeresource;
    NSString *_iqid;
    NSString *_to;
    NSString *_ownIP;
    
    RTP* rtp;
    RTP* rtp2;
    
    BOOL didStartCall;
    
    // jingle object elements
}
-(NSString*) getGoogleInfo:(NSString*) idval;

-(XMPPIQ*) acceptJingleTo:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource;
-(XMPPIQ*) rejectJingleTo:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource;
-(XMPPIQ*) initiateJingleTo:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource;
-(XMPPIQ*) terminateJinglewithId:(NSString*)iqid;

-(int) rtpConnect;
-(void) rtpDisconnect;

@property (nonatomic, strong) NSString* me;
@property (nonatomic, strong) NSString* thesid;
@property (nonatomic, strong) NSString* otherParty;

@property (nonatomic, strong) NSString* recipientIP;
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
