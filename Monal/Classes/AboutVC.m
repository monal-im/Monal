//
//  AboutVC.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/28/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "AboutVC.h"


@implementation AboutVC

-(IBAction) rateApp
{
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"itms://itunes.apple.com/us/app/monal/id317711500?mt=8&uo=4"]]; 
}



-(void)viewDidAppear:(BOOL)animated 
{
[versionText setText:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];

}

-(void) viewDidLoad
{
	
	
	debug_NSLog(@"about did  load");
	if(![[tools machine] hasPrefix:@"iPad"] )
	{
	[scroll setContentSize:CGSizeMake(320, 400)];
	}
	
}


	@end
