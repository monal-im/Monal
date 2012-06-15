//
//  iqJingle.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
//RTP library (jrtlb obj-c wrapper)
#import "RTP.hh"


@interface iqJingle : NSObject
{
    NSString* me; 
    NSString* otherParty; 
    NSString* thesid; 
    NSString* theaddress; 
    NSString* theport; 
    NSString* theusername;
    NSString* thepass; 
    
    RTP* rtp;     

}
-(NSString*) getGoogleInfo:(NSString*) idval;

-(NSString*) ack:(NSString*) to:(NSString*) iqid;
-(NSString*) acceptJingle:(NSString*) to:(NSString*) address: (NSString*) port: (NSString*) username: (NSString*) pass:  (NSString*)idval; 
-(NSString*) initiateJingle:(NSString*) to ;
-(NSString*) terminateJingle;
-(id) init; 

-(void) connect; 


@property (nonatomic) NSString* me; 
@property (nonatomic) NSString* thesid; 

@end
