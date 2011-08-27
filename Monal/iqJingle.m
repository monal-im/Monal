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

-(id) init: (NSString*) ownid
{
    self = [super init];
   
   
    
    thesid=nil; 
    otherParty=nil; 
    
    return self; 
}

-(NSString*) ack:(NSString*) to
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq to='%@' type='result'>", to]; 
    
    

    
    [query retain]; 
    
    
    [pool release]; 
    return query;
}


-(NSString*) acceptJingle:(NSString*) to  :(NSString*) sid
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq      to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-accept'  responder='%@' sid='%@'> <content creator='initiator' name='this-is-a-stub'> <description xmlns='urn:xmpp:jingle:apps:stub:0'/> <transport xmlns='urn:xmpp:jingle:transports:stub:0'/> </content> </jingle> </iq>", to, me,  sid]; 
    
    
    otherParty=[NSString stringWithString:to]; 
    thesid =[NSString stringWithString:sid]; 
    [otherParty retain]; 
    [thesid retain];
    
    [query retain]; 
    
    
    [pool release]; 
    return query;
}

-(NSString*) initiateJingle:(NSString*) to  :(NSString*) sid
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
 
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@" <iq to='%@' type='set'> <jingle xmlns='urn:xmpp:jingle:1' action='session-initiate' initiator='%@' sid='%@'> <content creator='initiator' name='this-is-a-stub'> <description xmlns='urn:xmpp:jingle:apps:stub:0'/> <transport xmlns='urn:xmpp:jingle:transports:stub:0'/> </content> </jingle> </iq>", to,me, sid]; 
    
    
    otherParty=[NSString stringWithString:to]; 
    thesid =[NSString stringWithString:sid]; 
    [otherParty retain]; 
    [thesid retain];
    
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
