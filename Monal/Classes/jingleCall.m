//
//  iqJingle.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "jingleCall.h"





@interface jingleCall()

@property (nonatomic, strong ) dispatch_queue_t netReadQueue;

@end

@implementation jingleCall

-(id) init{
    self=[super init];
    if(self)
    {
        IPAddress* ip = [[IPAddress alloc] init];
        _ownIP=[ip getIPAddress:YES];
    }
    return self;
}


-(int) rtpConnect
{
    self.activeCall=YES;
    // rtp2 =[RTP alloc];
    //  [rtp2 RTPConnect:theaddress:[destinationPort2 intValue]:[localPort2 intValue] ];
    NSString* monalNetWriteQueue =@"im.monal.jingleMain";
    self.netReadQueue = dispatch_queue_create([monalNetWriteQueue UTF8String], DISPATCH_QUEUE_SERIAL);
    
    
    dispatch_async(self.netReadQueue, ^{
        self->rtp =[[RTP alloc] init];
        [self->rtp RTPConnectAddress:self.recipientIP onRemotePort:[self.destinationPort intValue] withLocalPort:[self.localPort intValue]];
    });
   return 0;
}

-(void) rtpDisconnect
{
    if(!self.netReadQueue) return;
    
    dispatch_async(self.netReadQueue, ^{
        [self->rtp RTPDisconnect];
    });
}


#pragma mark jingle nodes

-(XMPPIQ*) acceptJingleTo:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource
{
    if(didStartCall==YES) return nil;
    if (self.activeCall==YES) return nil;
    
    didStartCall=YES;
    self.activeCall=YES;
    
    int localPortInt=[self.destinationPort intValue]+2;
    // local port can be the othersides port +2 shoudl be random .. needs to be even for RTP
    self.localPort=[NSString stringWithFormat:@"%d",localPortInt];
    
    self.localPort2=[NSString stringWithFormat:@"%d",localPortInt+10];
    
    NSDictionary* info =@{@"initiator":self.initiator, @"responder":self.responder, @"sid":self.thesid, @"ownip":_ownIP, @"localport1":self.localPort,@"localport2":self.localPort2};
    
    self.otherParty=self.initiator;
    _activeresource=resource;
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithType:kiqSetType];
    [node setJingleAcceptTo:to andResource:resource withValues:info];
    self.idval= iqid; 
    
    return node;
}

-(XMPPIQ*) initiateJingleTo:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource
{

    if(didStartCall==YES) return nil;
    if (self.activeCall==YES) return nil;
    
    didStartCall=YES;
    self.activeCall=YES;
    
    self.localPort=@"7078"; // some random val
    self.localPort2=@"7079"; // some random val
    self.otherParty=[NSString stringWithFormat:@"%@/%@",to,resource];
    
    self.thesid = [[NSUUID UUID] UUIDString];
    
    self.initiator=self.me;
    self.responder=self.otherParty;
    _activeresource=resource;
    
    if ([_ownIP isEqualToString:@"0.0.0.0"])
    {
        DDLogWarn( @"initiateJingleTo without valid own IP");
    }
    //initiator, responder, sid, ownip, localport1, localport2
    
     NSDictionary* info =@{@"initiator":self.initiator, @"responder":self.responder, @"sid":self.thesid, @"ownip":_ownIP, @"localport1":self.localPort,@"localport2":self.localPort2};
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithType:kiqSetType];
    [node setJingleInitiateTo:to andResource:resource withValues:info];
    
    return node;
}

-(XMPPIQ*) rejectJingleTo:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource
{
    NSDictionary* info =@{@"initiator":self.initiator, @"responder":self.responder, @"sid":self.thesid};
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithType:kiqSetType];
    [node setJingleDeclineTo:to andResource:resource withValues:info];
    
    return node;
}


-(XMPPIQ*) terminateJinglewithId:(NSString*)iqid
{
    [rtp RTPDisconnect];
    
    if(self.initiator && self.responder && self.thesid && _ownIP) {
        NSDictionary* info =@{@"initiator":self.initiator, @"responder":self.responder, @"sid":self.thesid, @"ownip":_ownIP};
        
        XMPPIQ* node =[[XMPPIQ alloc] initWithType:kiqSetType];
        [node setJingleTerminateTo:self.otherParty andResource:_activeresource withValues:info];
        return node;
    }
    else
    {
        return nil;
    }
}






@end
