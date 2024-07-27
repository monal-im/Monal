//
//  MLSplitViewDelegate.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/4/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLSplitViewDelegate.h"
#import "ActiveChatsViewController.h"
#import "MLSettingsTableViewController.h"

@implementation MLSplitViewDelegate


#pragma mark - Split view

-(BOOL) splitViewController:(UISplitViewController*) splitViewController collapseSecondaryViewController:(UIViewController*) secondaryViewController ontoPrimaryViewController:(UIViewController*) primaryViewController
{
    //return YES to indicate that we have handled the collapse by doing nothing; the secondary controller will be discarded.
    return YES;
}

-(void) splitViewControllerDidExpand:(UISplitViewController*) splitViewController
{
    UIViewController* primaryController = ((UINavigationController*)splitViewController.viewControllers[0]).viewControllers[0];
    UIViewController* secondaryController = nil;
    if([splitViewController.viewControllers count] > 1)
        secondaryController = splitViewController.viewControllers[1];
    
    if([primaryController isKindOfClass:NSClassFromString(@"ActiveChatsViewController")] && [secondaryController isKindOfClass:NSClassFromString(@"MLPlaceholderViewController")])
        [(ActiveChatsViewController*)primaryController presentSplitPlaceholder];
    
    if([primaryController isKindOfClass:NSClassFromString(@"MLSettingsTableViewController")] && [secondaryController isKindOfClass:NSClassFromString(@"MLPlaceholderViewController")])
        [(MLSettingsTableViewController*)primaryController presentSplitPlaceholder];
}

@end
