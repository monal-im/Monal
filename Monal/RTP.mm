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

   jrtplib::RTPSession sess;
 

typedef struct
{
    AudioStreamBasicDescription dataFormat;
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[NUM_BUFFERS];
    
    
} RecordState;

RecordState recordState;

@implementation RTP


#pragma mark RTP

void checkerror(int rtperr)
{
	if (rtperr < 0)
	{
       std::string msg= jrtplib::RTPGetErrorString(rtperr); 
		debug_NSLog(@"ERROR: %s" ,msg.c_str()  ); 
		return; 
	}
}

#pragma mark audio Queue

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
    
//send packet over RTP
   // const void* bytes=[]; 
    
    
    debug_NSLog(@"Sending packet sized %d", inBuffer->mAudioDataByteSize); 
    
    int rtpstatus = sess.SendPacket((void *)inBuffer->mAudioData,inBuffer->mAudioDataByteSize,8,false,8); // pt=8  is PCMA ,  timestamp 8 is 8Khz
    checkerror(rtpstatus);
       if(rtpstatus!=0) return; // gradually stop reenqueing
    
    //reenquue buffer to collect more
	OSStatus status= AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    if(status==0)
    {
   // debug_NSLog("audio reenqueue ok")
    }
    else {
        debug_NSLog(@"audio reenqueue error %d", status);
    }
	++count;
	debug_NSLog("Got buffer %d\n", count);
}

#pragma mark RTP cocoa wrapper 



-(int) RTPConnect:(NSString*) IP:(int) destPort:(int) localPort
{
 
    //********* Audio Queue ********/
    
    
    
    
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
    
    
    OSStatus audioStatus= AudioQueueNewInput(
                                             &recordState.dataFormat, // 1
                                             AudioInputCallback, // 2
                                             &recordState,  // 3
                                             CFRunLoopGetCurrent(),  // 4
                                             kCFRunLoopCommonModes, // 5
                                             0,  // 6
                                             &recordState.queue);  // 7
    
    
    
    if(audioStatus==0)
    {
        debug_NSLog(@"new queue started ok");
    }
    else {
        debug_NSLog(@"new queue start failed");
        return -1;
    }
    
    
    //******* RTP *****/
    
   
	uint16_t portbase,destport;
	uint32_t destip;
	std::string ipstr([IP  cStringUsingEncoding:NSUTF8StringEncoding]);
	int status,i;
    
    destport=destPort;
    portbase=localPort;
    
   
    destip = inet_addr(ipstr.c_str());
    
	// Now, we'll create a RTP session, set the destination, send some
	// packets and poll for incoming data.
	
	jrtplib::RTPUDPv4TransmissionParams transparams;
	jrtplib::RTPSessionParams sessparams;
	
   
   
   

	// IMPORTANT: The local timestamp unit MUST be set, otherwise
	//            RTCP Sender Report info will be calculated wrong
	// In this case, we'll be sending 10 samples each second, so we'll
	// put the timestamp unit to (1.0/10.0)
    
	sessparams.SetOwnTimestampUnit(1.0/recordState.dataFormat.mSampleRate );		
	
	sessparams.SetAcceptOwnPackets(true);
	transparams.SetPortbase(portbase);
	status = sess.Create(sessparams,&transparams);	
	checkerror(status);
	
    if(status!=0) return status;
    
	jrtplib::RTPIPv4Address addr(destip,destport);
	
	status = sess.AddDestination(addr);
	checkerror(status);
    
	if(status!=0) return status;
    
    debug_NSLog(@" RTP to ip %d  IP %@ on port %d", destip,IP,  destport);
    

  
    
    
    for(int i = 0; i < NUM_BUFFERS; i++)
    {
        audioStatus= AudioQueueAllocateBuffer(recordState.queue,
                                              1000, &recordState.buffers[i]);
        
        if(audioStatus==0)
        {
          // debug_NSLog("audio buffer allocate ok")
        }
        else {
            debug_NSLog(@"audio buffer allocate error %d", audioStatus);
        }
        audioStatus= AudioQueueEnqueueBuffer(recordState.queue,
                                             recordState.buffers[i], 0, NULL);
        
        if(audioStatus==0)
        {
           // debug_NSLog("audio buffer initial enqueue ok")
        }
        else {
            debug_NSLog(@"audio buffer  initial enqueue error %d", audioStatus);
        }
    }
    
    
   audioStatus = AudioQueueStart(recordState.queue, NULL);
    
    if(audioStatus==0)
    {
        debug_NSLog(@"record started ok");
    }
    else {
        debug_NSLog(@"error starting record");
        return -1;
    }  

  
	
    [NSThread detachNewThreadSelector:@selector(listenThread) toTarget:self withObject:nil];
 
    return 0;
    
}

-(void) listenThread
{
    debug_NSLog(@"entered RTP listen thread");
    while(1)
    {
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
    
		OSStatus status = sess.Poll();
		checkerror(status);
        if(status!=0) break;

		
        //wait
		jrtplib::RTPTime::Wait(jrtplib::RTPTime(1,0));
    }
    
    debug_NSLog(@"leaving RTP listen thread");
    [NSThread exit];

}

-(void) RTPDisconnect
{
   OSStatus  audioStatus = AudioQueueStop(recordState.queue, YES);
    
    if(audioStatus==0)
    {
        debug_NSLog(@"record stopped ok");
    }
    else {
        debug_NSLog(@"error stopping record");

    }

    sess.BYEDestroy(jrtplib::RTPTime(10,0),0,0);
}

@end
