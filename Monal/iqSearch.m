//
//  userSearch.m
//  Monal
//
//  Created by Anurodh Pokharel on 3/27/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "userSearch.h"


@implementation iqSearch

@synthesize userFields; 

-(id) init
{
    self = [super init];
    userFields=[[NSMutableArray alloc] init]; 
    return self; 
}

-(NSString*) constructUserSearch:(NSString*) to :(NSString*) request
{
    
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
    
    ; 
    return query;
}


@end
