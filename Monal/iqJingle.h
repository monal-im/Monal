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
    

}

-(NSString*) ack:(NSString*) to:(NSString*) theid;
-(NSString*) acceptJingle:(NSString*) to  :(NSString*) sid;
-(NSString*) initiateJingle:(NSString*) to ;
-(NSString*) terminateJingle:(NSString*) to  :(NSString*) sid;

-(id) init; 



@property (nonatomic, retain) NSString* me; 


@end
