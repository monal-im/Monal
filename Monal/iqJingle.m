//
//  iqJingle.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/27/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "iqJingle.h"

@implementation iqJingle


-(id) init
{
    self = [super init];
   
    return self; 
}

-(NSString*) constructUserSearch:(NSString*) to :(NSString*) request
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int counter=0; 
    NSMutableString* query=[[NSMutableString alloc] init];
    [query appendFormat:@"<iq type='set' to='%@' id='search2' > <query xmlns='jabber:iq:search'>", to]; 
   /* while(counter<[userFields count])
    {
        
        [query appendFormat:@"<%@>%@</%@>", [userFields objectAtIndex:counter],
         request, [userFields objectAtIndex:counter]]; 
        
        counter++; 
    }
    
    [query appendFormat:@"</query></iq>"]; 
    [query retain]; 
    */
    
    [pool release]; 
    return query;
}


-(void) dealloc
{
       
}


@end
