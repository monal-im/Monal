//
//  MLPlaceholderViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 1/5/20.
//  Copyright © 2020 Monal.im. All rights reserved.
//

#import "MLPlaceholderViewController.h"

@interface MLPlaceholderViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *backgroundImageView;

@end

@implementation MLPlaceholderViewController

- (void) viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}


-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.splitViewController.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    
    self.backgroundImageView.image = [UIImage imageNamed:@"park_colors"];
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
