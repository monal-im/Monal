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

-(id) init
{
    self = [super init];
   
   
    
    thesid=nil; 
    otherParty=nil; 
    theaddress=nil; 
    theport=nil; 
    theusername=nil;
    thepass=nil; 
    
    return self; 
}
-(NSString*) getGoogleInfo:(NSString*) idval
{
    return  [NSString stringWithFormat:@"<iq type='get' id='%@'  > <query xmlns='google:jingleinfo'/> </iq>", idval];
}

-(NSString*) ack:(NSString*) to:(NSString*) iqid
{
    
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq to='%@' from='%@' id='%@' type='result'/>", to, me, iqid]; 
    
    

    
    
    
    ; 
    return query;
}


-(void) connect
{
    rtp =[RTP alloc];
    [rtp RTPConnect:theaddress:[theport intValue]];
    
    	
	
  
    
}

-(NSString*) acceptJingle:(NSString*) to:(NSString*) address: (NSString*) port: (NSString*) username: (NSString*) pass:  (NSString*)idval
{
    
    
   
    
    NSMutableString* query=[[NSMutableString alloc] init];
   /* [query appendFormat:@"<iq      to='%@'  id='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name='voice'><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\"><parameter name=\"bitrate\" value=\"64000\"/> </description> <transport xmlns='urn:xmpp:jingle:transports:ice-udp:1'> <candidate address=\"%@\" port=\"%@\" name=\"rtp\"   protocol=\"udp\" generation=\"0\" network=\"en1\" type=\"stun\"/></transport> </content> </jingle> </iq>", to, idval,  me,  thesid, address, port]; 
    */
   
    
    [query appendFormat:  @" <iq type='set' to='%@' id='%@' from='%@'><ses:session type='accept' id='%@' initiator='%@' xmlns:ses='http://www.google.com/session'><description xmlns='http://www.google.com/session/phone'><payload-type id='8' name='PCMA' clockrate='8000'/></description></ses:session></iq>", to, idval, me,thesid,to]; 
    
    
    theaddress=address;
    theport=port; 
    theusername=username; 
    thepass=pass;

    
    
    otherParty=[NSString stringWithString:to]; 
  
    
    
    
    
    ; 
    return query;
}

-(NSString*) initiateJingle:(NSString*) to  
{
    
 
    NSString* sid=@"sfghj569"; //something random 
 NSMutableString* query=[[NSMutableString alloc] init];
       [query appendFormat:@" <iq to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' initiator='%@' sid='%@'> <content creator='initiator' name='audio'> <description xmlns='urn:xmpp:jingle:apps:rtp:1'/> <transport xmlns:p=\"http://www.google.com/transport/p2p\"/> </content> </jingle> </iq>", to,me, sid]; 
    

    otherParty=[NSString stringWithString:to]; 
    //thesid =[NSString stringWithString:sid]; 
    //[thesid retain];
    
    
    
    ; 
    return query;
}

-(NSString*) terminateJingle
{
    
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-terminate' sid='%@'> <reason> <success/> </reason> </jingle> </iq>", otherParty, thesid]; 
    
    
    
    
    ; 
    return query;
}






@end
