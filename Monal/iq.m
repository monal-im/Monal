//
//  iq.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/12/12.
//
//

#import "iq.h"

@implementation iq

@synthesize user ;
@synthesize from ;
@synthesize to ;
@synthesize  idval;
@synthesize  resource;
@synthesize type;
@synthesize ver;

-(void) reset
{
    user=nil;
	from=nil;
    to=nil;
    idval=nil;
    resource=nil;
    

	type=nil;
    ver=nil; 
}

@end
