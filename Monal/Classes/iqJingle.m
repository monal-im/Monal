//
//  iqJingle.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "iqJingle.h"

#ifdef DEBUG
#   define debug_NSLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#   define debug_NSLog(...)
#endif

@implementation iqJingle

-(void) resetVals
{
    self.thesid=nil;
    self.otherParty=nil;
    self.theaddress=nil;
    self.destinationPort=nil;
    self.destinationPort2=nil;
    
    self.localPort=nil;
    self.localPort2=nil;
    
    self.theusername=nil;
    self.thepass=nil;
    didReceiveTerminate=NO;
    
    self.activeCall=NO;
    didStartCall=NO;
    self.waitingOnUserAccept=NO; 

}

-(id) init
{
    self = [super init];

    [self resetVals];
    
    return self; 
}
-(NSString*) getGoogleInfo:(NSString*) theidval
{
    return  [NSString stringWithFormat:@"<iq type='get' id='%@'  > <query xmlns='google:jingleinfo'/> </iq>", theidval];
}


-(NSString*) ack:(NSString*) to:(NSString*) iqid
{
    if (self.activeCall==YES) return @"";
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq to='%@' from='%@' id='%@' type='result'/>", to, self.me, iqid];
    
 
    return query;
}


-(int) connect
{
    self.activeCall=YES;
    
    
   // rtp2 =[RTP alloc];
    
   //  [rtp2 RTPConnect:theaddress:[destinationPort2 intValue]:[localPort2 intValue] ];
    
    rtp =[RTP alloc];
    
    return [rtp RTPConnectAddress:self.theaddress onRemotePort:[self.destinationPort intValue] withLocalPort:[self.localPort intValue]];
    

}

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

-(NSString*) acceptJingle
{
    
      if(didStartCall==YES)
      {
          
       
          return @"";
      }
    
     if (self.activeCall==YES) return @"";

  
    NSString* ownIP= [self localIPAddress];
    int localPortInt=[self.destinationPort intValue]+2;
    // local port can be the othersides port +2 shoudl be rnadom .. needs to be even for RTP
   self.localPort=[NSString stringWithFormat:@"%d",localPortInt];

   self.localPort2=[NSString stringWithFormat:@"%d",localPortInt+10];
    
 
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@'  id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name=\"audio-session\" senders=\"both\"><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\"/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate type=\"host\" network=\"0\" component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\" protocol=\"udp\" priority=\"1\" /> <candidate type=\"host\" network=\"0\" component=\"2\" ip=\"%@\" port=\"%@\"   id=\"monal002\" generation=\"0\" protocol=\"udp\" priority=\"2\" /> </transport> </content> </jingle> </iq>", self.otherParty, self.idval,  self.me,  self.thesid, ownIP, self.localPort, ownIP, self.localPort2];
      
    
    self.initiator=self.otherParty;
    self.responder=self.me;
    
  /*  NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@'  id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name=\"audio-session\" senders=\"both\"><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type name='SPEEX' clockrate='8000' id='98' channels='1'/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate type=\"host\" network=\"0\" component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\" protocol=\"udp\" priority=\"1\" /></transport> </content> </jingle> </iq>", to, idval,  me,  thesid, ownIP, localPort];
    */
    
  
    return query;
}

-(NSString*) initiateJingle:(NSString*) to  :(NSString*)iqid:(NSString*) resource
{
    didStartCall=YES;
    self.activeCall=YES;
    
   
    
        NSString* ownIP= [self localIPAddress];
    self.localPort=@"7078"; // some random val
   self.localPort2=@"7079"; // some random val
    self.otherParty=to;
    debug_NSLog(@"resource id %@", resource); 
 
    self.thesid=@"Monal3sdfg"; //something random
 NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@" <iq to='%@/%@' id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' initiator='%@' responder='%@' sid='%@'> <content creator='initiator'  name=\"audio-session\" senders=\"both\" responder='%@'> <description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\" channels='0'/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\"   /><candidate component=\"2\" ip=\"%@\" port=\"%@\"   id=\"monal002\" generation=\"0\"  /> </transport> </content> </jingle> </iq>", self.otherParty, _resource, _iqid, self.me, _to,  self.thesid, _to, _ownIP, self.localPort, _ownIP,self.localPort2];
    
    self.initiator=self.me;
    self.responder=self.otherParty;
     _activeresource=resource;
    
    return query;
}

-(NSString*) rejectJingle
{
   
 NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq   id='%@'   to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-terminate'  initiator='%@' responder='%@' sid='%@'> <reason> <decline/> </reason> </jingle> </iq>", self.idval, self.otherParty, self.otherParty, self.me,  self.thesid];
   
   
     [self resetVals];
    return query;
}


-(NSString*) terminateJingle
{
    
   
    
    NSMutableString* query=[[NSMutableString alloc] init];
     if(!didReceiveTerminate)
         [query appendFormat:@"<iq   id='%@'   to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-terminate'  initiator='%@' responder='%@' sid='%@'> <reason> <success/> </reason> </jingle> </iq>", self.idval, self.otherParty, self.initiator, self.responder,  self.thesid];
    
    else
        query=@"";
    
     [self resetVals];
    
    [rtp RTPDisconnect];
    
   
    return query;
}






@end
