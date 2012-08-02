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


- (NSString *)getOwnIPAddress
{
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0)
    {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while(temp_addr != NULL)
        {
            if(temp_addr->ifa_addr->sa_family == AF_INET)
            {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"])
                {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
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
          
           [self performSelectorOnMainThread:@selector(connect) withObject:nil waitUntilDone:NO];
          
          return @"";
      }
    
     if (activeCall==YES) return @"";
    
    NSString* ownIP= [self getOwnIPAddress];
    int localPortInt=[port intValue]+2;
    // local port can be the othersides port +2 shoudl be rnadom .. needs to be even for RTP
   localPort=[NSString stringWithFormat:@"%d",localPortInt];

    theaddress=address;
    destinationPort=port;
    theusername=username;
    thepass=pass;
    
    //create the listener and get the port number before sending to the accept
     [self performSelectorOnMainThread:@selector(connect) withObject:nil waitUntilDone:NO];
    
   
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@'  id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name=\"audio-session\" senders=\"both\"><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\"/></description> <transport xmlns='urn:xmpp:jingle:transports:raw-udp:1'><candidate type=\"host\" network=\"0\" component=\"1\" ip=\"%@\" port=\"%@\"   id=\"monal001\" generation=\"0\" protocol=\"udp\" priority=\"1\" /></transport> </content> </jingle> </iq>", to, idval,  me,  thesid, ownIP, localPort];
    
    
   /* [query appendFormat:  @" <iq type='set' to='%@' id='%@' from='%@'><ses:session type='accept' id='%@' initiator='%@' xmlns:ses='http://www.google.com/session'><description xmlns='http://www.google.com/session/phone'><payload-type id='8' name='PCMA' clockrate='8000'/></description></ses:session></iq>", to, idval, me,thesid,to];
    */
    
   otherParty=[NSString stringWithString:to]; 
 
  
    
    return query;
}

-(NSString*) initiateJingle:(NSString*) to  :(NSString*)iqid
{
    didStartCall=YES;
        NSString* ownIP= [self getOwnIPAddress];
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
