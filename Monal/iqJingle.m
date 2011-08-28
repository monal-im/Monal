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

-(id) init
{
    self = [super init];
   
   
    
    thesid=nil; 
    otherParty=nil; 
    
    return self; 
}

-(NSString*) ack:(NSString*) to:(NSString*) theid
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq to='%@' from='%@' id='%@' type='result'/>", to, me, theid]; 
    
    

    
    [query retain]; 
    
    
    [pool release]; 
    return query;
}


-(NSString*) acceptJingle:(NSString*) to  :(NSString*) sid
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name='audio'> <description xmlns='urn:xmpp:jingle:apps:rtp:1'/> <transport xmlns:p=\"http://www.google.com/transport/p2p\"/> </content> </jingle> </iq>", to, me,  sid]; 
    
    
    otherParty=[NSString stringWithString:to]; 
    thesid =[NSString stringWithString:sid]; 
    [otherParty retain]; 
    [thesid retain];
    
    [query retain]; 
    
    
    [pool release]; 
    return query;
}

-(NSString*) initiateJingle:(NSString*) to  
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
 
 NSMutableString* query=[[NSMutableString alloc] init];
      /* [query appendFormat:@" <iq to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' initiator='%@' sid='%@'> <content creator='initiator' name='audio'> <description xmlns='urn:xmpp:jingle:apps:rtp:1'/> <transport xmlns:p=\"http://www.google.com/transport/p2p\"/> </content> </jingle> </iq>", to,me, sid]; 
    */
    

    [query appendFormat: @"<iq type='set' to='%@' id='45gt68ju9' from='%@'><jin:jingle action='session-initiate' sid='c233088176' initiator='%@' xmlns:jin='urn:xmpp:jingle:1'><jin:content name='audio' creator='initiator'><rtp:description media='audio' xmlns:rtp='urn:xmpp:jingle:apps:rtp:1'><rtp:payload-type id='103' name='ISAC' clockrate='16000'><rtp:parameter name='bitrate' value='32000'/></rtp:payload-type><rtp:payload-type id='104' name='ISAC' clockrate='32000'><rtp:parameter name='bitrate' value='56000'/></rtp:payload-type><rtp:payload-type id='119' name='ISACLC' clockrate='16000'><rtp:parameter name='bitrate' value='40000'/></rtp:payload-type><rtp:payload-type id='99' name='speex' clockrate='16000'><rtp:parameter name='bitrate' value='22000'/></rtp:payload-type><rtp:payload-type id='97' name='IPCMWB' clockrate='16000'><rtp:parameter name='bitrate' value='80000'/></rtp:payload-type><rtp:payload-type id='9' name='G722' clockrate='16000'><rtp:parameter name='bitrate' value='64000'/></rtp:payload-type><rtp:payload-type id='102' name='iLBC' clockrate='8000'><rtp:parameter name='bitrate' value='13300'/></rtp:payload-type><rtp:payload-type id='98' name='speex' clockrate='8000'><rtp:parameter name='bitrate' value='11000'/></rtp:payload-type><rtp:payload-type id='3' name='GSM' clockrate='8000'><rtp:parameter name='bitrate' value='13200'/></rtp:payload-type><rtp:payload-type id='100' name='EG711U' clockrate='8000'><rtp:parameter name='bitrate' value='64000'/></rtp:payload-type><rtp:payload-type id='101' name='EG711A' clockrate='8000'><rtp:parameter name='bitrate' value='64000'/></rtp:payload-type><rtp:payload-type id='0' name='PCMU' clockrate='8000'><rtp:parameter name='bitrate' value='64000'/></rtp:payload-type><rtp:payload-type id='8' name='PCMA' clockrate='8000'><rtp:parameter name='bitrate' value='64000'/></rtp:payload-type><rtp:payload-type id='117' name='red' clockrate='8000'/><rtp:payload-type id='106' name='telephone-event' clockrate='8000'/></rtp:description><p:transport xmlns:p='http://www.google.com/transport/p2p'/></jin:content></jin:jingle><ses:session type='initiate' id='c233088176' initiator='monaltest@gmail.com/gmail.FD4AED6E' xmlns:ses='http://www.google.com/session'><pho:description xmlns:pho='http://www.google.com/session/phone'><pho:payload-type id='103' name='ISAC' bitrate='32000' clockrate='16000'/><pho:payload-type id='104' name='ISAC' bitrate='56000' clockrate='32000'/><pho:payload-type id='119' name='ISACLC' bitrate='40000' clockrate='16000'/><pho:payload-type id='99' name='speex' bitrate='22000' clockrate='16000'/><pho:payload-type id='97' name='IPCMWB' bitrate='80000' clockrate='16000'/><pho:payload-type id='9' name='G722' bitrate='64000' clockrate='16000'/><pho:payload-type id='102' name='iLBC' bitrate='13300' clockrate='8000'/><pho:payload-type id='98' name='speex' bitrate='11000' clockrate='8000'/><pho:payload-type id='3' name='GSM' bitrate='13200' clockrate='8000'/><pho:payload-type id='100' name='EG711U' bitrate='64000' clockrate='8000'/><pho:payload-type id='101' name='EG711A' bitrate='64000' clockrate='8000'/><pho:payload-type id='0' name='PCMU' bitrate='64000' clockrate='8000'/><pho:payload-type id='8' name='PCMA' bitrate='64000' clockrate='8000'/><pho:payload-type id='117' name='red' clockrate='8000'/><pho:payload-type id='106' name='telephone-event' clockrate='8000'/></pho:description></ses:session></iq>", to, me, me]; 
    
    
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


/*
-(NSString*) constructUserSearch:(NSString*) to :(NSString*) request
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int counter=0; 
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq type='set' to='%@' id='search2' > <query xmlns='jabber:iq:search'>", to]; 
    while(counter<[userFields count])
    {
        
        [query appendFormat:@"<%@>%@</%@>", [userFields objectAtIndex:counter],
         request, [userFields objectAtIndex:counter]]; 
        
        counter++; 
    }
    
    [query appendFormat:@"</query></iq>"]; 
    [query retain]; 
   
    
    [pool release]; 
    return query;
}
*/

-(void) dealloc
{
   
    if(otherParty!=nil) [otherParty release]; 
    if(thesid!=nil) [thesid release];   
}


@end
