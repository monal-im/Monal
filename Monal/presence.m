//
//  presence.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/12/12.
//
//

#import "presence.h"

@implementation presence

@synthesize user ;
@synthesize from ;
@synthesize to ;
@synthesize  idval;
@synthesize  resource;

@synthesize  show;
@synthesize status;
@synthesize  photo;
@synthesize type;
@synthesize ver; 

-(void) reset
{
    user=nil; 
	from=nil;
    to=nil;
    idval=nil;
    resource=nil;

	show=nil;
	status=nil;
	photo=nil;
	type=nil;
    ver=nil; 
}

@end
