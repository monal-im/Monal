//
//  iqJingle.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "jingleCall.h"

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

-(NSString*) getGoogleInfo:(NSString*) theidval
{
    return  [NSString stringWithFormat:@"<iq type='get' id='%@'  > <query xmlns='google:jingleinfo'/> </iq>", theidval];
}

-(int) rtpConnect
{
    self.activeCall=YES;
    // rtp2 =[RTP alloc];
    //  [rtp2 RTPConnect:theaddress:[destinationPort2 intValue]:[localPort2 intValue] ];
    NSString* monalNetWriteQueue =@"im.monal.jingleMain.%@";
    dispatch_queue_t _netReadQueue = dispatch_queue_create([monalNetWriteQueue UTF8String], DISPATCH_QUEUE_SERIAL);
    
    
    dispatch_async(_netReadQueue, ^{
        rtp =[[RTP alloc] init];
        [rtp RTPConnectAddress:self.recipientIP onRemotePort:[self.destinationPort intValue] withLocalPort:[self.localPort intValue]];
    });
   return 0;
}

-(void) rtpDisconnect
{
    [rtp RTPDisconnect];
}


#pragma mark jingle nodes

-(XMPPIQ*) acceptJingleTo:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource
{
    if(didStartCall==YES) return nil;
    if (self.activeCall==YES) return nil;
    
    didStartCall=YES;
    self.activeCall=YES;
    
    int localPortInt=[self.destinationPort intValue]+2;
    // local port can be the othersides port +2 shoudl be rnadom .. needs to be even for RTP
    self.localPort=[NSString stringWithFormat:@"%d",localPortInt];
    
    self.localPort2=[NSString stringWithFormat:@"%d",localPortInt+10];
    
    NSDictionary* info =@{@"initiator":self.initiator, @"responder":self.responder, @"sid":self.thesid, @"ownip":_ownIP, @"localport1":self.localPort,@"localport2":self.localPort2};
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithId:iqid andType:kiqSetType];
    [node setJingleAcceptTo:to andResource:resource withValues:info];
    
    
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
    
    int random =  arc4random_uniform(100);
    self.thesid=[NSString stringWithFormat:@"Monal%d",random];
    
    self.initiator=self.me;
    self.responder=self.otherParty;
    _activeresource=resource;
    
    //initiator, responder, sid, ownip, localport1, localport2
    
     NSDictionary* info =@{@"initiator":self.initiator, @"responder":self.responder, @"sid":self.thesid, @"ownip":_ownIP, @"localport1":self.localPort,@"localport2":self.localPort2};
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithId:iqid andType:kiqSetType];
    [node setJingleInitiateTo:to andResource:resource withValues:info];
    
    return node;
}

-(XMPPIQ*) rejectJingleTo:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource
{
    NSDictionary* info =@{@"initiator":self.initiator, @"responder":self.responder, @"sid":self.thesid};
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithId:iqid andType:kiqSetType];
    [node setJingleDeclineTo:to andResource:resource withValues:info];
    
    return node;
}


-(XMPPIQ*) terminateJinglewithId:(NSString*)iqid
{
    [rtp RTPDisconnect];
    
    if(self.initiator && self.responder && self.thesid && _ownIP) {
        NSDictionary* info =@{@"initiator":self.initiator, @"responder":self.responder, @"sid":self.thesid, @"ownip":_ownIP};
        
        XMPPIQ* node =[[XMPPIQ alloc] initWithId:iqid andType:kiqSetType];
        [node setJingleTerminateTo:self.otherParty andResource:_activeresource withValues:info];
        return node;
    }
    else
    {
        return nil;
    }
}






@end
