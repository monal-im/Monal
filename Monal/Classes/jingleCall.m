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
        _ownIP=[self localIPAddress];
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
    
    rtp =[RTP alloc];
    return [rtp RTPConnectAddress:self.theaddress onRemotePort:[self.destinationPort intValue] withLocalPort:[self.localPort intValue]];
}


#pragma mark helper methods 

- (NSString *)hostname
{
    char baseHostName[256];
    int success = gethostname(baseHostName, 255);
    if (success != 0) return nil;
    baseHostName[255] = '\0';
    
#if !TARGET_IPHONE_SIMULATOR
    return [NSString stringWithFormat:@"%s.local", baseHostName];
#else
    return [NSString stringWithFormat:@"%s", baseHostName];
#endif
}

// return IP Address
- (NSString *)localIPAddress
{
    struct hostent *host = gethostbyname([[self hostname] UTF8String]);
    if (!host) {herror("resolv"); return nil;}
    struct in_addr **list = (struct in_addr **)host->h_addr_list;
    return [NSString stringWithCString:inet_ntoa(*list[0]) encoding:NSUTF8StringEncoding];
}


#pragma mark jingle nodes

-(XMPPIQ*) acceptJingle:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource
{
    if(didStartCall==YES)
    {
        return nil;
    }
    
    if (self.activeCall==YES) return nil;
    
    int localPortInt=[self.destinationPort intValue]+2;
    // local port can be the othersides port +2 shoudl be rnadom .. needs to be even for RTP
    self.localPort=[NSString stringWithFormat:@"%d",localPortInt];
    
    self.localPort2=[NSString stringWithFormat:@"%d",localPortInt+10];
    self.initiator=self.otherParty;
    self.responder=self.me;
    
   NSDictionary* info =@{self.initiator:@"initiator", self.responder:@"responder", self.thesid:@"sid", _ownIP:@"ownip", self.localPort:@"localport1", self.localPort2:@"localport2"};
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithId:iqid andType:kiqSetType];
    [node setJingleInitiateTo:to andResource:resource withValues:info];
    
    
    return node;
}

-(XMPPIQ*) initiateJingle:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource
{
    didStartCall=YES;
    self.activeCall=YES;
    
    self.localPort=@"7078"; // some random val
    self.localPort2=@"7079"; // some random val
    self.otherParty=to;
  
    
    self.thesid=@"Monal3sdfg"; //something random
    
    self.initiator=self.me;
    self.responder=self.otherParty;
    _activeresource=resource;
    
    //initiator, responder, sid, ownip, localport1, localport2
    
    NSDictionary* info =@{self.initiator:@"initiator", self.responder:@"responder", self.thesid:@"sid", _ownIP:@"ownip", self.localPort:@"localport1", self.localPort2:@"localport2"};
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithId:iqid andType:kiqSetType];
    [node setJingleInitiateTo:to andResource:resource withValues:info];
    
    return node;
}

-(XMPPIQ*) rejectJingle:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource
{

       NSDictionary* info =@{self.initiator:@"initiator", self.responder:@"responder", self.thesid:@"sid", _ownIP:@"ownip", self.localPort:@"localport1", self.localPort2:@"localport2"};
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithId:iqid andType:kiqSetType];
    [node setJingleDeclineTo:to andResource:resource withValues:info];
    
    return node;
}


-(XMPPIQ*) terminateJingle:(NSString*) to  withId:(NSString*)iqid andResource:(NSString*) resource
{

//    if(!_didReceiveTerminate)
//       
//        
//    else
//        query=@"";
    
    [rtp RTPDisconnect];
    
       NSDictionary* info =@{self.initiator:@"initiator", self.responder:@"responder", self.thesid:@"sid", _ownIP:@"ownip", self.localPort:@"localport1", self.localPort2:@"localport2"};
    
    XMPPIQ* node =[[XMPPIQ alloc] initWithId:iqid andType:kiqSetType];
    [node setJingleTerminateTo:to andResource:resource withValues:info];
    
    
    return node;
}






@end
