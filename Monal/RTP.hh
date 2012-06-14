//
//  RTP.h
//  Monal
//
//  Created by Anurodh Pokharel on 8/28/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>

@interface RTP : NSObject <AVAudioRecorderDelegate>
{
    NSURL * recordedTmpFile;
    AVAudioRecorder * recorder;
  
}

-(void) RTPConnect:(NSString*) IP:(int) port;  

@end
