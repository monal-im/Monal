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


#define NUM_BUFFERS 48





-(void) RTPConnect:(NSString*) IP:(int) port;  


@end
