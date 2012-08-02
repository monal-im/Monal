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


#define NUM_BUFFERS 3





-(int) RTPConnect:(NSString*) IP:(int) destPort:(int) localPort;
-(void) RTPDisconnect;
-(void) listenThread;

@end
