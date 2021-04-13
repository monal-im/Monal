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
    
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(updateBackground) name:kMonalBackgroundChanged object:nil];
}


-(void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.splitViewController.preferredDisplayMode=UISplitViewControllerDisplayModeAllVisible;
    
    [self updateBackground];
}

-(void) updateBackground {
    BOOL backgrounds = [[HelperTools defaultsDB] boolForKey:@"ChatBackgrounds"];
    
    if(backgrounds){
        self.backgroundImageView.hidden = NO;
        NSString* imageName = [[HelperTools defaultsDB] objectForKey:@"BackgroundImage"];
        if(imageName)
        {
            if([imageName isEqualToString:@"CUSTOM"])
            {
                self.backgroundImageView.image = [[MLImageManager sharedInstance] getBackground];
            } else  {
                self.backgroundImageView.image = [UIImage imageNamed:imageName];
            }
        }
        
    } else {
        self.backgroundImageView.hidden = YES;
    }
}

@end
