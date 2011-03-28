//
//  Status.m
//  Monal
//
//  Created by Anurodh Pokharel on 9/2/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "Scroller.h"


@implementation Scroller

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
	return YES;
}


-(void) viewDidLoad
{
	debug_NSLog(@"scroller did  appear");
	[scroll setContentSize:CGSizeMake(320, 400)];
}
@end
