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
	
	for (i = 1 ; i <= num ; i++)
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
	
	sess.BYEDestroy(jrtplib::RTPTime(10,0),0,0);
}

@end
