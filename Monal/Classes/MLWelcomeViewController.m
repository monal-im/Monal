//
//  MLWelcomeViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 11/23/18.
//  Copyright © 2018 Monal.im. All rights reserved.
//

#import "HelperTools.h"
#import "MLWelcomeViewController.h"
#import <EAIntroView/EAIntroView.h>
#import "UIColor+Theme.h"


@interface MLWelcomeViewController () <EAIntroDelegate>

@end

@implementation MLWelcomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self showIntro];
}

#pragma mark - welcome
- (void)showIntro {
    
    EAIntroPage* page1 = [EAIntroPage page];
    page1.title = NSLocalizedString(@"Welcome to Monal", @"");
    page1.titleColor = [UIColor darkGrayColor];
    page1.desc = NSLocalizedString(@"Chat for free with your friends, colleagues and family!", @"");
    if (@available(iOS 13.0, *)) {
        page1.descColor = [UIColor labelColor];
    } else {
       page1.descColor = [UIColor blackColor];
    }
    page1.titleIconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PeterRabbit7"]];
    page1.titleIconPositionY = 100.f;
    page1.titlePositionY = self.view.bounds.size.height/2 - 30;
    page1.descPositionY = self.view.bounds.size.height/2 - 70;
    
    EAIntroPage* page2 = [EAIntroPage page];
    page2.title = NSLocalizedString(@"Choices Galore", @"");
    page2.titleColor = [UIColor darkGrayColor];
    page2.desc = NSLocalizedString(@"Use your existing account or make a new one on the many servers around the world", @"");
    page2.titleIconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PeterRabbit8"]];
    if (@available(iOS 13.0, *)) {
        page2.descColor = [UIColor labelColor];
    } else {
       page2.descColor = [UIColor blackColor];
    }
    page2.titleIconPositionY = 100.f;
    page2.titlePositionY = self.view.bounds.size.height/2 - 30;
    page2.descPositionY = self.view.bounds.size.height/2 - 70;
    
    EAIntroPage* page3 = [EAIntroPage page];
    page3.title = NSLocalizedString(@"Escape The Garden", @"");
    page3.titleColor = [UIColor darkGrayColor];
    page3.desc = NSLocalizedString(@"You are not trapped in a garden. Talk to anyone else without anyone tracking you.", @"");
    if (@available(iOS 13.0, *)) {
        page3.descColor = [UIColor labelColor];
    } else {
        page3.descColor = [UIColor blackColor];
    }
    page3.titleIconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PeterRabbit23"]];
    page3.titleIconPositionY = 100.f;
    page3.titlePositionY = self.view.bounds.size.height/2 - 30;
    page3.descPositionY = self.view.bounds.size.height/2 - 70;
    
    EAIntroPage* page4 = [EAIntroPage page];
    page4.title = NSLocalizedString(@"Spread The Word", @"");
    page4.titleColor=[UIColor darkGrayColor];
    page4.desc = NSLocalizedString(@"If you like Monal, please let others know and leave a review", @"");
    if (@available(iOS 13.0, *)) {
        page4.descColor=[UIColor labelColor];
    } else {
        page4.descColor=[UIColor blackColor];
    }
    page4.titleIconView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"PeterRabbit24"]];
    page4.titleIconPositionY=100.f;
    page4.titlePositionY = self.view.bounds.size.height/2 - 30;
    page4.descPositionY = self.view.bounds.size.height/2 - 70;
    
    // Display intro pages
    EAIntroView* intro = [[EAIntroView alloc] initWithFrame:self.view.bounds andPages:@[page1, page2, page3, page4]];
    intro.skipButtonAlignment = EAViewAlignmentCenter;
    intro.skipButtonY = 100.f;
    intro.pageControlY = 120.0f;
    if (@available(iOS 13.0, *)) {
        intro.backgroundColor = [UIColor systemGroupedBackgroundColor];
    } else {
        intro.backgroundColor = [UIColor groupTableViewBackgroundColor];
    }
    [intro.skipButton setTitleColor:[UIColor monaldarkGreen] forState:UIControlStateNormal];
    [intro setDelegate:self];
    intro.pageControl.currentPageIndicatorTintColor = [UIColor monaldarkGreen];
    intro.pageControl.pageIndicatorTintColor = [UIColor monalGreen];
    
    [intro showInView:self.view animateDuration:0.3];
}


#pragma mark - EAIntroView delegate

- (void)introDidFinish:(EAIntroView *)introView wasSkipped:(BOOL)wasSkipped {
   
    [self dismissViewControllerAnimated:YES completion:self.completion];
    [[HelperTools defaultsDB] setObject:@YES forKey:@"HasSeenIntro"];
}


@end
