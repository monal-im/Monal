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
#include "rtppacket.hh"


#include <netinet/in.h>
#include <arpa/inet.h>

#include <stdlib.h>
#include  <stdio.h>
#include <string>
#include <string.h>

#import "RTP.hh"

#import <AudioToolbox/AudioToolbox.h>b

jrtplib::RTPSession sess;

NSMutableData* pcmBuffer;

typedef struct
{
    AudioStreamBasicDescription dataFormat;
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[NUM_BUFFERS];
    SInt64 currentPacket;
    
    
} RecordState;

RecordState recordState;


typedef struct
{
    AudioStreamBasicDescription dataFormat;
    AudioQueueRef  queue;
    AudioQueueBufferRef buffers[NUM_BUFFERS];
    AudioFileID audioFile;
    SInt64 currentPacket;
    bool  playing;
} PlayState;

PlayState playState;


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

#pragma mark audio output Queue





-(void) listenThread
{
    debug_NSLog(@"entered RTP listen thread");
    //create an input buffer

    
    pcmBuffer=[NSMutableData alloc];
    
    int packCount=0;
    
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
                   //  debug_NSLog(@"Got packet !\n");
                  
                    
                 
                    
                    
                    
                    debug_NSLog(@"got packet size %d, data: \n %s ",  pack->GetPayloadLength(),
                                pack->GetPayloadData());
                    
                    
                    [pcmBuffer appendBytes:pack->GetPayloadData() length:pack->GetPayloadLength()];
                    
                    // we don't longer need the packet, so
                    // we'll delete it
                    sess.DeletePacket(pack);
                    
                    packCount++;
                    
                    
                    
                    if(packCount==500)
                    {
                        NSError* err; 
                        AVAudioPlayer* avplayer=[AVAudioPlayer  alloc ];
                        if([avplayer initWithData:pcmBuffer error:&err]!=nil)
                                     {
                                         [avplayer play];
                                     }
                                     else{
                                         debug_NSLog(@"error with avplayer %@", [err localizedDescription]);
                                     }
                        
                        
                        
                        NSString *applicationDocumentsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];

                        
                        NSString *storePath = [applicationDocumentsDir stringByAppendingPathComponent:@"sample.au"];
                        [pcmBuffer writeToFile:storePath atomically:NO];
                        
                    }
                    
                    
                    //start playback after thre are 50 packets
                    
                    
                   /* if(packCount>50 && playState.playing==NO)
                    {
                        OSStatus status = AudioQueueStart(playState.queue, NULL);
                        if(status == 0)
                        {
                            playState.playing=YES;
                            debug_NSLog(@"Started play back ");
                            
                            
                            for(int i = 0; i < NUM_BUFFERS; i++)
                            {
                                
                                AudioOutputCallback(&playState, playState.queue, playState.buffers[i]);
                            }
                            
                            
                        }
                    }*/
                    
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




int  AudioReadPackets (
                       UInt32                       *outNumBytes,
                       AudioStreamPacketDescription *outPacketDescriptions,
                       UInt32                       *ioNumPackets,
                       void                         *outBuffer
                       )
{
    
    
/*
    if(readpos>=[packetInBuffer count]) return 0 ;
    
    NSData* thepacket=[packetInBuffer objectAtIndex:readpos];
    
    UInt32  payloadLength=[thepacket length];
    outNumBytes= &payloadLength;
    
    UInt32 numpackets=payloadLength/2;
    ioNumPackets=&numpackets;
    
    
    std::memcpy(outBuffer, [thepacket bytes], payloadLength);
    
    AudioStreamPacketDescription pacdesc[numpackets];
    
    
    int packCounter=0;
    while(packCounter<numpackets)
    {
        pacdesc[packCounter].mStartOffset=2*packCounter;
        pacdesc[packCounter].mVariableFramesInPacket=0;
        pacdesc[packCounter].mDataByteSize=2;
        
        packCounter++;
    }
    
    outPacketDescriptions=pacdesc;

    
    readpos++;*/
    
    return 0;
	
    
}

void AudioOutputCallback(
                         void* inUserData,
                         AudioQueueRef outAQ,
                         AudioQueueBufferRef outBuffer)
{
    PlayState* playState = (PlayState*)inUserData;
    if(!playState->playing)
    {
        debug_NSLog(@"Not playing, returning\n");
        return;
    }
    
    debug_NSLog(@"Queuing buffer %d for playback\n", playState->currentPacket);
    
    AudioStreamPacketDescription* packetDescs;
    
    UInt32 bytesRead;
    UInt32 numPackets;
    OSStatus status;
    status = AudioReadPackets( &bytesRead,
                              packetDescs,
                              &numPackets,
                              outBuffer->mAudioData);
    
    if(numPackets)
    {
        outBuffer->mAudioDataByteSize = bytesRead;
        status = AudioQueueEnqueueBuffer(
                                         playState->queue,
                                         outBuffer,
                                         0,
                                         packetDescs);
        
        playState->currentPacket += numPackets;
    }
    
    
}

#pragma mark audio input Queue

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
    
    
    //  debug_NSLog(@"Sending packet sized %d", inBuffer->mAudioDataByteSize);
    
    int rtpstatus = sess.SendPacket((void *)inBuffer->mAudioData,inBuffer->mAudioDataByteSize,8,false, 160/1000000 );
    // pt=8  is PCMA ,  timestamp 8 is 8Khz
    checkerror(rtpstatus);
    if(rtpstatus!=0) return; // gradually stop reenqueing
    recordState->currentPacket += inNumberPacketDescriptions;
    
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
	//debug_NSLog("Sent %d audio packets, current packet %d \n", inNumberPacketDescriptions, recordState->currentPacket );
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
        debug_NSLog(@"new audio in queue started ok");
    }
    else {
        debug_NSLog(@"new audio in queue start failed");
        return -1;
    }
    
    
    //***** ouput ******
    
    

    playState.dataFormat.mSampleRate = 8000.0;
	playState.dataFormat.mFormatID = kAudioFormatLinearPCM;
	playState.dataFormat.mFramesPerPacket = 1;
	playState.dataFormat.mChannelsPerFrame = 1;
	playState.dataFormat.mBytesPerFrame = 2;
	playState.dataFormat.mBytesPerPacket = 2;
	playState.dataFormat.mBitsPerChannel = 16;
	playState.dataFormat.mReserved = 0;
	playState.dataFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian |
    kLinearPCMFormatFlagIsSignedInteger |
    kLinearPCMFormatFlagIsPacked;
    
   /* audioStatus = AudioQueueNewOutput(
                                 &playState.dataFormat,
                                 AudioOutputCallback,
                                 &playState,
                                 CFRunLoopGetCurrent(),
                                 kCFRunLoopCommonModes,
                                 0,
                                 &playState.queue);
    */
    
    if(audioStatus==0)
    {
        debug_NSLog(@"new audio out queue started ok");
    }
    else {
        debug_NSLog(@"new audio out queue start failed");
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
    destip =htonl(destip);
    
	// Now, we'll create a RTP session, set the destination, send some
	// packets and poll for incoming data.
	
	jrtplib::RTPUDPv4TransmissionParams transparams;
	jrtplib::RTPSessionParams sessparams;
	
    
	// IMPORTANT: The local timestamp unit MUST be set, otherwise
	//            RTCP Sender Report info will be calculated wrong
	// In this case, we'll be sending 10 samples each second, so we'll
	// put the timestamp unit to (1.0/10.0)
    
	sessparams.SetOwnTimestampUnit(1.0/100 );
	
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
                                              160, &recordState.buffers[i]);
        
        if(audioStatus==0)
        {
            // debug_NSLog("audio buffer allocate ok")
        }
        else {
            debug_NSLog(@"audio in  buffer allocate error %d", audioStatus);
        }
        audioStatus= AudioQueueEnqueueBuffer(recordState.queue,
                                             recordState.buffers[i], 0, NULL);
        
        if(audioStatus==0)
        {
            // debug_NSLog("audio buffer initial enqueue ok")
        }
        else {
            debug_NSLog(@"audio in buffer  initial enqueue error %d", audioStatus);
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
    
    
    // ****ouput**********
    
    if(status == 0)
    {
        
        for(int i = 0; i < NUM_BUFFERS; i++)
        {
            
            AudioQueueAllocateBuffer(playState.queue, 160, &playState.buffers[i]);
            //    AudioOutputCallback(&playState, playState.queue, playState.buffers[i]);
        }
        
        
        
    }
    
    
    
    
    [NSThread detachNewThreadSelector:@selector(listenThread) toTarget:self withObject:nil];
    
    
    
    
    
    
    return 0;
    
}



-(void) RTPDisconnect
{
    
    //input
    OSStatus  audioStatus = AudioQueueStop(recordState.queue, YES);
    
    for(int i = 0; i < NUM_BUFFERS; i++)
    {
        AudioQueueFreeBuffer(recordState.queue,
                             recordState.buffers[i]);
    }
    AudioQueueDispose(recordState.queue, true);
    
    if(audioStatus==0)
    {
        debug_NSLog(@"record stopped ok");
    }
    else {
        debug_NSLog(@"error stopping record");
        
    }
    
    //output
    playState.playing = false;
    
    for(int i = 0; i < NUM_BUFFERS; i++)
    {
        AudioQueueFreeBuffer(playState.queue, playState.buffers[i]);
    }
    
    AudioQueueDispose(playState.queue, true);
    
    
    sess.BYEDestroy(jrtplib::RTPTime(10,0),0,0);
}

@end
