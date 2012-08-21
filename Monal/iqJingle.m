//
//  iqJingle.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "iqJingle.h"

@implementation iqJingle
@synthesize me; 
@synthesize thesid;
@synthesize didReceiveTerminate;



@synthesize otherParty;
@synthesize theaddress;
@synthesize destinationPort;
@synthesize  destinationPort2;

@synthesize  localPort;
@synthesize  localPort2;
@synthesize  theusername;
@synthesize  thepass;

@synthesize idval;

@synthesize action;

@synthesize activeCall;
@synthesize waitingOnUserAccept;

-(void) resetVals
{
    thesid=nil;
    otherParty=nil;
    theaddress=nil;
    destinationPort=nil;
    destinationPort2=nil;
    
    localPort=nil;
    localPort2=nil;
    
    theusername=nil;
    thepass=nil;
    didReceiveTerminate=NO;
    
    activeCall=NO;
    didStartCall=NO;
    waitingOnUserAccept=NO; 
    
    
    activeResource=nil;
    initiator=nil;
    responder=nil; 
}

-(id) init
{
    self = [super init];

    [self resetVals];
    
    return self; 
}
-(NSString*) getGoogleInfo:(NSString*) idval
{
    return  [NSString stringWithFormat:@"<iq type='get' id='%@'  > <query xmlns='google:jingleinfo'/> </iq>", idval];
}


-(NSString*) ack:(NSString*) to:(NSString*) iqid
{
    if (activeCall==YES) return @"";
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq to='%@' from='%@' id='%@' type='result'/>", to, me, iqid]; 
    
 
    return query;
}


-(int) connect
{
    activeCall=YES; 
    
    
   // rtp2 =[RTP alloc];
    
   //  [rtp2 RTPConnect:theaddress:[destinationPort2 intValue]:[localPort2 intValue] ];
    
    rtp =[RTP alloc];
    
    return [rtp RTPConnect:theaddress:[destinationPort intValue]:[localPort intValue] ];
    

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
          
        //  [self performSelectorOnMainThread:@selector(connect) withObject:nil waitUntilDone:NO];

          return @"";
      }
    
     if (activeCall==YES) return @"";

  
    NSString* ownIP= [self localIPAddress];
    int localPortInt=[destinationPort intValue]+2;
    // local port can be the othersides port +2 shoudl be rnadom .. needs to be even for RTP
   localPort=[NSString stringWithFormat:@"%d",localPortInt];

   localPort2=[NSString stringWithFormat:@"%d",localPortInt+10];
    
    

   
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@'  id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name=\"audio-session\" senders=\"both\"><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\"/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate type=\"host\" network=\"0\" component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\" protocol=\"udp\" priority=\"1\" /> <candidate type=\"host\" network=\"0\" component=\"2\" ip=\"%@\" port=\"%@\"   id=\"monal002\" generation=\"0\" protocol=\"udp\" priority=\"2\" /> </transport> </content> </jingle> </iq>", otherParty, idval,  me,  thesid, ownIP, localPort, ownIP, localPort2];
      
    
    initiator=otherParty;
    responder=me; 
    
  /*  NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@'  id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name=\"audio-session\" senders=\"both\"><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type name='SPEEX' clockrate='8000' id='98' channels='1'/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate type=\"host\" network=\"0\" component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\" protocol=\"udp\" priority=\"1\" /></transport> </content> </jingle> </iq>", to, idval,  me,  thesid, ownIP, localPort];
    */
    

    
 
  
    
    return query;
}

-(NSString*) initiateJingle:(NSString*) to  :(NSString*)iqid:(NSString*) resource
{
    didStartCall=YES;
    activeCall=YES;
    
   
    
        NSString* ownIP= [self localIPAddress];
    localPort=@"7078"; // some random val
   localPort2=@"7079"; // some random val
    otherParty=to;
    debug_NSLog(@"resource id %@", resource); 
 
    thesid=@"Monal3sdfg"; //something random
 NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@" <iq to='%@/%@' id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' initiator='%@' responder='%@' sid='%@'> <content creator='initiator'  name=\"audio-session\" senders=\"both\" responder='%@'> <description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\" channels='0'/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\"   /><candidate component=\"2\" ip=\"%@\" port=\"%@\"   id=\"monal002\" generation=\"0\"  /> </transport> </content> </jingle> </iq>", otherParty, resource, iqid, me, to,  thesid, to, ownIP, localPort,ownIP,localPort2];
    
    initiator=me;
    responder=otherParty;
     activeResource=resource;
    
    return query;
}

-(NSString*) rejectJingle
{
   
 NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq   id='%@'   to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-terminate'  initiator='%@' responder='%@' sid='%@'> <reason> <decline/> </reason> </jingle> </iq>", idval, otherParty, otherParty, me,  thesid];
   
   
     [self resetVals];
    return query;
}


-(NSString*) terminateJingle
{
    
   
    
    NSMutableString* query=[[NSMutableString alloc] init];
     if(!didReceiveTerminate)
         [query appendFormat:@"<iq   id='%@'   to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-terminate'  initiator='%@' responder='%@' sid='%@'> <reason> <success/> </reason> </jingle> </iq>", idval, otherParty, initiator, responder,  thesid];
    
    else
        query=@"";
    
     [self resetVals];
    
    [rtp RTPDisconnect];
    
   
    return query;
}






@end
