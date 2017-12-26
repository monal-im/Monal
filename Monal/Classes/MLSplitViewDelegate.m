//
//  MLSplitViewDelegate.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/4/17.
//  Copyright © 2017 Monal.im. All rights reserved.
//

#import "MLSplitViewDelegate.h"
#import "chatViewController.h"
#import "XMPPEdit.h"

@implementation MLSplitViewDelegate


#pragma mark - Split view

- (BOOL)splitViewController:(UISplitViewController *)splitViewController collapseSecondaryViewController:(UIViewController *)secondaryViewController ontoPrimaryViewController:(UIViewController *)primaryViewController {
   
     return YES;
    
//    if ([secondaryViewController isKindOfClass:[UINavigationController class]] &&( [[(UINavigationController *)secondaryViewController topViewController] isKindOfClass:[chatViewController class]] ||  [[(UINavigationController *)secondaryViewController topViewController] isKindOfClass:[XMPPEdit class]]) ){
//        // Return YES to indicate that we have handled the collapse by doing nothing; the secondary controller will be discarded.
//        return YES;
//    } else {
//        return NO;
//    }
}

@end
