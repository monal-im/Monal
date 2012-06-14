//
//  RTP.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/28/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//


#include "rtpsession.hh"
#include "rtpudpv4transmitter.hh"
#include "rtpipv4address.hh"
#include "rtpsessionparams.hh"
#include "rtperrors.hh"


#include <netinet/in.h>
#include <arpa/inet.h>

#include <stdlib.h>
#include  <stdio.h>
#include <string>

#import "RTP.hh"

@implementation RTP

void checkerror(int rtperr)
{
	if (rtperr < 0)
	{
       std::string msg= jrtplib::RTPGetErrorString(rtperr); 
		debug_NSLog(@"ERROR: %s" ,msg.c_str()  ); 
		return; 
	}
}

-(void) RTPConnect:(NSString*) IP:(int) port; 
{
    jrtplib::RTPSession sess;
	uint16_t portbase,destport;
	uint32_t destip;
	std::string ipstr([IP  cStringUsingEncoding:NSUTF8StringEncoding]);
	int status,i,num;
    
    destport=port; 
    portbase=port+2; 
    
    num=10; 
    
    
	// Now, we'll create a RTP session, set the destination, send some
	// packets and poll for incoming data.
	
	jrtplib::RTPUDPv4TransmissionParams transparams;
	jrtplib::RTPSessionParams sessparams;
	
	// IMPORTANT: The local timestamp unit MUST be set, otherwise
	//            RTCP Sender Report info will be calculated wrong
	// In this case, we'll be sending 10 samples each second, so we'll
	// put the timestamp unit to (1.0/10.0)
	sessparams.SetOwnTimestampUnit(1.0/10.0);		
	
	sessparams.SetAcceptOwnPackets(true);
	transparams.SetPortbase(portbase);
	status = sess.Create(sessparams,&transparams);	
	checkerror(status);
	
	jrtplib::RTPIPv4Address addr(destip,destport);
	
	status = sess.AddDestination(addr);
	checkerror(status);
	
    
    //Instanciate an instance of the AVAudioSession object.
    AVAudioSession * audioSession = [AVAudioSession sharedInstance];
    //Setup the audioSession for playback and record. 
    //We could just use record and then switch it to playback leter, but
    //since we are going to do both lets set it up once.
      NSError * error;
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error: &error];
    //Activate the session
    [audioSession setActive:YES error: &error];
    
    //Begin the recording session.
    //Error handling removed. Please add to your own code.
    
    //Setup the dictionary object with all the recording settings that this 
    //Recording sessoin will use
    //Its not clear to me which of these are required and which are the bare minimum.
    //This is a good resource: http://www.totodotnet.net/tag/avaudiorecorder/
    NSMutableDictionary* recordSetting = [[NSMutableDictionary alloc] init];
    [recordSetting setValue :[NSNumber numberWithInt:kAudioFormatALaw] forKey:AVFormatIDKey]; // PCMA Audio
    [recordSetting setValue:[NSNumber numberWithFloat:8000] forKey:AVSampleRateKey]; 
    [recordSetting setValue:[NSNumber numberWithInt: 1] forKey:AVNumberOfChannelsKey];

    //Now that we have our settings we are going to instanciate an instance of our recorder instance.
    //Generate a temp file for use by the recording.
    //This sample was one I found online and seems to be a good choice for making a tmp file that
    //will not overwrite an existing one.
    //I know this is a mess of collapsed things into 1 call. I can break it out if need be.
    recordedTmpFile = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent: [NSString stringWithString: @"temp_voip.caf"]]];
    
    debug_NSLog(@"Using File called: %@",recordedTmpFile);
    
    //Setup the recorder to use this file and record to it.
    recorder = [[ AVAudioRecorder alloc] initWithURL:recordedTmpFile settings:recordSetting error:&error];
    //Use the recorder to start the recording.
    //Im not sure why we set the delegate to self yet. 
    //Found this in antother example, but Im fuzzy on this still.
    [recorder setDelegate:self];
    //We call this to start the recording process and initialize 
    //the subsstems so that when we actually say "record" it starts right away.
    [recorder prepareToRecord];
    //Start the actual Recording
    [recorder record];
    //There is an optional method for doing the recording for a limited time see 
    [recorder recordForDuration:(NSTimeInterval) 3];
    
    
    
	//for (i = 1 ; i <= num ; i++)
	{
		debug_NSLog(@"\nSending packet %d/%d\n",i,num);
		
		// send the packet
		
        status = sess.SendPacket((void *)"1234567890",10,0,false,10);
		checkerror(status);
		
		sess.BeginDataAccess();
		
		// check incoming packets
		if (sess.GotoFirstSourceWithData())
		{
			do
			{
				jrtplib::RTPPacket *pack;
				
				while ((pack = sess.GetNextPacket()) != NULL)
				{
					// You can examine the data here
					debug_NSLog(@"Got packet !\n");
					
					// we don't longer need the packet, so
					// we'll delete it
					sess.DeletePacket(pack);
				}
			} while (sess.GotoNextSourceWithData());
		}
		
		sess.EndDataAccess();
        
#ifndef RTP_SUPPORT_THREAD
		status = sess.Poll();
		checkerror(status);
#endif // RTP_SUPPORT_THREAD
		
		jrtplib::RTPTime::Wait(jrtplib::RTPTime(1,0));
	}
	
	//sess.BYEDestroy(jrtplib::RTPTime(10,0),0,0);
}

@end
