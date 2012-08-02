//
//  RTP.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/28/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>





@interface RTP : NSObject 
{
    
}


#define NUM_BUFFERS 16
// 2 bye (16 bit)  8000 khz    for  16 x 1000 byte buffer




-(int) RTPConnect:(NSString*) IP:(int) destPort:(int) localPort;
-(void) RTPDisconnect;
-(void) listenThread;

@end
