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

-(NSString*) ack:(NSString*) to:(NSString*) iqid
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq to='%@' from='%@' id='%@' type='result'/>", to, me, iqid]; 
    
    

    
    [query retain]; 
    
    
    [pool release]; 
    return query;
}


-(NSString*) acceptJingle:(NSString*) to:(NSString*) address: (NSString*) port: (NSString*) username: (NSString*) pass
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name='audio'><description xmlns:rtp=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"> <rtp:payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\"><rtp:parameter name=\"bitrate\" value=\"64000\"/></rtp:payload-type> </description> <p:candidate address=\"%@\" port=\"%@\" name=\"rtp\" username=\"%@\" password=\"%@\" preference=\"%@\" protocol=\"udp\" generation=\"0\" network=\"en1\" type=\"stun\"/></p:transport><transport xmlns:p=\"http://www.google.com/transport/p2p\"> </transport> </content> </jingle> </iq>", to, me,  thesid, address, port, username, pass]; 
    
    theaddress=[NSString stringWithString:address]; 
    theport=[NSString stringWithString:port]; 
    theusername=[NSString stringWithString:username]; 
    thepass=[NSString stringWithString:pass]; 
    [theaddress retain]; 
    [theport retain]; 
    [theusername retain]; 
    [thepass retain]; 
    
    
    otherParty=[NSString stringWithString:to]; 
    [otherParty retain]; 
  
    
    [query retain]; 
    
    
    [pool release]; 
    return query;
}

-(NSString*) initiateJingle:(NSString*) to  
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
 
    NSString* sid=@"sfghj569"; //something random 
 NSMutableString* query=[[NSMutableString alloc] init];
       [query appendFormat:@" <iq to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' initiator='%@' sid='%@'> <content creator='initiator' name='audio'> <description xmlns='urn:xmpp:jingle:apps:rtp:1'/> <transport xmlns:p=\"http://www.google.com/transport/p2p\"/> </content> </jingle> </iq>", to,me, sid]; 
    

    otherParty=[NSString stringWithString:to]; 
    //thesid =[NSString stringWithString:sid]; 
    [otherParty retain]; 
    //[thesid retain];
    
    [query retain]; 
    
    
    [pool release]; 
    return query;
}

-(NSString*) terminateJingle
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-terminate' sid='%@'> <reason> <success/> </reason> </jingle> </iq>", otherParty, thesid]; 
    
    
    [query retain]; 
    if(otherParty!=nil) [otherParty release]; 
    if(thesid!=nil) [thesid release]; 
    
    
    [pool release]; 
    return query;
}




-(void) dealloc
{
   
    if(otherParty!=nil) [otherParty release]; 
    if(thesid!=nil) [thesid release];   
    [super dealloc];
}


@end
