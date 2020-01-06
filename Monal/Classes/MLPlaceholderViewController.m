//
//  MLPlaceholderViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/5/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPlaceholderViewController.h"

@interface MLPlaceholderViewController ()

@end

@implementation MLPlaceholderViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}


-(void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
}



@end
