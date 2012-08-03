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

-(void) resetVals
{
    thesid=nil;
    otherParty=nil;
    theaddress=nil;
    destinationPort=nil;
    localPort=nil;
    theusername=nil;
    thepass=nil;
    didReceiveTerminate=NO;
    
    activeCall=NO;
    didStartCall=NO;
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
    
    rtp =[RTP alloc];
    
    return [rtp RTPConnect:theaddress:[destinationPort intValue]:[localPort intValue]];
    

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

-(NSString*) acceptJingle:(NSString*) to:(NSString*) address: (NSString*) port: (NSString*) username: (NSString*) pass:  (NSString*)idval
{
    
      if(didStartCall==YES)
      {
          theaddress=address;
          destinationPort=port;
          theusername=username;
          thepass=pass;
          otherParty=[NSString stringWithString:to];
          
        //   [self performSelectorOnMainThread:@selector(connect) withObject:nil waitUntilDone:NO];
          
          return @"";
      }
    
     if (activeCall==YES) return @"";
    
  
    NSString* ownIP= [self localIPAddress];
    int localPortInt=[port intValue]+2;
    // local port can be the othersides port +2 shoudl be rnadom .. needs to be even for RTP
   localPort=[NSString stringWithFormat:@"%d",localPortInt];

    theaddress=address;
    destinationPort=port;
    theusername=username;
    thepass=pass;
    
    //create the listener and get the port number before sending to the accept
     //[self performSelectorOnMainThread:@selector(connect) withObject:nil waitUntilDone:NO];
    
   
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@'  id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name=\"audio-session\" senders=\"both\"><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\"/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate type=\"host\" network=\"0\" component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\" protocol=\"udp\" priority=\"1\" /></transport> </content> </jingle> </iq>", to, idval,  me,  thesid, ownIP, localPort];
      
    
    
  /*  NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@'  id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name=\"audio-session\" senders=\"both\"><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type name='SPEEX' clockrate='8000' id='98' channels='1'/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate type=\"host\" network=\"0\" component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\" protocol=\"udp\" priority=\"1\" /></transport> </content> </jingle> </iq>", to, idval,  me,  thesid, ownIP, localPort];
    */
    

    
   otherParty=[NSString stringWithString:to]; 
 
  
    
    return query;
}

-(NSString*) initiateJingle:(NSString*) to  :(NSString*)iqid
{
    didStartCall=YES;
        NSString* ownIP= [self localIPAddress];
    localPort=@"50002"; // some random val
 
    thesid=@"Monal3sdfg"; //something random
 NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@" <iq to='%@/Monal' id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' initiator='%@' responder='%@' sid='%@'> <content creator='initiator'  name=\"audio-session\" senders=\"both\" responder='%@'> <description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\" channels='0'/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\"  /></transport> </content> </jingle> </iq>", to, iqid, me, to,  thesid, to, ownIP, localPort];
    
//Note this needs the resource id after "to"  inorder to work.. 
    
    
    otherParty=[NSString stringWithString:to]; 
 
    return query;
}

-(NSString*) terminateJingle
{
    
    [self resetVals];
    
    NSMutableString* query=[[NSMutableString alloc] init];
     if(!didReceiveTerminate)
    [query appendFormat:@"<iq      to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-terminate' sid='%@'> <reason> <success/> </reason> </jingle> </iq>", otherParty, thesid]; 
    else
        query=@"";
    
    [rtp RTPDisconnect];
    
   
    return query;
}






@end
