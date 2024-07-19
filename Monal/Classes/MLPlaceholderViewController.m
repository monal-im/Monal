//
//  MLPlaceholderViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/5/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MLPlaceholderViewController : UIViewController
@end

@implementation MLPlaceholderViewController

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
}

@end
