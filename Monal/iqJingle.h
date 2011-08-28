//
//  iqJingle.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface iqJingle : NSObject
{
    NSString* me; 
    NSString* otherParty; 
    NSString* thesid; 
    NSString* theaddress; 
    NSString* theport; 
    NSString* theusername;
    NSString* thepass; 
    

}
-(NSString*) getGoogleInfo;

-(NSString*) ack:(NSString*) to:(NSString*) iqid;
-(NSString*) acceptJingle:(NSString*) to:(NSString*) address: (NSString*) port: (NSString*) username: (NSString*) pass: (NSString*) pref;
-(NSString*) initiateJingle:(NSString*) to ;
-(NSString*) terminateJingle:(NSString*) to  :(NSString*) sid;

-(id) init; 



@property (nonatomic, retain) NSString* me; 
@property (nonatomic, retain) NSString* thesid; 

@end
