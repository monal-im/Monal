//
//  TabMoreController.m
//  Monal
//
//  Created by Anurodh Pokharel on 8/24/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "TabMoreController.h"


@implementation TabMoreController




- (void)navigationController:(UINavigationController *)navigationController
	  willShowViewController:(UIViewController *)viewController
					animated:(BOOL)animated {
	debug_NSLog(@"more view will appear %@", viewController.title);
    UINavigationBar *morenavbar = navigationController.navigationBar;
    UINavigationItem *morenavitem = morenavbar.topItem;
    /* We don't need Edit button in More screen. */
    morenavitem.rightBarButtonItem = nil;
	
/*	if([viewController.title isEqualToString:@"About"])
	{
		[viewController initWithNibName:@"About" bundle:nil];
	}
*/

}
	

	


@end
