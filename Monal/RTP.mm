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


void AudioInputCallback(
                        void *inUserData, // 1
                        AudioQueueRef inAQ, // 2
                        AudioQueueBufferRef inBuffer, // 3
                        const AudioTimeStamp *inStartTime, // 4
                        UInt32 inNumberPacketDescriptions, // 5
                        const AudioStreamPacketDescription *inPacketDescs) // 6
{
	static int count = 0;
	RecordState* recordState = (RecordState*)inUserData;	
	AudioQueueEnqueueBuffer(recordState->queue, inBuffer, 0, NULL);
    
	++count;
	debug_NSLog("Got buffer %d\n", count);
}

-(void) RTPConnect:(NSString*) IP:(int) port; 
{    
    
    //********* Audio Queue ********/
    
    RecordState recordState;
    
    recordState.dataFormat.mSampleRate = 8000.0;
    recordState.dataFormat.mFormatID = kAudioFormatLinearPCM;
    recordState.dataFormat.mFramesPerPacket = 1;
    recordState.dataFormat.mChannelsPerFrame = 1;
    recordState.dataFormat.mBytesPerFrame = 2;
    recordState.dataFormat.mBytesPerPacket = 2;
    recordState.dataFormat.mBitsPerChannel = 16;
    recordState.dataFormat.mReserved = 0;
    recordState.dataFormat.mFormatFlags =
    kLinearPCMFormatFlagIsBigEndian |
    kLinearPCMFormatFlagIsSignedInteger |
    kLinearPCMFormatFlagIsPacked;


    OSStatus audioStatus = AudioQueueNewInput(
                                         &recordState.dataFormat, // 1
                                         AudioInputCallback, // 2
                                         &recordState,  // 3
                                         CFRunLoopGetCurrent(),  // 4
                                         kCFRunLoopCommonModes, // 5
                                         0,  // 6
                                         &recordState.queue);  // 7
    
    
    for(int i = 0; i < NUM_BUFFERS; i++)
    {
        AudioQueueAllocateBuffer(recordState.queue,
                                 16000, &recordState.buffers[i]);
        AudioQueueEnqueueBuffer(recordState.queue,
                                recordState.buffers[i], 0, NULL);
    }
    
    
     audioStatus = AudioQueueStart(recordState.queue, NULL);

    if(audioStatus==0)
    {
        debug_NSLog(@"record started ok");
    }
    else {
        debug_NSLog(@"error starting record");
    }   
    
    //******* RTP *****/
    
    jrtplib::RTPSession sess;
	uint16_t portbase,destport;
	uint32_t destip;
	std::string ipstr([IP  cStringUsingEncoding:NSUTF8StringEncoding]);
	int status,i;
    
    destport=port; 
    portbase=port+2; 
    
   
    destip = inet_addr(ipstr.c_str());
    
	// Now, we'll create a RTP session, set the destination, send some
	// packets and poll for incoming data.
	
	jrtplib::RTPUDPv4TransmissionParams transparams;
	jrtplib::RTPSessionParams sessparams;
	
	// IMPORTANT: The local timestamp unit MUST be set, otherwise
	//            RTCP Sender Report info will be calculated wrong
	// In this case, we'll be sending 10 samples each second, so we'll
	// put the timestamp unit to (1.0/10.0)
    
	sessparams.SetOwnTimestampUnit(1.0/10);		
	
	sessparams.SetAcceptOwnPackets(true);
	transparams.SetPortbase(portbase);
	status = sess.Create(sessparams,&transparams);	
	checkerror(status);
	
	jrtplib::RTPIPv4Address addr(destip,destport);
	
	status = sess.AddDestination(addr);
	checkerror(status);
	
    
    debug_NSLog(@" RTP to ip %d  IP %@ on port %d", destip,IP,  destport);
    

    /*
	for (i = 1 ; i <= packet_num ; i++)
	{
		
		
		// send the packet
		
        
        
       const void* bytes=[[audioData subdataWithRange:NSMakeRange(start, end)] bytes]; 
        
        
        debug_NSLog(@"Sending packet %d/%d\n  starting %d sized %d "
                    ,i,packet_num, start,  end );
        
        status = sess.SendPacket((void *)bytes,packetSize,8,false,8); // pt=8  is PCMA ,  timestamp 8 is 8Khz
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
	
	sess.BYEDestroy(jrtplib::RTPTime(10,0),0,0);*/
}

@end
