//
//  UITabBarController+Autorotate.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/18/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "MyTabController.h"

@implementation MyTabController

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    UIViewController *controller = self.selectedViewController;
  /*  if ([controller isKindOfClass:[chat class]])
	{  
		controller = [(UINavigationController *)controller visibleViewController];
	
	
    return [controller shouldAutorotateToInterfaceOrientation:interfaceOrientation];
	
	}*/
	
	
	
		
	bool val= [controller shouldAutorotateToInterfaceOrientation:interfaceOrientation]; 
	if(val!=true)
	{
		debug_NSLog(@"found  no to autorotate but ignoring :)");
					
	}
	
	return true; 
}

@end