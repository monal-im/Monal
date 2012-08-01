//
//  iqJingle.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#include <ifaddrs.h>
#include <arpa/inet.h>

#import <Foundation/Foundation.h>
//RTP library (jrtlb obj-c wrapper)
#import "RTP.hh"


@interface iqJingle : NSObject
{
    NSString* me; 
    NSString* otherParty; 
    NSString* thesid; 
    NSString* theaddress; 
    NSString* destinationPort;
    NSString* localPort;
    NSString* theusername;
    NSString* thepass; 
    
    RTP* rtp;
    
    BOOL didReceiveTerminate;
    BOOL activeCall; 

}
-(NSString*) getGoogleInfo:(NSString*) idval;

-(NSString*) ack:(NSString*) to:(NSString*) iqid;
-(NSString*) acceptJingle:(NSString*) to:(NSString*) address: (NSString*) port: (NSString*) username: (NSString*) pass:  (NSString*)idval; 
-(NSString*) initiateJingle:(NSString*) to  :(NSString*)iqid;
-(NSString*) terminateJingle;

-(void) resetVals;
-(id) init;

-(int) connect;



@property (nonatomic) NSString* me; 
@property (nonatomic) NSString* thesid;
@property (nonatomic) BOOL didReceiveTerminate; 

@end
