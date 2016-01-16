
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
#include <stdio.h>
#include <string>
#include <string.h>

#import "RTP.hh"


#ifdef DEBUG
#   define debug_NSLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#   define debug_NSLog(...)
#endif


jrtplib::RTPSession sess;


typedef struct
{
    AudioStreamBasicDescription dataFormat;
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[NUM_BUFFERS_REC];
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

TPCircularBuffer packetInCircularBuffer;
TPCircularBuffer packetOutCircularBuffer;
int packCount;

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
    while(1)
    {
        if(disconnecting==YES) break;
        sess.BeginDataAccess();
        
        // check incoming packets
        if (sess.GotoFirstSourceWithData())
        {
            do
            {
                jrtplib::RTPPacket *pack;
                
                while ((pack = sess.GetNextPacket()) != NULL)
                {
                    
                    //  debug_NSLog(@"Got packet");
                    
                    TPCircularBufferProduceBytes(&packetInCircularBuffer,pack->GetPayloadData(), pack->GetPayloadLength());
    
                    sess.DeletePacket(pack);
                    
                    packCount++;
                
                    //start playback after thre are 300 packets
                    if((packCount>300 && playState.playing==NO) && (disconnecting==NO))
                    {
                        OSStatus status = AudioQueueStart(playState.queue, NULL);
                        if(status == 0)
                        {
                            playState.playing=YES;
                            debug_NSLog(@"Started play back ");
                            for(int i = 0; i < NUM_BUFFERS; i++)
                            {
                                // needs a proper circular buffer before i use this again..
                                AudioOutputCallback(&playState, playState.queue, playState.buffers[i]);
                            }
     
                        }
                    }
                    
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
    
    // debug_NSLog(@"Queuing buffer %lld for playback\n", playState->currentPacket);
    uint32_t bytesToCopy=160;
    int32_t availableBytes;
    
    void *buffer = TPCircularBufferTail(&packetInCircularBuffer, &availableBytes);

    if(availableBytes>=bytesToCopy)
    {
        uint numPackets=bytesToCopy/2;
        //set packet descriptor for each audio packet
        
        AudioStreamPacketDescription packetDescs[numPackets];
    
        int packCounter=0;
        while(packCounter<numPackets)
        {
            packetDescs[packCounter].mStartOffset=2*packCounter;
            packetDescs[packCounter].mVariableFramesInPacket=0;
            packetDescs[packCounter].mDataByteSize=2;
            
            packCounter++;
        }
        

        //   debug_NSLog(" read %d pcm, %d packets bytes: \n %s", bytesRead,numPackets, outBuffer->mAudioData  )
  
        if(numPackets>0)
        {
            outBuffer->mAudioDataByteSize = bytesToCopy;
            void* pbuffer=outBuffer->mAudioData;
            memcpy(pbuffer, buffer, bytesToCopy);
            
            OSStatus status = AudioQueueEnqueueBuffer(
                                                      playState->queue,
                                                      outBuffer,
                                                      0,
                                                      packetDescs);
            
            playState->currentPacket += numPackets;
            
        }
        
        //clean up
        TPCircularBufferConsume(&packetInCircularBuffer, bytesToCopy);
        
    }
    
    
    
}


#pragma mark audio input Queue

-(void) sendThread
{
    debug_NSLog(@"entered RTP send thread");

    while(1)
    {
        if(disconnecting) break;
        //let it bufer a little
        if(packCount>300)
        {
            uint32_t bytesToCopy=160;
            int32_t availableBytes;
            void *buffer = TPCircularBufferTail(&packetOutCircularBuffer, &availableBytes);
            if(availableBytes>=bytesToCopy)
            {
                void *targetBuffer = malloc(bytesToCopy);
                memcpy(targetBuffer, buffer, bytesToCopy );
  
                int rtpstatus = sess.SendPacket(targetBuffer,bytesToCopy,8,false, bytesToCopy);
                // pt=8  is PCMA ,  timestamp 2x80 =160 is for 2x 8Khz records at 5 ms
                checkerror(rtpstatus);
                if(rtpstatus!=0) break; //  stop sending
                
                //clean up
                TPCircularBufferConsume(&packetOutCircularBuffer, bytesToCopy);
                free(targetBuffer);
            }
            
        }
    }
    
    debug_NSLog(@"leaving RTP send thread");
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
    
    TPCircularBufferProduceBytes(&packetOutCircularBuffer,inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
    
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
    
    packCount++;
    //debug_NSLog("Sent %d audio packets, current packet %d \n", inNumberPacketDescriptions, recordState->currentPacket );
}

#pragma mark RTP cocoa wrapper

-(int) RTPConnectAddress:(NSString*) IP onRemotePort:(int) destPort withLocalPort:(int) localPort
{
    TPCircularBufferInit(&packetInCircularBuffer, kBufferLength);
    TPCircularBufferInit(&packetOutCircularBuffer, kBufferLength);
    packCount=0;
    
    disconnecting=NO;
    #if TARGET_OS_IPHONE
[[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayAndRecord error: nil];
    
#else
#endif
   
    //********* Audio Queue ********/
    
    recordState.dataFormat.mSampleRate = 8000.0;
    recordState.dataFormat.mFormatID = kAudioFormatALaw;
    recordState.dataFormat.mFramesPerPacket = 1;
    recordState.dataFormat.mChannelsPerFrame = 1;
    recordState.dataFormat.mBytesPerFrame = 2;
    recordState.dataFormat.mBytesPerPacket = 2;
    recordState.dataFormat.mBitsPerChannel = 16;
    recordState.dataFormat.mReserved = 0;
    
    
    
    OSStatus audioStatus = AudioQueueNewInput(
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
    
    
    //******** ouput ******
    
    playState.dataFormat.mSampleRate = 8000.0;
    playState.dataFormat.mFormatID = kAudioFormatALaw;//kAudioFormatLinearPCM;
    playState.dataFormat.mFramesPerPacket = 1;
    playState.dataFormat.mChannelsPerFrame = 1;
    playState.dataFormat.mBytesPerFrame = 2;
    playState.dataFormat.mBytesPerPacket = 2;
    playState.dataFormat.mBitsPerChannel = 16;
    playState.dataFormat.mReserved = 0;
    
    
    
    
    audioStatus = AudioQueueNewOutput(
                                      &playState.dataFormat,
                                      AudioOutputCallback,
                                      &playState,
                                      CFRunLoopGetCurrent(),
                                      kCFRunLoopCommonModes,
                                      0,
                                      &playState.queue);
    
    
    
    
    
    
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
    int status;
    
    destport=destPort;
    portbase=localPort;
    
    
    destip = inet_addr(ipstr.c_str());
    destip =htonl(destip);
    
    // Now, we'll create a RTP session, set the destination, send some
    // packets and poll for incoming data.
    
    jrtplib::RTPUDPv4TransmissionParams transparams;
    jrtplib::RTPSessionParams sessparams;
    
    debug_NSLog(@" RTP to ip %d  IP %@ on port %d and potbase %d", destip,IP,  destport, portbase);
    
    
    // IMPORTANT: The local timestamp unit MUST be set, otherwise
    //            RTCP Sender Report info will be calculated wrong
    // In this case, we'll be sending 10 samples each second, so we'll
    // put the timestamp unit to (1.0/10.0)
    
    sessparams.SetOwnTimestampUnit(1.0/8000.0 );
    
    sessparams.SetAcceptOwnPackets(true);
    transparams.SetPortbase(portbase);
    status = sess.Create(sessparams,&transparams);
    checkerror(status);
    
    if(status!=0) return status;

    jrtplib::RTPIPv4Address addr(destip,destport);
    
    status = sess.AddDestination(addr);
    checkerror(status);
    
    if(status!=0) return status;
    
  
    for(int i = 0; i < NUM_BUFFERS_REC; i++)
    {
        audioStatus= AudioQueueAllocateBuffer(recordState.queue,
                                              160, &recordState.buffers[i]);
        
        if(audioStatus==0)
        {
          //   debug_NSLog("audio buffer allocate ok")
        }
        else {
            debug_NSLog(@"audio in  buffer allocate error %d", audioStatus);
        }
        audioStatus= AudioQueueEnqueueBuffer(recordState.queue,
                                             recordState.buffers[i], 0, NULL);
        
        if(audioStatus==0)
        {
           //  debug_NSLog("audio buffer initial enqueue ok")
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
        //return -1;
    }

    // ouput
    if(status == 0)
    {
        for(int i = 0; i < NUM_BUFFERS; i++)
        {
            
            AudioQueueAllocateBuffer(playState.queue, 160, &playState.buffers[i]);
        }
        
    }
    
    NSString* monalNetReadQueue =@"im.monal.jingleReadQueue.%@";
    NSString* monalNetWriteQueue =@"im.monal.jingleWriteQueue.%@";
    
    dispatch_queue_t _netReadQueue = dispatch_queue_create([monalNetReadQueue UTF8String], DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t _netWriteQueue = dispatch_queue_create([monalNetWriteQueue UTF8String], DISPATCH_QUEUE_SERIAL);
    
    
    dispatch_async(_netReadQueue, ^{
        [self listenThread];
    });
    
    dispatch_async(_netWriteQueue, ^{
        [self sendThread];
    });
    
    [[NSRunLoop currentRunLoop] run]; //needed for audio callbacks
    return 0;
    
}

-(void) RTPDisconnect
{
    
    disconnecting=true;
    //input
    OSStatus  audioStatus = AudioQueueStop(recordState.queue, YES);
    
    for(int i = 0; i < NUM_BUFFERS_REC; i++)
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